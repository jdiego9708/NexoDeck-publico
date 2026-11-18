//! La boveda del buzon, atendiendo al telefono.
//!
//! El transporte no puede depender de `nexodeck-docs` (tambien se compila para
//! Android, donde ese crate no entra), asi que la boveda se engancha en tiempo
//! de ejecucion: esto implementa `nexodeck_transport::notes::NotesVault` sobre
//! el mismo `DocsService` que usan el buzon, el editor y los agentes, y lo
//! registra al abrir el buzon. Mismo patron que
//! `nexodeck_control::control().set_docs(...)`.
//!
//! Aca no hay IA ni propuestas: es el usuario leyendo y escribiendo sus notas
//! desde el movil. Por eso viajan tambien las de `privado/`, que ningun agente
//! lee. Lo que **no** cambia es lo que evita perder trabajo: cada guardado y
//! cada borrado llevan el hash con el que el telefono vio la nota, y si en
//! disco hay otra cosa no se escribe nada y se devuelve lo que hay.
//!
//! Este modulo no expone nada a Dart: no es una api de frb, es el enganche
//! entre dos crates de Rust.

use std::sync::Arc;

use nexodeck_docs::{DeleteOutcome, DocsService, SaveOutcome};
use nexodeck_protocol::{NoteContentWire, NoteOpResultWire, NoteOpWire, NoteStampWire};
use nexodeck_transport::notes::NotesVault;

/// Engancha la boveda al transporte. Idempotente: registrar dos veces deja la
/// ultima, que es la misma.
pub(crate) fn register(service: &Arc<DocsService>) {
    let Some(host) = nexodeck_transport::server::host() else {
        // Todavia no arranco el transporte. `start_transport_host` vuelve a
        // registrar, asi que el orden entre los dos no importa.
        return;
    };
    host.set_notes_vault(Some(Arc::new(DocsVault {
        service: Arc::clone(service),
    })));
}

/// Avisa a los telefonos conectados con cada cambio del buzon: una nota
/// guardada, una propuesta aprobada, o lo que llegue desde otro telefono.
///
/// Se lanza una sola vez, al abrir el buzon. El aviso no lleva el cambio: cada
/// telefono pide el manifiesto y compara (ver `MessageV1::NotesChanged`).
pub(crate) fn spawn_change_notifier(service: &Arc<DocsService>) {
    let mut events = service.subscribe();
    tokio::spawn(async move {
        // Atrasarse (`Lagged`) no pierde nada: un aviso vale por todos los que
        // se saltaron, porque quien compara es el telefono con su copia. Solo
        // `Closed` corta el bucle.
        while let Ok(()) | Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) =
            events.recv().await
        {
            if let Some(host) = nexodeck_transport::server::host() {
                host.notify_notes_changed();
            }
        }
    });
}

struct DocsVault {
    service: Arc<DocsService>,
}

impl NotesVault for DocsVault {
    fn manifest(&self) -> Result<Vec<NoteStampWire>, String> {
        let manifest = self.service.vault_manifest().map_err(|e| e.to_string())?;
        Ok(manifest
            .notes
            .into_iter()
            .map(|note| NoteStampWire {
                path: note.path,
                hash: note.hash,
                modified_secs: note.modified_secs,
                private: note.private,
            })
            .collect())
    }

    fn fetch(&self, paths: &[String]) -> Result<Vec<NoteContentWire>, String> {
        Ok(paths
            .iter()
            .map(|path| match self.service.open_note_for_edit(path) {
                Ok(note) => NoteContentWire {
                    path: note.path,
                    text: note.text,
                    hash: note.hash,
                    private: note.private,
                    exists: true,
                },
                // Una nota que ya no esta no es un error: es justo lo que el
                // telefono necesita saber para borrarla de su copia.
                Err(_) => NoteContentWire {
                    path: path.clone(),
                    text: String::new(),
                    hash: String::new(),
                    private: false,
                    exists: false,
                },
            })
            .collect())
    }

    fn apply(&self, ops: &[NoteOpWire]) -> Vec<NoteOpResultWire> {
        ops.iter().map(|op| self.apply_one(op)).collect()
    }
}

impl DocsVault {
    fn apply_one(&self, op: &NoteOpWire) -> NoteOpResultWire {
        match op {
            NoteOpWire::Save {
                path,
                text,
                base_hash,
            } => match self.service.save_note(path, text, base_hash.as_deref()) {
                Ok(SaveOutcome::Saved { hash }) => NoteOpResultWire::Saved {
                    path: path.clone(),
                    hash,
                },
                Ok(SaveOutcome::Conflict {
                    disk_text,
                    disk_hash,
                }) => NoteOpResultWire::Conflict {
                    path: path.clone(),
                    disk_text,
                    disk_hash,
                },
                Err(error) => NoteOpResultWire::Failed {
                    path: path.clone(),
                    detail: error.to_string(),
                },
            },
            NoteOpWire::Delete { path, base_hash } => {
                match self.service.delete_note(path, base_hash.as_deref()) {
                    // Borrar lo que ya no esta no es un fallo: un telefono que
                    // reintenta tras quedarse sin cobertura tiene que terminar.
                    Ok(DeleteOutcome::Trashed { .. }) | Ok(DeleteOutcome::Missing) => {
                        NoteOpResultWire::Deleted { path: path.clone() }
                    }
                    Ok(DeleteOutcome::Conflict {
                        disk_text,
                        disk_hash,
                    }) => NoteOpResultWire::Conflict {
                        path: path.clone(),
                        disk_text,
                        disk_hash,
                    },
                    Err(error) => NoteOpResultWire::Failed {
                        path: path.clone(),
                        detail: error.to_string(),
                    },
                }
            }
        }
    }
}
