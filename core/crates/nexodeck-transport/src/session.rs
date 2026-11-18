use nexodeck_protocol::MessageV1;

use crate::error::Result;

/// Abstrae "un `MessageV1` adentro, un `MessageV1` afuera" sobre cualquier
/// transporte -- implementado una vez por WebSocket (`WsSession`, envolviendo
/// `wire::send_message`/`recv_message`) y, en Fase 5, una vez por USB
/// (`usb::session::UsbSession`). Se usa siempre de forma generica
/// (monomorfizada) en `server.rs`/`client.rs`, nunca como `dyn`, asi que
/// `async fn` en el trait no necesita boxing (RPITIT, estable desde 1.75;
/// el workspace fija `rust-version = "1.90"`).
pub(crate) trait SessionTransport: Send {
    async fn send(&mut self, msg: &MessageV1) -> Result<()>;
    async fn recv(&mut self) -> Result<Option<MessageV1>>;
}

pub(crate) struct WsSession<S>(pub tokio_tungstenite::WebSocketStream<S>);

impl<S> SessionTransport for WsSession<S>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send,
{
    async fn send(&mut self, msg: &MessageV1) -> Result<()> {
        crate::wire::send_message(&mut self.0, msg).await
    }

    async fn recv(&mut self) -> Result<Option<MessageV1>> {
        crate::wire::recv_message(&mut self.0).await
    }
}
