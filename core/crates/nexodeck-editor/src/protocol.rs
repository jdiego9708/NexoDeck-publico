//! Los mensajes entre la pagina y Rust.
//!
//! Tienen que coincidir uno a uno con `web/src/protocol.ts`: objetos con un
//! campo `type` y los nombres en camelCase, que es lo natural en TypeScript.
//! Los tests de abajo fijan la forma exacta del JSON, porque un campo mal
//! nombrado no falla en ningun compilador: la pagina simplemente no reacciona.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteDto {
    /// Relativa a la boveda, con `/` y `.md`.
    pub path: String,
    pub title: String,
    /// Con `\n`: el backend conserva el CRLF y el BOM del fichero al guardar.
    pub text: String,
    /// sha256 del fichero tal como se abrio; `None` en una nota que no existe.
    pub hash: Option<String>,
    /// Esta en `privado/`: ningun agente la lee.
    pub private: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LinkTargetDto {
    /// Lo que va dentro de `[[ ]]`: la ruta sin `.md`.
    pub target: String,
    pub title: String,
}

/// Los colores del `ColorScheme` de Flutter, en `#RRGGBB`, para que la ventana
/// del editor se vea como el resto de NexoDeck.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ThemeDto {
    pub dark: bool,
    pub surface: String,
    pub surface_container: String,
    pub surface_container_high: String,
    pub on_surface: String,
    pub on_surface_variant: String,
    pub primary: String,
    pub on_primary: String,
    pub primary_container: String,
    pub outline_variant: String,
    pub error: String,
    pub tertiary: String,
}

impl ThemeDto {
    /// El fondo del WebView antes de que pinte la pagina. Sin esto, abrir el
    /// editor en tema oscuro da un fogonazo blanco.
    pub fn background_rgba(&self) -> Option<(u8, u8, u8, u8)> {
        let hex = self.surface.strip_prefix('#')?;
        if hex.len() != 6 {
            return None;
        }
        let channel = |at: usize| u8::from_str_radix(hex.get(at..at + 2)?, 16).ok();
        Some((channel(0)?, channel(2)?, channel(4)?, 255))
    }
}

/// Una nota de la boveda, para la lista.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NoteSummaryDto {
    /// Virtual: `@<carpeta>/<ruta>` si es de una carpeta local.
    pub path: String,
    /// El id de su carpeta local, o `None` si es de la boveda principal.
    #[serde(default)]
    pub folder: Option<String>,
    /// El id de su agrupacion (la carpeta), o `None` si esta en `inbox/`.
    pub group: Option<String>,
    pub title: String,
    /// `note`, `daily` o `hub`.
    pub role: String,
    /// `AAAA-MM-DD`: la del frontmatter o la del nombre de una nota diaria.
    pub date: Option<String>,
    pub tags: Vec<String>,
    pub open_tasks: u32,
    /// `ai: false`: ningun agente la lee.
    pub ai_excluded: bool,
    /// Cuando cambio el fichero, RFC 3339.
    pub modified: Option<String>,
}

/// Una tarea abierta de alguna nota.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TaskDto {
    pub path: String,
    /// Linea del fichero, desde 1.
    pub line: u32,
    pub text: String,
    pub done: bool,
    /// `AAAA-MM-DD`, del `📅` de Obsidian Tasks.
    pub due: Option<String>,
}

/// Un resultado de busqueda: una seccion de nota, un hallazgo o un commit.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HitDto {
    /// `n:<ruta>#<seccion>`, `f:<hallazgo>` o `c:<repo>@<sha>`.
    pub id: String,
    /// `note`, `finding` o `commit`.
    pub kind: String,
    pub title: String,
    pub snippet: String,
    pub date: Option<String>,
    /// La nota, si el resultado es una seccion de nota.
    pub path: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentStepDto {
    /// `reader`, `memory`, `code`, `critic` o `synthesizer`, con `#2` si repitio.
    pub agent: String,
    pub ok: bool,
    pub millis: u32,
    /// Su salida ya verificada, en JSON legible.
    pub output: Option<String>,
    pub detail: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CandidateDto {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub snippet: String,
    pub date: Option<String>,
}

/// Lo que hizo el asistente con una nota, con su traza.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DigestDto {
    pub id: String,
    pub note: String,
    /// `manual`, `idle` o `mcp`.
    pub trigger: String,
    /// `queued`, `running`, `proposed`, `skipped`, `failed` o `waiting_model`.
    pub state: String,
    pub state_detail: Option<String>,
    pub proposal_id: Option<String>,
    pub created_at: String,
    pub model_label: String,
    pub hub: Option<String>,
    pub requeried: bool,
    pub discarded_ids: Vec<String>,
    pub redactions: u32,
    pub candidates: Vec<CandidateDto>,
    pub steps: Vec<AgentStepDto>,
}

/// Una agrupacion de notas: una carpeta de la boveda, con su nombre y color.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GroupDto {
    /// El nombre de la carpeta. Es la identidad.
    pub id: String,
    pub name: String,
    /// `#RRGGBB`. La pagina lo valida antes de usarlo: llega de un fichero que
    /// el usuario puede editar a mano.
    pub color_hex: String,
    pub notes: u32,
}

/// Una carpeta de notas: la boveda principal o una carpeta local, que se lee en
/// su sitio sin copiarse.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FolderDto {
    /// El id de su proyecto; el prefijo de sus notas si es local.
    pub id: String,
    pub name: String,
    /// La ruta real en disco.
    pub path: String,
    pub local: bool,
    /// `false` si la carpeta no esta (un disco desconectado).
    pub available: bool,
}

/// La foto de la boveda para la barra lateral.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OverviewDto {
    /// `false` si el buzon no tiene ninguna boveda configurada.
    pub configured: bool,
    pub root: Option<String>,
    /// La principal primero y despues las locales, en el orden de la
    /// configuracion.
    #[serde(default)]
    pub folders: Vec<FolderDto>,
    /// Ya ordenadas. Las notas sin agrupacion no estan en ninguna.
    pub groups: Vec<GroupDto>,
    /// De la tocada mas recientemente a la mas vieja.
    pub notes: Vec<NoteSummaryDto>,
    pub tasks: Vec<TaskDto>,
    /// Del mas nuevo al mas viejo.
    pub digests: Vec<DigestDto>,
    pub error: Option<String>,
}

/// Lo que rodea a la nota abierta, para el panel de la derecha.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DetailsDto {
    pub path: String,
    /// Las notas que enlazan a esta.
    pub backlinks: Vec<String>,
    pub related: Vec<HitDto>,
    /// Del mas nuevo al mas viejo.
    pub digests: Vec<DigestDto>,
}

impl DetailsDto {
    /// El panel vacio de una nota que no esta en el indice (una privada).
    pub fn empty(path: &str) -> DetailsDto {
        DetailsDto {
            path: path.to_string(),
            backlinks: Vec::new(),
            related: Vec::new(),
            digests: Vec::new(),
        }
    }
}

/// De Rust a la pagina.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum HostMessage {
    Load {
        note: NoteDto,
        targets: Vec<LinkTargetDto>,
        theme: Option<ThemeDto>,
    },
    Saved {
        path: String,
        hash: String,
    },
    /// En disco hay otra cosa que lo que abrio el editor; no se escribio nada.
    /// `disk_hash` vacio significa que la nota ya no existe.
    Conflict {
        path: String,
        disk_text: String,
        disk_hash: String,
    },
    Error {
        message: String,
    },
    Targets {
        targets: Vec<LinkTargetDto>,
    },
    Theme {
        theme: ThemeDto,
    },
    Overview {
        overview: OverviewDto,
    },
    SearchResults {
        query: String,
        hits: Vec<HitDto>,
    },
    Details {
        details: DetailsDto,
    },
    /// Un aviso breve que no es un error.
    Notice {
        message: String,
    },
    /// Alguien quiere cerrar la ventana (o cambiar de nota): la pagina guarda lo
    /// pendiente y contesta `closeReady`.
    RequestClose,
}

/// De la pagina a Rust.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum PageMessage {
    Ready,
    Save {
        path: String,
        text: String,
        base_hash: Option<String>,
        reason: SaveReason,
    },
    Dirty {
        dirty: bool,
    },
    OpenLink {
        target: String,
    },
    OpenExternal {
        url: String,
    },
    CloseReady,
    /// Abrir una nota de la barra lateral, de una tarea o de un enlace del panel.
    OpenNote {
        path: String,
    },
    CreateNote {
        path: String,
        title: String,
    },
    OpenDaily,
    /// Mover una nota a otra carpeta de la boveda. `group` vacio la devuelve a
    /// la bandeja (`inbox/`), `"privado"` la esconde de los agentes y cualquier
    /// otro nombre es una agrupacion.
    MoveNote {
        path: String,
        group: Option<String>,
    },
    Search {
        query: String,
    },
    RequestDetails {
        path: String,
    },
    /// Mandar la nota al asistente.
    Digest {
        path: String,
    },
    /// Abrir el buzon en la app, donde se aprueban las propuestas.
    ShowInbox,
    Refresh,
    /// Elegir otra carpeta principal de notas (el "espacio de NexoDeck"). La
    /// carpeta la elige el usuario en el dialogo nativo que abre Rust: la pagina
    /// nunca manda una ruta, asi no puede apuntar NexoDeck a donde quiera.
    ChooseVault,
    /// Añadir una carpeta de notas locales, elegida en el dialogo nativo.
    ImportLocalFolder,
    /// Importar un cuaderno de OneNote (`.one`): el fichero y la carpeta de
    /// destino se eligen en dialogos nativos.
    ImportOneNote,
    /// Quitar una carpeta local de NexoDeck. No borra nada del disco.
    RemoveLocalFolder {
        id: String,
    },
    /// Exportar la boveda principal a un zip. `file_name` es solo la sugerencia
    /// del dialogo de guardar (la pagina sabe la fecha local).
    ExportVault {
        file_name: String,
    },
    /// La pagina resolvio la banda de conflicto. `kept` es `mine` o `disk`.
    ///
    /// En la PC no hace falta: "recargar del disco" ya es lo que hay en disco, y
    /// "quedarme con lo mio" llega como un guardado. En el movil si: el choque
    /// esta guardado en el espejo, y si el usuario elige la version de la PC hay
    /// que decirselo al espejo, o la banda volveria a salir al abrir la nota.
    ConflictResolved {
        path: String,
        kept: String,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SaveReason {
    Auto,
    Manual,
    Close,
    Overwrite,
}

/// El JavaScript que entrega un mensaje a la pagina.
///
/// El JSON va como literal de objeto y no dentro de una cadena: asi no hay nada
/// que escapar, y desde ES2019 cualquier JSON valido es JavaScript valido
/// (incluidos U+2028 y U+2029, que antes no lo eran).
pub fn script_for(message: &HostMessage) -> String {
    let json = serde_json::to_string(message).unwrap_or_else(|_| "null".to_string());
    format!("window.nexodeck && window.nexodeck.receive({json});")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn theme() -> ThemeDto {
        ThemeDto {
            dark: true,
            surface: "#12141A".into(),
            surface_container: "#1E2028".into(),
            surface_container_high: "#282A33".into(),
            on_surface: "#E3E2E9".into(),
            on_surface_variant: "#C5C6D0".into(),
            primary: "#B0C6FF".into(),
            on_primary: "#002D6E".into(),
            primary_container: "#20438F".into(),
            outline_variant: "#44464F".into(),
            error: "#FFB4AB".into(),
            tertiary: "#E0B6F0".into(),
        }
    }

    #[test]
    fn host_messages_have_the_shape_the_page_expects() {
        let conflict = HostMessage::Conflict {
            path: "temas/malla.md".into(),
            disk_text: "de obsidian".into(),
            disk_hash: "h9".into(),
        };
        assert_eq!(
            serde_json::to_value(&conflict).unwrap(),
            json!({"type": "conflict", "path": "temas/malla.md", "diskText": "de obsidian", "diskHash": "h9"})
        );
        assert_eq!(
            serde_json::to_value(HostMessage::RequestClose).unwrap(),
            json!({"type": "requestClose"})
        );

        let load = serde_json::to_value(HostMessage::Load {
            note: NoteDto {
                path: "a.md".into(),
                title: "A".into(),
                text: "# A\n".into(),
                hash: None,
                private: true,
            },
            targets: vec![LinkTargetDto {
                target: "temas/malla".into(),
                title: "Malla".into(),
            }],
            theme: Some(theme()),
        })
        .unwrap();
        assert_eq!(load["type"], "load");
        assert_eq!(load["note"]["hash"], serde_json::Value::Null);
        assert_eq!(load["note"]["private"], true);
        assert_eq!(load["targets"][0]["target"], "temas/malla");
        assert_eq!(load["theme"]["surfaceContainerHigh"], "#282A33");
        assert_eq!(load["theme"]["onSurfaceVariant"], "#C5C6D0");
    }

    #[test]
    fn the_overview_uses_camel_case_all_the_way_down() {
        let overview = serde_json::to_value(HostMessage::Overview {
            overview: OverviewDto {
                configured: true,
                root: Some(r"D:\Notas".into()),
                folders: vec![FolderDto {
                    id: "apuntes".into(),
                    name: "Apuntes".into(),
                    path: r"D:\Apuntes".into(),
                    local: true,
                    available: true,
                }],
                groups: vec![GroupDto {
                    id: "temas".into(),
                    name: "Temas".into(),
                    color_hex: "#10B981".into(),
                    notes: 1,
                }],
                notes: vec![NoteSummaryDto {
                    path: "temas/malla.md".into(),
                    folder: None,
                    group: Some("temas".into()),
                    title: "Malla".into(),
                    role: "note".into(),
                    date: None,
                    tags: vec!["odm".into()],
                    open_tasks: 2,
                    ai_excluded: false,
                    modified: Some("2026-09-15T13:00:00Z".into()),
                }],
                tasks: vec![TaskDto {
                    path: "temas/malla.md".into(),
                    line: 5,
                    text: "Reprocesar".into(),
                    done: false,
                    due: Some("2026-09-10".into()),
                }],
                digests: vec![DigestDto {
                    id: "d-1".into(),
                    note: "temas/malla.md".into(),
                    trigger: "manual".into(),
                    state: "waiting_model".into(),
                    state_detail: Some("sin red".into()),
                    proposal_id: None,
                    created_at: "2026-09-15T14:05:00Z".into(),
                    model_label: "deepseek-chat".into(),
                    hub: None,
                    requeried: false,
                    discarded_ids: vec![],
                    redactions: 1,
                    candidates: vec![],
                    steps: vec![AgentStepDto {
                        agent: "reader".into(),
                        ok: true,
                        millis: 812,
                        output: None,
                        detail: None,
                    }],
                }],
                error: None,
            },
        })
        .unwrap();
        assert_eq!(overview["type"], "overview");
        let body = &overview["overview"];
        assert_eq!(body["notes"][0]["openTasks"], 2);
        assert_eq!(body["notes"][0]["aiExcluded"], false);
        assert_eq!(body["tasks"][0]["due"], "2026-09-10");
        assert_eq!(body["digests"][0]["stateDetail"], "sin red");
        assert_eq!(body["digests"][0]["modelLabel"], "deepseek-chat");
        assert_eq!(body["digests"][0]["steps"][0]["millis"], 812);

        assert_eq!(
            serde_json::to_value(HostMessage::SearchResults {
                query: "malla".into(),
                hits: vec![]
            })
            .unwrap(),
            json!({"type": "searchResults", "query": "malla", "hits": []})
        );
    }

    #[test]
    fn page_messages_parse_from_what_the_page_sends() {
        let save: PageMessage = serde_json::from_str(
            r#"{"type":"save","path":"a.md","text":"ñandú","baseHash":null,"reason":"overwrite"}"#,
        )
        .unwrap();
        assert_eq!(
            save,
            PageMessage::Save {
                path: "a.md".into(),
                text: "ñandú".into(),
                base_hash: None,
                reason: SaveReason::Overwrite,
            }
        );
        let link: PageMessage =
            serde_json::from_str(r#"{"type":"openLink","target":"temas/malla"}"#).unwrap();
        assert_eq!(link, PageMessage::OpenLink { target: "temas/malla".into() });
        assert_eq!(
            serde_json::from_str::<PageMessage>(r#"{"type":"closeReady"}"#).unwrap(),
            PageMessage::CloseReady
        );
        assert_eq!(
            serde_json::from_str::<PageMessage>(
                r#"{"type":"createNote","path":"privado/claves.md","title":"Claves"}"#
            )
            .unwrap(),
            PageMessage::CreateNote {
                path: "privado/claves.md".into(),
                title: "Claves".into()
            }
        );
        assert_eq!(
            serde_json::from_str::<PageMessage>(r#"{"type":"requestDetails","path":"a.md"}"#).unwrap(),
            PageMessage::RequestDetails { path: "a.md".into() }
        );
        assert_eq!(
            serde_json::from_str::<PageMessage>(
                r#"{"type":"moveNote","path":"temas/malla.md","group":"privado"}"#
            )
            .unwrap(),
            PageMessage::MoveNote {
                path: "temas/malla.md".into(),
                group: Some("privado".into()),
            }
        );
        assert_eq!(
            serde_json::from_str::<PageMessage>(r#"{"type":"moveNote","path":"a.md","group":null}"#).unwrap(),
            PageMessage::MoveNote {
                path: "a.md".into(),
                group: None,
            }
        );
        for (raw, expected) in [
            (r#"{"type":"openDaily"}"#, PageMessage::OpenDaily),
            (r#"{"type":"showInbox"}"#, PageMessage::ShowInbox),
            (r#"{"type":"refresh"}"#, PageMessage::Refresh),
            (r#"{"type":"importOneNote"}"#, PageMessage::ImportOneNote),
        ] {
            assert_eq!(serde_json::from_str::<PageMessage>(raw).unwrap(), expected);
        }
        assert!(serde_json::from_str::<PageMessage>(r#"{"type":"formatDisk"}"#).is_err());
    }

    #[test]
    fn the_background_comes_from_the_surface_color() {
        assert_eq!(theme().background_rgba(), Some((0x12, 0x14, 0x1A, 255)));
        let broken = ThemeDto {
            surface: "azul".into(),
            ..theme()
        };
        assert_eq!(broken.background_rgba(), None);
    }

    #[test]
    fn the_script_hands_the_json_to_the_page() {
        let script = script_for(&HostMessage::Error {
            message: "no hay \"boveda\"\u{2028}".into(),
        });
        assert!(script.starts_with("window.nexodeck && window.nexodeck.receive({"));
        assert!(script.contains(r#""type":"error""#));
        assert!(script.contains(r#"no hay \"boveda\""#));
    }
}
