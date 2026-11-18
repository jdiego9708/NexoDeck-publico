//! Cliente del relay: como las dos puntas llegan al punto de encuentro.
//!
//! El relay (`nexodeck-relay`, que corre en un VPS) es un empalmador de
//! bytes: la PC se aparca y espera, el telefono llega con el mismo token y a
//! partir de ahi el canal es transparente. Este modulo solo se ocupa del
//! saludo; una vez emparejado, el `TcpStream` que devuelve se trata
//! **exactamente igual que uno de la LAN** -- mismo TLS, mismo pinning,
//! mismo WebSocket, misma sesion.
//!
//! Que el stream final siga siendo un `TcpStream` no es casualidad: es lo
//! que permite que `server.rs` y `client.rs` reusen su camino de siempre sin
//! volverse genericos ni duplicar el manejo de sesion.

use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::TcpStream;

use nexodeck_relay::hello::{self, status, Role, TOKEN_LEN};

use crate::error::{Result, TransportError};

/// Traduce el byte de estado a un error que le sirva a quien lo lee.
///
/// Los mensajes van en espanol y son concretos porque terminan a la vista
/// del usuario: "no se pudo conectar" no le dice si el problema es que la PC
/// esta apagada, que el token no sirve o que el relay es de otra version.
fn error_de_estado(byte: u8) -> TransportError {
    let detalle = match byte {
        status::ERR_NO_HOST => "la PC no esta conectada al tunel".to_string(),
        status::ERR_HOST_TAKEN => {
            "ya hay otra instancia de NexoDeck usando este tunel".to_string()
        }
        status::ERR_TOKEN_REJECTED => {
            "el relay no acepta este token; hay que autorizarlo alla".to_string()
        }
        status::ERR_BAD_HELLO => {
            "el relay no entendio el saludo; probablemente sea de otra version".to_string()
        }
        otro => format!("respuesta desconocida del relay: {otro:#04x}"),
    };
    TransportError::Protocol(detalle)
}

async fn leer_byte<S: AsyncRead + Unpin>(stream: &mut S) -> Result<u8> {
    let mut b = [0u8; 1];
    stream.read_exact(&mut b).await?;
    Ok(b[0])
}

/// Rol PC: se presenta y queda registrado. Vuelve apenas el relay confirma,
/// **sin esperar** a que llegue ningun telefono.
///
/// La division en dos pasos existe para la UI: "aparcado en el tunel" es un
/// estado que el usuario tiene que poder ver, y si esta funcion esperara al
/// cliente no habria forma de distinguirlo de "el relay no contesta".
pub(crate) async fn saludar_como_host<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
    token: &[u8; TOKEN_LEN],
) -> Result<()> {
    stream.write_all(&hello::encode(Role::Host, token)).await?;
    match leer_byte(stream).await? {
        status::REGISTERED => Ok(()),
        otro => Err(error_de_estado(otro)),
    }
}

/// Rol PC, segundo paso: espera a que un telefono llame.
///
/// **Descarta los keepalives**, y esto es obligatorio: el relay los manda
/// para que el NAT no tire la conexion mientras la PC espera (puede ser
/// horas). Si el TLS arrancara antes de ver `HOST_MATCHED`, un keepalive
/// entraria como si fuera parte del handshake y lo romperia.
pub(crate) async fn esperar_cliente<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
) -> Result<()> {
    loop {
        match leer_byte(stream).await? {
            status::KEEPALIVE => continue,
            status::HOST_MATCHED => return Ok(()),
            otro => return Err(error_de_estado(otro)),
        }
    }
}

/// Rol telefono: se presenta y espera el empalme, que es inmediato si la PC
/// ya estaba aparcada.
pub(crate) async fn saludar_como_cliente<S: AsyncRead + AsyncWrite + Unpin>(
    stream: &mut S,
    token: &[u8; TOKEN_LEN],
) -> Result<()> {
    stream.write_all(&hello::encode(Role::Client, token)).await?;
    match leer_byte(stream).await? {
        status::MATCHED => Ok(()),
        otro => Err(error_de_estado(otro)),
    }
}

/// Abre el TCP contra el relay. Comun a los dos roles.
pub(crate) async fn conectar(host: &str, port: u16) -> Result<TcpStream> {
    Ok(TcpStream::connect(format!("{host}:{port}")).await?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::duplex;

    /// Se prueba contra un relay de mentira sobre `duplex` y no contra el de
    /// verdad porque lo que hay que fijar aca es el CONTRATO de bytes: que
    /// el saludo salga bien formado y que cada respuesta se interprete como
    /// corresponde. El relay real ya tiene sus propias pruebas sobre
    /// sockets.
    #[tokio::test]
    async fn el_host_manda_un_saludo_bien_formado() {
        let (mut mio, mut relay) = duplex(256);
        let token = [3u8; TOKEN_LEN];

        let tarea = tokio::spawn(async move { saludar_como_host(&mut mio, &token).await });

        let mut buf = [0u8; hello::HELLO_LEN];
        relay.read_exact(&mut buf).await.unwrap();
        assert_eq!(hello::decode(&buf).unwrap(), (Role::Host, token));

        relay.write_all(&[status::REGISTERED]).await.unwrap();
        tarea.await.unwrap().unwrap();
    }

    #[tokio::test]
    async fn el_cliente_manda_su_rol_y_acepta_el_empalme() {
        let (mut mio, mut relay) = duplex(256);
        let token = [9u8; TOKEN_LEN];

        let tarea = tokio::spawn(async move { saludar_como_cliente(&mut mio, &token).await });

        let mut buf = [0u8; hello::HELLO_LEN];
        relay.read_exact(&mut buf).await.unwrap();
        assert_eq!(hello::decode(&buf).unwrap(), (Role::Client, token));

        relay.write_all(&[status::MATCHED]).await.unwrap();
        tarea.await.unwrap().unwrap();
    }

    /// El contrato critico: los keepalives se descartan y solo `HOST_MATCHED`
    /// libera el paso. Sin esto el TLS arrancaria sobre un byte de relleno.
    #[tokio::test]
    async fn el_host_descarta_keepalives_hasta_el_aviso() {
        let (mut mio, mut relay) = duplex(256);

        let tarea = tokio::spawn(async move { esperar_cliente(&mut mio).await });

        for _ in 0..5 {
            relay.write_all(&[status::KEEPALIVE]).await.unwrap();
        }
        relay.write_all(&[status::HOST_MATCHED]).await.unwrap();

        tarea.await.unwrap().unwrap();
    }

    #[tokio::test]
    async fn cada_rechazo_dice_algo_distinto_y_util() {
        let casos = [
            (status::ERR_NO_HOST, "no esta conectada"),
            (status::ERR_HOST_TAKEN, "otra instancia"),
            (status::ERR_TOKEN_REJECTED, "token"),
            (status::ERR_BAD_HELLO, "version"),
        ];
        for (byte, esperado) in casos {
            let (mut mio, mut relay) = duplex(256);
            let tarea =
                tokio::spawn(async move { saludar_como_cliente(&mut mio, &[0u8; TOKEN_LEN]).await });
            let mut buf = [0u8; hello::HELLO_LEN];
            relay.read_exact(&mut buf).await.unwrap();
            relay.write_all(&[byte]).await.unwrap();

            let err = tarea.await.unwrap().unwrap_err().to_string();
            assert!(
                err.contains(esperado),
                "{byte:#04x} deberia mencionar {esperado:?}, dijo {err:?}"
            );
        }
    }

    /// Si el relay corta sin decir nada, tiene que salir un error de io y no
    /// un cuelgue: es lo que pasa cuando el VPS se reinicia.
    #[tokio::test]
    async fn un_corte_seco_no_deja_esperando() {
        let (mut mio, relay) = duplex(256);
        drop(relay);
        let err = esperar_cliente(&mut mio).await.unwrap_err();
        assert!(matches!(err, TransportError::Io(_)), "fue {err:?}");
    }
}
