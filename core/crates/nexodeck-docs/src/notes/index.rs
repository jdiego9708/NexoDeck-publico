//! El indice de la boveda: que notas hay, que dicen, que tareas quedan y que se
//! parece a que.
//!
//! **Vive en memoria y se reconstruye**, no es una base de datos. La verdad son
//! los `.md`; esto es una cache que se rehace al arrancar y se pone al dia
//! mirando fecha y tamaño de cada fichero, que es barato incluso con miles de
//! notas. Guardarlo en SQLite (FTS5) daria un buscador mejor, pero metia C en el
//! workspace y una segunda copia de las notas que habria que mantener en
//! sincronia; para una boveda personal, BM25 en memoria alcanza.
//!
//! Se buscan **secciones**, no notas enteras: una reunion de tres temas tiene
//! que poder relacionarse con cada uno por separado, y un agente necesita citar
//! el trozo concreto (`n:<ruta>#<n>`), no "la nota".

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use crate::config::{normalize_rel, vault_role, DocRole, PRIVATE_SEGMENT};
use crate::error::{DocsError, DocsResult};
use crate::markdown::Document;
use crate::model::Finding;
use crate::notes::git::CommitInfo;
use crate::notes::parse::{parse_note, NoteTask, ParsedNote};
use crate::notes::roots::{local_prefix, split_virtual, LOCAL_PREFIX};

/// BM25 de manual.
const K1: f32 = 1.2;
const B: f32 = 0.75;
const SNIPPET_CHARS: usize = 240;

const STOPWORDS: &[&str] = &[
    "que", "los", "las", "del", "por", "para", "con", "una", "uno", "como", "pero", "mas", "sus",
    "este", "esta", "esto", "ese", "esa", "son", "hay", "fue", "ser", "sin", "sobre", "entre",
    "cuando", "donde", "todo", "todos", "tambien", "the", "and", "for", "with", "that", "this",
    "from", "are", "not",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CandidateKind {
    Note,
    Finding,
    Commit,
}

impl CandidateKind {
    pub fn as_str(&self) -> &'static str {
        match self {
            CandidateKind::Note => "note",
            CandidateKind::Finding => "finding",
            CandidateKind::Commit => "commit",
        }
    }
}

/// Algo que un agente puede citar. El `id` es lo unico que puede usar para
/// referirse a ello, y es lo que se comprueba despues.
#[derive(Debug, Clone, PartialEq)]
pub struct Candidate {
    /// `n:<ruta>#<seccion>`, `f:<hallazgo>` o `c:<repo>@<sha>`.
    pub id: String,
    pub kind: CandidateKind,
    pub title: String,
    pub snippet: String,
    pub date: Option<String>,
    /// La nota, si es una seccion de nota.
    pub path: Option<String>,
    pub score: f32,
}

#[derive(Debug, Clone)]
pub struct IndexedNote {
    pub path: String,
    pub role: DocRole,
    pub note: ParsedNote,
    modified: Option<SystemTime>,
    size: u64,
}

impl IndexedNote {
    /// La ultima modificacion del fichero, segun el sistema.
    pub fn modified(&self) -> Option<SystemTime> {
        self.modified
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct RefreshStats {
    pub added: usize,
    pub changed: usize,
    pub removed: usize,
    /// Ficheros que no se pudieron leer (no UTF-8, bloqueados).
    pub skipped: usize,
}

impl RefreshStats {
    pub fn any(&self) -> bool {
        self.added + self.changed + self.removed > 0
    }
}

#[derive(Debug, Clone)]
struct Unit {
    id: String,
    kind: CandidateKind,
    title: String,
    text: String,
    date: Option<String>,
    path: Option<String>,
    excluded: bool,
    tf: HashMap<String, u32>,
    len: u32,
}

/// Clonable a proposito: el trabajador procesa un digest con una copia fija del
/// indice (`Arc`) mientras la UI sigue buscando y refrescando la suya. Sin eso,
/// una busqueda desde la app esperaria el minuto que tarda un digest.
#[derive(Clone)]
pub struct NotesIndex {
    /// Las carpetas que recorre, con su prefijo: vacio en la boveda principal y
    /// `@id/` en una carpeta local. La clave de cada nota es su ruta virtual
    /// (`notes/roots.rs`), asi que busqueda, tareas y backlinks cruzan todas las
    /// carpetas sin saber que son varias.
    roots: Vec<(String, PathBuf)>,
    notes: BTreeMap<String, IndexedNote>,
    findings: Vec<Finding>,
    commits: Vec<CommitInfo>,
    units: Vec<Unit>,
    df: HashMap<String, usize>,
    avg_len: f32,
}

impl NotesIndex {
    /// Una sola carpeta: la boveda principal.
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self::with_roots(vec![(String::new(), root.into())])
    }

    /// Varias carpetas, la principal primero (`InboxConfig::note_roots`).
    pub fn with_roots(roots: Vec<(String, PathBuf)>) -> Self {
        NotesIndex {
            roots,
            notes: BTreeMap::new(),
            findings: Vec::new(),
            commits: Vec::new(),
            units: Vec::new(),
            df: HashMap::new(),
            avg_len: 0.0,
        }
    }

    /// La carpeta de la boveda principal.
    pub fn root(&self) -> &Path {
        &self.roots[0].1
    }

    /// Pone el indice al dia con lo que hay en disco. Solo relee lo que cambio
    /// de fecha o de tamaño.
    ///
    /// **Solo falla si falta la boveda principal.** Una carpeta local que no
    /// esta —un disco desconectado, una unidad de red caida— se salta: sus notas
    /// dejan de salir y vuelven cuando vuelva la carpeta. Que una carpeta
    /// secundaria dejara sin notas a todas las demas seria peor.
    pub fn refresh(&mut self) -> DocsResult<RefreshStats> {
        let main = self.root().to_path_buf();
        if !main.is_dir() {
            return Err(DocsError::NotFound(format!(
                "la carpeta de la boveda {}",
                main.display()
            )));
        }
        let mut stats = RefreshStats::default();
        let mut seen = HashSet::new();
        let mut files = Vec::new();
        for (prefix, root) in &self.roots {
            if !root.is_dir() {
                continue;
            }
            let mut found = Vec::new();
            // En la principal se saltan las carpetas `@...` de primer nivel:
            // chocarian con el prefijo de una carpeta local.
            walk(root, root, prefix.is_empty(), &mut found);
            files.extend(found.into_iter().map(|(rel, full)| (prefix.clone(), rel, full)));
        }

        for (prefix, rel, full) in files {
            // El rol se calcula sobre la ruta dentro de su carpeta: con el
            // prefijo, `@apuntes/diario/x.md` ya no empezaria por `diario/`.
            let Some(role) = vault_role(&rel) else { continue };
            let key = format!("{prefix}{rel}");
            let Ok(meta) = std::fs::metadata(&full) else {
                stats.skipped += 1;
                continue;
            };
            seen.insert(key.clone());
            let modified = meta.modified().ok();
            let size = meta.len();
            if let Some(existing) = self.notes.get(&key) {
                if existing.modified == modified && existing.size == size {
                    continue;
                }
            }
            let parsed = std::fs::read(&full)
                .ok()
                .and_then(|raw| Document::parse(&raw).ok())
                .map(|doc| parse_note(&rel, &doc.body));
            let Some(note) = parsed else {
                stats.skipped += 1;
                continue;
            };
            if self.notes.contains_key(&key) {
                stats.changed += 1;
            } else {
                stats.added += 1;
            }
            self.notes.insert(
                key.clone(),
                IndexedNote {
                    path: key,
                    role,
                    note,
                    modified,
                    size,
                },
            );
        }

        let before = self.notes.len();
        self.notes.retain(|path, _| seen.contains(path));
        stats.removed = before - self.notes.len();

        if stats.any() {
            self.rebuild();
        }
        Ok(stats)
    }

    /// Los hallazgos del buzon, para que un agente pueda relacionar una nota con
    /// lo que Claude Code ya documento.
    /// No reconstruye nada si llega lo mismo: el trabajador lo llama en cada
    /// vuelta y casi nunca cambia.
    pub fn set_findings(&mut self, findings: Vec<Finding>) {
        if self.findings != findings {
            self.findings = findings;
            self.rebuild();
        }
    }

    pub fn set_commits(&mut self, commits: Vec<CommitInfo>) {
        if self.commits != commits {
            self.commits = commits;
            self.rebuild();
        }
    }

    pub fn notes(&self) -> impl Iterator<Item = &IndexedNote> {
        self.notes.values()
    }

    pub fn note(&self, path: &str) -> Option<&IndexedNote> {
        self.notes.get(&normalize_rel(path))
    }

    pub fn commits(&self) -> &[CommitInfo] {
        &self.commits
    }

    /// Tareas sin hacer: primero las que tienen fecha, de la mas proxima a la
    /// mas lejana.
    pub fn open_tasks(&self) -> Vec<(String, NoteTask)> {
        let mut tasks: Vec<(String, NoteTask)> = self
            .notes
            .values()
            .flat_map(|n| {
                n.note
                    .tasks
                    .iter()
                    .filter(|t| !t.done)
                    .map(|t| (n.path.clone(), t.clone()))
            })
            .collect();
        tasks.sort_by(|a, b| {
            let due = |t: &NoteTask| t.due.clone().unwrap_or_else(|| "9999".into());
            due(&a.1)
                .cmp(&due(&b.1))
                .then(a.0.cmp(&b.0))
                .then(a.1.line.cmp(&b.1.line))
        });
        tasks
    }

    /// A que nota apunta un `[[enlace]]`: la ruta exacta, o como en Obsidian, la
    /// unica nota con ese nombre de fichero.
    pub fn resolve_link(&self, target: &str) -> Option<String> {
        self.exact(target).or_else(|| self.unique_stem(target))
    }

    /// A que nota apunta un enlace escrito **dentro de la nota `source`**.
    ///
    /// Dentro de una carpeta local, un enlace con ruta y sin prefijo se busca
    /// **primero en esa carpeta** (es como lo escribe Obsidian al abrirla como
    /// boveda) y, si no esta, **en la principal**, que es la unica sin prefijo:
    /// sin eso, una nota local no podria enlazar a la principal por ruta. Nunca en
    /// otra carpeta local, que se nombra con su `@id/`. Por nombre suelto se busca
    /// en todas, con la regla de siempre: unico o nada.
    pub fn resolve_link_from(&self, target: &str, source: &str) -> Option<String> {
        let wanted = normalize_rel(target.trim());
        if !wanted.starts_with(LOCAL_PREFIX) {
            if let (Some(id), _) = split_virtual(&normalize_rel(source)) {
                if let Some(path) = self.exact(&format!("{}{wanted}", local_prefix(id))) {
                    return Some(path);
                }
                return if wanted.contains('/') {
                    // Sin prefijo, `exact` solo puede casar con la principal.
                    self.exact(&wanted)
                } else {
                    self.unique_stem(&wanted)
                };
            }
        }
        self.resolve_link(target)
    }

    fn exact(&self, target: &str) -> Option<String> {
        let wanted = with_md(&normalize_rel(target.trim()));
        self.notes
            .keys()
            .find(|p| p.to_lowercase() == wanted)
            .cloned()
    }

    fn unique_stem(&self, target: &str) -> Option<String> {
        let wanted = with_md(&normalize_rel(target.trim()));
        let stem = wanted.rsplit('/').next().unwrap_or(&wanted);
        let mut matches = self
            .notes
            .keys()
            .filter(|p| p.to_lowercase().rsplit('/').next() == Some(stem));
        match (matches.next(), matches.next()) {
            (Some(only), None) => Some(only.clone()),
            _ => None,
        }
    }

    /// Las notas que enlazan a esta.
    pub fn backlinks(&self, path: &str) -> Vec<String> {
        let path = normalize_rel(path);
        self.notes
            .values()
            .filter(|n| n.path != path)
            .filter(|n| {
                n.note
                    .links
                    .iter()
                    .any(|l| self.resolve_link_from(l, &n.path).as_deref() == Some(path.as_str()))
            })
            .map(|n| n.path.clone())
            .collect()
    }

    /// Lo que mas se parece a una nota, sin contarse a si misma.
    pub fn related(&self, path: &str, limit: usize) -> Vec<Candidate> {
        let Some(entry) = self.note(path) else { return Vec::new() };
        let mut query = entry.note.title.clone();
        query.push(' ');
        query.push_str(&entry.note.tags.join(" "));
        for section in entry.note.sections.iter().take(3) {
            query.push(' ');
            query.push_str(&section.text);
        }
        self.search(&query, &[CandidateKind::Note], limit, Some(&entry.path))
    }

    /// BM25 sobre secciones de notas, hallazgos y commits. Nunca devuelve una
    /// nota con `ai: false`: esto es lo que ven los agentes.
    pub fn search(
        &self,
        query: &str,
        kinds: &[CandidateKind],
        limit: usize,
        exclude_path: Option<&str>,
    ) -> Vec<Candidate> {
        let terms: Vec<String> = tokens(query)
            .into_iter()
            .collect::<HashSet<_>>()
            .into_iter()
            .collect();
        if terms.is_empty() || self.units.is_empty() {
            return Vec::new();
        }
        let exclude = exclude_path.map(normalize_rel);
        let n = self.units.len() as f32;

        let mut scored: Vec<(f32, &Unit)> = self
            .units
            .iter()
            .filter(|u| !u.excluded && (kinds.is_empty() || kinds.contains(&u.kind)))
            .filter(|u| exclude.is_none() || u.path != exclude)
            .filter_map(|u| {
                let score: f32 = terms
                    .iter()
                    .filter_map(|term| {
                        let tf = *u.tf.get(term)? as f32;
                        let df = *self.df.get(term).unwrap_or(&0) as f32;
                        let idf = (1.0 + (n - df + 0.5) / (df + 0.5)).ln();
                        let norm = 1.0 - B + B * u.len as f32 / self.avg_len.max(1.0);
                        Some(idf * tf * (K1 + 1.0) / (tf + K1 * norm))
                    })
                    .sum();
                (score > 0.0).then_some((score, u))
            })
            .collect();
        scored.sort_by(|a, b| b.0.total_cmp(&a.0).then(a.1.id.cmp(&b.1.id)));

        scored
            .into_iter()
            .take(limit)
            .map(|(score, u)| candidate(u, score, &terms))
            .collect()
    }

    /// Lo que corresponde a un id, si existe y un agente puede verlo.
    pub fn candidate(&self, id: &str) -> Option<Candidate> {
        self.units
            .iter()
            .find(|u| u.id == id && !u.excluded)
            .map(|u| candidate(u, 0.0, &[]))
    }

    fn rebuild(&mut self) {
        let mut units = Vec::new();
        for entry in self.notes.values() {
            for (index, section) in entry.note.sections.iter().enumerate() {
                let heading = section.heading.trim_start_matches('#').trim();
                let title = if heading.is_empty() {
                    entry.note.title.clone()
                } else {
                    format!("{} › {heading}", entry.note.title)
                };
                // El titulo y las etiquetas cuentan en cada seccion: de que nota
                // viene un trozo dice mucho de que trata.
                let text = format!("{}\n{}\n{}", title, entry.note.tags.join(" "), section.text);
                units.push(unit(
                    format!("n:{}#{index}", entry.path),
                    CandidateKind::Note,
                    title,
                    text,
                    entry.note.date.clone(),
                    Some(entry.path.clone()),
                    entry.note.ai_excluded,
                ));
            }
        }
        for finding in &self.findings {
            let content = &finding.content;
            let evidence: Vec<&str> = content.evidence.iter().map(|e| e.text.as_str()).collect();
            let text = format!("{}\n{}\n{}", content.title, content.body, evidence.join("\n"));
            let date = content
                .date
                .clone()
                .or_else(|| finding.created_at.get(..10).map(str::to_string));
            units.push(unit(
                format!("f:{}", finding.id),
                CandidateKind::Finding,
                format!("{} ({})", content.title, finding.project),
                text,
                date,
                None,
                false,
            ));
        }
        for commit in &self.commits {
            let text = format!("{}\n{}\n{}", commit.subject, commit.body, commit.repo);
            units.push(unit(
                commit.id(),
                CandidateKind::Commit,
                format!("{}: {}", commit.repo, commit.subject),
                text,
                Some(commit.date.clone()),
                None,
                false,
            ));
        }

        let mut df: HashMap<String, usize> = HashMap::new();
        for u in &units {
            for term in u.tf.keys() {
                *df.entry(term.clone()).or_default() += 1;
            }
        }
        let total: u64 = units.iter().map(|u| u64::from(u.len)).sum();
        self.avg_len = if units.is_empty() {
            0.0
        } else {
            total as f32 / units.len() as f32
        };
        self.df = df;
        self.units = units;
    }
}

fn unit(
    id: String,
    kind: CandidateKind,
    title: String,
    text: String,
    date: Option<String>,
    path: Option<String>,
    excluded: bool,
) -> Unit {
    let mut tf: HashMap<String, u32> = HashMap::new();
    let words = tokens(&text);
    for word in &words {
        *tf.entry(word.clone()).or_default() += 1;
    }
    Unit {
        id,
        kind,
        title,
        len: words.len() as u32,
        text,
        date,
        path,
        excluded,
        tf,
    }
}

fn candidate(u: &Unit, score: f32, terms: &[String]) -> Candidate {
    Candidate {
        id: u.id.clone(),
        kind: u.kind,
        title: u.title.clone(),
        snippet: snippet(&u.text, terms),
        date: u.date.clone(),
        path: u.path.clone(),
        score,
    }
}

/// La linea con mas terminos de la busqueda, o el principio del texto.
fn snippet(text: &str, terms: &[String]) -> String {
    let best = text
        .lines()
        .filter(|l| !l.trim().is_empty())
        .max_by_key(|line| {
            let words: HashSet<String> = tokens(line).into_iter().collect();
            terms.iter().filter(|t| words.contains(*t)).count()
        })
        .unwrap_or("");
    let line = if terms.is_empty() {
        text.lines().find(|l| !l.trim().is_empty()).unwrap_or("")
    } else {
        best
    };
    let line = line.trim();
    if line.chars().count() <= SNIPPET_CHARS {
        line.to_string()
    } else {
        let cut: String = line.chars().take(SNIPPET_CHARS).collect();
        format!("{cut}…")
    }
}

/// Palabras de busqueda: minusculas, sin tildes, de tres letras o mas y sin las
/// que no dicen nada.
pub(crate) fn tokens(text: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    for ch in text.chars() {
        let folded = fold(ch);
        if folded.is_alphanumeric() {
            current.extend(folded.to_lowercase());
        } else if !current.is_empty() {
            push_token(&mut out, std::mem::take(&mut current));
        }
    }
    if !current.is_empty() {
        push_token(&mut out, current);
    }
    out
}

/// Letras que se conservan de cada palabra. Es una raiz de pobre, pero en
/// español casi todo cambia por el final: "ortofoto" y "ortofotos", "deforma" y
/// "deformada", "migracion" y "migraciones" tienen que encontrarse. Un stemmer de
/// verdad meteria una dependencia para ganar poco en una boveda personal.
const STEM_CHARS: usize = 6;

fn push_token(out: &mut Vec<String>, token: String) {
    if token.chars().count() < 3 || STOPWORDS.contains(&token.as_str()) {
        return;
    }
    out.push(token.chars().take(STEM_CHARS).collect());
}

fn fold(c: char) -> char {
    match c {
        'á' | 'à' | 'ä' | 'â' | 'Á' | 'À' | 'Ä' | 'Â' => 'a',
        'é' | 'è' | 'ë' | 'ê' | 'É' | 'È' | 'Ë' | 'Ê' => 'e',
        'í' | 'ì' | 'ï' | 'î' | 'Í' | 'Ì' | 'Ï' | 'Î' => 'i',
        'ó' | 'ò' | 'ö' | 'ô' | 'Ó' | 'Ò' | 'Ö' | 'Ô' => 'o',
        'ú' | 'ù' | 'ü' | 'û' | 'Ú' | 'Ù' | 'Ü' | 'Û' => 'u',
        'ñ' | 'Ñ' => 'n',
        other => other,
    }
}

/// `x` y `x.md` en minusculas, que es como se comparan los enlaces.
fn with_md(target: &str) -> String {
    let lower = target.to_lowercase();
    if lower.ends_with(".md") {
        lower
    } else {
        format!("{lower}.md")
    }
}

/// Los `.md` de la boveda, sin entrar en carpetas ocultas, privadas ni enlaces
/// simbolicos (un enlace podria sacar la lectura de la boveda).
///
/// Con `skip_markers`, tampoco en las carpetas de primer nivel que empiezan por
/// `@`: en la boveda principal chocarian con el prefijo de una carpeta local.
fn walk(root: &Path, dir: &Path, skip_markers: bool, out: &mut Vec<(String, PathBuf)>) {
    let Ok(entries) = std::fs::read_dir(dir) else { return };
    for entry in entries.flatten() {
        let path = entry.path();
        let Ok(kind) = entry.file_type() else { continue };
        if kind.is_symlink() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with('.') {
            continue;
        }
        if kind.is_dir() {
            if name.eq_ignore_ascii_case(PRIVATE_SEGMENT) {
                continue;
            }
            if skip_markers && dir == root && name.starts_with(LOCAL_PREFIX) {
                continue;
            }
            walk(root, &path, skip_markers, out);
        } else if name.to_lowercase().ends_with(".md") {
            if let Ok(rel) = path.strip_prefix(root) {
                out.push((normalize_rel(&rel.to_string_lossy()), path));
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::{Evidence, EvidenceLabel, FindingKind, FindingStatus, NewFinding};

    fn write(root: &Path, rel: &str, text: &str) {
        let path = root.join(rel);
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        std::fs::write(path, text).unwrap();
    }

    fn vault(name: &str) -> PathBuf {
        let root = crate::test_support::temp_dir(name);
        write(
            &root,
            "diario/2026-09-15.md",
            "# 15 de septiembre\n\nLa ortofoto de la tanda R sale deformada. Ver [[proyectos/ODM]].\n\n## Tareas\n\n- [ ] reprocesar la tanda R 📅 2026-09-18\n- [x] avisar al equipo\n",
        );
        write(
            &root,
            "proyectos/ODM.md",
            "# ODM\n\n## Decisiones\n\nLa malla 2.5D deforma las ortofotos de relieve fuerte.\n",
        );
        write(
            &root,
            "temas/drift.md",
            "# Drift\n\nLas migraciones van por `_addColumnIfMissing` desde el apagon.\n\n- [ ] documentar la migracion 13\n",
        );
        write(&root, "temas/secreto.md", "---\nai: false\n---\n# Nomina\n\nortofoto ortofoto ortofoto\n");
        write(&root, "privado/claves.md", "# Claves\n\nortofoto\n");
        write(&root, ".obsidian/cache.md", "ortofoto");
        root
    }

    fn finding() -> Finding {
        Finding {
            id: "f-1".into(),
            batch_id: "b".into(),
            project: "ia".into(),
            from: None,
            created_at: "2026-09-14T10:00:00Z".into(),
            content_hash: String::new(),
            content: NewFinding {
                kind: FindingKind::Decision,
                title: "Reprocesar con malla 3D".into(),
                body: "La ortofoto ultra se deforma con la malla 2.5D.".into(),
                evidence: vec![Evidence {
                    label: EvidenceLabel::S,
                    text: "visto en la tanda R".into(),
                    source: None,
                }],
                supersedes: None,
                date: None,
                target_hint: None,
            },
            status: FindingStatus::Applied {
                proposal_id: "p".into(),
            },
        }
    }

    #[test]
    fn indexes_the_vault_but_not_private_hidden_or_excluded_notes() {
        let root = vault("index-basic");
        let mut index = NotesIndex::new(&root);
        let stats = index.refresh().unwrap();
        assert_eq!(stats.added, 4, "{stats:?}");
        assert!(index.note("privado/claves.md").is_none());
        assert!(index.note(".obsidian/cache.md").is_none());
        assert_eq!(index.note("diario/2026-09-15.md").unwrap().role, DocRole::Daily);

        let hits = index.search("ortofoto deformada", &[], 10, None);
        let ids: Vec<&str> = hits.iter().map(|h| h.id.as_str()).collect();
        assert!(ids.contains(&"n:diario/2026-09-15.md#0"), "{ids:?}");
        assert!(ids.contains(&"n:proyectos/ODM.md#1"), "{ids:?}");
        assert!(!ids.iter().any(|id| id.contains("secreto")), "ai: false no se busca: {ids:?}");
        assert!(index.candidate("n:temas/secreto.md#0").is_none());
        assert!(hits[0].snippet.contains("ortofoto"), "{}", hits[0].snippet);
    }

    #[test]
    fn tasks_links_and_backlinks() {
        let root = vault("index-links");
        let mut index = NotesIndex::new(&root);
        index.refresh().unwrap();

        let tasks = index.open_tasks();
        assert_eq!(tasks.len(), 2, "{tasks:?}");
        assert_eq!(tasks[0].1.due.as_deref(), Some("2026-09-18"), "con fecha primero");
        assert_eq!(tasks[1].0, "temas/drift.md");

        assert_eq!(index.resolve_link("ODM").as_deref(), Some("proyectos/ODM.md"));
        assert_eq!(index.backlinks("proyectos/ODM.md"), vec!["diario/2026-09-15.md"]);
    }

    #[test]
    fn refresh_only_rereads_what_changed_and_forgets_deleted_notes() {
        let root = vault("index-refresh");
        let mut index = NotesIndex::new(&root);
        index.refresh().unwrap();
        assert!(!index.refresh().unwrap().any(), "sin cambios no relee nada");

        write(&root, "temas/drift.md", "# Drift\n\nAhora hablamos de riverpod y de nada mas, con otro tamaño.\n");
        std::fs::remove_file(root.join("proyectos/ODM.md")).unwrap();
        let stats = index.refresh().unwrap();
        assert_eq!((stats.changed, stats.removed), (1, 1), "{stats:?}");
        assert!(index.search("riverpod", &[], 5, None)[0].id.starts_with("n:temas/drift.md"));
        assert!(index.search("malla", &[CandidateKind::Note], 5, None).is_empty());
    }

    #[test]
    fn findings_and_commits_are_searchable_and_can_be_filtered() {
        let root = vault("index-sources");
        let mut index = NotesIndex::new(&root);
        index.refresh().unwrap();
        index.set_findings(vec![finding()]);
        index.set_commits(vec![CommitInfo {
            repo: "ExampleApi".into(),
            sha: "abcdef1234567".into(),
            date: "2026-09-15".into(),
            author: "Juan".into(),
            subject: "Tanda R: reprocesar con malla 3D".into(),
            body: "La 2.5D deformaba la ortofoto.".into(),
        }]);

        let commits = index.search("malla ortofoto", &[CandidateKind::Commit], 5, None);
        assert_eq!(commits.len(), 1);
        assert_eq!(commits[0].id, "c:ExampleApi@abcdef1");
        let findings = index.search("malla ortofoto", &[CandidateKind::Finding], 5, None);
        assert_eq!(findings[0].id, "f:f-1");
        assert_eq!(findings[0].date.as_deref(), Some("2026-09-14"));

        let related = index.related("diario/2026-09-15.md", 5);
        assert!(related.iter().all(|c| c.path.as_deref() != Some("diario/2026-09-15.md")));
        assert!(related.iter().any(|c| c.path.as_deref() == Some("proyectos/ODM.md")), "{related:?}");
    }

    #[test]
    fn tokens_ignore_accents_case_filler_words_and_endings() {
        assert_eq!(
            tokens("La Migración de la BASE, para ñandúes"),
            vec!["migrac", "base", "nandue"]
        );
        assert_eq!(tokens("ortofotos deformada"), tokens("ortofoto deforma"));
    }

    /// Una carpeta local entra con su prefijo y su rol se calcula sin el; una
    /// carpeta `@` de la principal no se cuela; una local que no esta no tumba el
    /// indice; y los enlaces se resuelven desde la nota que los escribe.
    #[test]
    fn indexes_several_note_folders() {
        let main = vault("index-roots-main");
        write(&main, "@falsa/x.md", "# Falsa\n\nno deberia salir\n");
        let local = crate::test_support::temp_dir("index-roots-local");
        write(&local, "diario/2026-09-16.md", "# Hoy\n\nVer [[clientes/acme]].\n");
        write(&local, "clientes/acme.md", "# Acme\n\nEl cliente de la malla.\n");
        let mut index = NotesIndex::with_roots(vec![
            (String::new(), main.clone()),
            ("@apuntes/".into(), local.clone()),
            ("@fuera/".into(), local.join("no-existe")),
        ]);
        index.refresh().unwrap();

        assert!(index.note("@apuntes/clientes/acme.md").is_some());
        assert_eq!(index.note("@apuntes/diario/2026-09-16.md").unwrap().role, DocRole::Daily);
        assert!(index.note("proyectos/ODM.md").is_some(), "la principal no cambia");
        assert!(index.notes().all(|n| !n.path.starts_with("@falsa")));

        // Dentro de la carpeta local, el enlace con ruta se busca en ella...
        assert_eq!(
            index.resolve_link_from("clientes/acme", "@apuntes/diario/2026-09-16.md").as_deref(),
            Some("@apuntes/clientes/acme.md")
        );
        assert_eq!(
            index.backlinks("@apuntes/clientes/acme.md"),
            vec!["@apuntes/diario/2026-09-16.md"]
        );
        // ...y si no esta en ella, en la principal (que no lleva prefijo).
        assert_eq!(
            index.resolve_link_from("temas/drift", "@apuntes/diario/2026-09-16.md").as_deref(),
            Some("temas/drift.md")
        );
        // Con las dos, gana la de su propia carpeta.
        write(&local, "temas/drift.md", "# Drift local\n");
        index.refresh().unwrap();
        assert_eq!(
            index.resolve_link_from("temas/drift", "@apuntes/diario/2026-09-16.md").as_deref(),
            Some("@apuntes/temas/drift.md")
        );
        // Desde la principal, con el prefijo.
        assert_eq!(
            index.resolve_link_from("@apuntes/clientes/acme", "temas/drift.md").as_deref(),
            Some("@apuntes/clientes/acme.md")
        );
    }
}
