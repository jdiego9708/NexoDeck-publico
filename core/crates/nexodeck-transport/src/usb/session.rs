use tokio::io::{AsyncRead, AsyncWrite};

use nexodeck_protocol::MessageV1;

use crate::error::Result;
use crate::session::SessionTransport;
use crate::usb::framing::FramedUsb;

pub(crate) struct UsbSession<S>(pub(crate) FramedUsb<S>);

impl<S> SessionTransport for UsbSession<S>
where
    S: AsyncRead + AsyncWrite + Unpin + Send,
{
    async fn send(&mut self, msg: &MessageV1) -> Result<()> {
        self.0.send_message(msg).await
    }

    async fn recv(&mut self) -> Result<Option<MessageV1>> {
        self.0.recv_message().await
    }
}
