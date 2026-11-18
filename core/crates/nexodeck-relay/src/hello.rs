//! Saludo de 38 bytes con el que las dos puntas se presentan al relay.
//!
//! Vive aca --y no en `nexodeck-protocol`-- porque no es un mensaje de la
//! aplicacion: es el sobre que el relay necesita leer para saber a quien
//! empalmar con quien. El relay NUNCA mira nada mas alla de estos bytes; de
//! ahi en adelante solo copia. Es codigo puro, sin async ni dependencias,
//! justamente para que `nexodeck-transport` lo pueda reusar y no existan dos
//! definiciones del mismo formato.

/// `NXDR` = NeXoDeck Relay.
pub const MAGIC: [u8; 4] = *b"NXDR";
pub const VERSION: u8 = 1;

/// Bytes del token compartido. 32 = 256 bits: no se escribe a mano, viaja
/// por la sesion ya autenticada (ver el mensaje `RelayConfig`).
pub const TOKEN_LEN: usize = 32;

/// magic(4) + version(1) + rol(1) + token(32).
pub const HELLO_LEN: usize = 4 + 1 + 1 + TOKEN_LEN;

/// Quien es cada punta. La PC se aparca y espera; el telefono llega y
/// dispara el empalme.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    /// La PC: se registra y queda esperando (posiblemente horas).
    Host,
    /// El telefono: llega buscando a un host ya registrado.
    Client,
}

impl Role {
    const HOST: u8 = 1;
    const CLIENT: u8 = 2;

    fn to_byte(self) -> u8 {
        match self {
            Role::Host => Self::HOST,
            Role::Client => Self::CLIENT,
        }
    }

    fn from_byte(b: u8) -> Option<Self> {
        match b {
            Self::HOST => Some(Role::Host),
            Self::CLIENT => Some(Role::Client),
            _ => None,
        }
    }
}

/// Respuestas del relay, un byte.
///
/// `KEEPALIVE` solo puede aparecer ANTES de `MATCHED`: una vez empalmado, el
/// relay no vuelve a escribir un byte propio nunca mas. Si lo hiciera,
/// corromperia el TLS que viaja adentro.
pub mod status {
    /// Al cliente: hay un host esperando, empieza a hablar.
    pub const MATCHED: u8 = 0x00;
    /// Al host: quedaste registrado, espera.
    pub const REGISTERED: u8 = 0x01;
    /// Al host: llego un cliente, de aca en mas son bytes tuyos.
    pub const HOST_MATCHED: u8 = 0x02;
    /// Al host, mientras espera: mantiene viva la conexion a traves del NAT.
    pub const KEEPALIVE: u8 = 0xF0;

    /// El saludo no se entendio (magic o version).
    pub const ERR_BAD_HELLO: u8 = 0xE0;
    /// El cliente llego y no hay ningun host con ese token.
    pub const ERR_NO_HOST: u8 = 0xE1;
    /// Ya habia un host registrado con ese token.
    pub const ERR_HOST_TAKEN: u8 = 0xE2;
    /// El token no esta en la lista blanca del relay.
    pub const ERR_TOKEN_REJECTED: u8 = 0xE3;
}

pub fn encode(role: Role, token: &[u8; TOKEN_LEN]) -> [u8; HELLO_LEN] {
    let mut out = [0u8; HELLO_LEN];
    out[0..4].copy_from_slice(&MAGIC);
    out[4] = VERSION;
    out[5] = role.to_byte();
    out[6..].copy_from_slice(token);
    out
}

#[derive(Debug, PartialEq, Eq)]
pub enum HelloError {
    BadMagic,
    UnsupportedVersion(u8),
    BadRole(u8),
}

pub fn decode(buf: &[u8; HELLO_LEN]) -> Result<(Role, [u8; TOKEN_LEN]), HelloError> {
    if buf[0..4] != MAGIC {
        return Err(HelloError::BadMagic);
    }
    if buf[4] != VERSION {
        return Err(HelloError::UnsupportedVersion(buf[4]));
    }
    let role = Role::from_byte(buf[5]).ok_or(HelloError::BadRole(buf[5]))?;
    let mut token = [0u8; TOKEN_LEN];
    token.copy_from_slice(&buf[6..]);
    Ok((role, token))
}

/// Hex en minusculas, que es como el token se guarda y se transporta.
pub fn token_to_hex(token: &[u8; TOKEN_LEN]) -> String {
    token.iter().map(|b| format!("{b:02x}")).collect()
}

pub fn token_from_hex(hex: &str) -> Option<[u8; TOKEN_LEN]> {
    if hex.len() != TOKEN_LEN * 2 {
        return None;
    }
    let mut out = [0u8; TOKEN_LEN];
    for (i, chunk) in hex.as_bytes().chunks(2).enumerate() {
        let s = std::str::from_utf8(chunk).ok()?;
        out[i] = u8::from_str_radix(s, 16).ok()?;
    }
    Some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn roundtrip_de_los_dos_roles() {
        let token = [7u8; TOKEN_LEN];
        for role in [Role::Host, Role::Client] {
            let bytes = encode(role, &token);
            assert_eq!(bytes.len(), HELLO_LEN);
            assert_eq!(decode(&bytes).unwrap(), (role, token));
        }
    }

    #[test]
    fn rechaza_magic_version_y_rol_invalidos() {
        let token = [0u8; TOKEN_LEN];
        let mut bad = encode(Role::Host, &token);
        bad[0] = b'X';
        assert_eq!(decode(&bad), Err(HelloError::BadMagic));

        let mut bad = encode(Role::Host, &token);
        bad[4] = 99;
        assert_eq!(decode(&bad), Err(HelloError::UnsupportedVersion(99)));

        let mut bad = encode(Role::Host, &token);
        bad[5] = 9;
        assert_eq!(decode(&bad), Err(HelloError::BadRole(9)));
    }

    #[test]
    fn el_token_va_y_vuelve_por_hex() {
        let token: [u8; TOKEN_LEN] = std::array::from_fn(|i| i as u8);
        let hex = token_to_hex(&token);
        assert_eq!(hex.len(), TOKEN_LEN * 2);
        assert_eq!(token_from_hex(&hex), Some(token));
    }

    #[test]
    fn hex_invalido_no_pasa() {
        assert_eq!(token_from_hex(""), None);
        assert_eq!(token_from_hex("ab"), None);
        assert_eq!(token_from_hex(&"zz".repeat(TOKEN_LEN)), None);
    }

    // El keepalive tiene que ser distinguible de las dos respuestas que
    // puede recibir el host mientras espera; si colisionara, la PC
    // arrancaria el TLS a destiempo.
    #[test]
    fn el_keepalive_no_colisiona_con_ninguna_respuesta() {
        let otros = [
            status::MATCHED,
            status::REGISTERED,
            status::HOST_MATCHED,
            status::ERR_BAD_HELLO,
            status::ERR_NO_HOST,
            status::ERR_HOST_TAKEN,
            status::ERR_TOKEN_REJECTED,
        ];
        assert!(!otros.contains(&status::KEEPALIVE));
    }
}
