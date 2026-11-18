---
date: 2026-09-17
source: opencode
session: NexoDeck en feat/note-editor
---
# Soporte de imágenes en el editor

Estado de lo implementado para leer imágenes dentro de las notas, y lo que queda
para el móvil. Es el prerequisito del importador de OneNote.

## Lo que ya funciona

- El editor pinta `![alt](src)` como imagen real (un widget inline de CodeMirror)
  y esconde la sintaxis al no estar editando esa línea. Si la imagen no carga, se
  esconde en vez de dejar el icono roto del navegador.
- **`data:` URIs** funcionan en PC y móvil: la CSP de los dos ya permite
  `img-src data:`.
- **Rutas relativas** (lo que extrae el importador de OneNote): en Windows el
  editor pide el adjunto por el protocolo propio
  (`nexodeck://localhost/attachment?note=..&src=..`) y Rust lo sirve. La
  resolución es segura: `src` se resuelve relativa a la nota y **nunca sale de la
  carpeta de notas** (se rechazan los `..` que escapan, las rutas absolutas y el
  `:` de una unidad).

## Cómo está montado

- `livePreview.ts`: `ImageWidget` + `attachmentUrl()`. `main.ts` fija la nota
  abierta (`setCurrentNote`) para poder resolver lo relativo.
- `nexodeck-docs`: `DocsService::read_attachment(note, src) -> (mime, bytes)`.
  Mime por extensión y, si no, por firma (PNG/JPEG/GIF).
- `nexodeck-editor`: el trait `EditorBackend` gana `read_attachment`; el
  protocolo sirve `/attachment` en `host.rs`.
- `nexodeck-ffi`: `DocsBackend::read_attachment` sobre el servicio de notas.

## Pendiente: el móvil

En Android las imágenes por ruta relativa **no se ven todavía**, por dos motivos:

1. El motor de sincronización replica notas `.md`, **no** archivos de imagen. Hay
   que sincronizarlas también.
2. La página del móvil se carga con `loadHtmlString` (origen `about:blank`) y su
   CSP solo permite `img-src data:`. Habría que resolver cada imagen a un data URI
   desde el host de Dart, o servirla de otra forma.

## Notas

- El importador de OneNote ya extrae las imágenes a `imagenes/` y las referencia
  relativas: en la PC se ven, en el móvil aún no.
- Limitaciones del conversor de OneNote (v1): bloques de código, encabezados por
  estilo y tablas sin mapear.
