//! Las notas del telefono, resueltas contra la boveda de la PC.
//!
//! **El transporte no puede depender de `nexodeck-docs`**: ese crate arrastra
//! `nexodeck-ai` (pila HTTP y sidecar del modelo), y este se compila tambien
//! para el `.so` de Android. Mismo gotcha que `nusb` y `arboard`.
//!
//! Asi que la boveda se engancha en tiempo de ejecucion: la FFI, que si es de
//! escritorio, registra un [`NotesVault`] con
//! [`crate::server::TransportHost::set_notes_vault`]. Sin nadie registrado, las
//! peticiones se contestan con `Failed` en vez de quedarse mudas -- un telefono
//! esperando sin respuesta no distingue "todavia no" de "nunca".
//!
//! Mismo patron que `nexodeck_control::control().set_docs(...)`.

use nexodeck_protocol::{NoteOpResultWire, NoteOpWire, NotesRequestWire, NotesResponseWire};

/// La boveda, vista desde el transporte.
///
/// **Los tres metodos son sincronos y lentos**: recorren la carpeta y leen
/// ficheros. Nunca se llaman desde el bucle de la sesion; van en
/// `spawn_blocking` (ver `server.rs`).
pub trait NotesVault: Send + Sync + 'static {
    /// Todas las notas con su hash, `privado/` incluido.
    fn manifest(&self) -> Result<Vec<nexodeck_protocol::NoteStampWire>, String>;
    /// El texto de esas notas. Una que ya no exista vuelve con `exists: false`,
    /// que es como el telefono se entera de que tiene que borrarla de su copia.
    fn fetch(&self, paths: &[String]) -> Result<Vec<nexodeck_protocol::NoteContentWire>, String>;
    /// Guarda o borra, **en orden**, y devuelve un resultado por operacion.
    fn apply(&self, ops: &[NoteOpWire]) -> Vec<NoteOpResultWire>;
}

/// Resuelve una peticion del telefono. Se llama dentro de `spawn_blocking`.
pub(crate) fn resolve(vault: &dyn NotesVault, request: NotesRequestWire) -> NotesResponseWire {
    match request {
        NotesRequestWire::Manifest => match vault.manifest() {
            Ok(notes) => NotesResponseWire::Manifest { notes },
            Err(detail) => NotesResponseWire::Failed { detail },
        },
        NotesRequestWire::Fetch { paths } => match vault.fetch(&paths) {
            Ok(notes) => NotesResponseWire::Fetch { notes },
            Err(detail) => NotesResponseWire::Failed { detail },
        },
        // `apply` no falla entera: cada operacion trae su propio resultado, para
        // que un choque en la tercera no tire las dos que ya se guardaron.
        NotesRequestWire::Apply { ops } => NotesResponseWire::Applied {
            results: vault.apply(&ops),
        },
    }
}

/// Lo que se contesta cuando la PC no tiene boveda enganchada: el buzon todavia
/// no arranco, o esta app no es de escritorio.
pub(crate) fn no_vault() -> NotesResponseWire {
    NotesResponseWire::Failed {
        detail: "la PC no tiene el buzon de notas iniciado".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nexodeck_protocol::{NoteContentWire, NoteStampWire};

    struct Fake;

    impl NotesVault for Fake {
        fn manifest(&self) -> Result<Vec<NoteStampWire>, String> {
            Ok(vec![NoteStampWire {
                path: "temas/malla.md".into(),
                hash: "h1".into(),
                modified_secs: Some(10),
                private: false,
            }])
        }

        fn fetch(&self, paths: &[String]) -> Result<Vec<NoteContentWire>, String> {
            Ok(paths
                .iter()
                .map(|path| NoteContentWire {
                    path: path.clone(),
                    text: "# Malla\n".into(),
                    hash: "h1".into(),
                    private: false,
                    exists: true,
                })
                .collect())
        }

        fn apply(&self, ops: &[NoteOpWire]) -> Vec<NoteOpResultWire> {
            ops.iter()
                .map(|op| match op {
                    NoteOpWire::Save { path, text, .. } => NoteOpResultWire::Saved {
                        path: path.clone(),
                        hash: format!("h:{}", text.len()),
                    },
                    NoteOpWire::Delete { path, .. } => {
                        NoteOpResultWire::Deleted { path: path.clone() }
                    }
                })
                .collect()
        }
    }

    struct Roto;

    impl NotesVault for Roto {
        fn manifest(&self) -> Result<Vec<NoteStampWire>, String> {
            Err("no hay boveda configurada".into())
        }
        fn fetch(&self, _paths: &[String]) -> Result<Vec<NoteContentWire>, String> {
            Err("no hay boveda configurada".into())
        }
        fn apply(&self, ops: &[NoteOpWire]) -> Vec<NoteOpResultWire> {
            ops.iter()
                .map(|op| {
                    let path = match op {
                        NoteOpWire::Save { path, .. } | NoteOpWire::Delete { path, .. } => path,
                    };
                    NoteOpResultWire::Failed {
                        path: path.clone(),
                        detail: "no hay boveda configurada".into(),
                    }
                })
                .collect()
        }
    }

    #[test]
    fn each_request_gets_its_own_answer() {
        assert!(matches!(
            resolve(&Fake, NotesRequestWire::Manifest),
            NotesResponseWire::Manifest { notes } if notes.len() == 1
        ));
        assert!(matches!(
            resolve(&Fake, NotesRequestWire::Fetch { paths: vec!["a.md".into(), "b.md".into()] }),
            NotesResponseWire::Fetch { notes } if notes.len() == 2
        ));
    }

    /// Un choque o un fallo en una operacion no tira las demas: por eso `apply`
    /// contesta una lista y no un error.
    #[test]
    fn a_batch_answers_one_result_per_operation() {
        let ops = vec![
            NoteOpWire::Save {
                path: "temas/nueva.md".into(),
                text: "hola".into(),
                base_hash: None,
            },
            NoteOpWire::Delete {
                path: "temas/vieja.md".into(),
                base_hash: Some("h2".into()),
            },
        ];
        let NotesResponseWire::Applied { results } = resolve(&Fake, NotesRequestWire::Apply { ops })
        else {
            panic!("tendria que ser Applied");
        };
        assert_eq!(
            results,
            vec![
                NoteOpResultWire::Saved {
                    path: "temas/nueva.md".into(),
                    hash: "h:4".into()
                },
                NoteOpResultWire::Deleted {
                    path: "temas/vieja.md".into()
                },
            ]
        );
    }

    #[test]
    fn a_vault_that_fails_answers_instead_of_going_quiet() {
        assert!(matches!(
            resolve(&Roto, NotesRequestWire::Manifest),
            NotesResponseWire::Failed { .. }
        ));
        assert!(matches!(no_vault(), NotesResponseWire::Failed { .. }));
    }
}
