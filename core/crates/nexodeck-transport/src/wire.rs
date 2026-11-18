use futures_util::{SinkExt, StreamExt};
use nexodeck_protocol::{MessageV1, NexoDeckMessage};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio_tungstenite::WebSocketStream;
use tokio_tungstenite::tungstenite::Message as WsMessage;

use crate::error::{Result, TransportError};

pub async fn send_message<S>(ws: &mut WebSocketStream<S>, msg: &MessageV1) -> Result<()>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    let wrapped = NexoDeckMessage::V1(msg.clone());
    let bytes =
        postcard::to_allocvec(&wrapped).map_err(|e| TransportError::Protocol(e.to_string()))?;
    ws.send(WsMessage::Binary(bytes.into())).await?;
    Ok(())
}

/// `Ok(None)` significa que la conexion se cerro limpiamente (o el frame no
/// era uno de los que nos interesan y el stream terminó mientras tanto).
pub async fn recv_message<S>(ws: &mut WebSocketStream<S>) -> Result<Option<MessageV1>>
where
    S: AsyncRead + AsyncWrite + Unpin,
{
    loop {
        match ws.next().await {
            None => return Ok(None),
            Some(Ok(WsMessage::Binary(bytes))) => {
                let NexoDeckMessage::V1(msg) = postcard::from_bytes(&bytes)
                    .map_err(|e| TransportError::Protocol(e.to_string()))?;
                return Ok(Some(msg));
            }
            Some(Ok(WsMessage::Close(_))) => return Ok(None),
            Some(Ok(_)) => continue,
            Some(Err(e)) => return Err(e.into()),
        }
    }
}
