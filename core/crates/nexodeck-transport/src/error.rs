#[derive(Debug, thiserror::Error)]
pub enum TransportError {
    #[error("io: {0}")]
    Io(#[from] std::io::Error),
    #[error("tls: {0}")]
    Tls(String),
    #[error("websocket: {0}")]
    WebSocket(#[from] tokio_tungstenite::tungstenite::Error),
    #[error("protocolo invalido: {0}")]
    Protocol(String),
    #[error("ya hay un pairing en curso")]
    AlreadyPairing,
    #[error("no armado para aceptar dispositivos nuevos")]
    NotAccepting,
    #[error("dispositivo no autorizado")]
    Unauthorized,
    #[error("no hay conexion activa con ese dispositivo")]
    NotConnected,
    #[error("descubrimiento mdns: {0}")]
    Discovery(String),
    #[error("el host de transporte no esta iniciado")]
    HostNotStarted,
    #[error("el cliente de transporte no esta conectado")]
    ClientNotStarted,
    #[error("usb: {0}")]
    Usb(String),
    /// El dispositivo esta ahi pero el SO no nos deja hablarle: hay un driver
    /// de fabricante atado a sus interfaces. Se distingue del resto de los
    /// errores de USB a proposito -- es el caso del ADR 0002, y la respuesta
    /// no es "reintentar" sino ofrecerle al usuario instalar WinUSB.
    #[error("usb: driver incompatible en {vendor_id:04x}:{product_id:04x}")]
    UsbDriverBlocked {
        vendor_id: u16,
        product_id: u16,
        driver: Option<String>,
    },
    #[error("usb: el dispositivo no habla AOA")]
    UsbNotAoaCapable,
}

pub type Result<T> = std::result::Result<T, TransportError>;
