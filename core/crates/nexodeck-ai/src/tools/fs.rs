//! Herramientas de lectura del sistema de archivos.
//!
//! Las tres son **estrictamente de solo lectura**. No hay escritura, ni
//! borrado, ni ejecucion: lo unico que el asistente puede hacer con el disco es
//! mirarlo para poder proponer una ruta absoluta que exista de verdad, en vez
//! de inventarla.
//!
//! Cada resultado que confirma una ruta la anota en [`TurnFacts`], que es
//! contra lo que despues valida `propose_action`.

use std::path::{Path, PathBuf};

use serde_json::{Value, json};

use crate::openai::types::ToolDef;
use crate::tools::{Tool, ToolContext, arg_str, error};

/// Tope de entradas por listado. Una carpeta con 5000 archivos llenaria el
/// contexto del modelo sin aportar nada.
const MAX_ENTRIES: usize = 120;

/// Tope de bytes que se leen de un archivo de texto.
const MAX_READ_BYTES: usize = 8_192;

/// Carpetas que `find_project` nunca entra: gigantes y sin proyectos adentro.
/// Sin esto, una busqueda en `C:/` tarda minutos.
const SKIP_DIRS: &[&str] = &[
    "node_modules",
    ".git",
    "target",
    "build",
    ".dart_tool",
    ".gradle",
    "windows",
    "$recycle.bin",
    "system volume information",
    "appdata",
    "program files",
    "program files (x86)",
    "programdata",
    "$windows.~bt",
    ".cargo",
    ".pub-cache",
    "obj",
    "bin",
];

/// Profundidad maxima de la busqueda. Un proyecto enterrado a mas de esto es
/// mas rapido de preguntar que de encontrar.
const MAX_DEPTH: usize = 6;

/// Tope de directorios visitados.
const MAX_VISITED: usize = 12_000;

/// Presupuesto de **tiempo** de la busqueda.
///
/// Es el limite que realmente importa: contar directorios no acota nada
/// util cuando el costo por directorio va de microsegundos (SSD con cache
/// caliente) a milisegundos (disco mecanico frio, unidad de red). Medido en
/// directorios, la misma busqueda tarda 200 ms en una maquina y varios minutos
/// en otra — y el usuario esta mirando un chat que no responde. Con un
/// deadline, el peor caso es siempre el mismo y la herramienta devuelve lo que
/// alcanzo a encontrar mas un aviso de que quedo incompleta.
const SEARCH_BUDGET: std::time::Duration = std::time::Duration::from_secs(6);

pub struct ListDirectory;

impl Tool for ListDirectory {
    fn name(&self) -> &'static str {
        "list_directory"
    }

    fn definition(&self) -> ToolDef {
        ToolDef::function(
            "list_directory",
            "Lista el contenido de una carpeta del equipo del usuario. Solo lectura. \
             Usala para confirmar que una ruta existe antes de meterla en un comando.",
            json!({
                "type": "object",
                "properties": {
                    "path": {
                        "type": "string",
                        "description": "Ruta absoluta de la carpeta, por ejemplo E:/Proyectos"
                    }
                },
                "required": ["path"]
            }),
        )
    }

    fn call(&self, args: &Value, ctx: &ToolContext) -> Value {
        let Some(raw) = arg_str(args, "path") else {
            return error("falta el parametro 'path'");
        };
        let path = PathBuf::from(raw);

        if !ctx.is_readable(&path) {
            return not_allowed(&path, ctx);
        }
        if !path.is_dir() {
            return error(format!(
                "'{raw}' no existe o no es una carpeta. Probá con find_project si no sabes la ruta exacta."
            ));
        }

        let Ok(entries) = std::fs::read_dir(&path) else {
            return error(format!("no se pudo leer '{raw}'"));
        };

        let mut directories = Vec::new();
        let mut files = Vec::new();
        let mut truncated = false;

        for entry in entries.flatten() {
            if directories.len() + files.len() >= MAX_ENTRIES {
                truncated = true;
                break;
            }
            let name = entry.file_name().to_string_lossy().to_string();
            match entry.file_type() {
                Ok(kind) if kind.is_dir() => directories.push(name),
                Ok(_) => files.push(name),
                Err(_) => {}
            }
        }

        directories.sort();
        files.sort();

        ctx.with_facts(|facts| facts.confirm_path(&path));

        json!({
            "ok": true,
            "path": path.to_string_lossy(),
            "directories": directories,
            "files": files,
            "truncated": truncated
        })
    }
}

pub struct FindProject;

impl Tool for FindProject {
    fn name(&self) -> &'static str {
        "find_project"
    }

    fn definition(&self) -> ToolDef {
        ToolDef::function(
            "find_project",
            "Busca una carpeta de proyecto por nombre en las carpetas que el usuario permitio. \
             Devuelve rutas absolutas y, si puede, que tipo de proyecto es (Flutter, Node, Rust...). \
             Es la forma correcta de resolver 'mi proyecto X' sin pedirle la ruta al usuario.",
            json!({
                "type": "object",
                "properties": {
                    "name": {
                        "type": "string",
                        "description": "Nombre o parte del nombre de la carpeta, por ejemplo ExampleApp"
                    }
                },
                "required": ["name"]
            }),
        )
    }

    fn call(&self, args: &Value, ctx: &ToolContext) -> Value {
        let Some(needle) = arg_str(args, "name") else {
            return error("falta el parametro 'name'");
        };
        let needle_lower = needle.to_lowercase();

        let mut matches = Vec::new();
        let mut budget = SearchBudget {
            visited: 0,
            deadline: std::time::Instant::now() + SEARCH_BUDGET,
        };

        for root in ctx.allowed_roots() {
            search(&root, 0, &needle_lower, ctx, &mut matches, &mut budget);
            if budget.is_exhausted() || matches.len() >= 20 {
                break;
            }
        }
        let incomplete = budget.is_exhausted();

        // Coincidencia exacta primero: buscando "app" no sirve que la primera
        // sea "aplicaciones-viejas".
        matches.sort_by_key(|found| {
            let name = found
                .path
                .file_name()
                .map(|n| n.to_string_lossy().to_lowercase())
                .unwrap_or_default();
            (name != needle_lower, found.path.components().count())
        });

        for found in &matches {
            ctx.with_facts(|facts| facts.confirm_path(&found.path));
        }

        if matches.is_empty() {
            return json!({
                "ok": true,
                "matches": [],
                "incomplete": incomplete,
                "hint": if incomplete {
                    format!(
                        "La busqueda de '{needle}' se corto por tiempo sin encontrar nada. \
                         Preguntale al usuario la ruta absoluta en vez de volver a buscar."
                    )
                } else {
                    format!(
                        "No se encontro ninguna carpeta que contenga '{needle}' en las carpetas permitidas. \
                         Preguntale al usuario la ruta absoluta."
                    )
                }
            });
        }

        let paths: Vec<PathBuf> = matches.iter().map(|found| found.path.clone()).collect();
        let independent = independent_roots(&paths);

        let mut response = json!({
            "ok": true,
            "incomplete": incomplete,
            "matches": matches.iter().map(|found| json!({
                "path": found.path.to_string_lossy(),
                "project_type": found.project_type,
            })).collect::<Vec<_>>()
        });

        // Mas de un match NO es lo mismo que mas de un proyecto: si "proyecto"
        // encuentra 11 carpetas pero 10 son subcarpetas de la primera, hay UN
        // solo proyecto. Si en cambio hay varias carpetas que NO son subcarpeta
        // una de otra (siete "Example*" hermanas, por ejemplo), esa es la
        // ambiguedad real — y el modelo tiene que resolverla preguntando, no
        // adivinando cual "se parece mas". Structural, no prosa: el aviso vive
        // en el resultado de la herramienta, no solo en el system prompt (que
        // ya se demostro que un modelo de 14B no sigue con suficiente
        // fiabilidad).
        if independent.len() > 1 {
            let preview: Vec<String> = independent
                .iter()
                .take(8)
                .map(|path| path.to_string_lossy().to_string())
                .collect();
            response["hint"] = json!(format!(
                "Hay {} proyectos DISTINTOS que coinciden con '{needle}' (no uno solo con \
                 subcarpetas): {}. No elijas uno por tu cuenta: mostraselos al usuario y \
                 pregunta cual es antes de seguir.",
                independent.len(),
                preview.join(", ")
            ));
        }

        response
    }
}

/// De una lista de rutas, cuales NO son subcarpeta de ninguna otra de la
/// misma lista. Un proyecto que aparece varias veces (el proyecto mismo mas
/// sus subcarpetas) cuenta una sola vez; proyectos hermanos sin relacion de
/// contencion cuentan cada uno.
fn independent_roots(paths: &[PathBuf]) -> Vec<&PathBuf> {
    paths
        .iter()
        .enumerate()
        .filter(|(i, candidate)| {
            !paths
                .iter()
                .enumerate()
                .any(|(j, other)| j != *i && candidate.starts_with(other))
        })
        .map(|(_, path)| path)
        .collect()
}

struct FoundProject {
    path: PathBuf,
    project_type: &'static str,
}

struct SearchBudget {
    visited: usize,
    deadline: std::time::Instant,
}

impl SearchBudget {
    fn is_exhausted(&self) -> bool {
        self.visited >= MAX_VISITED || std::time::Instant::now() >= self.deadline
    }
}

fn search(
    dir: &Path,
    depth: usize,
    needle: &str,
    ctx: &ToolContext,
    matches: &mut Vec<FoundProject>,
    budget: &mut SearchBudget,
) {
    if depth > MAX_DEPTH || matches.len() >= 20 {
        return;
    }
    // El reloj se consulta una vez por directorio, no por entrada: en una
    // carpeta con miles de archivos, un `Instant::now()` por entrada cuesta
    // mas que el propio `read_dir`.
    if budget.is_exhausted() {
        return;
    }
    budget.visited += 1;

    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };

    for entry in entries.flatten() {
        let Ok(kind) = entry.file_type() else { continue };
        if !kind.is_dir() {
            continue;
        }

        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_lowercase();

        if SKIP_DIRS.contains(&name.as_str()) || name.starts_with('.') {
            continue;
        }
        if !ctx.is_readable(&path) {
            continue;
        }

        if name.contains(needle) {
            matches.push(FoundProject {
                project_type: detect_project_type(&path),
                path: path.clone(),
            });
        }

        search(&path, depth + 1, needle, ctx, matches, budget);
    }
}

/// Deduce el tipo de proyecto por su archivo marcador. Le ahorra al modelo una
/// ronda de `list_directory` para saber si puede correr `flutter` o `npm`.
fn detect_project_type(path: &Path) -> &'static str {
    const MARKERS: &[(&str, &str)] = &[
        ("pubspec.yaml", "flutter/dart"),
        ("Cargo.toml", "rust"),
        ("package.json", "node"),
        ("pom.xml", "java/maven"),
        ("build.gradle", "gradle"),
        ("requirements.txt", "python"),
        ("pyproject.toml", "python"),
        ("go.mod", "go"),
        ("*.sln", "dotnet"),
    ];

    for (marker, kind) in MARKERS {
        if !marker.starts_with('*') && path.join(marker).exists() {
            return kind;
        }
    }

    if path.join(".git").exists() {
        return "git";
    }

    "desconocido"
}

pub struct ReadTextFile;

impl Tool for ReadTextFile {
    fn name(&self) -> &'static str {
        "read_text_file"
    }

    fn definition(&self) -> ToolDef {
        ToolDef::function(
            "read_text_file",
            "Lee el principio de un archivo de texto (pubspec.yaml, package.json, README...). \
             Solo lectura y truncado. Usala para entender de que va un proyecto.",
            json!({
                "type": "object",
                "properties": {
                    "path": { "type": "string", "description": "Ruta absoluta del archivo" }
                },
                "required": ["path"]
            }),
        )
    }

    fn call(&self, args: &Value, ctx: &ToolContext) -> Value {
        let Some(raw) = arg_str(args, "path") else {
            return error("falta el parametro 'path'");
        };
        let path = PathBuf::from(raw);

        if !ctx.is_readable(&path) {
            return not_allowed(&path, ctx);
        }
        if !path.is_file() {
            return error(format!("'{raw}' no existe o no es un archivo"));
        }

        let Ok(bytes) = std::fs::read(&path) else {
            return error(format!("no se pudo leer '{raw}'"));
        };

        let truncated = bytes.len() > MAX_READ_BYTES;
        let slice = &bytes[..bytes.len().min(MAX_READ_BYTES)];

        // Binario: devolverle bytes crudos a un modelo solo gasta contexto.
        if slice.contains(&0) {
            return error(format!("'{raw}' parece un archivo binario, no de texto"));
        }

        if let Some(parent) = path.parent() {
            ctx.with_facts(|facts| facts.confirm_path(parent));
        }

        json!({
            "ok": true,
            "path": path.to_string_lossy(),
            "content": String::from_utf8_lossy(slice),
            "truncated": truncated
        })
    }
}

/// Mensaje comun de "no puedo leer ahi". Incluye las raices permitidas: sin
/// eso el modelo reintenta la misma ruta prohibida una y otra vez.
fn not_allowed(path: &Path, ctx: &ToolContext) -> Value {
    json!({
        "ok": false,
        "error": format!(
            "'{}' esta fuera de las carpetas que el usuario permitio leer. Carpetas permitidas: {}. \
             Si el proyecto esta en otro lado, preguntale al usuario.",
            path.display(),
            ctx.allowed_roots()
                .iter()
                .map(|root| root.to_string_lossy().to_string())
                .collect::<Vec<_>>()
                .join(", ")
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tools::ToolRegistry;

    /// Crea un arbol temporal con un proyecto Flutter adentro.
    fn temp_tree() -> PathBuf {
        let base = std::env::temp_dir().join(format!(
            "nexodeck-ai-fs-{}-{:?}",
            std::process::id(),
            std::thread::current().id()
        ));
        let project = base.join("Proyectos").join("ExampleApp");
        std::fs::create_dir_all(project.join("lib")).unwrap();
        std::fs::write(project.join("pubspec.yaml"), "name: proyecto\n").unwrap();
        std::fs::write(project.join("lib").join("main.dart"), "void main() {}").unwrap();
        base
    }

    fn ctx_for(base: &Path) -> ToolContext {
        ToolContext::new(vec![base.to_path_buf()], nexodeck_hardware::HostOs::Windows)
    }

    #[test]
    fn list_directory_separa_carpetas_de_archivos_y_confirma_la_ruta() {
        let base = temp_tree();
        let ctx = ctx_for(&base);
        let project = base.join("Proyectos").join("ExampleApp");

        let result = ListDirectory.call(
            &json!({ "path": project.to_string_lossy() }),
            &ctx,
        );

        assert_eq!(result["ok"], true);
        assert!(result["directories"]
            .as_array()
            .unwrap()
            .iter()
            .any(|d| d == "lib"));
        assert!(result["files"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f == "pubspec.yaml"));

        // Y la ruta queda confirmada para el gate de propose_action.
        assert!(ctx.with_facts(|facts| facts.knows_path(&project.to_string_lossy())));

        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn list_directory_rechaza_una_ruta_fuera_de_las_raices_y_dice_cuales_son() {
        let base = temp_tree();
        let ctx = ctx_for(&base);

        let result = ListDirectory.call(&json!({ "path": "C:/Windows" }), &ctx);

        assert_eq!(result["ok"], false);
        let message = result["error"].as_str().unwrap();
        assert!(message.contains("fuera de las carpetas"));
        assert!(
            message.contains(&base.to_string_lossy().to_string()),
            "tiene que listar las permitidas para que el modelo no reintente a ciegas"
        );

        let _ = std::fs::remove_dir_all(&base);
    }

    /// El caso del brief: "mi proyecto ExampleApp" tiene que resolverse solo.
    #[test]
    fn find_project_encuentra_el_proyecto_y_deduce_que_es_flutter() {
        let base = temp_tree();
        let ctx = ctx_for(&base);

        let result = FindProject.call(&json!({ "name": "proyecto" }), &ctx);

        assert_eq!(result["ok"], true);
        let matches = result["matches"].as_array().unwrap();
        assert!(!matches.is_empty(), "tendria que haber encontrado el proyecto");
        assert_eq!(matches[0]["project_type"], "flutter/dart");
        assert!(matches[0]["path"]
            .as_str()
            .unwrap()
            .to_lowercase()
            .contains("proyectoapp"));

        let _ = std::fs::remove_dir_all(&base);
    }

    /// Bug real: pedile "proyecto" a este equipo y `find_project` encuentra
    /// siete carpetas hermanas (Example, ExampleApi, ExampleApp...) sin
    /// relacion de contencion entre si. Sin este hint, el modelo eligio en
    /// silencio la mas profunda de las 20 en vez de preguntar.
    #[test]
    fn find_project_con_varios_proyectos_hermanos_pide_preguntar() {
        let base = temp_tree();
        // El proyecto que ya trae temp_tree() es ExampleApp; se agregan
        // hermanos sin relacion de contencion entre ellos.
        for hermano in ["Example", "ExampleApi", "ExampleADMIN"] {
            std::fs::create_dir_all(base.join("Proyectos").join(hermano)).unwrap();
        }
        let ctx = ctx_for(&base);

        let result = FindProject.call(&json!({ "name": "proyecto" }), &ctx);

        assert_eq!(result["ok"], true);
        assert!(
            result["matches"].as_array().unwrap().len() > 1,
            "tiene que encontrar los cuatro"
        );
        let hint = result["hint"]
            .as_str()
            .expect("con proyectos hermanos tiene que haber un hint de ambiguedad");
        assert!(hint.contains("DISTINTOS"));
        assert!(hint.to_lowercase().contains("pregunta"));

        let _ = std::fs::remove_dir_all(&base);
    }

    /// Contracara: muchos matches que son todos subcarpeta del mismo proyecto
    /// NO son ambiguos. Pedir que el modelo pregunte igual seria puro ruido
    /// (la regla del prompt es "no preguntes lo que una herramienta ya
    /// contesto").
    #[test]
    fn find_project_con_un_solo_proyecto_no_pide_preguntar_aunque_haya_varios_matches() {
        let base = temp_tree();
        let ctx = ctx_for(&base);

        let result = FindProject.call(&json!({ "name": "proyecto" }), &ctx);

        assert_eq!(result["ok"], true);
        assert!(result["hint"].is_null(), "un solo proyecto no es ambiguo");

        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn independent_roots_colapsa_las_subcarpetas_del_mismo_proyecto() {
        let paths = vec![
            PathBuf::from("E:/Proyectos/ExampleApp"),
            PathBuf::from("E:/Proyectos/ExampleApp/lib"),
            PathBuf::from("E:/Proyectos/ExampleApp/lib/main"),
        ];
        assert_eq!(independent_roots(&paths).len(), 1);
    }

    #[test]
    fn independent_roots_cuenta_los_hermanos_por_separado() {
        let paths = vec![
            PathBuf::from("E:/Proyectos/Example"),
            PathBuf::from("E:/Proyectos/ExampleApi"),
            PathBuf::from("E:/Proyectos/ExampleApp"),
        ];
        assert_eq!(independent_roots(&paths).len(), 3);
    }

    /// Sin resultados tiene que decirle al modelo que **pregunte**, no que
    /// invente una ruta.
    #[test]
    fn find_project_sin_resultados_indica_preguntarle_al_usuario() {
        let base = temp_tree();
        let ctx = ctx_for(&base);

        let result = FindProject.call(&json!({ "name": "no-existe-nada" }), &ctx);

        assert_eq!(result["ok"], true);
        assert!(result["matches"].as_array().unwrap().is_empty());
        assert!(result["hint"].as_str().unwrap().contains("Preguntale"));

        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn read_text_file_trunca_y_rechaza_binarios() {
        let base = temp_tree();
        let ctx = ctx_for(&base);
        let pubspec = base.join("Proyectos").join("ExampleApp").join("pubspec.yaml");

        let result = ReadTextFile.call(&json!({ "path": pubspec.to_string_lossy() }), &ctx);
        assert_eq!(result["ok"], true);
        assert!(result["content"].as_str().unwrap().contains("proyecto"));

        let binary = base.join("binario.bin");
        std::fs::write(&binary, [0u8, 1, 2, 3]).unwrap();
        let result = ReadTextFile.call(&json!({ "path": binary.to_string_lossy() }), &ctx);
        assert_eq!(result["ok"], false);
        assert!(result["error"].as_str().unwrap().contains("binario"));

        let _ = std::fs::remove_dir_all(&base);
    }

    #[test]
    fn falta_de_argumentos_devuelve_un_error_util_no_un_panic() {
        let base = temp_tree();
        let ctx = ctx_for(&base);

        for tool_name in ["list_directory", "find_project", "read_text_file"] {
            let result = ToolRegistry::standard().dispatch(tool_name, "{}", &ctx);
            assert_eq!(result["ok"], false, "{tool_name}");
        }

        let _ = std::fs::remove_dir_all(&base);
    }
}
