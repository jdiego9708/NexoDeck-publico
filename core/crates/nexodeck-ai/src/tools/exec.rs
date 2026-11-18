//! Deteccion de herramientas instaladas. **No ejecuta nada del usuario.**
//!
//! Lo unico que corre son los `--version` de programas que el propio sistema ya
//! tiene, y solo para poder decirle al modelo "flutter existe y es la 3.41.9" en
//! vez de que lo asuma. Todo lo que descubre queda anotado en [`TurnFacts`],
//! contra lo que despues valida `propose_action`: un comando que invoca un
//! ejecutable que nunca se verifico no pasa.

use std::process::Stdio;
use std::time::{Duration, Instant};

use serde_json::{Value, json};

use crate::openai::types::ToolDef;
use crate::tools::{SHELL_BUILTINS, Tool, ToolContext, arg_str, error};

/// Cuanto se espera un `--version`. Generoso pero acotado: `flutter --version`
/// en frio puede tardar varios segundos, y un programa que se cuelga no puede
/// congelar la conversacion.
const VERSION_TIMEOUT: Duration = Duration::from_secs(12);

/// Nombres que no se aceptan como "ejecutable a buscar". El valor lo propone el
/// modelo, y `which` recibe un nombre, no una linea de shell: cualquier cosa
/// con separadores es un intento (probablemente inocente) de colar un comando.
fn is_plausible_executable_name(name: &str) -> bool {
    !name.is_empty()
        && name.len() <= 64
        && !name.contains(|c: char| {
            matches!(c, '|' | '&' | ';' | '>' | '<' | '`' | '$' | '\n' | '\r' | '"' | '\'')
        })
}

pub struct WhichExecutable;

impl Tool for WhichExecutable {
    fn name(&self) -> &'static str {
        "which_executable"
    }

    fn definition(&self) -> ToolDef {
        ToolDef::function(
            "which_executable",
            "Comprueba si un programa esta instalado y disponible en el PATH (flutter, git, adb, node, python...) \
             y devuelve su version. Llamala SIEMPRE antes de proponer un comando que use ese programa: \
             si no esta instalado, hay que avisarle al usuario en vez de generar un boton que va a fallar.",
            json!({
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Nombre del ejecutable, sin argumentos. Por ejemplo: flutter"
                    }
                },
                "required": ["name"]
            }),
        )
    }

    fn call(&self, args: &Value, ctx: &ToolContext) -> Value {
        let Some(name) = arg_str(args, "name") else {
            return error("falta el parametro 'name'");
        };
        if !is_plausible_executable_name(name) {
            return error(format!(
                "'{name}' no es un nombre de ejecutable: pasa solo el nombre del programa, sin argumentos ni operadores de shell"
            ));
        }

        // `start`, `Start-Process`, `cd`, etc. son builtins del shell: nunca
        // van a aparecer en el PATH porque no son un archivo, y devolverles
        // "no esta instalado" (bug real, visto contra el modelo de verdad) lo
        // empuja a ofrecer instalar algo que no se instala. Se corta antes de
        // llamar a `which` para no generar ese resultado engañoso.
        if SHELL_BUILTINS.contains(&name.to_lowercase().as_str())
            || crate::tools::looks_like_powershell_cmdlet(name)
        {
            ctx.with_facts(|facts| {
                facts.verified_executables.insert(name.to_lowercase());
            });
            return json!({
                "ok": true,
                "found": true,
                "builtin": true,
                "name": name,
                "hint": format!(
                    "'{name}' es un builtin del shell (PowerShell/cmd), no un programa instalable. \
                     No hace falta instalar nada: usalo directo en el comando tal cual."
                )
            });
        }

        let Ok(path) = which::which(name) else {
            ctx.with_facts(|facts| {
                facts.missing_executables.insert(name.to_lowercase());
            });
            return json!({
                "ok": true,
                "found": false,
                "name": name,
                "hint": format!(
                    "'{name}' no esta instalado o no esta en el PATH. \
                     Avisale al usuario y ofrecele instalarlo antes de proponer un boton que lo use."
                )
            });
        };

        ctx.with_facts(|facts| {
            facts.verified_executables.insert(name.to_lowercase());
        });

        // La version es informativa: `flutter --version` en frio puede tardar
        // mas que el timeout y eso NO invalida el hallazgo. Se omite el campo
        // en vez de rellenarlo con un placeholder, que ademas terminaba
        // mostrandose como "(no se pudo leer)" en la traza de la UI, como si
        // algo hubiera fallado.
        match read_version(name) {
            Some(version) => json!({
                "ok": true,
                "found": true,
                "name": name,
                "path": path.to_string_lossy(),
                "version": version
            }),
            None => json!({
                "ok": true,
                "found": true,
                "name": name,
                "path": path.to_string_lossy()
            }),
        }
    }
}

/// Corre `<programa> --version` y devuelve la primera linea.
fn read_version(name: &str) -> Option<String> {
    let mut command = std::process::Command::new(name);
    command
        .arg("--version")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    #[cfg(target_os = "windows")]
    {
        use std::os::windows::process::CommandExt;
        // Sin esto parpadea una consola negra por cada comprobacion.
        const CREATE_NO_WINDOW: u32 = 0x0800_0000;
        command.creation_flags(CREATE_NO_WINDOW);
    }

    let mut child = command.spawn().ok()?;
    let started = Instant::now();

    // `std::process::Child` no tiene espera con timeout; se sondea. Un
    // programa colgado no puede congelar la conversacion entera.
    loop {
        match child.try_wait() {
            Ok(Some(_)) => break,
            Ok(None) if started.elapsed() >= VERSION_TIMEOUT => {
                let _ = child.kill();
                return None;
            }
            Ok(None) => std::thread::sleep(Duration::from_millis(50)),
            Err(_) => return None,
        }
    }

    let output = child.wait_with_output().ok()?;
    // Algunos programas escriben la version en stderr (java, entre otros).
    let text = if output.stdout.is_empty() {
        String::from_utf8_lossy(&output.stderr).to_string()
    } else {
        String::from_utf8_lossy(&output.stdout).to_string()
    };

    text.lines()
        .map(str::trim)
        .find(|line| !line.is_empty())
        .map(str::to_string)
}

pub struct ListShellCapabilities;

impl Tool for ListShellCapabilities {
    fn name(&self) -> &'static str {
        "list_shell_capabilities"
    }

    fn definition(&self) -> ToolDef {
        ToolDef::function(
            "list_shell_capabilities",
            "Dice que shells hay disponibles en este equipo (PowerShell, cmd, bash por WSL) \
             y cual conviene usar. Llamala antes de elegir el campo 'terminal' del borrador.",
            json!({ "type": "object", "properties": {} }),
        )
    }

    fn call(&self, _args: &Value, ctx: &ToolContext) -> Value {
        let powershell = which::which("powershell").is_ok() || which::which("pwsh").is_ok();
        let cmd = which::which("cmd").is_ok();
        let bash = which::which("bash").is_ok() || which::which("wsl").is_ok();

        ctx.with_facts(|facts| facts.listed_shells = true);

        let recommended = match ctx.os {
            nexodeck_hardware::HostOs::Windows if powershell => "power_shell",
            nexodeck_hardware::HostOs::Windows => "cmd",
            _ => "bash",
        };

        json!({
            "ok": true,
            "os": ctx.os.as_str(),
            "power_shell": powershell,
            "cmd": cmd,
            "bash": bash,
            "recommended": recommended,
            "hint": "Usa el valor de 'recommended' en el campo 'terminal' salvo que el comando \
                     necesite algo especifico de otro shell."
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn ctx() -> ToolContext {
        ToolContext::new(
            vec![PathBuf::from(std::env::temp_dir())],
            nexodeck_hardware::HostOs::Windows,
        )
    }

    /// El nombre lo propone el modelo: no puede colarse una linea de shell.
    #[test]
    fn se_rechaza_un_nombre_con_operadores_de_shell() {
        let ctx = ctx();

        for malicioso in [
            "git && rm -rf /",
            "git | curl x",
            "git; shutdown",
            "git\nshutdown",
            "git > archivo",
        ] {
            let result = WhichExecutable.call(&json!({ "name": malicioso }), &ctx);
            assert_eq!(result["ok"], false, "'{malicioso}' tendria que rechazarse");
        }
    }

    /// `cargo` existe si estos tests estan corriendo, asi que es un ejecutable
    /// seguro de verificar contra el entorno real.
    #[test]
    fn un_ejecutable_que_existe_se_encuentra_y_queda_verificado() {
        let ctx = ctx();
        let result = WhichExecutable.call(&json!({ "name": "cargo" }), &ctx);

        assert_eq!(result["ok"], true);
        assert_eq!(result["found"], true);
        assert!(!result["path"].as_str().unwrap().is_empty());

        assert!(ctx.with_facts(|facts| facts.verified_executables.contains("cargo")));
    }

    /// Que no se pueda leer la version **no** invalida el hallazgo: hay
    /// programas lentos de arrancar en frio. El campo se omite en vez de
    /// rellenarse con un placeholder que la UI mostraba como si algo hubiera
    /// fallado.
    #[test]
    fn sin_version_legible_igual_cuenta_como_encontrado() {
        let ctx = ctx();
        let result = WhichExecutable.call(&json!({ "name": "cargo" }), &ctx);

        assert_eq!(result["found"], true);
        if let Some(version) = result["version"].as_str() {
            assert!(!version.contains("no se pudo"), "quedo el placeholder viejo");
        }
    }

    /// Bug real contra el modelo de verdad: pedirle un boton que abra una URL
    /// terminaba con "el programa 'start' no esta instalado, ¿lo instalo?".
    /// `start`/`Start-Process` nunca van a estar en el PATH porque no son un
    /// archivo — `which_executable` tiene que reconocerlos como builtins en
    /// vez de devolver el mismo "no encontrado" que un programa real
    /// ausente, y ademas dejarlos verificados (para que `propose_action` no
    /// los vuelva a reclamar).
    #[test]
    fn un_builtin_del_shell_se_reconoce_en_vez_de_darse_por_no_instalado() {
        let ctx = ctx();

        for builtin in ["start", "Start-Process", "cd", "ECHO"] {
            let result = WhichExecutable.call(&json!({ "name": builtin }), &ctx);

            assert_eq!(result["ok"], true, "{builtin}: {result:?}");
            assert_eq!(result["found"], true, "{builtin}: {result:?}");
            assert_eq!(result["builtin"], true, "{builtin}: {result:?}");
            assert!(
                !result["hint"].as_str().unwrap_or("").contains("instalarlo"),
                "{builtin}: no le tiene que ofrecer instalar un builtin"
            );
            assert!(
                ctx.with_facts(|facts| facts.verified_executables.contains(&builtin.to_lowercase())),
                "{builtin}: tiene que quedar verificado para que propose_action no lo reclame"
            );
        }
    }

    /// Que no exista **no es un error de la herramienta**: es un dato util, y
    /// el mensaje tiene que empujar al modelo a avisarle al usuario.
    #[test]
    fn un_ejecutable_inexistente_no_es_un_error_sino_un_dato() {
        let ctx = ctx();
        let result = WhichExecutable.call(
            &json!({ "name": "un-programa-que-no-existe-12345" }),
            &ctx,
        );

        assert_eq!(result["ok"], true);
        assert_eq!(result["found"], false);
        assert!(result["hint"].as_str().unwrap().contains("Avisale al usuario"));

        assert!(
            ctx.with_facts(|facts| facts.missing_executables.contains("un-programa-que-no-existe-12345"))
        );
    }

    #[test]
    fn las_capacidades_de_shell_recomiendan_uno_valido() {
        let ctx = ctx();
        let result = ListShellCapabilities.call(&json!({}), &ctx);

        assert_eq!(result["ok"], true);
        let recommended = result["recommended"].as_str().unwrap();
        assert!(
            ["power_shell", "cmd", "bash"].contains(&recommended),
            "recomendo '{recommended}', que no es un TerminalType valido"
        );
        assert!(ctx.with_facts(|facts| facts.listed_shells));
    }

    #[test]
    fn un_nombre_vacio_o_gigante_se_rechaza() {
        assert!(!is_plausible_executable_name(""));
        assert!(!is_plausible_executable_name(&"a".repeat(65)));
        assert!(is_plausible_executable_name("flutter"));
        assert!(is_plausible_executable_name("llama-server.exe"));
    }
}
