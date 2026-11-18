# ADR 0004 — Índice de notas: en memoria en Rust, sobre SQLite FTS5 o Drift

## Contexto

El asistente de notas relaciona cada nota de la bóveda con otras notas, con los
hallazgos del buzón y con los commits de los repositorios. Quien busca es Rust:
el trabajador de `nexodeck-docs` prepara los candidatos y los agentes solo
razonan sobre ellos, citándolos por id (`n:<ruta>#<sección>`, `f:<hallazgo>`,
`c:<repo>@<sha>`). Por eso el índice tiene que vivir donde vive el trabajador, y
tiene que seguir funcionando con la ventana oculta (modo solo teléfono), cuando
Dart puede no estar escuchando.

La fuente de verdad son los ficheros `.md` de la bóveda, que el usuario edita
también desde Obsidian o desde cualquier editor, sin avisar a NexoDeck.

El plan inicial proponía SQLite con FTS5 (`rusqlite`).

## Decisión

**Un índice en memoria, en Rust, que se reconstruye.** Al arrancar se leen todas
las notas; después se relee solo lo que cambió de fecha o de tamaño. La búsqueda
es BM25 sobre secciones de notas, hallazgos y commits, con las palabras en
minúsculas, sin tildes y reducidas a una raíz de seis letras. Vive en
`nexodeck-docs/src/notes/`, sin crate aparte, porque su único consumidor es el
trabajador de ese crate.

## Alternativas descartadas

- **SQLite con FTS5 (`rusqlite`)**: da un buscador mejor (frases, prefijos,
  ranking afinado) y no hay que releer nada al arrancar. Pero `rusqlite` no
  estaba en el `Cargo.lock`, con `bundled` compila SQLite en C dentro de
  cargokit (el build que ya es frágil entre máquinas, ver ADR 0003), y deja una
  **segunda copia de las notas** en disco que habría que mantener sincronizada con
  ficheros que cambian por fuera. Si se desincroniza, los agentes relacionarían
  con texto que ya no existe.
- **Drift**: la base de la app es de Dart, y el trabajador está en Rust. Cada
  nota haría dos saltos por el puente, y en modo solo teléfono no hay nadie en
  Dart para contestar. Es el mismo motivo por el que el buzón guarda sus
  hallazgos en ficheros.
- **`tantivy`**: motor de búsqueda completo en Rust puro. Resuelve el ranking,
  pero es una dependencia grande para una bóveda personal, y seguiría siendo una
  segunda copia en disco.

## Consecuencias

- **No hay nada que migrar ni que se pueda corromper.** Borrar el índice es
  reiniciar la app.
- **El arranque lee la bóveda entera.** Con unos pocos miles de notas son
  milisegundos a segundos; con decenas de miles habría que persistir algo.
- **La búsqueda es por palabras, no por significado.** "Base de datos" no
  encuentra "Postgres". Los embeddings locales (`llama-server --embedding`) son
  la siguiente iteración y no cambian esta decisión: los vectores de unos miles
  de secciones también caben en memoria.
- **La raíz de seis letras es tosca.** Junta "ortofoto" con "ortofotos" y
  "deforma" con "deformada", que es lo que importa en español, pero también puede
  juntar palabras distintas con el mismo principio. Se aceptó porque un falso
  candidato lo descarta el agente; uno que no aparece no lo recupera nadie.

## Cuándo reconsiderarlo

- La bóveda pasa de unas 20.000 notas o el arranque se nota lento.
- Hace falta buscar desde Dart sin pasar por el trabajador.
- Llegan los embeddings y el coste de recalcularlos al arrancar deja de ser
  despreciable: entonces se persisten los vectores, no el texto.
