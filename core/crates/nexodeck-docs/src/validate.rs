//! Lo que tiene que cumplir una propuesta antes de enseñarsela al usuario.
//!
//! Se aplican todas las operaciones en memoria, en orden, sobre una copia. Si
//! una sola falla, la propuesta entera vuelve al modelo con la lista de errores:
//! una propuesta a medias seria peor que ninguna, porque las operaciones que
//! quedan pueden depender de la que fallo.

use std::collections::BTreeMap;

use crate::config::{normalize_rel, DocProject, DocRole};
use crate::dates::{is_short_date, SpanishDate};
use crate::model::{EvidenceLabel, Finding, ProposedOperation};
use crate::ops::{apply_operation, preview, Operation};

/// Una operacion que borra mas lineas que esto se marca como destructiva.
pub const DESTRUCTIVE_LINES: usize = 40;
const MAX_ADDED_CHARS: usize = 12_000;

pub struct ValidationInput<'a> {
    pub project: &'a DocProject,
    /// El texto actual de cada documento, por ruta normalizada.
    pub bodies: &'a BTreeMap<String, String>,
    /// Lo que se le enseño al modelo. `None` al revalidar sobre un documento
    /// que cambio: ahi basta con que el ancla exista.
    pub visible: Option<&'a BTreeMap<String, String>>,
    pub findings: &'a [Finding],
    pub today: SpanishDate,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Validated {
    pub operations: Vec<ProposedOperation>,
    /// El texto final de cada documento tocado.
    pub new_bodies: BTreeMap<String, String>,
    pub warnings: Vec<String>,
}

pub fn validate_operations(
    operations: &[Operation],
    input: &ValidationInput,
) -> Result<Validated, Vec<String>> {
    let mut errors = Vec::new();
    let mut warnings = Vec::new();
    let mut proposed = Vec::new();
    let mut working: BTreeMap<String, String> = BTreeMap::new();
    // Lo que las operaciones anteriores de esta misma propuesta añadieron: una
    // operacion puede anclarse en una seccion que acaba de crear otra.
    let mut added: BTreeMap<String, String> = BTreeMap::new();

    if operations.is_empty() {
        errors.push("la propuesta no trae ninguna operacion".to_string());
    }

    let mut allowed_dates = vec![input.today.short()];
    for finding in input.findings {
        if let Some(date) = finding.content.date.as_deref().and_then(SpanishDate::parse_iso) {
            allowed_dates.push(date.short());
        }
    }
    let any_measured = input
        .findings
        .iter()
        .any(|f| f.content.evidence.iter().any(|e| e.label == EvidenceLabel::M));

    for (index, op) in operations.iter().enumerate() {
        let tag = format!("operacion {} ({} en {})", index + 1, op.name(), op.file());
        let path = normalize_rel(op.file());

        let Some(doc) = input.project.document(&path) else {
            if input.project.kind == crate::config::ProjectKind::Vault {
                errors.push(format!(
                    "{tag}: no es una nota que se pueda tocar: es privada, esta en una carpeta oculta, no es un .md o se sale de la boveda"
                ));
            } else {
                let valid: Vec<&str> = input
                    .project
                    .documents
                    .iter()
                    .map(|d| d.path.as_str())
                    .collect();
                errors.push(format!(
                    "{tag}: no es un documento del proyecto. Los validos: {}",
                    valid.join(", ")
                ));
            }
            continue;
        };

        if let Operation::InsertSectionTop { heading, .. } = op {
            if doc.role != DocRole::Journal {
                errors.push(format!(
                    "{tag}: insert_section_top solo vale en un diario (role journal)"
                ));
                continue;
            }
            if let Err(e) = check_journal_heading(heading, &allowed_dates) {
                errors.push(format!("{tag}: {e}"));
                continue;
            }
        }

        // Crear secciones y tocar el frontmatter es cosa de notas. En un diario o
        // un plan del buzon rompería su estructura fija.
        if matches!(
            op,
            Operation::AddSection { .. } | Operation::SetFrontmatterKey { .. }
        ) && !doc.role.is_note()
        {
            errors.push(format!(
                "{tag}: {} solo vale en notas de una boveda (roles note, daily y hub)",
                op.name()
            ));
            continue;
        }

        let new_text = op.added_text();
        if new_text.chars().count() > MAX_ADDED_CHARS {
            errors.push(format!(
                "{tag}: añade mas de {MAX_ADDED_CHARS} caracteres; partelo o resumelo"
            ));
            continue;
        }

        let Some(current) = working.get(&path).or_else(|| input.bodies.get(&path)).cloned() else {
            errors.push(format!("{tag}: no se pudo leer el documento"));
            continue;
        };

        if let (Some(visible), Some(anchor)) = (input.visible, op.anchor()) {
            let seen = visible.get(&path).is_some_and(|v| v.contains(anchor))
                || added.get(&path).is_some_and(|a| a.contains(anchor));
            if !seen {
                errors.push(format!(
                    "{tag}: el texto de referencia no estaba en lo que se te enseño del documento; solo puedes editar lo que viste"
                ));
                continue;
            }
        }

        match apply_operation(&current, op) {
            Ok(next) => {
                let change = preview(&current, &next);
                let destructive = change.removed_lines > DESTRUCTIVE_LINES;
                warnings.extend(
                    content_warnings(op, doc.evidence_labels, any_measured, &current)
                        .into_iter()
                        .map(|w| format!("{tag}: {w}")),
                );
                proposed.push(ProposedOperation {
                    operation: op.clone(),
                    preview: change,
                    destructive,
                });
                added.entry(path.clone()).or_default().push_str(&new_text);
                working.insert(path, next);
            }
            Err(e) => errors.push(format!("{tag}: {e}")),
        }
    }

    if errors.is_empty() {
        Ok(Validated {
            operations: proposed,
            new_bodies: working,
            warnings,
        })
    } else {
        Err(errors)
    }
}

fn check_journal_heading(heading: &str, allowed_dates: &[String]) -> Result<(), String> {
    const SHAPE: &str = "el encabezado del diario tiene que ser \"## <dia>-<mes>: <conclusion>\", por ejemplo \"## 15-sep: la deteccion es 3,5 veces mas rapida\"";
    let heading = heading.trim();
    let Some(rest) = heading.strip_prefix("## ") else {
        return Err(SHAPE.to_string());
    };
    let Some((date, title)) = rest.split_once(": ") else {
        return Err(SHAPE.to_string());
    };
    if title.trim().is_empty() || !is_short_date(date.trim()) {
        return Err(SHAPE.to_string());
    }
    if !allowed_dates.iter().any(|d| d == date.trim()) {
        return Err(format!(
            "la fecha {} no es la de hoy ({}) ni la de ningun hallazgo",
            date.trim(),
            allowed_dates[0]
        ));
    }
    Ok(())
}

/// Avisos que no bloquean: el usuario decide.
fn content_warnings(
    op: &Operation,
    evidence_labels: bool,
    any_measured: bool,
    current: &str,
) -> Vec<String> {
    let mut warnings = Vec::new();
    let text = op.added_text();
    let has_digits = text.chars().any(|c| c.is_ascii_digit());

    let date_only = matches!(op, Operation::SetLastUpdated { .. });
    if evidence_labels && has_digits && !date_only && !text.contains("[M]") && !text.contains("[S]") {
        warnings.push("trae cifras sin marcar como [M] medidas o [S] supuestas".to_string());
    }
    if text.contains("[M]") && !any_measured {
        warnings.push(
            "marca algo como [M] medido, pero ningun hallazgo trae evidencia medida".to_string(),
        );
    }
    if let Operation::InsertSectionTop { heading, .. } = op {
        if current.split('\n').any(|l| l.trim_end() == heading.trim()) {
            warnings.push("ya existe una seccion con ese mismo encabezado".to_string());
        }
    }
    warnings
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::DocTarget;
    use crate::model::{Evidence, FindingKind, FindingStatus, NewFinding};

    const JOURNAL: &str = "# Estado\n\n> Última actualización: **14 de septiembre de 2026**.\n\n## 14-sep: algo\n\ntexto viejo\n";

    #[test]
    fn note_operations_only_go_in_vault_notes() {
        let on_journal = Operation::AddSection {
            file: "docs/estado.md".into(),
            heading: "## Tareas".into(),
            body: "- [ ] x".into(),
        };
        assert!(validate(&[on_journal], None).unwrap_err()[0].contains("solo vale en notas"));

        let vault = DocProject {
            id: "notas".into(),
            name: "Notas".into(),
            repo_root: "D:/v".into(),
            kind: crate::config::ProjectKind::Vault,
            conventions: String::new(),
            documents: vec![],
        };
        let mut bodies = BTreeMap::new();
        bodies.insert("temas/a.md".to_string(), "# A\n\ntexto\n".to_string());
        let ops = [
            Operation::AddSection {
                file: "temas/a.md".into(),
                heading: "## Tareas".into(),
                body: "- [ ] revisar las 3 tandas".into(),
            },
            Operation::SetFrontmatterKey {
                file: "temas/a.md".into(),
                key: "status".into(),
                value: "procesada".into(),
            },
        ];
        let validated = validate_operations(
            &ops,
            &ValidationInput {
                project: &vault,
                bodies: &bodies,
                visible: Some(&bodies),
                findings: &[],
                today: today(),
            },
        )
        .unwrap();
        let text = &validated.new_bodies["temas/a.md"];
        assert!(text.starts_with("---\nstatus: procesada\n---\n# A"), "{text}");
        assert!(text.contains("## Tareas\n\n- [ ] revisar las 3 tandas"), "{text}");
        assert!(
            validated.warnings.is_empty(),
            "una nota no pide [M]/[S]: {:?}",
            validated.warnings
        );

        let private = Operation::AddSection {
            file: "privado/claves.md".into(),
            heading: "## Tareas".into(),
            body: "x".into(),
        };
        let errors = validate_operations(
            &[private],
            &ValidationInput {
                project: &vault,
                bodies: &bodies,
                visible: None,
                findings: &[],
                today: today(),
            },
        )
        .unwrap_err();
        assert!(errors[0].contains("privada"), "{errors:?}");
    }

    fn project() -> DocProject {
        DocProject {
            id: "ia".into(),
            name: "IA".into(),
            repo_root: "D:/x".into(),
            kind: crate::config::ProjectKind::Docs,
            conventions: String::new(),
            documents: vec![
                DocTarget {
                    path: "docs/estado.md".into(),
                    role: DocRole::Journal,
                    answers: String::new(),
                    evidence_labels: true,
                },
                DocTarget {
                    path: "docs/plan.md".into(),
                    role: DocRole::Plan,
                    answers: String::new(),
                    evidence_labels: true,
                },
            ],
        }
    }

    fn today() -> SpanishDate {
        SpanishDate::parse_iso("2026-09-15").unwrap()
    }

    fn bodies() -> BTreeMap<String, String> {
        let mut map = BTreeMap::new();
        map.insert("docs/estado.md".to_string(), JOURNAL.to_string());
        map.insert("docs/plan.md".to_string(), "# Plan\n\n## 5. Pasos\n\n- [ ] uno\n".to_string());
        map
    }

    fn measured_finding() -> Finding {
        Finding {
            id: "f-1".into(),
            batch_id: "b-1".into(),
            project: "ia".into(),
            from: None,
            created_at: "2026-09-15T00:00:00Z".into(),
            content_hash: String::new(),
            content: NewFinding {
                kind: FindingKind::Measurement,
                title: "t".into(),
                body: "b".into(),
                evidence: vec![Evidence {
                    label: EvidenceLabel::M,
                    text: "474 s".into(),
                    source: Some("log".into()),
                }],
                supersedes: None,
                date: None,
                target_hint: None,
            },
            status: FindingStatus::Queued,
        }
    }

    fn validate(ops: &[Operation], visible: Option<&BTreeMap<String, String>>) -> Result<Validated, Vec<String>> {
        let bodies = bodies();
        let findings = [measured_finding()];
        validate_operations(
            ops,
            &ValidationInput {
                project: &project(),
                bodies: &bodies,
                visible,
                findings: &findings,
                today: today(),
            },
        )
    }

    fn section(heading: &str) -> Operation {
        Operation::InsertSectionTop {
            file: "docs/estado.md".into(),
            heading: heading.into(),
            body: "Q paso de 1.652 s a 474 s [M].".into(),
        }
    }

    #[test]
    fn a_good_proposal_validates_and_builds_the_final_text() {
        let ops = [
            section("## 15-sep: la deteccion es mas rapida"),
            Operation::SetLastUpdated {
                file: "docs/estado.md".into(),
                date: "15 de septiembre de 2026".into(),
            },
        ];
        let validated = validate(&ops, Some(&bodies())).unwrap();
        let text = &validated.new_bodies["docs/estado.md"];
        assert!(text.contains("**15 de septiembre de 2026**"));
        assert!(text.find("## 15-sep").unwrap() < text.find("## 14-sep").unwrap());
        assert!(validated.warnings.is_empty(), "{:?}", validated.warnings);
    }

    #[test]
    fn a_file_outside_the_project_is_refused() {
        let op = Operation::ReplaceExact {
            file: "../secreto.md".into(),
            old: "a".into(),
            new: "b".into(),
            reason: String::new(),
        };
        let errors = validate(&[op], None).unwrap_err();
        assert!(errors[0].contains("no es un documento del proyecto"));
    }

    #[test]
    fn journal_sections_only_go_in_a_journal_and_with_a_valid_date() {
        let mut in_plan = section("## 15-sep: algo");
        if let Operation::InsertSectionTop { file, .. } = &mut in_plan {
            *file = "docs/plan.md".into();
        }
        assert!(validate(&[in_plan], None).unwrap_err()[0].contains("solo vale en un diario"));
        assert!(validate(&[section("## algo nuevo")], None).unwrap_err()[0].contains("<dia>-<mes>"));
        assert!(validate(&[section("## 3-ene: algo")], None).unwrap_err()[0].contains("no es la de hoy"));
    }

    #[test]
    fn an_anchor_the_model_never_saw_is_refused() {
        let op = Operation::ReplaceExact {
            file: "docs/estado.md".into(),
            old: "texto viejo".into(),
            new: "texto nuevo".into(),
            reason: String::new(),
        };
        let mut visible = BTreeMap::new();
        visible.insert("docs/estado.md".to_string(), "[CABECERA]\n# Estado".to_string());
        let errors = validate(std::slice::from_ref(&op), Some(&visible)).unwrap_err();
        assert!(errors[0].contains("no estaba en lo que se te enseño"));

        // Al revalidar sobre un documento que cambio basta con que exista.
        assert!(validate(&[op], None).is_ok());
    }

    #[test]
    fn an_operation_can_anchor_on_a_section_created_earlier_in_the_same_proposal() {
        let ops = [
            section("## 15-sep: nueva"),
            Operation::AppendUnderHeading {
                file: "docs/estado.md".into(),
                heading: "## 15-sep: nueva".into(),
                text: "y algo mas [S]".into(),
            },
        ];
        let mut visible = BTreeMap::new();
        visible.insert("docs/estado.md".to_string(), JOURNAL.to_string());
        assert!(validate(&ops, Some(&visible)).is_ok());
    }

    #[test]
    fn numbers_without_labels_warn_but_do_not_block() {
        let op = Operation::AppendUnderHeading {
            file: "docs/plan.md".into(),
            heading: "## 5. Pasos".into(),
            text: "- [ ] repetir con 3 semillas".into(),
        };
        let validated = validate(&[op], None).unwrap();
        assert!(validated.warnings[0].contains("[M]"));
    }

    #[test]
    fn deleting_many_lines_is_marked_destructive() {
        let long: String = (0..60).map(|i| format!("linea {i}\n")).collect();
        let mut bodies = bodies();
        let journal = format!("{JOURNAL}{long}");
        bodies.insert("docs/estado.md".to_string(), journal);
        let op = Operation::ReplaceExact {
            file: "docs/estado.md".into(),
            old: long.clone(),
            new: "resumido [S]\n".into(),
            reason: "ya no es cierto".into(),
        };
        let findings = [measured_finding()];
        let validated = validate_operations(
            &[op],
            &ValidationInput {
                project: &project(),
                bodies: &bodies,
                visible: None,
                findings: &findings,
                today: today(),
            },
        )
        .unwrap();
        assert!(validated.operations[0].destructive);
    }

    #[test]
    fn every_error_is_reported_not_just_the_first() {
        let ops = [
            section("## sin fecha"),
            Operation::ReplaceExact {
                file: "docs/plan.md".into(),
                old: "no existe".into(),
                new: "x".into(),
                reason: String::new(),
            },
        ];
        assert_eq!(validate(&ops, None).unwrap_err().len(), 2);
    }
}
