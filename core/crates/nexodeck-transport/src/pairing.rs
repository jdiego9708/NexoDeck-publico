use nexodeck_protocol::DevicePlatformWire;

/// Estado en memoria del flujo de pairing, del lado host (PC). Un solo
/// intento de pairing a la vez en v1 -- ver `AlreadyPairing`.
#[derive(Debug, Clone, Default)]
pub enum PairingState {
    #[default]
    Idle,
    Armed {
        pin: String,
    },
    AwaitingHostConfirm {
        pin: String,
        device_name: String,
        platform: DevicePlatformWire,
        conn_id: uuid::Uuid,
    },
}

pub fn generate_pin() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    format!("{:06}", rng.gen_range(0..1_000_000u32))
}

/// Token del tunel: 32 bytes aleatorios, en hex.
///
/// Vive al lado de `generate_pin` porque son los dos secretos que genera la
/// PC, pero no se parecen en nada y conviene no confundirlos: el PIN son 6
/// digitos que un humano compara de un vistazo y muere en dos minutos; esto
/// son 256 bits que nadie lee nunca, viajan por la sesion ya autenticada y
/// duran hasta que el usuario los rote. Un PIN como token del tunel seria
/// adivinable a mano.
pub fn generate_relay_token() -> String {
    use rand::Rng;
    let mut rng = rand::thread_rng();
    let bytes: [u8; nexodeck_relay::hello::TOKEN_LEN] = rng.gen();
    nexodeck_relay::hello::token_to_hex(&bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn el_token_tiene_el_largo_esperado_y_no_se_repite() {
        let a = generate_relay_token();
        assert_eq!(a.len(), nexodeck_relay::hello::TOKEN_LEN * 2);
        assert!(nexodeck_relay::hello::token_from_hex(&a).is_some());
        assert_ne!(a, generate_relay_token(), "dos tokens seguidos iguales");
    }
}
