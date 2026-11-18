//! La pagina del editor, embebida en el binario.
//!
//! `web/` se construye con esbuild a `assets/` (`melos run editor:build`) y esos
//! ficheros se commitean: asi `flutter build` no necesita Node. Se sirven por un
//! protocolo propio que wry traduce en Windows a `http://nexodeck.localhost/`;
//! nunca se leen del disco, y nada fuera de esta lista existe.

pub(crate) const PROTOCOL: &str = "nexodeck";

/// wry convierte `nexodeck://localhost/` en `http://nexodeck.localhost/` en
/// Windows; escrito asi vale igual en las otras plataformas.
pub(crate) const START_URL: &str = "nexodeck://localhost/";

/// Los prefijos con los que se ve la pagina propia. La barra final importa:
/// sin ella, `http://nexodeck.localhost.otro.com` pasaria por propia.
const OWN_PREFIXES: [&str; 2] = ["http://nexodeck.localhost/", "nexodeck://localhost/"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Asset {
    pub(crate) bytes: &'static [u8],
    pub(crate) mime: &'static str,
}

const INDEX: &[u8] = include_bytes!("../assets/index.html");
const SCRIPT: &[u8] = include_bytes!("../assets/editor.js");
const STYLES: &[u8] = include_bytes!("../assets/editor.css");

pub(crate) fn lookup(path: &str) -> Option<Asset> {
    let path = path.split(['?', '#']).next().unwrap_or(path);
    let (bytes, mime) = match path {
        "" | "/" | "/index.html" => (INDEX, "text/html; charset=utf-8"),
        "/editor.js" => (SCRIPT, "text/javascript; charset=utf-8"),
        "/editor.css" => (STYLES, "text/css; charset=utf-8"),
        _ => return None,
    };
    Some(Asset { bytes, mime })
}

pub(crate) fn is_own_url(url: &str) -> bool {
    OWN_PREFIXES.iter().any(|prefix| url.starts_with(prefix))
}

/// Un enlace que se puede mandar al navegador. Solo web y correo: un `file:` o un
/// `javascript:` escrito en una nota no puede terminar ejecutando nada.
pub(crate) fn is_external_url(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    let web = ["https://", "http://", "mailto:"]
        .iter()
        .any(|scheme| lower.starts_with(scheme));
    web && !is_own_url(url) && !url.chars().any(|c| c.is_control() || c.is_whitespace())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_page_file_is_served_with_its_type() {
        let index = lookup("/").unwrap();
        assert_eq!(index.mime, "text/html; charset=utf-8");
        assert_eq!(lookup("/index.html"), Some(index));
        assert_eq!(lookup("/editor.js").unwrap().mime, "text/javascript; charset=utf-8");
        assert_eq!(lookup("/editor.css?v=2").unwrap().mime, "text/css; charset=utf-8");
        for asset in [index, lookup("/editor.js").unwrap(), lookup("/editor.css").unwrap()] {
            assert!(!asset.bytes.is_empty(), "falta correr `melos run editor:build`");
        }
    }

    #[test]
    fn nothing_outside_the_list_exists() {
        for path in ["/secret.txt", "/../Cargo.toml", "/assets/editor.js", "/EDITOR.JS"] {
            assert_eq!(lookup(path), None, "{path}");
        }
    }

    #[test]
    fn the_page_loads_the_bundle_it_ships_with() {
        let html = std::str::from_utf8(INDEX).unwrap();
        assert!(html.contains("editor.js"));
        assert!(html.contains("editor.css"));
        assert!(html.contains("Content-Security-Policy"));
    }

    #[test]
    fn own_and_external_links_are_told_apart() {
        assert!(is_own_url("http://nexodeck.localhost/"));
        assert!(is_own_url("nexodeck://localhost/index.html"));
        assert!(!is_own_url("http://nexodeck.localhost.evil.com/"));
        assert!(!is_own_url("http://nexodeck.localhost@evil.com/"));

        assert!(is_external_url("https://docs.rs/wry"));
        assert!(is_external_url("mailto:equipo@example.com"));
        assert!(!is_external_url("http://nexodeck.localhost/"));
        assert!(!is_external_url("file:///C:/Windows/System32/calc.exe"));
        assert!(!is_external_url("javascript:alert(1)"));
        assert!(!is_external_url("https://example.com/a b"));
    }
}
