use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};

use nexodeck_protocol::{MessageV1, NexoDeckMessage};

use crate::error::{Result, TransportError};

/// Cota defensiva contra un length-prefix corrupto/hostil -- el mensaje mas
/// grande real hoy (el catalogo de acciones) esta muy por debajo de esto.
const MAX_MESSAGE_BYTES: u32 = 16 * 1024 * 1024;

/// Framing de mensajes sobre un canal de bytes crudo (length-prefix de 4
/// bytes LE + postcard) -- a diferencia de `wire::send_message`/`recv_message`
/// (que dependen del framing propio de WebSocket), esto sirve para
/// cualquier `AsyncRead + AsyncWrite`, en particular el puente bulk-USB
/// (Fase 5-C) y el `tokio::fs::File` que envuelve el fd crudo del lado
/// Android (Fase 5-D). `read_exact` ya resuelve la acumulacion de bytes
/// fragmentados entre transfers bulk, no hace falta un buffer acumulador
/// hecho a mano.
pub(crate) struct FramedUsb<S> {
    inner: S,
}

impl<S: AsyncRead + AsyncWrite + Unpin> FramedUsb<S> {
    pub(crate) fn new(inner: S) -> Self {
        Self { inner }
    }

    pub(crate) async fn send_message(&mut self, msg: &MessageV1) -> Result<()> {
        let wrapped = NexoDeckMessage::V1(msg.clone());
        let bytes =
            postcard::to_allocvec(&wrapped).map_err(|e| TransportError::Protocol(e.to_string()))?;
        let len = u32::try_from(bytes.len())
            .map_err(|_| TransportError::Protocol("mensaje demasiado grande".into()))?;
        self.inner.write_all(&len.to_le_bytes()).await?;
        self.inner.write_all(&bytes).await?;
        self.inner.flush().await?;
        Ok(())
    }

    /// `Ok(None)` = EOF limpio (cable desconectado / fd cerrado del otro
    /// lado) -- mismo contrato que `wire::recv_message`.
    pub(crate) async fn recv_message(&mut self) -> Result<Option<MessageV1>> {
        let mut len_buf = [0u8; 4];
        if let Err(e) = self.inner.read_exact(&mut len_buf).await {
            return match e.kind() {
                std::io::ErrorKind::UnexpectedEof => Ok(None),
                _ => Err(e.into()),
            };
        }
        let len = u32::from_le_bytes(len_buf);
        if len > MAX_MESSAGE_BYTES {
            return Err(TransportError::Protocol(format!(
                "mensaje USB de {len} bytes excede el maximo"
            )));
        }
        let mut body = vec![0u8; len as usize];
        self.inner.read_exact(&mut body).await?;
        let NexoDeckMessage::V1(msg) =
            postcard::from_bytes(&body).map_err(|e| TransportError::Protocol(e.to_string()))?;
        Ok(Some(msg))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_message() -> MessageV1 {
        MessageV1::PairHello {
            device_name: "TestAndroid".into(),
            platform: nexodeck_protocol::DevicePlatformWire::Android,
        }
    }

    #[tokio::test]
    async fn roundtrip_single_write() {
        // Buffer grande de sobra: todo el mensaje entra en un solo write,
        // sin fragmentacion -- caso base.
        let (client, server) = tokio::io::duplex(64 * 1024);
        let mut writer = FramedUsb::new(client);
        let mut reader = FramedUsb::new(server);

        let msg = sample_message();
        writer.send_message(&msg).await.expect("send_message");
        let received = reader
            .recv_message()
            .await
            .expect("recv_message")
            .expect("no deberia ser EOF");
        assert_eq!(received, msg);
    }

    #[tokio::test]
    async fn roundtrip_fragmented_across_small_chunks() {
        // Buffer minusculo fuerza que `duplex` entregue el mensaje en varios
        // chunks pequenos -- emula el tamano maximo de paquete de un bulk
        // transfer USB real. `read_exact` debe acumular correctamente.
        let (client, server) = tokio::io::duplex(8);
        let mut writer = FramedUsb::new(client);
        let mut reader = FramedUsb::new(server);

        let msg = MessageV1::ActionsCatalog {
            actions: vec![nexodeck_protocol::RemoteAction {
                id: "git-status".into(),
                name: "Git status con un nombre mas largo para forzar fragmentacion".into(),
                icon: "terminal".into(),
                color_hex: "#6366F1".into(),
                group_id: None,
                group_name: None,
                group_color_hex: None,
                kind: nexodeck_protocol::RemoteActionKind::Terminal,
                parameters: vec![],
                step_count: 0,
            }],
        };

        let write_task = {
            let msg = msg.clone();
            tokio::spawn(async move { writer.send_message(&msg).await })
        };
        let received = reader
            .recv_message()
            .await
            .expect("recv_message")
            .expect("no deberia ser EOF");
        write_task.await.expect("join").expect("send_message");
        assert_eq!(received, msg);
    }

    #[tokio::test]
    async fn clean_eof_mid_length_prefix_is_none() {
        let (client, server) = tokio::io::duplex(64);
        drop(client); // cierra el otro extremo antes de escribir nada
        let mut reader = FramedUsb::new(server);
        let result = reader.recv_message().await.expect("no deberia ser Err");
        assert!(result.is_none());
    }

    #[tokio::test]
    async fn oversized_length_prefix_is_rejected() {
        let (mut client, server) = tokio::io::duplex(64);
        let mut reader = FramedUsb::new(server);

        let huge_len = MAX_MESSAGE_BYTES + 1;
        client
            .write_all(&huge_len.to_le_bytes())
            .await
            .expect("write length prefix");

        let result = reader.recv_message().await;
        assert!(
            result.is_err(),
            "un length-prefix por encima del maximo debe rechazarse sin intentar alocar el buffer"
        );
    }
}
