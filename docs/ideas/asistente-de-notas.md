# Asistente de notas

> Estado: **primera iteración implementada** en la rama `feat/notes-assistant`
> (15-sep-2026). Lo que está hecho y verificado, en `ESTADO-DEL-PROYECTO.md`; los
> detalles que costaron tiempo, en la sección "Asistente de notas" de `CLAUDE.md`.

## La idea

Las notas de trabajo vivían en OneNote, desconectadas del código, de los commits,
de las sesiones con Claude Code y de lo que se ejecuta desde NexoDeck. El objetivo
es que NexoDeck sea **el sitio donde se escribe y se piensa el trabajo**: cada nota
se relaciona con lo que ya se habló, con lo que quedó pendiente y con lo que se
hizo en el código, y se completa con lo aprendido.

Tres principios que guiaron el diseño:

1. **Las notas son ficheros `.md` en una carpeta.** Compatibles con Obsidian, que
   sigue sirviendo para editar y ver el grafo sin ninguna integración. NexoDeck es
   el dueño del índice y de los agentes, no del formato.
2. **La IA propone, el usuario aprueba.** Nunca se escribe una nota sin que el
   usuario vea el antes y el después. Las propuestas son las del buzón de
   documentación, con la misma validación y la misma aprobación con revisión.
3. **Lo que la IA cita tiene que existir, y lo privado no sale.** Se comprueba en
   Rust; no se confía en que el modelo obedezca.

## Por qué no usar Obsidian como motor

Se valoró incrustar Obsidian o controlarlo desde NexoDeck:

- **No se puede incrustar.** Es una aplicación Electron de código cerrado, sin
  motor embebible ni versión web. Meter su ventana dentro de la de NexoDeck por
  Win32 es frágil (foco, DPI, teclado).
- **Su CLI oficial (1.12+) y el plugin Local REST API exigen la app abierta**, y no
  aportan lo que hace falta: ni búsqueda por relaciones ni commits. Habría hecho
  falta un índice propio igualmente, y dos aplicaciones abiertas para consultarlo.

Lo que sí valía la pena copiar de Obsidian es su editor (CodeMirror 6, de código
abierto), y eso se hizo en la rama `feat/note-editor`:
- CodeMirror 6 en una ventana WebView2 propia, gestionada desde Rust con `wry`;
- la vista previa en vivo, con decoraciones propias.

**Por qué no un plugin de Flutter.** `webview_windows` y `flutter_inappwebview` están
estancados, y pintan la web como textura reenviando el teclado. Justo ahí fallan
las tildes, las teclas muertas y el corrector.

## Cómo funciona

```
nota ─► Lector ─► (Rust busca) ─┬─► Memoria ─┐
                                 └─► Código  ─┴─► Crítico ─(¿busca más? una vez)─► Redactor ─► propuesta
```

| Agente | Qué hace |
|---|---|
| Lector | Resume la nota, saca entidades, decisiones, tareas candidatas y dudas, y dice qué buscar |
| Memoria | Entre fragmentos de notas y hallazgos, decide qué tiene que ver, qué ya se habló y qué quedó pendiente |
| Código | Entre commits, decide cuáles tienen que ver y qué de la nota ya está hecho |
| Crítico | Busca preguntas que faltan, contradicciones con lo anterior y huecos; puede pedir una búsqueda más |
| Redactor | Propone operaciones sobre la nota y su nota de proyecto: resumen, relacionados, tareas, preguntas |

**Rust busca y el modelo razona.** Los agentes no tienen herramientas: Rust hace
las búsquedas y cada agente recibe candidatos con id, que es lo único que puede
citar. Es más barato, se prueba entero con un modelo de mentira y hace verificable
"lo citado existe".

**Una cadena, no un chat entre agentes.** La comunicación entre ellos es un
documento compartido, más una ronda de repregunta del crítico. Un chat libre sería
caro, difícil de reproducir e imposible de auditar. La traza de cada digest queda
guardada y la app la enseña.

## Organizar la bóveda

La bóveda es una carpeta que el usuario elige. Conviene que sea un repositorio git
con remoto privado, como copia de seguridad (NexoDeck no hace commits: los hace
el usuario).

```
Notas/
├── diario/2026-09-15.md      rol daily: lo que pasó cada día
├── proyectos/NexoDeck.md     rol hub: la nota viva de cada proyecto
├── reuniones/…               rol note
├── temas/…                   rol note
└── privado/…                 ningún agente la lee, en ningún nivel
```

- **Frontmatter**: `project: NexoDeck` hace que el digest cruce la nota con
  `proyectos/NexoDeck.md`; `ai: false` la excluye de todo; el redactor pone
  `status: procesada`.
- **Tareas** con el formato de Obsidian Tasks: `- [ ] texto 📅 2026-09-20 #tag`.
- **Enlaces** `[[ruta]]`, que Obsidian convierte en grafo.

## Migrar desde OneNote (lo hace el usuario)

Una sola vez, y después se deja de usar OneNote. Con
[`onenote-md-exporter`](https://github.com/alxnbl/onenote-md-exporter):

1. **Requisitos**: Windows con **OneNote de escritorio** 2013 o posterior (no la
   versión de la Store) y **Word** 2013 o posterior, los dos del mismo Office.
2. Desbloquear antes las secciones con contraseña: si no, no se exportan.
3. Exportar cada cuaderno en formato **Markdown**, con enlaces como wikilinks,
   frontmatter con fechas y los adjuntos en una carpeta por nota.
4. Copiar lo exportado a `Notas/onenote/<cuaderno>/` y abrir la carpeta en
   Obsidian para revisar enlaces rotos e imágenes.
5. Lo que **se pierde o sale mal**: la escritura a mano, las tablas complejas
   (salen como HTML), los dibujos (salen como imagen) y los enlaces entre
   cuadernos distintos.
6. Mover a `privado/` lo que no deba leer ningún agente antes de configurar la
   bóveda en NexoDeck.

## Próximas iteraciones

Por orden de lo que más aportaría:

1. **Probarlo de verdad**: un digest contra DeepSeek sobre notas reales, ajustar
   los prompts y el presupuesto de contexto con lo que salga.
2. **Embeddings locales** (`llama-server --embedding` con un modelo multilingüe
   como `bge-m3`) y búsqueda híbrida: hoy la búsqueda es por palabras y "base de
   datos" no encuentra "Postgres". Los vectores de unos miles de secciones caben
   en memoria, así que no cambia el ADR 0004.
3. **Revisión matutina**: tareas vencidas, temas que quedaron abiertos ayer y
   commits de ayer que no aparecen en ninguna nota, escrito en el diario y con
   aviso por WhatsApp (`nexodeck-notify`).
4. **Más editor**. Ya existe la ventana de notas: CodeMirror 6 en WebView2, con
   `[[` autocompletado, lista, tareas, búsqueda y traza del asistente en una
   ventana propia. Faltan:
   - las propuestas de la IA como diff en línea dentro del editor, en vez de en el
     buzón;
   - el grafo;
   - pegar imágenes a una carpeta de adjuntos.
5. **Captura desde el teléfono** a la nota del día, y `append_to_daily` por MCP
   para que una sesión de Claude Code deje constancia de lo que hizo.
6. **Sesiones de Claude Code como fuente**: hoy entran por los hallazgos que
   mandan; leer los `.jsonl` daría "qué se hizo cada día" sin pedirlo.
