//! Agrupaciones de notas: **una agrupacion ES una carpeta** de la boveda.
//!
//! Decision del usuario, tomada sabiendo el precio: la alternativa era una clave
//! en el frontmatter, que no mueve ficheros y no rompe nada, pero no se ve como
//! estructura al abrir la boveda en Obsidian. Se eligio la carpeta porque la
//! boveda se abre por fuera a menudo y ahi las carpetas son lo que se entiende.
//!
//! La consecuencia es que agrupar una nota **mueve el fichero**, y la ruta es la
//! identidad de una nota en medio sistema (digests, propuestas, enlaces, el
//! espejo del movil). Por eso mover no es un `rename` suelto: ver
//! `DocsService::move_note` en `notes/editing.rs`.
//!
//! Aqui no se toca el disco. Esto decide **que es un grupo y como se llama**, y
//! es todo puro para poder probarlo sin boveda.
//!
//! **Toda carpeta de primer nivel cuenta como grupo**, este o no en el catalogo
//! (tambien decision del usuario): asi lo que se ve en NexoDeck y lo que hay en
//! el disco no pueden discrepar. El catalogo de `NotesConfig` solo le pone
//! nombre bonito, color y orden.

use std::collections::BTreeMap;

use crate::config::{NoteGroup, DAILY_DIR, HUB_DIR, PRIVATE_SEGMENT};
use crate::notes::capture::CAPTURE_DIR;

/// El color de un grupo que todavia no tiene uno elegido. Es el mismo que usan
/// los grupos del deck (`action_groups_table.dart`): son el mismo concepto para
/// el usuario y no hay motivo para que se vean distintos.
pub const DEFAULT_GROUP_COLOR: &str = "#6366F1";

/// Carpetas que **no** son agrupaciones, con su motivo:
///
/// - `diario/` y `proyectos/` ya tienen significado: cambian el `DocRole` de la
///   nota, y con el su comportamiento (el modo automatico salta los `hub`).
///   Dejar que fueran grupos significaria que meter una nota en un grupo le
///   cambia lo que es.
/// - `privado/` no lo lee ningun agente y no aparece en el indice.
/// - `inbox/` es justamente "sin agrupacion".
pub fn is_reserved(segment: &str) -> bool {
    let lower = segment.trim().trim_end_matches('/').to_lowercase();
    lower.is_empty()
        || lower.starts_with('.')
        || lower == DAILY_DIR.trim_end_matches('/')
        || lower == HUB_DIR.trim_end_matches('/')
        || lower == PRIVATE_SEGMENT
        || lower == CAPTURE_DIR.trim_end_matches('/')
}

/// La agrupacion de una nota: la primera carpeta de su ruta.
///
/// `None` para una nota suelta en la raiz, para `inbox/` y para las reservadas.
/// Solo cuenta el **primer** nivel: `odm/vuelos/x.md` es del grupo `odm`, no de
/// `vuelos`.
pub fn group_of(rel: &str) -> Option<String> {
    let rel = rel.trim().replace('\\', "/");
    let (head, rest) = rel.split_once('/')?;
    // Sin nada detras no hay nota, solo una carpeta.
    if rest.trim().is_empty() {
        return None;
    }
    if is_reserved(head) {
        return None;
    }
    Some(head.to_string())
}

/// La agrupacion de una nota por su ruta **virtual**. En una carpeta local lleva
/// su prefijo (`@apuntes/clientes/acme.md` -> `@apuntes/clientes`): cada carpeta
/// tiene sus agrupaciones, y un `clientes/` en dos carpetas no es la misma.
pub fn virtual_group_of(path: &str) -> Option<String> {
    match super::roots::split_virtual(path) {
        (Some(id), inner) => {
            group_of(inner).map(|group| format!("{}{group}", super::roots::local_prefix(id)))
        }
        (None, rel) => group_of(rel),
    }
}

/// La ruta que le toca a una nota dentro de un grupo, conservando su nombre de
/// fichero. Con `group` vacio vuelve a `inbox/`, que es "sin agrupacion".
pub fn path_in_group(rel: &str, group: Option<&str>) -> String {
    let rel = rel.trim().replace('\\', "/");
    let file = rel.rsplit('/').next().unwrap_or(&rel);
    match group.map(str::trim).filter(|g| !g.is_empty()) {
        Some(group) => format!("{}/{file}", group.trim_matches('/')),
        None => format!("{CAPTURE_DIR}{file}"),
    }
}

/// Comprueba un nombre de agrupacion y devuelve el nombre de carpeta.
///
/// El usuario escribe "Trabajo de campo" y la carpeta se llama
/// `trabajo-de-campo`: el nombre bonito vive en el catalogo, y en el disco va
/// algo que no dependa de tildes ni mayusculas. Mismo criterio que el nombre de
/// fichero de una captura (`capture::slug`), y por el mismo motivo: la boveda se
/// sincroniza con el movil y se abre en Obsidian.
pub fn validate_group_name(name: &str) -> Result<String, String> {
    let name = name.trim();
    if name.is_empty() {
        return Err("el nombre de la agrupacion no puede estar vacio".to_string());
    }
    let id = super::capture::slug(name);
    if is_reserved(&id) {
        return Err(format!(
            "'{id}' es una carpeta reservada de la boveda (diario, proyectos, privado, inbox): \
            elige otro nombre"
        ));
    }
    Ok(id)
}

/// `#RRGGBB`, que es lo que ya guardan los grupos del deck.
pub fn validate_color(hex: &str) -> Result<String, String> {
    let hex = hex.trim();
    let ok = hex.len() == 7
        && hex.starts_with('#')
        && hex[1..].chars().all(|c| c.is_ascii_hexdigit());
    if !ok {
        return Err(format!("'{hex}' no es un color valido: se espera #RRGGBB"));
    }
    Ok(hex.to_uppercase())
}

/// Una agrupacion tal como se enseña: lo que hay en el disco, vestido con lo que
/// diga el catalogo.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NoteGroupView {
    /// El nombre de la carpeta. Es la identidad.
    pub id: String,
    /// Lo que se enseña. Sin entrada en el catalogo, el propio nombre de la
    /// carpeta.
    pub name: String,
    pub color_hex: String,
    pub order: u32,
    /// Cuantas notas tiene ahora mismo.
    pub notes: usize,
}

/// Une las carpetas que existen con el catalogo.
///
/// **Una carpeta sin entrada en el catalogo aparece igual**, con el color por
/// defecto: es lo que evita que la boveda y lo que se ve discrepen. Y una
/// entrada del catalogo cuya carpeta ya no tiene notas tambien aparece, vacia:
/// borrar la ultima nota de un grupo no puede hacer desaparecer el grupo sin
/// avisar.
pub fn list_groups<'a>(
    paths: impl Iterator<Item = &'a str>,
    catalog: &[NoteGroup],
) -> Vec<NoteGroupView> {
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    for path in paths {
        if let Some(group) = virtual_group_of(path) {
            *counts.entry(group).or_default() += 1;
        }
    }
    for entry in catalog {
        counts.entry(entry.id.clone()).or_default();
    }

    let by_id: BTreeMap<&str, &NoteGroup> =
        catalog.iter().map(|g| (g.id.as_str(), g)).collect();

    let mut groups: Vec<NoteGroupView> = counts
        .into_iter()
        .map(|(id, notes)| {
            let entry = by_id.get(id.as_str());
            NoteGroupView {
                // Sin nombre en el catalogo, el de la carpeta: sin el prefijo de
                // una carpeta local, que no aporta nada al leerlo.
                name: entry
                    .map(|e| e.name.clone())
                    .filter(|n| !n.trim().is_empty())
                    .unwrap_or_else(|| id.rsplit('/').next().unwrap_or(&id).to_string()),
                color_hex: entry
                    .map(|e| e.color_hex.clone())
                    .filter(|c| !c.trim().is_empty())
                    .unwrap_or_else(|| DEFAULT_GROUP_COLOR.to_string()),
                order: entry.map(|e| e.order).unwrap_or(u32::MAX),
                notes,
                id,
            }
        })
        .collect();

    // Primero lo que el usuario ordeno; el resto, alfabetico. Un orden que
    // cambia solo al guardar una nota seria ilegible.
    groups.sort_by(|a, b| a.order.cmp(&b.order).then_with(|| a.id.cmp(&b.id)));
    groups
}

#[cfg(test)]
mod tests {
    use super::*;

    fn group(id: &str, name: &str, order: u32) -> NoteGroup {
        NoteGroup {
            id: id.to_string(),
            name: name.to_string(),
            color_hex: "#FF0000".to_string(),
            order,
        }
    }

    #[test]
    fn the_first_folder_is_the_group() {
        assert_eq!(group_of("odm/vuelo-27.md").as_deref(), Some("odm"));
        // Solo el primer nivel: un grupo no tiene subgrupos.
        assert_eq!(group_of("odm/vuelos/x.md").as_deref(), Some("odm"));
    }

    #[test]
    fn notes_without_a_group() {
        assert_eq!(group_of("suelta.md"), None);
        assert_eq!(group_of("inbox/2026-09-16-algo.md"), None);
    }

    /// Meter una nota en `diario/` o `proyectos/` le cambiaria el rol, y con el
    /// su comportamiento. No pueden ser agrupaciones.
    #[test]
    fn reserved_folders_are_never_groups() {
        assert_eq!(group_of("diario/2026-09-16.md"), None);
        assert_eq!(group_of("proyectos/ODM.md"), None);
        assert_eq!(group_of("privado/claves.md"), None);
        assert_eq!(group_of(".obsidian/config.md"), None);
    }

    /// Cada carpeta tiene sus agrupaciones: el mismo `clientes/` en dos carpetas
    /// son dos agrupaciones distintas.
    #[test]
    fn a_local_folder_has_its_own_groups() {
        assert_eq!(virtual_group_of("clientes/acme.md").as_deref(), Some("clientes"));
        assert_eq!(
            virtual_group_of("@apuntes/clientes/acme.md").as_deref(),
            Some("@apuntes/clientes")
        );
        assert_eq!(virtual_group_of("@apuntes/suelta.md"), None);
        assert_eq!(virtual_group_of("@apuntes/diario/hoy.md"), None);

        let groups = list_groups(["clientes/a.md", "@apuntes/clientes/b.md"].into_iter(), &[]);
        let ids: Vec<&str> = groups.iter().map(|g| g.id.as_str()).collect();
        assert_eq!(ids, ["@apuntes/clientes", "clientes"]);
        assert_eq!(groups[0].name, "clientes", "sin el prefijo al enseñarlo");
    }

    #[test]
    fn moving_between_groups_keeps_the_file_name() {
        assert_eq!(path_in_group("inbox/nota.md", Some("odm")), "odm/nota.md");
        assert_eq!(path_in_group("odm/nota.md", Some("trabajo")), "trabajo/nota.md");
        // Sin grupo vuelve a la bandeja.
        assert_eq!(path_in_group("odm/nota.md", None), "inbox/nota.md");
        assert_eq!(path_in_group("odm/nota.md", Some("   ")), "inbox/nota.md");
    }

    #[test]
    fn a_name_becomes_a_safe_folder() {
        assert_eq!(validate_group_name("Trabajo de campo").unwrap(), "trabajo-de-campo");
        assert_eq!(validate_group_name(" ODM ").unwrap(), "odm");
        assert_eq!(validate_group_name("Año ñandú").unwrap(), "ano-nandu");
        assert!(validate_group_name("   ").is_err());
    }

    #[test]
    fn a_reserved_name_is_refused_with_its_reason() {
        let error = validate_group_name("Diario").unwrap_err();
        assert!(error.contains("reservada"), "{error}");
        assert!(validate_group_name("inbox").is_err());
    }

    #[test]
    fn colors_are_rrggbb() {
        assert_eq!(validate_color("#6366f1").unwrap(), "#6366F1");
        assert!(validate_color("6366F1").is_err());
        assert!(validate_color("#63F").is_err());
        assert!(validate_color("#GGGGGG").is_err());
    }

    /// Lo que hay en el disco manda: una carpeta sin catalogo se enseña igual.
    #[test]
    fn folders_without_a_catalog_entry_still_show_up() {
        let groups = list_groups(
            ["odm/a.md", "odm/b.md", "temas/c.md", "inbox/d.md"].into_iter(),
            &[],
        );
        let ids: Vec<&str> = groups.iter().map(|g| g.id.as_str()).collect();
        assert_eq!(ids, ["odm", "temas"]);
        assert_eq!(groups[0].notes, 2);
        assert_eq!(groups[0].color_hex, DEFAULT_GROUP_COLOR);
        assert_eq!(groups[0].name, "odm");
    }

    #[test]
    fn the_catalog_adds_name_color_and_order() {
        let catalog = vec![group("odm", "Tandas de ODM", 0)];
        let groups = list_groups(["temas/a.md", "odm/b.md"].into_iter(), &catalog);
        assert_eq!(groups[0].id, "odm", "el orden del catalogo va primero");
        assert_eq!(groups[0].name, "Tandas de ODM");
        assert_eq!(groups[0].color_hex, "#FF0000");
        assert_eq!(groups[1].id, "temas");
    }

    /// Borrar la ultima nota de un grupo no puede hacerlo desaparecer sin decir
    /// nada: sigue en la lista, vacio.
    #[test]
    fn a_catalog_group_with_no_notes_is_still_listed() {
        let catalog = vec![group("vacio", "Vacío", 1)];
        let groups = list_groups(["odm/a.md"].into_iter(), &catalog);
        let vacio = groups.iter().find(|g| g.id == "vacio").expect("sigue estando");
        assert_eq!(vacio.notes, 0);
    }
}
