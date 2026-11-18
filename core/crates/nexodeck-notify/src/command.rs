//! El canal de tipo **comando**: mandar un aviso es ejecutar un programa.
//!
//! ## Por que el mensaje NUNCA se interpola en una linea de shell
//!
//! El aviso acaba viajando por `ssh` y por `docker exec`, o sea por dos
//! interpretes de shell encadenados. `avisar.sh` resuelve su mitad mandando el
//! texto en base64 justamente porque un acento, una comilla o un `$` en el
//! mensaje se comerian el resto de la orden.
//!
//! Aca la mitad de NexoDeck se resuelve antes y mejor: el texto viaja **como un
//! elemento de `argv` entero**, o por **stdin**. En los dos casos ningun shell
//! lo llega a parsear, asi que no hay nada que escapar y no hay forma de que un
//! mensaje se convierta en una orden.
//!
//! La configuracion correcta pone el marcador **solo** como argumento suelto y
//! deja que el script lo lea de su parametro posicional. Escribir el marcador
//! dentro de un argumento mas grande, entre comillas de shell, **funciona hasta
//! el primer mensaje con comillas** y despues rompe en silencio. Por eso el
//! canal recomendado de esta maquina usa [`MessageDelivery::Stdin`], que no
//! deja lugar a la duda: `avisar.sh` ya acepta `-` para leer de stdin.

use std::process::Stdio;
use std::time::Instant;

use serde::{Deserialize, Serialize};
use tokio::io::AsyncWriteExt;

use crate::{NotifyLevel, NotifyOutcome, NotifyRequest};

/// Marcador que se sustituye por el texto del aviso, elemento a elemento.
pub const MESSAGE_PLACEHOLDER: &str = "{{message}}";

/// Cuanto se espera a que el comando entregue antes de darlo por perdido.
/// `avisar.sh` ya usa `ConnectTimeout=25` para el `ssh`, asi que el techo de
/// aca tiene que ser comodamente mayor o cortariamos justo el caso lento que
/// todavia iba a funcionar.
const DEFAULT_TIMEOUT_SECS: u32 = 45;

/// Cuanto texto del comando se guarda como detalle del fallo. Suficiente para
/// leer el motivo, poco para no llenar la UI.
const MAX_DETAIL_BYTES: usize = 2000;

/// Por donde recibe el texto el programa del canal.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MessageDelivery {
    /// Sustituyendo [`MESSAGE_PLACEHOLDER`] en los argumentos.
    Argv,
    /// Escribiendolo en la entrada estandar y cerrandola. Es la via sin
    /// ambiguedad posible, y la recomendada.
    Stdin,
}

impl Default for MessageDelivery {
    fn default() -> Self {
        MessageDelivery::Argv
    }
}

/// Un canal de aviso configurado.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CommandChannel {
    pub id: String,
    pub label: String,
    pub program: String,
    #[serde(default)]
    pub args: Vec<String>,
    #[serde(default)]
    pub delivery: MessageDelivery,
    /// Nivel minimo que este canal acepta. Con `Always`, el canal solo recibe
    /// lo critico: sirve para tener un destino ruidoso y otro que solo suena
    /// cuando algo se rompio.
    #[serde(default)]
    pub min_level: NotifyLevel,
    #[serde(default)]
    pub timeout_secs: Option<u32>,
    #[serde(default = "default_true")]
    pub enabled: bool,
}

fn default_true() -> bool {
    true
}

impl CommandChannel {
    /// Los argumentos ya con el texto puesto. Publico porque es lo que el
    /// ensayo en seco le ensena al usuario, y lo que se testea directo.
    pub fn rendered_args(&self, text: &str) -> Vec<String> {
        match self.delivery {
            MessageDelivery::Stdin => self.args.clone(),
            MessageDelivery::Argv => self
                .args
                .iter()
                .map(|arg| arg.replace(MESSAGE_PLACEHOLDER, text))
                .collect(),
        }
    }

    fn timeout(&self) -> std::time::Duration {
        let secs = self.timeout_secs.unwrap_or(DEFAULT_TIMEOUT_SECS).max(1);
        std::time::Duration::from_secs(u64::from(secs))
    }

    fn skip(&self, request: &NotifyRequest, detail: &str) -> NotifyOutcome {
        NotifyOutcome {
            channel_id: self.id.clone(),
            delivered: false,
            exit_code: None,
            detail: detail.to_string(),
            elapsed_ms: 0,
            skipped: true,
            dry_run: request.dry_run,
        }
    }

    pub(crate) async fn send(&self, request: &NotifyRequest) -> NotifyOutcome {
        if !self.enabled {
            return self.skip(request, "canal desactivado");
        }
        // `Always` pasa siempre; `Milestone` solo si el canal lo acepta.
        if request.level < self.min_level {
            return self.skip(request, "el canal solo acepta avisos criticos");
        }

        let args = self.rendered_args(&request.text);

        if request.dry_run {
            return NotifyOutcome {
                channel_id: self.id.clone(),
                delivered: false,
                exit_code: None,
                detail: describe_invocation(&self.program, &args, self.delivery),
                elapsed_ms: 0,
                skipped: false,
                dry_run: true,
            };
        }

        let started = Instant::now();
        let result = self.run(&args, &request.text).await;
        let elapsed_ms = started.elapsed().as_millis().min(u128::from(u32::MAX)) as u32;

        match result {
            Ok(delivery) => NotifyOutcome {
                channel_id: self.id.clone(),
                delivered: delivery.code == Some(0),
                exit_code: delivery.code,
                detail: delivery.detail,
                elapsed_ms,
                skipped: false,
                dry_run: false,
            },
            Err(detail) => NotifyOutcome {
                channel_id: self.id.clone(),
                delivered: false,
                exit_code: None,
                detail,
                elapsed_ms,
                skipped: false,
                dry_run: false,
            },
        }
    }

    async fn run(&self, args: &[String], text: &str) -> Result<Delivery, String> {
        let uses_stdin = self.delivery == MessageDelivery::Stdin;

        let mut command = tokio::process::Command::new(&self.program);
        command
            .args(args)
            .stdin(if uses_stdin {
                Stdio::piped()
            } else {
                // Nunca heredada: un canal es un comando no interactivo, y con
                // la entrada del proceso padre se colgaria esperando a nadie.
                Stdio::null()
            })
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());

        // Sin esto, cada aviso hace parpadear una consola encima de lo que el
        // usuario este haciendo. Un aviso tiene que ser invisible.
        // `tokio::process::Command` expone `creation_flags` el mismo, sin el
        // trait `CommandExt` que si necesita la version sincrona de `kill_tree`.
        #[cfg(target_os = "windows")]
        {
            const CREATE_NO_WINDOW: u32 = 0x0800_0000;
            command.creation_flags(CREATE_NO_WINDOW);
        }

        let mut child = command
            .spawn()
            .map_err(|e| format!("no se pudo lanzar {}: {e}", self.program))?;

        // El pid se guarda **antes** de consumir el hijo: `wait_with_output` se
        // lo lleva, y si hay que matar el arbol por timeout ya no habria de
        // donde sacarlo.
        let pid = child.id();

        if uses_stdin {
            if let Some(mut stdin) = child.stdin.take() {
                // El fallo de escritura no se propaga: si el programa ya cerro
                // su entrada, lo que importa es el codigo de salida que dara a
                // continuacion, no este error intermedio.
                let _ = stdin.write_all(text.as_bytes()).await;
                let _ = stdin.write_all(b"\n").await;
                let _ = stdin.shutdown().await;
            }
        }

        match tokio::time::timeout(self.timeout(), child.wait_with_output()).await {
            Ok(Ok(output)) => {
                let code = output.status.code();
                let detail = if code == Some(0) {
                    String::new()
                } else {
                    detail_from_output(&output.stderr, &output.stdout, code)
                };
                Ok(Delivery { code, detail })
            }
            Ok(Err(e)) => Err(format!("fallo esperando a {}: {e}", self.program)),
            Err(_) => {
                // Matar solo al hijo no alcanza: el arbol real es
                // bash -> ssh, y en Windows matar al padre deja al nieto vivo
                // ocupando la conexion. Mismo motivo que el `taskkill /T` de
                // `runner.rs`.
                if let Some(pid) = pid {
                    kill_tree(pid);
                }
                Err(format!(
                    "el canal no respondio en {} s",
                    self.timeout().as_secs()
                ))
            }
        }
    }
}

struct Delivery {
    code: Option<i32>,
    detail: String,
}

/// Compone el detalle de un fallo a partir de lo que dijo el comando.
///
/// `from_utf8_lossy` sobre el buffer entero, nunca `BufReader::lines()`: ese
/// exige UTF-8 valido y devuelve `Err(InvalidData)` en el primer byte que no lo
/// sea, lo que corta la lectura en silencio. En Windows la consola entrega
/// cp850/cp1252 y la primera tilde de un mensaje en espanol bastaria. Ver
/// `LineSplitter` en `nexodeck-actions/src/runner.rs`.
///
/// Aca alcanza con decodificar el buffer completo porque el canal no emite en
/// vivo: se espera a que el comando termine y recien entonces se lee.
fn detail_from_output(stderr: &[u8], stdout: &[u8], code: Option<i32>) -> String {
    let mut detail = String::from_utf8_lossy(stderr).trim().to_string();
    if detail.is_empty() {
        detail = String::from_utf8_lossy(stdout).trim().to_string();
    }
    if detail.is_empty() {
        detail = format!("el comando termino con codigo {}", code_text(code));
    }
    truncate_detail(detail)
}

fn code_text(code: Option<i32>) -> String {
    code.map(|c| c.to_string())
        .unwrap_or_else(|| "desconocido (terminado por senal)".to_string())
}

fn truncate_detail(detail: String) -> String {
    if detail.len() <= MAX_DETAIL_BYTES {
        return detail;
    }
    // Se corta por el principio: lo que explica un fallo casi siempre esta al
    // final de la salida.
    let mut start = detail.len() - MAX_DETAIL_BYTES;
    while start < detail.len() && !detail.is_char_boundary(start) {
        start += 1;
    }
    format!("[...] {}", &detail[start..])
}

/// Lo que el ensayo en seco muestra: exactamente que se iba a ejecutar.
fn describe_invocation(program: &str, args: &[String], delivery: MessageDelivery) -> String {
    let mut parts = vec![program.to_string()];
    parts.extend(args.iter().map(|arg| {
        if arg.contains(' ') {
            format!("\"{arg}\"")
        } else {
            arg.clone()
        }
    }));
    let line = parts.join(" ");
    match delivery {
        MessageDelivery::Stdin => format!("{line}   [el texto va por stdin]"),
        MessageDelivery::Argv => line,
    }
}

/// Mata el proceso y su descendencia. Calcado de `kill_tree` en
/// `nexodeck-actions/src/runner.rs`, y por el mismo motivo.
#[cfg(target_os = "windows")]
fn kill_tree(pid: u32) {
    use std::os::windows::process::CommandExt;
    const CREATE_NO_WINDOW: u32 = 0x0800_0000;
    let _ = std::process::Command::new("taskkill")
        .args(["/T", "/F", "/PID", &pid.to_string()])
        .creation_flags(CREATE_NO_WINDOW)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

#[cfg(not(target_os = "windows"))]
fn kill_tree(pid: u32) {
    let _ = std::process::Command::new("kill")
        .args(["-9", &pid.to_string()])
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn();
}

#[cfg(test)]
mod tests {
    use super::*;

    fn channel() -> CommandChannel {
        CommandChannel {
            id: "wa".into(),
            label: "WhatsApp".into(),
            program: "bash".into(),
            args: vec!["-lc".into(), "avisar \"$1\"".into(), "nexodeck".into(), MESSAGE_PLACEHOLDER.into()],
            delivery: MessageDelivery::Argv,
            min_level: NotifyLevel::Milestone,
            timeout_secs: None,
            enabled: true,
        }
    }

    /// El texto entra como **un** elemento de argv, sin tocar los demas. Es la
    /// propiedad que hace innecesario escapar nada.
    #[test]
    fn message_lands_in_its_own_argv_slot() {
        let args = channel().rendered_args("tanda K: 42% \"listo\" $HOME; rm -rf /");
        assert_eq!(args.len(), 4);
        assert_eq!(args[1], "avisar \"$1\"");
        assert_eq!(args[3], "tanda K: 42% \"listo\" $HOME; rm -rf /");
    }

    #[test]
    fn stdin_delivery_leaves_args_untouched() {
        let mut ch = channel();
        ch.delivery = MessageDelivery::Stdin;
        ch.args = vec!["-lc".into(), "avisar -".into()];
        assert_eq!(ch.rendered_args("lo que sea"), ch.args);
    }

    #[tokio::test]
    async fn dry_run_reports_the_invocation_without_running_anything() {
        // El programa no existe: si el ensayo en seco lo ejecutara, el
        // resultado seria un fallo de spawn en vez de la descripcion.
        let mut ch = channel();
        ch.program = "no-existe-este-programa".into();

        let outcome = ch
            .send(&NotifyRequest {
                text: "hola".into(),
                level: NotifyLevel::Milestone,
                dry_run: true,
            })
            .await;

        assert!(outcome.dry_run);
        assert!(!outcome.skipped);
        assert!(outcome.detail.contains("no-existe-este-programa"));
        assert!(outcome.detail.contains("hola"));
    }

    #[tokio::test]
    async fn a_channel_that_only_takes_critical_skips_a_milestone() {
        let mut ch = channel();
        ch.min_level = NotifyLevel::Always;

        let skipped = ch
            .send(&NotifyRequest {
                text: "hito".into(),
                level: NotifyLevel::Milestone,
                dry_run: true,
            })
            .await;
        assert!(skipped.skipped);
        assert!(!skipped.is_failure());

        let taken = ch
            .send(&NotifyRequest {
                text: "disco lleno".into(),
                level: NotifyLevel::Always,
                dry_run: true,
            })
            .await;
        assert!(!taken.skipped);
    }

    /// Un programa que no existe tiene que salir como fallo **con motivo**, no
    /// como entregado ni como un panic. Es el caso que mas veces se va a dar en
    /// una maquina recien configurada.
    #[tokio::test]
    async fn a_missing_program_fails_loudly() {
        let mut ch = channel();
        ch.program = "no-existe-este-programa".into();

        let outcome = ch
            .send(&NotifyRequest {
                text: "hola".into(),
                level: NotifyLevel::Always,
                dry_run: false,
            })
            .await;

        assert!(outcome.is_failure());
        assert!(!outcome.delivered);
        assert!(outcome.detail.contains("no se pudo lanzar"));
    }

    #[test]
    fn long_details_keep_the_end_which_is_where_the_reason_is() {
        let detail = truncate_detail(format!("{}FINAL", "x".repeat(MAX_DETAIL_BYTES * 2)));
        assert!(detail.starts_with("[...]"));
        assert!(detail.ends_with("FINAL"));
    }

    #[test]
    fn truncation_never_splits_a_multibyte_character() {
        let detail = truncate_detail("ñ".repeat(MAX_DETAIL_BYTES));
        assert!(detail.starts_with("[...]"));
    }
}
