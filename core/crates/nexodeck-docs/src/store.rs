//! El almacen en disco: `config.json`, un fichero por hallazgo y una carpeta por
//! propuesta.
//!
//! Toda escritura es atomica ([`write_atomic`]): se escribe a un temporal en el
//! mismo directorio, se fuerza a disco y se renombra encima. Un corte a mitad
//! deja el fichero anterior intacto. Este equipo ya perdio una migracion de
//! Drift a medias por un apagon; aca eso no puede dejar un JSON cortado.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::de::DeserializeOwned;
use serde::Serialize;
use sha2::{Digest, Sha256};

use crate::config::InboxConfig;
use crate::error::{DocsError, DocsResult};
use crate::model::{Finding, FindingStatus, NewFinding, Proposal, MAX_FINDINGS_PER_CALL};

/// Un reenvio del mismo hallazgo dentro de este plazo devuelve el id que ya
/// existe. Un cliente MCP que reintenta tras un timeout no duplica nada.
const DEDUP_WINDOW_SECS: i64 = 24 * 3600;

const TMP_SUFFIX: &str = ".nexodeck-tmp";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SubmitOutcome {
    /// El lote de los hallazgos guardados en esta llamada. Si ninguno era
    /// nuevo, es el lote en el que ya estaban: un cliente que reintenta el mismo
    /// envio recibe el lote original, y `finding_status` por ese lote los
    /// encuentra. En un envio mezclado, los repetidos conservan su lote de antes.
    pub batch_id: String,
    /// Uno por hallazgo recibido, en el mismo orden.
    pub ids: Vec<String>,
    /// Los que ya existian y no se volvieron a guardar.
    pub duplicates: Vec<String>,
}

pub struct Inbox {
    root: PathBuf,
    /// Serializa las escrituras de hallazgos: dos `submit` a la vez podrian no
    /// verse entre si y saltarse la deduplicacion.
    write_lock: Mutex<()>,
}

impl Inbox {
    /// `<datos del usuario>/docs_inbox`, al lado de `control_token.txt`.
    pub fn default_root() -> DocsResult<PathBuf> {
        let dirs = directories::ProjectDirs::from("dev", "nexodeck", "NexoDeck")
            .ok_or(DocsError::NoDataDir)?;
        Ok(dirs.data_dir().join("docs_inbox"))
    }

    pub fn open(root: impl Into<PathBuf>) -> DocsResult<Self> {
        let root = root.into();
        for dir in [root.join("findings"), root.join("proposals")] {
            std::fs::create_dir_all(&dir).map_err(|e| DocsError::io(&dir, e))?;
        }
        Ok(Inbox {
            root,
            write_lock: Mutex::new(()),
        })
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    fn config_path(&self) -> PathBuf {
        self.root.join("config.json")
    }

    /// Sin fichero, la configuracion por defecto: sin proyectos y con el
    /// trabajador apagado.
    pub fn config(&self) -> DocsResult<InboxConfig> {
        let path = self.config_path();
        if !path.exists() {
            return Ok(InboxConfig::default());
        }
        read_json(&path)
    }

    /// Se valida antes de guardar: una configuracion rota en disco haria
    /// fallar cada `submit_findings` con un error que no dice nada del fichero.
    pub fn save_config(&self, config: &InboxConfig) -> DocsResult<()> {
        let problems = config.problems();
        if !problems.is_empty() {
            return Err(DocsError::Invalid(problems.join("\n")));
        }
        write_json(&self.config_path(), config)
    }

    pub fn submit(
        &self,
        project: &str,
        from: Option<String>,
        items: Vec<NewFinding>,
        now: jiff::Timestamp,
    ) -> DocsResult<SubmitOutcome> {
        let config = self.config()?;
        if config.project(project).is_none() {
            let valid = config.project_ids();
            return Err(DocsError::Invalid(if valid.is_empty() {
                format!("no hay ningun proyecto '{project}': NexoDeck todavia no tiene proyectos de documentacion configurados")
            } else {
                format!(
                    "no hay ningun proyecto '{project}'. Los validos: {}",
                    valid.join(", ")
                )
            }));
        }
        if items.is_empty() {
            return Err(DocsError::Invalid("'findings' esta vacio".into()));
        }
        if items.len() > MAX_FINDINGS_PER_CALL {
            return Err(DocsError::Invalid(format!(
                "llegaron {} hallazgos y el maximo por llamada es {MAX_FINDINGS_PER_CALL}",
                items.len()
            )));
        }

        let problems: Vec<String> = items
            .iter()
            .enumerate()
            .flat_map(|(i, item)| {
                item.problems()
                    .into_iter()
                    .map(move |p| format!("hallazgo {}: {p}", i + 1))
            })
            .collect();
        if !problems.is_empty() {
            return Err(DocsError::Invalid(problems.join("\n")));
        }

        let _guard = self.write_lock.lock().unwrap_or_else(|e| e.into_inner());
        let existing = self.findings()?;
        let stamp = now.strftime("%Y%m%d-%H%M%S").to_string();
        let from = from.filter(|f| !f.trim().is_empty());

        let batch_hash = sha256_hex(format!("{project}{stamp}{}", items.len()).as_bytes());
        let batch_id = format!("b-{stamp}-{}", &batch_hash[..4]);

        let mut ids = Vec::with_capacity(items.len());
        let mut duplicates = Vec::new();
        let mut duplicate_batch: Option<String> = None;

        for (index, item) in items.into_iter().enumerate() {
            let hash = sha256_hex(
                format!("{project}\u{1f}{}\u{1f}{}", item.title.trim(), item.body.trim())
                    .as_bytes(),
            );

            if let Some(dup) = existing
                .iter()
                .find(|f| f.content_hash == hash && within_window(now, &f.created_at))
            {
                ids.push(dup.id.clone());
                duplicates.push(dup.id.clone());
                duplicate_batch.get_or_insert_with(|| dup.batch_id.clone());
                continue;
            }

            let mut id = format!("f-{stamp}-{}", &hash[..6]);
            if self.finding_path(&id).exists() {
                id = format!("{id}-{index}");
            }

            let finding = Finding {
                id: id.clone(),
                batch_id: batch_id.clone(),
                project: project.to_string(),
                from: from.clone(),
                created_at: now.to_string(),
                content_hash: hash,
                content: item,
                status: FindingStatus::Queued,
            };
            write_json(&self.finding_path(&id), &finding)?;
            ids.push(id);
        }

        // Sin nada nuevo, un lote recien inventado no tendria ningun hallazgo:
        // `finding_status` por ese lote contestaria "nada" a quien acaba de
        // enviar. Se devuelve el lote en el que ya estaban.
        let batch_id = match duplicate_batch {
            Some(existing) if duplicates.len() == ids.len() => existing,
            _ => batch_id,
        };

        Ok(SubmitOutcome {
            batch_id,
            ids,
            duplicates,
        })
    }

    fn finding_path(&self, id: &str) -> PathBuf {
        self.root.join("findings").join(format!("{id}.json"))
    }

    fn proposal_dir(&self, id: &str) -> PathBuf {
        self.root.join("proposals").join(id)
    }

    /// Donde se guardan los bytes originales de los documentos que toca una
    /// propuesta aplicada.
    pub fn originals_dir(&self, proposal_id: &str) -> DocsResult<PathBuf> {
        check_id(proposal_id)?;
        Ok(self.proposal_dir(proposal_id).join("originals"))
    }

    /// Todos, del mas viejo al mas nuevo.
    pub fn findings(&self) -> DocsResult<Vec<Finding>> {
        let mut findings: Vec<Finding> = read_json_dir(&self.root.join("findings"))?;
        findings.sort_by(|a, b| (&a.created_at, &a.id).cmp(&(&b.created_at, &b.id)));
        Ok(findings)
    }

    pub fn finding(&self, id: &str) -> DocsResult<Finding> {
        check_id(id)?;
        let path = self.finding_path(id);
        if !path.exists() {
            return Err(DocsError::NotFound(format!("el hallazgo '{id}'")));
        }
        read_json(&path)
    }

    pub fn save_finding(&self, finding: &Finding) -> DocsResult<()> {
        check_id(&finding.id)?;
        write_json(&self.finding_path(&finding.id), finding)
    }

    /// Todas, de la mas vieja a la mas nueva.
    pub fn proposals(&self) -> DocsResult<Vec<Proposal>> {
        let dir = self.root.join("proposals");
        let mut proposals = Vec::new();
        let entries = std::fs::read_dir(&dir).map_err(|e| DocsError::io(&dir, e))?;
        for entry in entries {
            let entry = entry.map_err(|e| DocsError::io(&dir, e))?;
            let path = entry.path().join("proposal.json");
            if path.exists() {
                proposals.push(read_json::<Proposal>(&path)?);
            }
        }
        proposals.sort_by(|a, b| (&a.created_at, &a.id).cmp(&(&b.created_at, &b.id)));
        Ok(proposals)
    }

    pub fn proposal(&self, id: &str) -> DocsResult<Proposal> {
        check_id(id)?;
        let path = self.proposal_dir(id).join("proposal.json");
        if !path.exists() {
            return Err(DocsError::NotFound(format!("la propuesta '{id}'")));
        }
        read_json(&path)
    }

    pub fn save_proposal(&self, proposal: &Proposal) -> DocsResult<()> {
        check_id(&proposal.id)?;
        let dir = self.proposal_dir(&proposal.id);
        std::fs::create_dir_all(&dir).map_err(|e| DocsError::io(&dir, e))?;
        write_json(&dir.join("proposal.json"), proposal)
    }

    fn digests_dir(&self) -> PathBuf {
        self.root.join("digests")
    }

    /// Todos los digests de notas, del mas viejo al mas nuevo. La carpeta se
    /// crea con el primero: un buzon anterior al asistente de notas no la tiene.
    pub fn digests(&self) -> DocsResult<Vec<crate::notes::Digest>> {
        let dir = self.digests_dir();
        if !dir.exists() {
            return Ok(Vec::new());
        }
        let mut digests: Vec<crate::notes::Digest> = read_json_dir(&dir)?;
        digests.sort_by(|a, b| (&a.created_at, &a.id).cmp(&(&b.created_at, &b.id)));
        Ok(digests)
    }

    pub fn digest(&self, id: &str) -> DocsResult<crate::notes::Digest> {
        check_id(id)?;
        let path = self.digests_dir().join(format!("{id}.json"));
        if !path.exists() {
            return Err(DocsError::NotFound(format!("el digest '{id}'")));
        }
        read_json(&path)
    }

    pub fn save_digest(&self, digest: &crate::notes::Digest) -> DocsResult<()> {
        check_id(&digest.id)?;
        let dir = self.digests_dir();
        std::fs::create_dir_all(&dir).map_err(|e| DocsError::io(&dir, e))?;
        write_json(&dir.join(format!("{}.json", digest.id)), digest)
    }

    /// Al arrancar: lo que estaba `proposing` lo estaba procesando un proceso
    /// que ya no existe. Vuelve a la cola en vez de quedarse colgado para
    /// siempre. Vale igual para los digests de notas que estaban corriendo.
    /// Devuelve cuantos recupero.
    pub fn recover_interrupted(&self) -> DocsResult<usize> {
        let mut recovered = 0;
        for mut finding in self.findings()? {
            if finding.status == FindingStatus::Proposing {
                finding.status = FindingStatus::Queued;
                self.save_finding(&finding)?;
                recovered += 1;
            }
        }
        for mut digest in self.digests()? {
            if digest.status == crate::notes::DigestStatus::Running {
                digest.status = crate::notes::DigestStatus::Queued;
                self.save_digest(&digest)?;
                recovered += 1;
            }
        }
        Ok(recovered)
    }
}

/// Los ids vienen de fuera (Claude Code, la UI) y acaban siendo nombres de
/// fichero: nada de `..` ni separadores.
fn check_id(id: &str) -> DocsResult<()> {
    let ok = !id.is_empty()
        && id.len() <= 64
        && id
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-');
    if ok {
        Ok(())
    } else {
        Err(DocsError::Invalid(format!("'{id}' no es un id valido")))
    }
}

fn within_window(now: jiff::Timestamp, created_at: &str) -> bool {
    created_at
        .parse::<jiff::Timestamp>()
        .is_ok_and(|then| now.as_second() - then.as_second() <= DEDUP_WINDOW_SECS)
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    Sha256::digest(bytes)
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// Temporal en el mismo directorio + `sync_all` + `rename` encima. En Windows
/// `rename` reemplaza el destino; si un editor lo tiene bloqueado, el error se
/// devuelve con la ruta y el temporal se borra.
pub fn write_atomic(path: &Path, bytes: &[u8]) -> DocsResult<()> {
    let dir = path
        .parent()
        .ok_or_else(|| DocsError::Invalid(format!("{} no tiene carpeta", path.display())))?;
    let mut name = path.file_name().unwrap_or_default().to_os_string();
    name.push(TMP_SUFFIX);
    let tmp = dir.join(name);

    let written = (|| {
        let mut file = std::fs::File::create(&tmp)?;
        file.write_all(bytes)?;
        file.sync_all()
    })();
    if let Err(e) = written {
        let _ = std::fs::remove_file(&tmp);
        return Err(DocsError::io(&tmp, e));
    }

    std::fs::rename(&tmp, path).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        DocsError::io(path, e)
    })
}

fn write_json<T: Serialize>(path: &Path, value: &T) -> DocsResult<()> {
    let bytes = serde_json::to_vec_pretty(value).map_err(|source| DocsError::Json {
        path: path.to_path_buf(),
        source,
    })?;
    write_atomic(path, &bytes)
}

fn read_json<T: DeserializeOwned>(path: &Path) -> DocsResult<T> {
    let bytes = std::fs::read(path).map_err(|e| DocsError::io(path, e))?;
    serde_json::from_slice(&bytes).map_err(|source| DocsError::Json {
        path: path.to_path_buf(),
        source,
    })
}

fn read_json_dir<T: DeserializeOwned>(dir: &Path) -> DocsResult<Vec<T>> {
    let mut out = Vec::new();
    let entries = std::fs::read_dir(dir).map_err(|e| DocsError::io(dir, e))?;
    for entry in entries {
        let path = entry.map_err(|e| DocsError::io(dir, e))?.path();
        // Un temporal que sobrevivio a un corte no es un hallazgo.
        if path.extension().is_some_and(|ext| ext == "json") {
            out.push(read_json(&path)?);
        }
    }
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{DocProject, DocRole, DocTarget, ProjectKind};
    use crate::model::{Evidence, EvidenceLabel, FindingKind};

    fn configured(name: &str) -> Inbox {
        let inbox = Inbox::open(crate::test_support::temp_dir(name)).unwrap();
        let config = InboxConfig {
            projects: vec![DocProject {
                id: "ia".into(),
                name: "IA".into(),
                repo_root: std::env::temp_dir().to_string_lossy().into_owned(),
                kind: ProjectKind::Docs,
                conventions: String::new(),
                documents: vec![DocTarget {
                    path: "docs/estado.md".into(),
                    role: DocRole::Journal,
                    answers: String::new(),
                    evidence_labels: true,
                }],
            }],
            ..InboxConfig::default()
        };
        inbox.save_config(&config).unwrap();
        inbox
    }

    fn item(title: &str) -> NewFinding {
        NewFinding {
            kind: FindingKind::Decision,
            title: title.into(),
            body: "cuerpo".into(),
            evidence: vec![Evidence {
                label: EvidenceLabel::S,
                text: "supuesto".into(),
                source: None,
            }],
            supersedes: None,
            date: None,
            target_hint: None,
        }
    }

    fn at(seconds: i64) -> jiff::Timestamp {
        jiff::Timestamp::from_second(1_789_000_000 + seconds).unwrap()
    }

    #[test]
    fn submit_stores_one_file_per_finding_and_survives_reopening() {
        let inbox = configured("submit");
        let out = inbox
            .submit("ia", Some("NexoDeck en main".into()), vec![item("uno"), item("dos")], at(0))
            .unwrap();
        assert_eq!(out.ids.len(), 2);
        assert!(out.duplicates.is_empty());

        let reopened = Inbox::open(inbox.root()).unwrap();
        let stored = reopened.findings().unwrap();
        assert_eq!(stored.len(), 2);
        assert_eq!(stored[0].status, FindingStatus::Queued);
        assert_eq!(stored[0].from.as_deref(), Some("NexoDeck en main"));
    }

    #[test]
    fn resubmitting_within_a_day_returns_the_same_id() {
        let inbox = configured("dedup");
        let first = inbox.submit("ia", None, vec![item("uno")], at(0)).unwrap();
        let again = inbox.submit("ia", None, vec![item("uno")], at(3600)).unwrap();
        assert_eq!(first.ids, again.ids);
        assert_eq!(again.duplicates, first.ids);
        assert_eq!(inbox.findings().unwrap().len(), 1);
        assert_eq!(
            again.batch_id, first.batch_id,
            "sin nada nuevo se devuelve el lote en el que ya estaba"
        );

        // Mezclado: el lote nuevo agrupa solo lo que se guardo en esta llamada.
        let mixed = inbox
            .submit("ia", None, vec![item("uno"), item("dos")], at(7200))
            .unwrap();
        assert_eq!(mixed.duplicates, first.ids);
        assert_ne!(mixed.batch_id, first.batch_id);
        let in_new_batch: Vec<String> = inbox
            .findings()
            .unwrap()
            .into_iter()
            .filter(|f| f.batch_id == mixed.batch_id)
            .map(|f| f.content.title)
            .collect();
        assert_eq!(in_new_batch, vec!["dos".to_string()]);

        let next_week = inbox.submit("ia", None, vec![item("uno")], at(8 * 24 * 3600)).unwrap();
        assert_ne!(next_week.ids, first.ids);
    }

    #[test]
    fn an_unknown_project_lists_the_valid_ones() {
        let inbox = configured("unknown");
        let err = inbox.submit("mapas", None, vec![item("x")], at(0)).unwrap_err();
        assert!(err.to_string().contains("Los validos: ia"), "{err}");
    }

    #[test]
    fn every_problem_is_reported_with_its_finding_number() {
        let inbox = configured("problems");
        let mut bad = item("x");
        bad.evidence.clear();
        let err = inbox
            .submit("ia", None, vec![item("bien"), bad], at(0))
            .unwrap_err();
        assert!(err.to_string().starts_with("hallazgo 2:"), "{err}");
        assert!(inbox.findings().unwrap().is_empty(), "no se guarda nada si uno falla");
    }

    #[test]
    fn interrupted_work_goes_back_to_the_queue() {
        let inbox = configured("recover");
        let out = inbox.submit("ia", None, vec![item("uno")], at(0)).unwrap();
        let mut finding = inbox.finding(&out.ids[0]).unwrap();
        finding.status = FindingStatus::Proposing;
        inbox.save_finding(&finding).unwrap();

        assert_eq!(inbox.recover_interrupted().unwrap(), 1);
        assert_eq!(inbox.finding(&out.ids[0]).unwrap().status, FindingStatus::Queued);
    }

    #[test]
    fn ids_cannot_escape_the_inbox() {
        let inbox = configured("ids");
        assert!(matches!(inbox.finding("../config"), Err(DocsError::Invalid(_))));
        assert!(matches!(inbox.proposal("a/b"), Err(DocsError::Invalid(_))));
    }

    #[test]
    fn write_atomic_leaves_no_temporary_behind() {
        let dir = crate::test_support::temp_dir("atomic");
        let path = dir.join("a.json");
        write_atomic(&path, b"uno").unwrap();
        write_atomic(&path, b"dos").unwrap();
        assert_eq!(std::fs::read(&path).unwrap(), b"dos");
        let leftovers: Vec<_> = std::fs::read_dir(&dir).unwrap().collect();
        assert_eq!(leftovers.len(), 1);
    }

    #[test]
    fn an_invalid_config_is_not_saved() {
        let inbox = Inbox::open(crate::test_support::temp_dir("badconfig")).unwrap();
        let mut config = InboxConfig::default();
        config.projects.push(DocProject {
            id: "X".into(),
            name: String::new(),
            repo_root: "relativa".into(),
            kind: ProjectKind::Docs,
            conventions: String::new(),
            documents: vec![],
        });
        assert!(inbox.save_config(&config).is_err());
        assert_eq!(inbox.config().unwrap(), InboxConfig::default());
    }
}
