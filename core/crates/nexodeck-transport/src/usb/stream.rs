//! Adaptador de los dos endpoints bulk de accessory mode a un unico
//! `AsyncRead + AsyncWrite`, que es lo que `FramedUsb` espera.
//!
//! No hay logica propia aca: `nusb` ya expone `EndpointRead`/`EndpointWrite`
//! con impls de `tokio::io` (feature `tokio`), que se encargan de partir y
//! juntar los bulk transfers. Esto solo los une en un tipo bidireccional,
//! porque USB expone cada direccion como un endpoint separado mientras que
//! el resto del transporte razona en terminos de "un canal".

use std::pin::Pin;
use std::task::{Context, Poll};

use nusb::io::{EndpointRead, EndpointWrite};
use nusb::transfer::Bulk;
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};

/// Tamano del buffer que se le pasa al SO por transfer. `nusb` lo redondea
/// al multiplo siguiente del max packet size del endpoint (512 en bulk
/// high-speed), asi que el valor exacto no es critico; 16 KiB deja lugar de
/// sobra para el mensaje mas grande que mandamos (el catalogo de acciones)
/// sin fragmentarlo en muchos transfers.
const TRANSFER_SIZE: usize = 16 * 1024;

pub(crate) struct UsbStream {
    reader: EndpointRead<Bulk>,
    writer: EndpointWrite<Bulk>,
}

impl UsbStream {
    pub(crate) fn new(
        read_endpoint: nusb::Endpoint<Bulk, nusb::transfer::In>,
        write_endpoint: nusb::Endpoint<Bulk, nusb::transfer::Out>,
    ) -> Self {
        Self {
            reader: EndpointRead::new(read_endpoint, TRANSFER_SIZE),
            writer: EndpointWrite::new(write_endpoint, TRANSFER_SIZE),
        }
    }
}

impl AsyncRead for UsbStream {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.get_mut().reader).poll_read(cx, buf)
    }
}

impl AsyncWrite for UsbStream {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        Pin::new(&mut self.get_mut().writer).poll_write(cx, buf)
    }

    /// `EndpointWrite` acumula en un buffer y solo submitea al llenarlo o al
    /// hacer flush -- por eso `FramedUsb::send_message` hace flush explicito
    /// despues de cada mensaje. Sin eso, un mensaje chico se quedaria
    /// esperando en RAM hasta que otro lo empuje.
    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.get_mut().writer).poll_flush(cx)
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.get_mut().writer).poll_shutdown(cx)
    }
}
