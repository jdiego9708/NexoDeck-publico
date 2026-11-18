using System.Diagnostics;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

using LibreHardwareMonitor.Hardware;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Hosting.WindowsServices;

namespace NexoDeck.Sensors;

/// <summary>
/// Publica los sensores que Windows no expone a espacio de usuario, para que
/// NexoDeck los lea sin depender de que el usuario instale y abra otra app.
///
/// Existe porque en Windows la temperatura del CPU **solo** se puede leer
/// desde kernel-mode: los Ryzen la publican en el registro SMN 0x00059800
/// (espacio de configuracion PCI) y los Intel en un MSR. La via generica del
/// SO (zonas termicas ACPI) depende de que la placa las implemente, y en un
/// desktop tipico no existe -- verificado en el equipo principal, donde
/// MSAcpi_ThermalZoneTemperature responde "Incompatible", el contador PDH de
/// zona termica no tiene ni una instancia y Win32_TemperatureProbe tampoco.
///
/// **Corre como servicio de Windows**, no como tarea programada. La tarea fue
/// la primera version y tenia cuatro debilidades que se pagaron en vivo: solo
/// corria con el usuario conectado, no se reiniciaba si el proceso moria,
/// `schtasks /run` no deja estado que consultar, y sobre todo dependia de que
/// el instalador se hubiera corrido elevado -- una instalacion por usuario
/// dejaba la temperatura muerta **en silencio**.
///
/// El mismo .exe hace tres cosas segun como se lo invoque:
///
/// - sin argumentos y lanzado por el SCM: corre como servicio.
/// - sin argumentos desde una consola: corre en primer plano, para depurar.
/// - `--install` / `--uninstall`: registra o quita el servicio. Necesita
///   elevacion, y es lo que NexoDeck dispara con un UAC unico cuando detecta
///   que el ayudante no esta.
/// </summary>
internal static class Program
{
    /// <summary>
    /// Nombre del servicio y del pipe. El del pipe tiene que coincidir con el
    /// del lado Rust (`cpu_temp/windows_provider.rs`).
    /// </summary>
    internal const string ServiceName = "NexoDeckSensors";

    internal const string PipeName = "nexodeck-sensors";

    private static int Main(string[] args)
    {
        // Los dos verbos de instalacion se resuelven y se sale: no levantan ni
        // sensores ni pipe.
        if (args.Contains("--install", StringComparer.OrdinalIgnoreCase))
        {
            return ServiceInstaller.Install();
        }
        if (args.Contains("--uninstall", StringComparer.OrdinalIgnoreCase))
        {
            return ServiceInstaller.Uninstall();
        }

        var builder = Host.CreateApplicationBuilder(args);
        // Detecta solo si lo lanzo el SCM o una consola: con el mismo binario
        // se puede depurar en primer plano sin registrar nada.
        builder.Services.AddWindowsService(options => options.ServiceName = ServiceName);
        builder.Services.AddHostedService<SensorPipeService>();

        try
        {
            builder.Build().Run();
            return 0;
        }
        catch (Exception error)
        {
            Log($"el servicio termino con error: {error.Message}");
            return 1;
        }
    }

    /// <summary>
    /// Deja rastro en `%ProgramData%\NexoDeck\sensors.log`.
    ///
    /// **ProgramData y no LocalApplicationData**: como servicio esto corre bajo
    /// LocalSystem, y ahi `LocalApplicationData` resuelve a
    /// `C:\Windows\System32\config\systemprofile\AppData\Local` -- o sea que el
    /// log iria a parar a un lugar donde el usuario no lo va a buscar nunca.
    /// ProgramData es el mismo para todas las cuentas.
    ///
    /// Best-effort a proposito: que no se pueda escribir el log no puede tumbar
    /// el servicio.
    /// </summary>
    internal static void Log(string message)
    {
        try
        {
            var directory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "NexoDeck");
            Directory.CreateDirectory(directory);
            File.AppendAllText(
                Path.Combine(directory, "sensors.log"),
                $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}{Environment.NewLine}");
        }
        catch
        {
            // Sin log tambien se puede vivir.
        }
    }
}

/// <summary>
/// Registra y quita el servicio con `sc.exe`.
///
/// Se usa `sc.exe` y no la API de servicios por P/Invoke porque son cuatro
/// llamadas de una sola vez, y el codigo equivalente con `OpenSCManager` /
/// `CreateService` seria varias veces mas largo sin ganar nada.
/// </summary>
internal static class ServiceInstaller
{
    public static int Install()
    {
        if (!IsElevated())
        {
            Program.Log("--install necesita privilegios de administrador");
            return 5; // ERROR_ACCESS_DENIED
        }

        var exe = Environment.ProcessPath;
        if (string.IsNullOrEmpty(exe))
        {
            Program.Log("--install no pudo resolver la ruta del ejecutable");
            return 1;
        }

        // Si ya existia (reinstalacion, o una version anterior), se quita
        // primero: `sc create` sobre un nombre existente falla, y dejar el
        // binPath viejo apuntando a una ruta que ya no existe es peor.
        //
        // **Y hay que ESPERAR a que se vaya.** `sc stop` y `sc delete` son
        // asincronos: devuelven en cuanto el SCM acepta el pedido, no cuando
        // termino. Encadenarlos con `create` fallaba con 1072
        // (ERROR_SERVICE_MARKED_FOR_DELETE), que es el SCM diciendo "todavia
        // hay handles abiertos sobre el servicio que estas borrando".
        // Verificado en vivo, y el sintoma es traicionero: el servicio queda
        // borrado y el nuevo no se crea, o sea peor que antes de empezar.
        if (Exists())
        {
            Run("stop", Program.ServiceName);
            Run("delete", Program.ServiceName);
            if (!WaitUntilAbsent())
            {
                Program.Log("el servicio anterior no termino de borrarse a tiempo");
                return 1072;
            }
        }

        // `binPath=` con la ruta entre comillas: si la ruta tiene espacios
        // --y `C:\Program Files\NexoDeck` los tiene-- sin comillas el SCM
        // interpreta el resto como argumentos y el servicio no arranca nunca.
        var created = Run(
            "create", Program.ServiceName,
            "binPath=", $"\"{exe}\"",
            "start=", "auto",
            "DisplayName=", "NexoDeck Sensors");
        if (created != 0)
        {
            Program.Log($"sc create fallo con codigo {created}");
            return created;
        }

        Run("description", Program.ServiceName,
            "Publica la temperatura del procesador para NexoDeck.");

        // Recuperacion ante fallo: es una de las razones de ser servicio y no
        // tarea programada. Tres reintentos con espera creciente, y el contador
        // se reinicia al dia.
        Run("failure", Program.ServiceName,
            "reset=", "86400",
            "actions=", "restart/5000/restart/10000/restart/30000");

        var started = Run("start", Program.ServiceName);
        if (started != 0)
        {
            Program.Log($"sc start fallo con codigo {started}");
            return started;
        }

        Program.Log("servicio instalado y arrancado");
        return 0;
    }

    public static int Uninstall()
    {
        if (!IsElevated())
        {
            Program.Log("--uninstall necesita privilegios de administrador");
            return 5;
        }

        Run("stop", Program.ServiceName);
        var deleted = Run("delete", Program.ServiceName);
        Program.Log($"servicio quitado (codigo {deleted})");
        return deleted;
    }

    /// <summary>`sc query` devuelve 1060 (ERROR_SERVICE_DOES_NOT_EXIST) cuando
    /// el servicio no esta registrado. Es la forma barata de preguntarlo sin
    /// abrir el SCM por P/Invoke.</summary>
    private static bool Exists() => Run("query", Program.ServiceName) != 1060;

    /// <summary>
    /// Espera a que el servicio realmente desaparezca del SCM.
    ///
    /// Un servicio marcado para borrar sigue existiendo hasta que se cierran
    /// todos los handles que lo referencian -- incluido el de una consola de
    /// `services.msc` abierta, que es el caso clasico en una maquina de
    /// desarrollo. Por eso hay tope: si alguien lo tiene abierto, es mejor
    /// avisar que colgarse.
    /// </summary>
    private static bool WaitUntilAbsent()
    {
        var deadline = DateTime.UtcNow.AddSeconds(15);
        while (DateTime.UtcNow < deadline)
        {
            if (!Exists())
            {
                return true;
            }
            Thread.Sleep(500);
        }
        return false;
    }

    private static bool IsElevated()
    {
        using var identity = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(identity).IsInRole(WindowsBuiltInRole.Administrator);
    }

    /// <summary>
    /// `sc.exe` exige que el `=` y su valor sean argumentos SEPARADOS
    /// (`binPath=` y despues la ruta). Por eso se pasa cada uno como elemento
    /// de `ArgumentList` en vez de armar una linea de comandos a mano.
    /// </summary>
    private static int Run(params string[] arguments)
    {
        var info = new ProcessStartInfo("sc.exe")
        {
            CreateNoWindow = true,
            UseShellExecute = false,
            // Se traga la salida de `sc`: lo que importa es el codigo, y las
            // consultas de `Exists()` llenarian la consola de tablas.
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        foreach (var argument in arguments)
        {
            info.ArgumentList.Add(argument);
        }

        try
        {
            using var process = Process.Start(info);
            if (process is null)
            {
                return 1;
            }
            // Se leen los dos flujos antes de esperar: con `sc` la salida es
            // chica, pero un pipe lleno con nadie leyendo es un bloqueo
            // clasico.
            process.StandardOutput.ReadToEnd();
            process.StandardError.ReadToEnd();
            process.WaitForExit();
            return process.ExitCode;
        }
        catch (Exception error)
        {
            Program.Log($"sc.exe {string.Join(' ', arguments)} fallo: {error.Message}");
            return 1;
        }
    }
}

/// <summary>
/// El servicio en si: abre los sensores una vez y sirve el pipe mientras viva.
/// </summary>
internal sealed class SensorPipeService : BackgroundService
{
    /// <summary>
    /// Cada cuanto se refrescan los sensores y se emite una linea, mientras
    /// haya un cliente. Sin cliente conectado **no se refresca nada**: el
    /// servicio arranca con Windows y no tiene por que estar leyendo sensores
    /// cuando NexoDeck ni siquiera esta abierto.
    /// </summary>
    private static readonly TimeSpan EmitInterval = TimeSpan.FromSeconds(1);

    /// <summary>
    /// Cuanto se espera antes de reintentar cuando **no se pudo crear el
    /// pipe**. Sin esta pausa, un fallo persistente se convierte en un bucle
    /// cerrado que quema un nucleo y llena el log.
    ///
    /// Ojo: NO se aplica cuando lo que termina es un cliente. Esa es la via
    /// normal (pasa cada vez que se cierra NexoDeck) y ahi hay que volver a
    /// escuchar en el acto. Tenerlas juntas fue un bug real: al cerrarse la app
    /// el pipe quedaba sordo unos segundos.
    /// </summary>
    private static readonly TimeSpan RetryDelay = TimeSpan.FromSeconds(5);

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
    };

    /// <summary>
    /// Rango en el que una lectura se considera real.
    ///
    /// El piso **no es paranoia**: corriendo esto SIN elevar, la libreria
    /// enumera igual el sensor "Core (Tctl/Tdie)" pero devuelve exactamente 0
    /// -- no lanza, no avisa. Verificado en vivo. Sin este filtro NexoDeck
    /// dibujaria un "0 C" que parece un dato y no lo es.
    /// </summary>
    private const float MinPlausibleC = 1.0f;

    private const float MaxPlausibleC = 150.0f;

    /// <summary>
    /// Cuantos clientes simultaneos admite el pipe.
    ///
    /// **Era 1, y eso mordio en vivo.** Con una sola instancia, la app tomaba
    /// el pipe y cualquier otro lector --el modo compacto, un segundo
    /// NexoDeck, o simplemente una herramienta de diagnostico-- recibia
    /// ERROR_PIPE_BUSY (231), que se ve igual que "el servicio no esta". Se
    /// perdio un buen rato diagnosticando el servicio cuando lo unico que
    /// pasaba era que la app ya estaba leyendo.
    /// </summary>
    private const int MaxClients = 4;

    /// <summary>
    /// La ultima linea JSON lista para mandar, y cuantos clientes hay.
    ///
    /// **Existe por una razon de correccion, no de eficiencia.**
    /// LibreHardwareMonitorLib no es thread-safe: `computer.Accept(visitor)`
    /// muta el arbol de sensores, asi que con varios clientes atendidos en
    /// paralelo llamarlo desde cada uno seria una carrera. Un solo hilo
    /// refresca y todos escriben lo mismo.
    ///
    /// De paso resuelve lo otro: con N clientes los sensores se leen una vez
    /// por intervalo, no N.
    /// </summary>
    private volatile string _latestLine = string.Empty;

    private int _clientCount;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var computer = new ComputerHandle();
        if (!computer.TryOpen())
        {
            // Sin sensores no hay nada que publicar, pero el servicio sigue
            // vivo: pararlo haria que el SCM lo reintente por la politica de
            // recuperacion, en un bucle que no puede arreglar nada.
            return;
        }

        var visitor = new UpdateVisitor();
        var first = Read(computer.Computer, visitor);
        // Se deja una linea lista antes de aceptar a nadie: un cliente que
        // conecta no tiene por que esperar al primer refresco para recibir
        // algo.
        _latestLine = JsonSerializer.Serialize(first, JsonOptions);
        Program.Log($"sensores abiertos; {first.CpuTemps.Count} lecturas de CPU");

        var refresher = RefreshLoopAsync(computer.Computer, visitor, stoppingToken);

        while (!stoppingToken.IsCancellationRequested)
        {
            NamedPipeServerStream pipe;
            try
            {
                pipe = CreatePipe();
            }
            catch (Exception error)
            {
                Program.Log($"no se pudo crear el pipe: {error.Message}");
                await Task.Delay(RetryDelay, stoppingToken).ConfigureAwait(false);
                continue;
            }

            try
            {
                // Se espera la conexion aca y se atiende al cliente en una
                // tarea aparte: asi el bucle vuelve enseguida a crear otra
                // instancia y quedan varios lectores posibles a la vez.
                await pipe.WaitForConnectionAsync(stoppingToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                await pipe.DisposeAsync().ConfigureAwait(false);
                return;
            }
            catch (Exception error)
            {
                Program.Log($"fallo esperando conexion: {error.Message}");
                await pipe.DisposeAsync().ConfigureAwait(false);
                await Task.Delay(RetryDelay, stoppingToken).ConfigureAwait(false);
                continue;
            }

            // Sin `await`: el cliente se atiende en paralelo. Los errores se
            // manejan adentro, asi que no queda ninguna tarea sin observar.
            _ = ServeClientAsync(pipe, stoppingToken);
        }

        await refresher.ConfigureAwait(false);
    }

    /// <summary>
    /// El unico lugar que toca los sensores. Se queda quieto mientras no haya
    /// clientes: el servicio arranca con Windows y no tiene por que estar
    /// leyendo sensores cuando NexoDeck ni siquiera esta abierto.
    /// </summary>
    private async Task RefreshLoopAsync(
        Computer computer,
        UpdateVisitor visitor,
        CancellationToken stoppingToken)
    {
        try
        {
            while (!stoppingToken.IsCancellationRequested)
            {
                await Task.Delay(EmitInterval, stoppingToken).ConfigureAwait(false);
                if (Volatile.Read(ref _clientCount) > 0)
                {
                    _latestLine = JsonSerializer.Serialize(Read(computer, visitor), JsonOptions);
                }
            }
        }
        catch (OperationCanceledException)
        {
            // El servicio se esta deteniendo.
        }
    }

    /// <summary>
    /// Atiende a UN cliente ya conectado hasta que se va. Se llama sin
    /// `await` desde el bucle principal, asi que se traga sus propios errores:
    /// que un cliente se corte es lo normal y no puede tumbar el servicio.
    /// </summary>
    private async Task ServeClientAsync(
        NamedPipeServerStream pipe,
        CancellationToken stoppingToken)
    {
        Interlocked.Increment(ref _clientCount);
        try
        {
            // `AutoFlush` porque el consumidor lee linea a linea: sin esto la
            // primera lectura se queda esperando a que se llene el buffer.
            await using var writer = new StreamWriter(pipe, new UTF8Encoding(false))
            {
                AutoFlush = true,
            };

            while (pipe.IsConnected && !stoppingToken.IsCancellationRequested)
            {
                await writer.WriteLineAsync(_latestLine).ConfigureAwait(false);
                await Task.Delay(EmitInterval, stoppingToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
            // El servicio se esta deteniendo.
        }
        catch (Exception error)
        {
            Program.Log($"cliente terminado: {error.Message}");
        }
        finally
        {
            Interlocked.Decrement(ref _clientCount);
            await pipe.DisposeAsync().ConfigureAwait(false);
        }
    }

    /// <summary>
    /// Named pipe accesible por un proceso **sin elevar**.
    ///
    /// Esto no es opcional ni cosmetico: el pipe lo crea LocalSystem y lo abre
    /// NexoDeck como el usuario normal; con la ACL por defecto recibiria
    /// ACCESS_DENIED, con un sintoma identico al de "el servicio no esta
    /// corriendo" -- o sea, el diagnostico equivocado.
    ///
    /// Se concede solo lectura a los usuarios autenticados: lo unico que viaja
    /// son lecturas de sensores, y nadie tiene por que escribir.
    /// </summary>
    private static NamedPipeServerStream CreatePipe()
    {
        var security = new PipeSecurity();
        security.AddAccessRule(
            new PipeAccessRule(
                new SecurityIdentifier(WellKnownSidType.AuthenticatedUserSid, null),
                PipeAccessRights.Read | PipeAccessRights.Synchronize,
                AccessControlType.Allow));
        security.AddAccessRule(
            new PipeAccessRule(
                new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null),
                PipeAccessRights.FullControl,
                AccessControlType.Allow));

        return NamedPipeServerStreamAcl.Create(
            Program.PipeName,
            PipeDirection.Out,
            MaxClients,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous,
            inBufferSize: 0,
            outBufferSize: 4096,
            security);
    }

    /// <summary>
    /// Todas las lecturas de temperatura del CPU, con su etiqueta.
    ///
    /// Se manda la **lista completa** y no la mejor: cual gana lo decide el
    /// lado Rust (`cpu_temp::label_priority`), que ya tiene esa regla escrita y
    /// testeada --Tctl/Tdie del paquete por encima de un CCD suelto, y descarte
    /// de lo que seguro no es el CPU-- y que la comparte con la ruta de Linux,
    /// donde los sensores llegan por sysfs. Elegir en los dos lados seria tener
    /// la misma decision escrita dos veces.
    /// </summary>
    private static SensorsPayload Read(Computer computer, UpdateVisitor visitor)
    {
        computer.Accept(visitor);
        var readings = new List<TemperatureReading>();

        foreach (var hardware in computer.Hardware)
        {
            if (hardware.HardwareType != HardwareType.Cpu)
            {
                continue;
            }

            foreach (var sensor in hardware.Sensors)
            {
                if (sensor.SensorType != SensorType.Temperature || !sensor.Value.HasValue)
                {
                    continue;
                }

                var value = sensor.Value.Value;
                if (value >= MinPlausibleC && value <= MaxPlausibleC)
                {
                    readings.Add(new TemperatureReading(sensor.Name, value));
                }
            }
        }

        return new SensorsPayload(readings);
    }
}

/// <summary>
/// `Computer` no implementa IDisposable pero si necesita `Close()`. Este
/// envoltorio existe para que el `using` del servicio suelte el driver aunque
/// el bucle termine por una excepcion.
/// </summary>
internal sealed class ComputerHandle : IDisposable
{
    public Computer Computer { get; } = new()
    {
        // Solo el CPU a proposito. `IsStorageEnabled` **despertaria los
        // discos** en cada refresco (NexoDeck ya lee su temperatura por su
        // cuenta, ver `disk_temp.rs`), y el resto de los subsistemas alarga el
        // arranque para datos que nadie muestra todavia.
        IsCpuEnabled = true,
    };

    private bool _opened;

    public bool TryOpen()
    {
        try
        {
            Computer.Open();
            _opened = true;
            return true;
        }
        catch (Exception error)
        {
            Program.Log($"no se pudieron abrir los sensores: {error.Message}");
            return false;
        }
    }

    public void Dispose()
    {
        if (_opened)
        {
            Computer.Close();
        }
    }
}

internal sealed record TemperatureReading(string Label, float ValueC);

internal sealed record SensorsPayload(IReadOnlyList<TemperatureReading> CpuTemps);

/// <summary>
/// Refresca cada componente antes de leerlo. Es el patron que exige
/// LibreHardwareMonitorLib: sin el, los sensores devuelven el valor con el que
/// se enumeraron y nunca cambian.
/// </summary>
internal sealed class UpdateVisitor : IVisitor
{
    public void VisitComputer(IComputer computer) => computer.Traverse(this);

    public void VisitHardware(IHardware hardware)
    {
        hardware.Update();
        foreach (var subHardware in hardware.SubHardware)
        {
            subHardware.Accept(this);
        }
    }

    public void VisitSensor(ISensor sensor)
    {
    }

    public void VisitParameter(IParameter parameter)
    {
    }
}
