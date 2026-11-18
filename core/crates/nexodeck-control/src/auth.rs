//! Quien puede hablar con el servidor de control.
//!
//! Son tres guardias y cada una tapa un agujero distinto. Ninguna sobra.

use axum::http::HeaderMap;

pub(crate) enum Guard {
    Allowed,
    /// Falta el token o no coincide. 401.
    Unauthorized(&'static str),
    /// El token podria estar bien, pero quien llama no es un cliente legitimo.
    /// 403.
    Forbidden(&'static str),
}

/// Comprueba las tres condiciones, en orden de mas barata a mas cara.
pub(crate) fn check(headers: &HeaderMap, expected_token: &str) -> Guard {
    // 1. El `Host` tiene que ser la propia maquina.
    //
    // Contra el **reenlace de DNS**: una pagina web hace que `malo.example`
    // resuelva a 127.0.0.1 y desde ahi habla con este puerto como si fuera
    // suyo. El socket ve una conexion de loopback perfectamente normal, asi que
    // atar a 127.0.0.1 no lo detiene. Lo unico que delata al ataque es que el
    // `Host` que manda el navegador sigue siendo el dominio del atacante.
    if let Some(host) = headers.get(axum::http::header::HOST).and_then(|h| h.to_str().ok()) {
        if !is_loopback_host(host) {
            return Guard::Forbidden("la peticion no venia dirigida a la propia maquina");
        }
    }

    // 2. Ningun navegador, tenga el token o no.
    //
    // `Origin` lo pone el navegador y **no se puede falsificar desde JavaScript**.
    // Un cliente MCP de linea de comandos no lo manda nunca. Asi que su mera
    // presencia significa "esto lo origino una pagina web", y ninguna pagina web
    // tiene por que estar pidiendole cosas a NexoDeck.
    if headers.contains_key(axum::http::header::ORIGIN) {
        return Guard::Forbidden("las peticiones desde un navegador no se aceptan");
    }

    // 3. El token.
    //
    // Loopback **no es** una frontera de seguridad: cualquier proceso que corra
    // como el usuario puede abrir una conexion a este puerto. Sin token, el
    // servidor le daria a cualquier programa instalado la capacidad de mandar
    // avisos en nombre del usuario.
    let Some(provided) = headers
        .get(axum::http::header::AUTHORIZATION)
        .and_then(|h| h.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
    else {
        return Guard::Unauthorized("falta la cabecera Authorization: Bearer");
    };

    if constant_time_eq(provided.trim().as_bytes(), expected_token.as_bytes()) {
        Guard::Allowed
    } else {
        Guard::Unauthorized("el token no coincide")
    }
}

/// El `Host` puede traer puerto (`127.0.0.1:58646`) y, si es IPv6, corchetes.
fn is_loopback_host(host: &str) -> bool {
    let name = match host.rsplit_once(':') {
        // `[::1]:58646` parte bien; `[::1]` sin puerto no tiene que partirse.
        Some((name, port)) if port.chars().all(|c| c.is_ascii_digit()) && !port.is_empty() => name,
        _ => host,
    };
    let name = name.trim_start_matches('[').trim_end_matches(']');
    name.eq_ignore_ascii_case("localhost") || name == "127.0.0.1" || name == "::1"
}

/// Comparacion sin fuga de tiempo.
///
/// Con `==` el tiempo de respuesta depende de cuantos caracteres del principio
/// acertaste, y un atacante local puede medirlo para adivinar el token byte a
/// byte en vez de a lo bruto. Cuesta cuatro lineas evitarlo.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        diff |= x ^ y;
    }
    diff == 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::http::{header, HeaderValue};

    const TOKEN: &str = "abc123";

    fn headers(pairs: &[(header::HeaderName, &str)]) -> HeaderMap {
        let mut map = HeaderMap::new();
        for (name, value) in pairs {
            map.insert(name.clone(), HeaderValue::from_str(value).unwrap());
        }
        map
    }

    fn allowed(map: &HeaderMap) -> bool {
        matches!(check(map, TOKEN), Guard::Allowed)
    }

    #[test]
    fn the_right_token_from_a_cli_gets_in() {
        let map = headers(&[
            (header::HOST, "127.0.0.1:58646"),
            (header::AUTHORIZATION, "Bearer abc123"),
        ]);
        assert!(allowed(&map));
    }

    #[test]
    fn no_token_and_wrong_token_are_both_unauthorized() {
        let bare = headers(&[(header::HOST, "localhost")]);
        assert!(matches!(check(&bare, TOKEN), Guard::Unauthorized(_)));

        let wrong = headers(&[
            (header::HOST, "localhost"),
            (header::AUTHORIZATION, "Bearer otro"),
        ]);
        assert!(matches!(check(&wrong, TOKEN), Guard::Unauthorized(_)));
    }

    /// El caso del reenlace de DNS: la conexion llega por loopback y el token
    /// podria haberse filtrado, pero el `Host` delata que el destino real era
    /// otro dominio.
    #[test]
    fn a_rebound_dns_host_is_forbidden_even_with_the_right_token() {
        let map = headers(&[
            (header::HOST, "malo.example"),
            (header::AUTHORIZATION, "Bearer abc123"),
        ]);
        assert!(matches!(check(&map, TOKEN), Guard::Forbidden(_)));
    }

    /// Una pagina web nunca entra, aunque acierte el token.
    #[test]
    fn a_browser_origin_is_forbidden_even_with_the_right_token() {
        let map = headers(&[
            (header::HOST, "127.0.0.1:58646"),
            (header::ORIGIN, "https://cualquier.sitio"),
            (header::AUTHORIZATION, "Bearer abc123"),
        ]);
        assert!(matches!(check(&map, TOKEN), Guard::Forbidden(_)));
    }

    #[test]
    fn loopback_hosts_are_recognised_with_and_without_port() {
        for host in [
            "localhost",
            "LOCALHOST:58646",
            "127.0.0.1",
            "127.0.0.1:58646",
            "[::1]",
            "[::1]:58646",
        ] {
            assert!(is_loopback_host(host), "{host} deberia valer");
        }
        for host in ["malo.example", "malo.example:58646", "192.168.1.5:58646"] {
            assert!(!is_loopback_host(host), "{host} no deberia valer");
        }
    }

    #[test]
    fn tokens_of_different_length_never_match() {
        assert!(!constant_time_eq(b"abc", b"abcd"));
        assert!(constant_time_eq(b"abc", b"abc"));
    }
}
