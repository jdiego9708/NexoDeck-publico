//! El servidor de control de verdad: se levanta, se le habla por HTTP y se
//! comprueba lo que contesta.
//!
//! **Tarda mas de un minuto, y no esta colgado.** Comprobar que una sesion
//! NO recibe lo que era para otra obliga a esperar el timeout real del buzon
//! (25 s), y eso pasa tres veces. Acortarlo pediria un knob que solo existiria
//! para los tests, y preferimos el minuto a la pieza de mentira.
//!
//! **Es un solo test y no varios a proposito.** `control()` es un singleton, y
//! con varios `#[tokio::test]` en el mismo binario se pelearian por el: uno
//! pararia el servidor que otro acaba de levantar, y el fallo aparecería una
//! vez de cada diez segun el orden en que los programe el runtime. Es
//! exactamente el tipo de test intermitente que despues nadie cree.

use nexodeck_control::{control, ControlConfig, DEFAULT_PORT};
use nexodeck_notify::{CommandChannel, MessageDelivery, NotifyLevel};
use serde_json::{json, Value};

const TOKEN: &str = "token-de-prueba-0123456789";

/// Un canal que no manda nada a ningun sitio pero termina con codigo 0, para
/// poder comprobar la entrega sin depender del VPS ni de la red.
fn fake_channel() -> CommandChannel {
    let (program, args) = if cfg!(windows) {
        ("cmd".to_string(), vec!["/C".to_string(), "exit 0".to_string()])
    } else {
        ("sh".to_string(), vec!["-c".to_string(), "exit 0".to_string()])
    };
    CommandChannel {
        id: "prueba".into(),
        label: "Canal de prueba".into(),
        program,
        args,
        delivery: MessageDelivery::Stdin,
        min_level: NotifyLevel::Milestone,
        timeout_secs: Some(10),
        enabled: true,
    }
}

async fn rpc(
    client: &reqwest::Client,
    url: &str,
    token: Option<&str>,
    origin: Option<&str>,
    body: Value,
) -> (reqwest::StatusCode, Value) {
    let mut request = client.post(url).json(&body);
    if let Some(token) = token {
        request = request.header("Authorization", format!("Bearer {token}"));
    }
    if let Some(origin) = origin {
        request = request.header("Origin", origin);
    }
    let response = request.send().await.expect("la peticion tiene que llegar");
    let status = response.status();
    let value = response.json::<Value>().await.unwrap_or(Value::Null);
    (status, value)
}

#[tokio::test]
async fn the_control_server_serves_mcp_over_loopback_and_guards_the_door() {
    let control = control();

    // Puerto 0: lo elige el sistema. Con `DEFAULT_PORT` el test fallaria en
    // cualquier maquina que tenga NexoDeck abierto, que es justo la maquina en
    // la que uno lo corre.
    assert_eq!(DEFAULT_PORT, 58646);
    let port = control
        .start(ControlConfig {
            port: 0,
            token: TOKEN.into(),
            channels: vec![fake_channel()],
        })
        .await
        .expect("el servidor tiene que levantar");
    assert!(control.is_running());
    assert_eq!(control.port(), Some(port));

    let url = format!("http://127.0.0.1:{port}/mcp");
    let client = reqwest::Client::new();

    // --- La puerta ---------------------------------------------------

    let (status, _) = rpc(&client, &url, None, None, json!({"jsonrpc":"2.0","id":1,"method":"ping"})).await;
    assert_eq!(
        status,
        reqwest::StatusCode::UNAUTHORIZED,
        "sin token no se entra"
    );

    let (status, _) = rpc(
        &client,
        &url,
        Some("token-equivocado"),
        None,
        json!({"jsonrpc":"2.0","id":1,"method":"ping"}),
    )
    .await;
    assert_eq!(status, reqwest::StatusCode::UNAUTHORIZED);

    // Una pagina web no entra ni con el token correcto.
    let (status, _) = rpc(
        &client,
        &url,
        Some(TOKEN),
        Some("https://cualquier.sitio"),
        json!({"jsonrpc":"2.0","id":1,"method":"ping"}),
    )
    .await;
    assert_eq!(status, reqwest::StatusCode::FORBIDDEN);

    // --- El apreton de manos -----------------------------------------

    let (status, body) = rpc(
        &client,
        &url,
        Some(TOKEN),
        None,
        json!({
            "jsonrpc":"2.0","id":1,"method":"initialize",
            "params":{"protocolVersion":"2025-06-18","capabilities":{},
                      "clientInfo":{"name":"test","version":"0"}}
        }),
    )
    .await;
    assert_eq!(status, reqwest::StatusCode::OK);
    assert_eq!(body["result"]["protocolVersion"], "2025-06-18");
    assert_eq!(body["result"]["serverInfo"]["name"], "nexodeck");

    // Una notificacion (sin `id`) se acusa y no lleva respuesta.
    let response = client
        .post(&url)
        .header("Authorization", format!("Bearer {TOKEN}"))
        .json(&json!({"jsonrpc":"2.0","method":"notifications/initialized"}))
        .send()
        .await
        .expect("acuse");
    assert_eq!(response.status(), reqwest::StatusCode::ACCEPTED);

    // --- Las herramientas --------------------------------------------

    let (_, body) = rpc(
        &client,
        &url,
        Some(TOKEN),
        None,
        json!({"jsonrpc":"2.0","id":2,"method":"tools/list"}),
    )
    .await;
    let tools = body["result"]["tools"].as_array().expect("lista de tools");
    let names: Vec<&str> = tools.iter().filter_map(|t| t["name"].as_str()).collect();
    assert!(names.contains(&"notify"));
    assert!(names.contains(&"list_runs"));
    assert!(names.contains(&"tail_run"));

    // El ensayo en seco describe lo que haria y **no ejecuta nada**.
    let (_, body) = rpc(
        &client,
        &url,
        Some(TOKEN),
        None,
        json!({"jsonrpc":"2.0","id":3,"method":"tools/call",
               "params":{"name":"notify","arguments":{"text":"hola","dry_run":true}}}),
    )
    .await;
    assert_eq!(body["result"]["isError"], false);
    let text = body["result"]["content"][0]["text"].as_str().unwrap();
    assert!(text.contains("ensayo en seco"), "texto: {text}");

    // Entrega de verdad contra el canal falso.
    let (_, body) = rpc(
        &client,
        &url,
        Some(TOKEN),
        None,
        json!({"jsonrpc":"2.0","id":4,"method":"tools/call",
               "params":{"name":"notify","arguments":{"text":"hola","level":"always"}}}),
    )
    .await;
    let text = body["result"]["content"][0]["text"].as_str().unwrap_or("<sin texto>");
    assert_eq!(body["result"]["isError"], false, "el canal falso no entrego: {text}");
    assert!(text.contains("entregado"), "texto: {text}");

    // Una herramienta que no existe es error de protocolo, no de herramienta.
    let (_, body) = rpc(
        &client,
        &url,
        Some(TOKEN),
        None,
        json!({"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"inventada"}}),
    )
    .await;
    assert_eq!(body["error"]["code"], -32602);

    // --- La correspondencia con Claude Code, ida y vuelta ------------
    //
    // Es el sentido que el servidor MCP no tiene: NexoDeck pregunta, un oyente
    // externo recoge por HTTP, y la respuesta vuelve como llamada a herramienta.

    let mut correo = control.subscribe_correspondent();
    let outbox_url = format!("http://127.0.0.1:{port}/outbox");

    // Un ayudante que hace de vigilante: se presenta y recoge lo suyo.
    let consultar = |session: &'static str, label: &'static str, since: u64| {
        let client = client.clone();
        let url = outbox_url.clone();
        async move {
            client
                .get(&url)
                .query(&[
                    ("since", since.to_string()),
                    ("confirm", since.to_string()),
                    ("session", session.to_string()),
                    ("label", label.to_string()),
                    ("cwd", "/d/Repositorios/NexoDeck".to_string()),
                ])
                .header("Authorization", format!("Bearer {TOKEN}"))
                .send()
                .await
                .expect("peticion")
                .json::<Value>()
                .await
                .expect("json")
        }
    };

    // Sin token no entra, igual que todo lo demas: por aqui sale lo que el
    // usuario le dijo a su asistente.
    let sin_token = client.get(&outbox_url).send().await.expect("peticion");
    assert_eq!(sin_token.status(), reqwest::StatusCode::UNAUTHORIZED);

    // Y sin identificarse tampoco: un oyente sin `session` recibiria solo los
    // avisos generales y ninguna pregunta, y el sintoma seria un puente que
    // "no funciona a veces".
    let sin_sesion = client
        .get(&outbox_url)
        .header("Authorization", format!("Bearer {TOKEN}"))
        .send()
        .await
        .expect("peticion");
    assert_eq!(sin_sesion.status(), reqwest::StatusCode::BAD_REQUEST);

    // Dos vigilantes se presentan. **Este es el caso de las cinco terminales.**
    let _ = consultar("2001", "NexoDeck en main", 0).await;
    let _ = consultar("2002", "ExampleApi en dev", 0).await;

    let sesiones = control.correspondent_sessions();
    assert_eq!(sesiones.len(), 2);
    assert!(sesiones.iter().all(|s| !s.stale));
    assert!(sesiones.iter().any(|s| s.label == "NexoDeck en main"));

    // Una pregunta dirigida a la primera.
    let seq = control.ask_correspondent(
        "necesito un script que archive la tanda K".into(),
        Some("2001".into()),
    );
    assert_eq!(control.pending_replies(), 1);

    let body = consultar("2001", "NexoDeck en main", 0).await;
    let mensajes = body["messages"].as_array().expect("lista de mensajes");
    assert_eq!(mensajes.len(), 1);
    assert_eq!(mensajes[0]["seq"].as_u64(), Some(seq));
    assert_eq!(mensajes[0]["expects_reply"], true);
    assert!(mensajes[0]["text"].as_str().unwrap().contains("tanda K"));

    // **La segunda no lo ve.** Sin esto las cinco terminales recibirian todo.
    let body = consultar("2002", "ExampleApi en dev", 0).await;
    assert!(
        body["messages"].as_array().unwrap().is_empty(),
        "la pregunta era para la otra sesion"
    );

    // Entregar no consume: un oyente que muere sin confirmar repesca lo mismo.
    // Repetir molesta; perder no se arregla.
    let body = consultar("2001", "NexoDeck en main", 0).await;
    assert_eq!(body["messages"].as_array().unwrap().len(), 1);

    // Un aviso sin destinatario si lo reciben las dos.
    control.tell_correspondent("aviso para todas".into(), None);
    for session in ["2001", "2002"] {
        let body = consultar(session, "x", 1).await;
        let mensajes = body["messages"].as_array().unwrap();
        assert_eq!(mensajes.len(), 1, "la sesion {session} tenia que verlo");
        assert!(mensajes[0]["text"].as_str().unwrap().contains("para todas"));
    }

    // Claude Code contesta con la herramienta.
    let (_, body) = rpc(
        &client,
        &url,
        Some(TOKEN),
        None,
        json!({"jsonrpc":"2.0","id":7,"method":"tools/call",
               "params":{"name":"reply","arguments":{"message_id": seq, "text":"listo, aqui va"}}}),
    )
    .await;
    assert_eq!(body["result"]["isError"], false);
    assert_eq!(control.pending_replies(), 0);

    // El canal lleva tambien acuses y altas de sesion, asi que se busca la
    // respuesta en vez de exigir que sea el primer evento.
    let mut encontrada = false;
    for _ in 0..20 {
        let evento = tokio::time::timeout(std::time::Duration::from_secs(2), correo.recv())
            .await
            .expect("la respuesta tenia que llegar")
            .expect("canal vivo");
        if let nexodeck_control::CorrespondentEvent::Replied { seq: got, text } = evento {
            assert_eq!(got, seq);
            assert_eq!(text, "listo, aqui va");
            encontrada = true;
            break;
        }
    }
    assert!(encontrada, "no llego la respuesta");

    // Contestar dos veces a la misma pregunta se rechaza CON MOTIVO, en vez de
    // emitir un evento que el chat no sabria donde poner.
    let (_, body) = rpc(
        &client,
        &url,
        Some(TOKEN),
        None,
        json!({"jsonrpc":"2.0","id":8,"method":"tools/call",
               "params":{"name":"reply","arguments":{"message_id": seq, "text":"otra vez"}}}),
    )
    .await;
    assert_eq!(body["result"]["isError"], true);
    let texto = body["result"]["content"][0]["text"].as_str().unwrap();
    assert!(texto.contains("post_message"), "texto: {texto}");

    // Y un mensaje suelto, sin que nadie preguntara.
    let (_, body) = rpc(
        &client,
        &url,
        Some(TOKEN),
        None,
        json!({"jsonrpc":"2.0","id":9,"method":"tools/call",
               "params":{"name":"post_message","arguments":{"text":"termine la tanda","from":"NexoDeck en main"}}}),
    )
    .await;
    assert_eq!(body["result"]["isError"], false);
    // La firma es cooperativa: la sesion la pasa porque sus instrucciones se lo
    // dicen, y llega tal cual. No se puede exigir, porque todas las terminales
    // hablan con el mismo token.
    let mut encontrado = false;
    for _ in 0..20 {
        let evento = tokio::time::timeout(std::time::Duration::from_secs(2), correo.recv())
            .await
            .expect("el mensaje tenia que llegar")
            .expect("canal vivo");
        if let nexodeck_control::CorrespondentEvent::Posted { text, from } = evento {
            assert_eq!(text, "termine la tanda");
            assert_eq!(from.as_deref(), Some("NexoDeck en main"));
            encontrado = true;
            break;
        }
    }
    assert!(encontrado, "no llego el mensaje suelto");

    // --- El buzon de documentacion -----------------------------------

    let call = |id: u64, name: &'static str, arguments: Value| {
        let client = client.clone();
        let url = url.clone();
        async move {
            let (_, body) = rpc(
                &client,
                &url,
                Some(TOKEN),
                None,
                json!({"jsonrpc":"2.0","id":id,"method":"tools/call",
                       "params":{"name":name,"arguments":arguments}}),
            )
            .await;
            let text = body["result"]["content"][0]["text"].as_str().unwrap_or("").to_string();
            (body["result"]["isError"] == true, text)
        }
    };

    // Sin buzon, las herramientas lo dicen en vez de fallar raro.
    control.set_docs(None);
    let (is_error, text) = call(20, "list_doc_projects", json!({})).await;
    assert!(is_error && text.contains("no esta inicializado"), "texto: {text}");

    let docs_dir = std::env::temp_dir().join(format!("nexodeck-control-e2e-docs-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&docs_dir);
    let repo = docs_dir.join("repo");
    std::fs::create_dir_all(repo.join("docs")).unwrap();
    std::fs::write(repo.join("docs/estado.md"), "# Estado\n\n## 14-sep: algo\n").unwrap();

    let inbox = nexodeck_docs::Inbox::open(docs_dir.join("inbox")).unwrap();
    inbox
        .save_config(&nexodeck_docs::InboxConfig {
            projects: vec![nexodeck_docs::DocProject {
                id: "ia".into(),
                name: "Deteccion por IA".into(),
                repo_root: repo.to_string_lossy().into_owned(),
                kind: nexodeck_docs::ProjectKind::Docs,
                conventions: String::new(),
                documents: vec![nexodeck_docs::DocTarget {
                    path: "docs/estado.md".into(),
                    role: nexodeck_docs::DocRole::Journal,
                    answers: "el diario".into(),
                    evidence_labels: true,
                }],
            }],
            ..nexodeck_docs::InboxConfig::default()
        })
        .unwrap();
    let findings_dir = inbox.root().join("findings");
    control.set_docs(Some(nexodeck_docs::DocsService::new(
        inbox,
        nexodeck_docs::Backends::Fixed(vec![]),
    )));

    let (_, body) = rpc(&client, &url, Some(TOKEN), None, json!({"jsonrpc":"2.0","id":21,"method":"tools/list"})).await;
    let names: Vec<String> = body["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|t| t["name"].as_str().map(str::to_string))
        .collect();
    for tool in ["submit_findings", "list_doc_projects", "finding_status"] {
        assert!(names.iter().any(|n| n == tool), "falta {tool}");
    }

    let (is_error, text) = call(22, "list_doc_projects", json!({})).await;
    assert!(!is_error, "texto: {text}");
    assert!(text.contains("ia - Deteccion por IA") && text.contains("APAGADO"), "texto: {text}");

    let hallazgo = |evidence: Value| {
        json!({
            "project": "ia",
            "from": "NexoDeck en main",
            "findings": [{
                "kind": "measurement",
                "title": "La deteccion es 3,5 veces mas rapida",
                "body": "Q entera paso de 1.652 s a 474 s.",
                "evidence": evidence
            }]
        })
    };

    let (is_error, text) = call(23, "submit_findings", hallazgo(json!([]))).await;
    assert!(is_error && text.contains("evidencia"), "texto: {text}");

    let (is_error, text) = call(24, "submit_findings", hallazgo(json!([{"label":"M","text":"474 s"}]))).await;
    assert!(is_error && text.contains("source"), "texto: {text}");

    let buena = hallazgo(json!([{"label":"M","text":"474 s","source":"odm_tandaq.log"}]));
    let (is_error, text) = call(25, "submit_findings", buena.clone()).await;
    assert!(!is_error, "texto: {text}");
    assert!(text.contains("(en cola)") && text.contains("APAGADO"), "texto: {text}");
    assert_eq!(std::fs::read_dir(&findings_dir).unwrap().count(), 1);

    // Un reenvio del cliente no duplica.
    let (_, text) = call(26, "submit_findings", buena).await;
    assert!(text.contains("ya estaba"), "texto: {text}");
    assert_eq!(std::fs::read_dir(&findings_dir).unwrap().count(), 1);

    let (is_error, text) = call(27, "finding_status", json!({"project":"ia"})).await;
    assert!(!is_error && text.contains("en cola"), "texto: {text}");

    let mut otra = hallazgo(json!([{"label":"S","text":"x"}]));
    otra["project"] = json!("mapas");
    let (is_error, text) = call(28, "submit_findings", otra).await;
    assert!(is_error && text.contains("Los validos: ia"), "texto: {text}");

    // --- El asistente de notas ---------------------------------------

    let vault = docs_dir.join("boveda");
    std::fs::create_dir_all(vault.join("temas")).unwrap();
    std::fs::create_dir_all(vault.join("privado")).unwrap();
    std::fs::write(
        vault.join("temas/malla.md"),
        "# Malla\n\nLa malla 2.5D deforma las ortofotos de la tanda R.\nConexion: Password=NoSalir123;\n",
    )
    .unwrap();
    std::fs::write(vault.join("temas/nomina.md"), "---\nai: false\n---\n# Nomina\n\nmalla malla malla ortofotos\n").unwrap();
    std::fs::write(vault.join("privado/claves.md"), "# Claves\n\nmalla ortofotos\n").unwrap();

    // Una carpeta local: notas del usuario que se leen en su sitio, sin copiarse.
    let apuntes = docs_dir.join("apuntes");
    std::fs::create_dir_all(apuntes.join("clientes")).unwrap();
    std::fs::write(apuntes.join("clientes/acme.md"), "# Acme\n\nContrato renovado en agosto.\n").unwrap();

    let notes_inbox = nexodeck_docs::Inbox::open(docs_dir.join("inbox-notas")).unwrap();
    notes_inbox
        .save_config(&nexodeck_docs::InboxConfig {
            projects: vec![
                nexodeck_docs::DocProject {
                    id: "notas".into(),
                    name: "Notas".into(),
                    repo_root: vault.to_string_lossy().into_owned(),
                    kind: nexodeck_docs::ProjectKind::Vault,
                    conventions: String::new(),
                    documents: vec![],
                },
                nexodeck_docs::DocProject {
                    id: "apuntes".into(),
                    name: "Apuntes".into(),
                    repo_root: apuntes.to_string_lossy().into_owned(),
                    kind: nexodeck_docs::ProjectKind::Vault,
                    conventions: String::new(),
                    documents: vec![],
                },
            ],
            notes: Some(nexodeck_docs::NotesConfig {
                vault_project: "notas".into(),
                repos: vec![],
                digest_on_idle: false,
                groups: vec![],
                local_folders: vec!["apuntes".into()],
            }),
            ..nexodeck_docs::InboxConfig::default()
        })
        .unwrap();
    control.set_docs(Some(nexodeck_docs::DocsService::new(
        notes_inbox,
        nexodeck_docs::Backends::Fixed(vec![]),
    )));

    let (_, body) = rpc(&client, &url, Some(TOKEN), None, json!({"jsonrpc":"2.0","id":29,"method":"tools/list"})).await;
    let names: Vec<String> = body["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .filter_map(|t| t["name"].as_str().map(str::to_string))
        .collect();
    for tool in ["search_notes", "get_note", "digest_note"] {
        assert!(names.iter().any(|n| n == tool), "falta {tool}");
    }

    let (is_error, text) = call(30, "search_notes", json!({"query": "malla ortofotos"})).await;
    assert!(!is_error && text.contains("nota: temas/malla.md"), "texto: {text}");
    assert!(!text.contains("nomina") && !text.contains("privado"), "salio una nota excluida: {text}");
    assert!(!text.contains("NoSalir123"), "un secreto salio por MCP: {text}");

    let (is_error, text) = call(31, "get_note", json!({"path": "temas/malla.md"})).await;
    assert!(!is_error && text.contains("deforma las ortofotos"), "texto: {text}");
    assert!(!text.contains("NoSalir123"), "un secreto salio por MCP: {text}");

    let (is_error, text) = call(32, "get_note", json!({"path": "temas/nomina.md"})).await;
    assert!(is_error && text.contains("ai: false"), "texto: {text}");

    let (is_error, text) = call(33, "digest_note", json!({"path": "privado/claves.md"})).await;
    assert!(is_error && text.contains("privada"), "texto: {text}");

    let (is_error, text) = call(34, "digest_note", json!({"path": "temas/malla.md"})).await;
    assert!(!is_error && text.contains("en cola") && text.contains("APAGADO"), "texto: {text}");

    // --- Guardar una nota que manda la sesion ------------------------
    //
    // Es la unica herramienta que escribe en la boveda sin pasar por el buzon:
    // el usuario ya dijo "guarda esto". Lo que se comprueba aqui es que el
    // formato lo arregla NexoDeck y que nunca se pisa una nota.

    assert!(names.iter().any(|n| n == "save_note"), "falta save_note");

    let (is_error, text) = call(35, "save_note", json!({})).await;
    assert!(is_error && text.contains("Falta 'text'"), "texto: {text}");

    // Lo que manda una sesion en el peor caso realista: todo envuelto en una
    // cerca de markdown y con un frontmatter inventado.
    let (is_error, text) = call(
        36,
        "save_note",
        json!({
            "text": "```markdown\n---\nai: false\n---\n# Resumen del paso 4\n\nLa cola sale al reconectar.\n```",
            "from": "NexoDeck en feat/note-editor"
        }),
    )
    .await;
    assert!(!is_error, "texto: {text}");
    assert!(text.contains("inbox/"), "deberia caer en la bandeja: {text}");

    let creada = std::fs::read_dir(vault.join("inbox"))
        .expect("la carpeta inbox")
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .next()
        .expect("una nota creada");
    let escrito = std::fs::read_to_string(&creada).unwrap();
    assert!(escrito.contains("source: claude-code"), "{escrito}");
    assert!(escrito.contains("session: NexoDeck en feat/note-editor"), "{escrito}");
    assert!(escrito.contains("# Resumen del paso 4"), "{escrito}");
    assert!(escrito.contains("La cola sale al reconectar."), "{escrito}");
    // El frontmatter que venia en el texto NO se respeta: si no, una sesion
    // podria marcar la nota como invisible para los agentes sin pedirlo nadie.
    assert!(!escrito.contains("ai: false"), "colo su frontmatter: {escrito}");
    // Y tampoco queda la cerca con la que vino envuelto.
    assert!(!escrito.contains("```"), "no se desenvolvio: {escrito}");

    // Con ruta de una nota que ya existe se AÑADE, nunca se pisa.
    let (is_error, text) = call(
        37,
        "save_note",
        json!({"text": "Una cosa mas.", "title": "Apunte", "path": "temas/malla.md"}),
    )
    .await;
    assert!(!is_error && text.contains("no se piso"), "texto: {text}");
    let malla = std::fs::read_to_string(vault.join("temas/malla.md")).unwrap();
    assert!(malla.contains("deforma las ortofotos"), "se perdio lo que habia: {malla}");
    assert!(malla.contains("## Apunte · "), "no se añadio la seccion: {malla}");
    assert!(malla.contains("Una cosa mas."), "{malla}");

    // --- Agrupaciones de notas ---------------------------------------
    //
    // Cada agrupacion es una carpeta de la boveda. Lo que se comprueba es lo que
    // hace que eso no rompa nada: la nota nace donde debe, y moverla reescribe el
    // enlace de otra nota que la citaba por ruta.

    for tool in ["list_note_groups", "create_note_group", "move_note_to_group"] {
        assert!(names.iter().any(|n| n == tool), "falta {tool}");
    }

    let (is_error, text) = call(
        40,
        "create_note_group",
        json!({"name": "Tandas de ODM", "color": "#10b981"}),
    )
    .await;
    assert!(!is_error && text.contains("carpeta 'tandas-de-odm'"), "texto: {text}");
    assert!(vault.join("tandas-de-odm").is_dir(), "la agrupacion tiene que existir en disco");

    // Una carpeta reservada no puede ser agrupacion: le cambiaria el rol a la nota.
    let (is_error, text) = call(41, "create_note_group", json!({"name": "Diario"})).await;
    assert!(is_error && text.contains("reservada"), "texto: {text}");

    let (is_error, text) = call(
        42,
        "save_note",
        json!({"text": "# Vuelo 27\n\nReprocesado con malla 3D.", "group": "Tandas de ODM"}),
    )
    .await;
    assert!(!is_error && text.contains("tandas-de-odm/"), "texto: {text}");
    let en_grupo = std::fs::read_dir(vault.join("tandas-de-odm"))
        .unwrap()
        .filter_map(|e| e.ok())
        .count();
    assert_eq!(en_grupo, 1, "la nota tenia que nacer dentro de la agrupacion");

    let (is_error, text) = call(43, "list_note_groups", json!({})).await;
    assert!(!is_error, "texto: {text}");
    assert!(text.contains("Tandas de ODM") && text.contains("#10B981"), "texto: {text}");

    // Mover una nota que otra cita por ruta: el enlace tiene que seguirla.
    std::fs::write(vault.join("temas/indice.md"), "# Indice\n\nVer [[temas/malla]].\n").unwrap();
    let (is_error, text) = call(
        44,
        "move_note_to_group",
        json!({"path": "temas/malla.md", "group": "Tandas de ODM"}),
    )
    .await;
    assert!(!is_error, "texto: {text}");
    assert!(text.contains("tandas-de-odm/malla.md"), "texto: {text}");
    assert!(text.contains("temas/indice.md"), "tenia que decir que nota reescribio: {text}");
    assert!(vault.join("tandas-de-odm/malla.md").exists());
    assert!(!vault.join("temas/malla.md").exists());
    assert_eq!(
        std::fs::read_to_string(vault.join("temas/indice.md")).unwrap(),
        "# Indice\n\nVer [[tandas-de-odm/malla]].\n",
        "el enlace por ruta se tenia que reescribir"
    );

    let (is_error, text) = call(45, "move_note_to_group", json!({})).await;
    assert!(is_error && text.contains("Falta 'path'"), "texto: {text}");

    // --- Notas locales -------------------------------------------------
    //
    // Una carpeta del usuario que NexoDeck lee en su sitio. Sus notas se nombran
    // `@apuntes/…`, se leen por MCP como cualquier otra, y moverlas a la boveda
    // lleva el fichero de verdad de una carpeta a otra.

    let (is_error, text) = call(46, "get_note", json!({"path": "@apuntes/clientes/acme.md"})).await;
    assert!(!is_error && text.contains("Contrato renovado"), "texto: {text}");

    let (is_error, text) = call(47, "list_note_groups", json!({})).await;
    assert!(!is_error, "texto: {text}");
    assert!(text.contains("id 'apuntes'") && text.contains("notas locales"), "texto: {text}");
    assert!(text.contains("@apuntes/clientes"), "su agrupacion tiene que salir con prefijo: {text}");

    let (is_error, text) = call(
        48,
        "create_note_group",
        json!({"name": "Proveedores", "folder": "apuntes"}),
    )
    .await;
    assert!(!is_error && text.contains("@apuntes/proveedores"), "texto: {text}");
    assert!(apuntes.join("proveedores").is_dir(), "la agrupacion va dentro de la carpeta local");

    // El id tal como lo da list_note_groups vale como destino.
    let (is_error, text) = call(
        49,
        "move_note_to_group",
        json!({"path": "@apuntes/clientes/acme.md", "group": "@apuntes/proveedores"}),
    )
    .await;
    assert!(!is_error && text.contains("@apuntes/proveedores/acme.md"), "texto: {text}");
    assert!(apuntes.join("proveedores/acme.md").exists());

    // Entre carpetas: el fichero sale de la local y entra en la boveda.
    let (is_error, text) = call(
        50,
        "move_note_to_group",
        json!({"path": "@apuntes/proveedores/acme.md", "folder": "notas"}),
    )
    .await;
    assert!(!is_error, "texto: {text}");
    assert!(vault.join("proveedores/acme.md").exists(), "tenia que llegar a la boveda: {text}");
    assert!(!apuntes.join("proveedores/acme.md").exists(), "el original tenia que irse");

    control.set_docs(None);

    // Sin buzon tampoco se traga el fallo: lo dice y no escribe nada.
    let (is_error, text) = call(38, "save_note", json!({"text": "algo"})).await;
    assert!(is_error && text.contains("no esta inicializado"), "texto: {text}");

    // --- Sin canales, el aviso es un FALLO, no un silencio -----------
    //
    // Es la regla central de todo esto: un aviso que no tiene por donde salir
    // no se puede parecer a uno entregado.
    control.set_channels(Vec::new());
    let (_, body) = rpc(
        &client,
        &url,
        Some(TOKEN),
        None,
        json!({"jsonrpc":"2.0","id":6,"method":"tools/call",
               "params":{"name":"notify","arguments":{"text":"hola"}}}),
    )
    .await;
    assert_eq!(body["result"]["isError"], true);
    let text = body["result"]["content"][0]["text"].as_str().unwrap();
    assert!(text.contains("NO se mando"), "texto: {text}");

    // --- Parar de verdad cierra el puerto ----------------------------

    control.stop();
    assert!(!control.is_running());

    // La parada es elegante, asi que puede tardar un instante en soltar el
    // socket. Se reintenta un poco antes de dar por bueno el corte.
    let mut still_up = true;
    for _ in 0..20 {
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
        if client
            .post(&url)
            .header("Authorization", format!("Bearer {TOKEN}"))
            .json(&json!({"jsonrpc":"2.0","id":9,"method":"ping"}))
            .send()
            .await
            .is_err()
        {
            still_up = false;
            break;
        }
    }
    assert!(!still_up, "el puerto tenia que quedar cerrado tras stop()");

    // Parar dos veces no puede reventar.
    control.stop();
}
