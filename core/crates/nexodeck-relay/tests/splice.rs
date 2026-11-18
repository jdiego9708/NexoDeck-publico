//! El relay contra sockets de verdad: dos puntas por loopback.
//!
//! Se prueba sobre TCP real y no con un canal simulado porque lo unico que
//! el relay hace es manejar sockets: un doble de prueba testearia el doble.

use std::collections::HashSet;
use std::net::SocketAddr;
use std::time::Duration;

use nexodeck_relay::hello::{self, status, Role, TOKEN_LEN};
use nexodeck_relay::{serve, RelayConfig};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;

const TOKEN: [u8; TOKEN_LEN] = [42u8; TOKEN_LEN];
const OTRO_TOKEN: [u8; TOKEN_LEN] = [7u8; TOKEN_LEN];

/// Levanta un relay en un puerto efimero y devuelve su direccion.
async fn relay_con(config: RelayConfig) -> SocketAddr {
    let listener = tokio::net::TcpListener::bind(("127.0.0.1", 0))
        .await
        .unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move { serve(listener, config).await });
    addr
}

async fn relay() -> SocketAddr {
    relay_con(RelayConfig::default()).await
}

async fn saludar(addr: SocketAddr, role: Role, token: &[u8; TOKEN_LEN]) -> TcpStream {
    let mut s = TcpStream::connect(addr).await.unwrap();
    s.write_all(&hello::encode(role, token)).await.unwrap();
    s
}

async fn un_byte(s: &mut TcpStream) -> u8 {
    let mut b = [0u8; 1];
    tokio::time::timeout(Duration::from_secs(5), s.read_exact(&mut b))
        .await
        .expect("el relay no contesto")
        .expect("la conexion se corto");
    b[0]
}

#[tokio::test]
async fn empalma_las_dos_puntas_y_los_bytes_viajan_en_ambos_sentidos() {
    let addr = relay().await;

    let mut host = saludar(addr, Role::Host, &TOKEN).await;
    assert_eq!(un_byte(&mut host).await, status::REGISTERED);

    let mut client = saludar(addr, Role::Client, &TOKEN).await;
    assert_eq!(un_byte(&mut client).await, status::MATCHED);
    assert_eq!(un_byte(&mut host).await, status::HOST_MATCHED);

    // De la PC al telefono...
    host.write_all(b"hola").await.unwrap();
    let mut buf = [0u8; 4];
    client.read_exact(&mut buf).await.unwrap();
    assert_eq!(&buf, b"hola");

    // ...y de vuelta.
    client.write_all(b"chau").await.unwrap();
    host.read_exact(&mut buf).await.unwrap();
    assert_eq!(&buf, b"chau");
}

/// El contrato que la PC tiene que respetar: mientras espera puede recibir
/// keepalives, y solo despues de `HOST_MATCHED` los bytes son del telefono.
/// Si arrancara el TLS antes, un keepalive entraria como si fuera parte del
/// handshake y lo romperia.
#[tokio::test]
async fn el_host_recibe_keepalives_hasta_que_llega_el_cliente() {
    let addr = relay_con(RelayConfig {
        keepalive_every: Duration::from_millis(40),
        ..RelayConfig::default()
    })
    .await;

    let mut host = saludar(addr, Role::Host, &TOKEN).await;
    assert_eq!(un_byte(&mut host).await, status::REGISTERED);

    // Varios keepalives seguidos mientras nadie llama.
    for _ in 0..3 {
        assert_eq!(un_byte(&mut host).await, status::KEEPALIVE);
    }

    let mut client = saludar(addr, Role::Client, &TOKEN).await;
    assert_eq!(un_byte(&mut client).await, status::MATCHED);

    // El host descarta los keepalives que queden y encuentra el aviso.
    let mut visto = 0;
    loop {
        match un_byte(&mut host).await {
            status::KEEPALIVE => {
                visto += 1;
                assert!(visto < 50, "demasiados keepalives, nunca llego el aviso");
            }
            status::HOST_MATCHED => break,
            otro => panic!("byte inesperado: {otro:#x}"),
        }
    }

    // Y despues del aviso el canal es transparente: ni un byte del relay.
    client.write_all(b"ping").await.unwrap();
    let mut buf = [0u8; 4];
    host.read_exact(&mut buf).await.unwrap();
    assert_eq!(&buf, b"ping");
}

#[tokio::test]
async fn un_cliente_sin_host_es_rechazado() {
    let addr = relay().await;
    let mut client = saludar(addr, Role::Client, &TOKEN).await;
    assert_eq!(un_byte(&mut client).await, status::ERR_NO_HOST);
}

#[tokio::test]
async fn un_segundo_host_con_el_mismo_token_es_rechazado() {
    let addr = relay().await;
    let mut host = saludar(addr, Role::Host, &TOKEN).await;
    assert_eq!(un_byte(&mut host).await, status::REGISTERED);

    let mut intruso = saludar(addr, Role::Host, &TOKEN).await;
    assert_eq!(un_byte(&mut intruso).await, status::ERR_HOST_TAKEN);
}

/// Dos parejas distintas no se cruzan: es lo que separa una sesion de otra.
#[tokio::test]
async fn tokens_distintos_no_se_mezclan() {
    let addr = relay().await;

    let mut host_a = saludar(addr, Role::Host, &TOKEN).await;
    assert_eq!(un_byte(&mut host_a).await, status::REGISTERED);
    let mut host_b = saludar(addr, Role::Host, &OTRO_TOKEN).await;
    assert_eq!(un_byte(&mut host_b).await, status::REGISTERED);

    let mut client_b = saludar(addr, Role::Client, &OTRO_TOKEN).await;
    assert_eq!(un_byte(&mut client_b).await, status::MATCHED);
    assert_eq!(un_byte(&mut host_b).await, status::HOST_MATCHED);

    client_b.write_all(b"para-b").await.unwrap();
    let mut buf = [0u8; 6];
    host_b.read_exact(&mut buf).await.unwrap();
    assert_eq!(&buf, b"para-b");

    // El host A sigue esperando: no le llego nada de la pareja B.
    let sin_nada =
        tokio::time::timeout(Duration::from_millis(150), host_a.read_exact(&mut [0u8; 1])).await;
    assert!(
        sin_nada.is_err(),
        "el host A no deberia haber recibido nada"
    );
}

#[tokio::test]
async fn un_token_fuera_de_la_lista_blanca_es_rechazado() {
    let addr = relay_con(RelayConfig {
        allowed_tokens: Some(HashSet::from([TOKEN])),
        ..RelayConfig::default()
    })
    .await;

    let mut permitido = saludar(addr, Role::Host, &TOKEN).await;
    assert_eq!(un_byte(&mut permitido).await, status::REGISTERED);

    let mut ajeno = saludar(addr, Role::Host, &OTRO_TOKEN).await;
    assert_eq!(un_byte(&mut ajeno).await, status::ERR_TOKEN_REJECTED);
}

#[tokio::test]
async fn un_saludo_que_no_se_entiende_es_rechazado() {
    let addr = relay().await;
    let mut s = TcpStream::connect(addr).await.unwrap();
    // Del largo correcto para que el relay lo lea entero, pero con la magia
    // equivocada: es lo que manda cualquier escaner que encuentre el puerto.
    s.write_all(&[0u8; hello::HELLO_LEN]).await.unwrap();
    assert_eq!(un_byte(&mut s).await, status::ERR_BAD_HELLO);
}

/// Si la PC se cae mientras espera, su token tiene que quedar libre. Sin
/// esto, un registro muerto bloquearia al proximo host legitimo con
/// ERR_HOST_TAKEN y la unica salida seria reiniciar el relay.
#[tokio::test]
async fn si_el_host_se_va_su_token_queda_libre() {
    let addr = relay_con(RelayConfig {
        keepalive_every: Duration::from_millis(30),
        ..RelayConfig::default()
    })
    .await;

    let mut host = saludar(addr, Role::Host, &TOKEN).await;
    assert_eq!(un_byte(&mut host).await, status::REGISTERED);
    drop(host);

    // El relay se entera al fallar el keepalive siguiente.
    let mut nuevo = None;
    for _ in 0..40 {
        tokio::time::sleep(Duration::from_millis(50)).await;
        let mut s = saludar(addr, Role::Host, &TOKEN).await;
        if un_byte(&mut s).await == status::REGISTERED {
            nuevo = Some(s);
            break;
        }
    }
    assert!(nuevo.is_some(), "el token quedo tomado por un host muerto");
}

/// Un host que hace un cierre a medias (FIN de escritura) tiene que liberar su
/// token YA, sin esperar a que falle un keepalive. Un host asi **sigue
/// leyendo**, asi que la escritura del keepalive no falla: en la version vieja
/// el token quedaba tomado para siempre y bloqueaba al proximo host legitimo
/// con `ERR_HOST_TAKEN`. La deteccion tiene que salir de LEER el socket.
#[tokio::test]
async fn un_host_con_cierre_a_medias_libera_su_token() {
    // Keepalive largo a proposito: si la deteccion dependiera de el, este test
    // no terminaria en un tiempo razonable, que es justo lo que se arregla.
    let addr = relay_con(RelayConfig {
        keepalive_every: Duration::from_secs(30),
        ..RelayConfig::default()
    })
    .await;

    let mut host = saludar(addr, Role::Host, &TOKEN).await;
    assert_eq!(un_byte(&mut host).await, status::REGISTERED);
    // Cierre a medias: el relay ve EOF al leer, pero el host sigue pudiendo
    // recibir keepalives (la escritura no falla).
    host.shutdown().await.unwrap();

    // El relay tiene que verlo al LEER; el keepalive (30 s) no ayuda. Se
    // reintenta por la carrera entre el FIN y el proximo host, con un
    // presupuesto muy por debajo de esos 30 s: solo pasa si la deteccion es
    // por lectura.
    let mut nuevo = None;
    for _ in 0..20 {
        let mut s = saludar(addr, Role::Host, &TOKEN).await;
        if un_byte(&mut s).await == status::REGISTERED {
            nuevo = Some(s);
            break;
        }
        tokio::time::sleep(Duration::from_millis(50)).await;
    }
    assert!(
        nuevo.is_some(),
        "el token de un host con FIN no se libero leyendo el socket"
    );
}
