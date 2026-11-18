use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use rustls::client::danger::{HandshakeSignatureValid, ServerCertVerified, ServerCertVerifier};
use rustls::{DigitallySignedStruct, Error as RustlsError, SignatureScheme};
use rustls_pki_types::{CertificateDer, PrivateKeyDer, ServerName, UnixTime};
use sha2::{Digest, Sha256};

use crate::error::{Result, TransportError};

fn ensure_crypto_provider() {
    let _ = rustls::crypto::ring::default_provider().install_default();
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|b| format!("{b:02x}")).collect()
}

/// Identidad TLS del rol host (PC). Persistida en disco para que el
/// fingerprint sea estable entre reinicios -- si cambiara en cada arranque,
/// el pinning del lado Android nunca podria confiar en el.
pub struct ServerIdentity {
    pub cert_der: Vec<u8>,
    pub key_der: Vec<u8>,
    pub fingerprint_hex: String,
}

fn identity_dir() -> Result<PathBuf> {
    let dirs = directories::ProjectDirs::from("dev", "nexodeck", "NexoDeck")
        .ok_or_else(|| TransportError::Tls("no se pudo resolver el directorio de datos".into()))?;
    let dir = dirs.data_dir().to_path_buf();
    std::fs::create_dir_all(&dir)?;
    Ok(dir)
}

/// Genera el certificado autofirmado la primera vez que corre, y lo
/// reutiliza en arranques siguientes -- ver comentario de `ServerIdentity`.
pub fn load_or_generate_server_identity() -> Result<ServerIdentity> {
    let dir = identity_dir()?;
    let cert_path = dir.join("server_cert.der");
    let key_path = dir.join("server_key.der");

    if cert_path.exists() && key_path.exists() {
        let cert_der = std::fs::read(&cert_path)?;
        let key_der = std::fs::read(&key_path)?;
        let fingerprint_hex = sha256_hex(&cert_der);
        return Ok(ServerIdentity {
            cert_der,
            key_der,
            fingerprint_hex,
        });
    }

    let key_pair = rcgen::KeyPair::generate().map_err(|e| TransportError::Tls(e.to_string()))?;
    let mut params = rcgen::CertificateParams::new(vec!["nexodeck.local".to_string()])
        .map_err(|e| TransportError::Tls(e.to_string()))?;
    params.not_after = rcgen::date_time_ymd(2099, 1, 1);
    let cert = params
        .self_signed(&key_pair)
        .map_err(|e| TransportError::Tls(e.to_string()))?;

    let cert_der = cert.der().to_vec();
    let key_der = key_pair.serialize_der();

    std::fs::write(&cert_path, &cert_der)?;
    std::fs::write(&key_path, &key_der)?;

    let fingerprint_hex = sha256_hex(&cert_der);
    Ok(ServerIdentity {
        cert_der,
        key_der,
        fingerprint_hex,
    })
}

pub fn make_server_config(identity: &ServerIdentity) -> Result<rustls::ServerConfig> {
    ensure_crypto_provider();
    let cert = CertificateDer::from(identity.cert_der.clone());
    let key = PrivateKeyDer::try_from(identity.key_der.clone())
        .map_err(|e| TransportError::Tls(e.to_string()))?;
    let config = rustls::ServerConfig::builder()
        .with_no_client_auth()
        .with_single_cert(vec![cert], key)
        .map_err(|e| TransportError::Tls(e.to_string()))?;
    Ok(config)
}

/// Estrategia de confianza del lado cliente (Android). `TrustOnFirstUse` se
/// usa solo durante el primer pairing (aun no hay nada que pinnear);
/// `Pinned` se usa en toda reconexion siguiente y RECHAZA la conexion TLS
/// -- ni siquiera llega a intercambiar mensajes -- si el certificado
/// presentado no coincide con el fingerprint guardado.
pub enum ClientTrust {
    TrustOnFirstUse {
        captured: Arc<Mutex<Option<String>>>,
    },
    Pinned(String),
}

#[derive(Debug)]
struct TrustOnFirstUseVerifier {
    captured: Arc<Mutex<Option<String>>>,
}

impl ServerCertVerifier for TrustOnFirstUseVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> std::result::Result<ServerCertVerified, RustlsError> {
        let fingerprint = sha256_hex(end_entity.as_ref());
        *self.captured.lock().unwrap() = Some(fingerprint);
        Ok(ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, RustlsError> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, RustlsError> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

#[derive(Debug)]
struct PinnedVerifier {
    expected_fingerprint_hex: String,
}

impl ServerCertVerifier for PinnedVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &CertificateDer<'_>,
        _intermediates: &[CertificateDer<'_>],
        _server_name: &ServerName<'_>,
        _ocsp_response: &[u8],
        _now: UnixTime,
    ) -> std::result::Result<ServerCertVerified, RustlsError> {
        let fingerprint = sha256_hex(end_entity.as_ref());
        if fingerprint.eq_ignore_ascii_case(&self.expected_fingerprint_hex) {
            Ok(ServerCertVerified::assertion())
        } else {
            Err(RustlsError::General(format!(
                "fingerprint del certificado no coincide: esperado {}, recibido {}",
                self.expected_fingerprint_hex, fingerprint
            )))
        }
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, RustlsError> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &CertificateDer<'_>,
        dss: &DigitallySignedStruct,
    ) -> std::result::Result<HandshakeSignatureValid, RustlsError> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

pub fn make_client_config(trust: ClientTrust) -> rustls::ClientConfig {
    ensure_crypto_provider();
    let verifier: Arc<dyn ServerCertVerifier> = match trust {
        ClientTrust::TrustOnFirstUse { captured } => Arc::new(TrustOnFirstUseVerifier { captured }),
        ClientTrust::Pinned(fp) => Arc::new(PinnedVerifier {
            expected_fingerprint_hex: fp,
        }),
    };
    rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(verifier)
        .with_no_client_auth()
}
