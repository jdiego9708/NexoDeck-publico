; Instalador de NexoDeck para Windows x64.
;
; No se compila a mano: usar scripts\build_installer.ps1, que construye el
; release de Flutter, copia el runtime de MSVC junto al .exe y recien despues
; invoca ISCC con la version leida de app\pubspec.yaml.
;
; Compilar este .iss suelto tambien funciona, pero da por sentado que
; app\build\windows\x64\runner\Release ya existe y ya tiene las DLLs del
; runtime al lado (ver la seccion [Files]).

#define AppName        "NexoDeck"
#define AppPublisher   "NexoDeck"
#define AppExeName     "nexodeck.exe"
#define TransportPort  "58643"

; La version la inyecta build_installer.ps1 con /DAppVersion=...; el valor de
; abajo es solo el fallback para compilar el .iss a mano.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define SourceDir SourcePath + "..\app\build\windows\x64\runner\Release"
; El sidecar de sensores, publicado por `melos run sensors:build`. Va
; aparte del bundle de Flutter porque lo produce el SDK de .NET, no
; cargokit ni flutter build.
#define SensorsDir SourcePath + "..\dist\sensors"
#define IconFile  SourcePath + "..\app\windows\runner\resources\app_icon.ico"

[Setup]
; AppId identifica al producto entre versiones: NO cambiarlo nunca, o una
; version nueva se instalaria al lado de la vieja en vez de actualizarla.
AppId={{8F3A6C41-1D7E-4B92-9E64-2A5C0D8B7F13}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayName={#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
OutputDir={#SourcePath}..\dist
OutputBaseFilename=nexodeck-setup-{#AppVersion}-x64
SetupIconFile={#IconFile}

; x64 puro: el core de Rust y el runner de Flutter se compilan solo para esa
; arquitectura, asi que en un Windows de 32 bits ni conviene dejar empezar.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

; Arranca sin pedir UAC e instala en %LocalAppData%\Programs\NexoDeck; quien
; quiera Program Files para todos los usuarios lo elige en el primer dialogo.
; NexoDeck no necesita privilegios para funcionar (sus datos viven en la
; carpeta del usuario), asi que pedir admin de entrada seria de mas.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

; Cierra la app si esta corriendo en vez de fallar con "archivo en uso".
CloseApplications=yes
RestartApplications=no

WizardStyle=modern
DisableProgramGroupPage=yes
AllowNoIcons=yes
Compression=lzma2/max
SolidCompression=yes

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
es.CreateDesktopIcon=Crear un acceso directo en el &escritorio
es.StartWithWindows=Iniciar {#AppName} al arrancar Windows
es.FirewallRule=Permitir {#AppName} en el Firewall de Windows (redes privadas)
es.FirewallNeedsAdmin=Requiere instalar para todos los usuarios
es.SensorsTask=Medir la temperatura del procesador (instala un servicio de Windows)
en.CreateDesktopIcon=Create a &desktop shortcut
en.StartWithWindows=Start {#AppName} when Windows starts
en.FirewallRule=Allow {#AppName} through Windows Firewall (private networks)
en.FirewallNeedsAdmin=Requires installing for all users
en.SensorsTask=Measure processor temperature (installs a Windows service)

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
Name: "startup";     Description: "{cm:StartWithWindows}";  GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
; Las reglas de firewall son de maquina: sin elevacion netsh no puede
; escribirlas. En instalacion por usuario la tarea se oculta y Windows
; muestra su propio dialogo la primera vez que la app abre el puerto.
Name: "firewall";    Description: "{cm:FirewallRule}";      GroupDescription: "{cm:AdditionalIcons}"; Check: IsAdminInstallMode
; Registrar un servicio de Windows es de maquina, igual que las reglas de
; firewall: por eso la casilla se oculta en instalacion por usuario. Ahi la
; temperatura del CPU no queda muerta: la app detecta que falta el servicio y
; ofrece instalarlo con un UAC unico (menu "Mas" -> "Temperatura del
; procesador", ver `sensor_helper.rs`).
Name: "sensors";     Description: "{cm:SensorsTask}";       GroupDescription: "{cm:AdditionalIcons}"; Check: IsAdminInstallMode

[Files]
; Todo el bundle de release: nexodeck.exe, flutter_windows.dll, los .dll de
; los plugins (incluido libnexodeck_ffi.dll que produce cargokit) y data\,
; que lleva el AOT snapshot y los assets.
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; El sidecar, en su propio subdirectorio para que no se mezcle con el
; bundle de Flutter. Se copia siempre y no solo con la casilla marcada: es
; justamente el .exe que la app lanza con `--install` cuando ofrece registrar
; el servicio despues, en una instalacion por usuario.
Source: "{#SensorsDir}\*"; DestDir: "{app}\sensors"; Flags: ignoreversion recursesubdirs createallsubdirs

; Nota: las DLLs del runtime de MSVC (msvcp140 / vcruntime140 / vcruntime140_1)
; entran por el comodin de arriba porque build_installer.ps1 las copia dentro
; de Release\ antes de compilar. Van app-local a proposito: asi el instalador
; no depende de que la PC destino tenga el VC++ Redistributable ni necesita
; elevacion para instalarlo.

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}";  Filename: "{app}\{#AppExeName}"; Tasks: desktopicon
Name: "{autostartup}\{#AppName}";  Filename: "{app}\{#AppExeName}"; Tasks: startup

[Run]
; Dos reglas y no una: el transporte WiFi escucha TCP en el puerto fijo, y el
; descubrimiento mDNS necesita UDP 5353. Solo perfiles private/domain — esto
; es una app de red local y no tiene por que quedar expuesta en una red publica.
Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall add rule name=""{#AppName} (TCP {#TransportPort})"" dir=in action=allow program=""{app}\{#AppExeName}"" protocol=TCP localport={#TransportPort} profile=private,domain enable=yes"; \
  Flags: runhidden; Tasks: firewall
Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall add rule name=""{#AppName} (mDNS UDP 5353)"" dir=in action=allow program=""{app}\{#AppExeName}"" protocol=UDP localport=5353 profile=private,domain enable=yes"; \
  Flags: runhidden; Tasks: firewall

; El sidecar se registra a si mismo como servicio de Windows. Antes esto
; creaba una tarea programada, y se cambio despues de pagarlo en vivo: una
; tarea solo corre con el usuario conectado, no se reinicia sola si el
; proceso muere, y `schtasks /run` no deja estado que la app pueda
; consultar para saber si el ayudante esta o no.
;
; El servicio corre como LocalSystem (que es lo que le permite cargar el
; driver), arranca con Windows y tiene politica de reintento ante fallo.
; El registro lo hace el propio .exe con --install, para que la app pueda
; usar EXACTAMENTE el mismo camino cuando lo ofrece con un UAC en una
; instalacion por usuario -- ver `sensor_helper.rs`.
Filename: "{app}\sensors\NexoDeckSensors.exe"; Parameters: "--install"; \
  Flags: runhidden; Tasks: sensors

Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; \
  Flags: nowait postinstall skipifsilent

[UninstallRun]
; Se borran por nombre y sin condicionar a la tarea: el desinstalador no sabe
; que se marco al instalar, y un netsh que no encuentra la regla es inocuo.
Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall delete rule name=""{#AppName} (TCP {#TransportPort})"""; \
  Flags: runhidden; RunOnceId: "DelFwTcp"; Check: IsAdminInstallMode
Filename: "{sys}\netsh.exe"; \
  Parameters: "advfirewall firewall delete rule name=""{#AppName} (mDNS UDP 5353)"""; \
  Flags: runhidden; RunOnceId: "DelFwUdp"; Check: IsAdminInstallMode
; Mismo criterio que las reglas de firewall: se quita siempre, y un
; --uninstall sobre un servicio que no existe es inocuo. Va ANTES de que
; [Files] borre el .exe, que es el orden en que Inno corre las secciones.
Filename: "{app}\sensors\NexoDeckSensors.exe"; Parameters: "--uninstall"; \
  Flags: runhidden; RunOnceId: "DelSensorsService"; Check: IsAdminInstallMode

[UninstallDelete]
; data\ y los .dll se van con [Files], pero el directorio queda si la app
; escribio algo adentro. Los datos del usuario (nexodeck.sqlite, el vault y
; el certificado) viven fuera de {app} y NO se tocan a proposito: desinstalar
; para actualizar no puede borrar el deck ni los emparejamientos.
Type: dirifempty; Name: "{app}"
