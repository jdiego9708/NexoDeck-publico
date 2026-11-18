// La pagina del editor en un solo fichero HTML, para el WebView de Android.
//
// En Android la pagina no se sirve por el protocolo propio de wry. Cargarla
// desde `file://` deja un origen opaco, y con `loadHtmlString` el documento
// queda en `about:blank`: en los dos casos la CSP de `index.html`
// (`default-src 'self'`) no se puede cumplir. Con todo incrustado no hace falta
// ningun origen, y la CSP se ajusta a que nada venga de fuera.
//
// El documento se escribe entero aqui en vez de parchear `index.html` con
// expresiones regulares: la primera version lo intento asi y, como el `<meta>`
// de la CSP y el `<link>` estan repartidos en varias lineas, no casaron. El
// resultado fue una pagina con el bundle incrustado pero sin estilos y con el
// `<link>` apuntando a un fichero que no existe, que WebView pinto como texto.
//
//   node inline.mjs   ->  ../../../../app/assets/editor/editor.html

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const assets = resolve(here, '../assets');
const out = resolve(here, '../../../../app/assets/editor/editor.html');

// Nada de red y nada que no venga incrustado. `unsafe-inline` es inevitable
// aqui: el bundle y los estilos van dentro del propio documento.
const CSP = [
  "default-src 'none'",
  "script-src 'unsafe-inline'",
  "style-src 'unsafe-inline'",
  "img-src data:",
  "connect-src 'none'",
  "frame-src 'none'",
  "object-src 'none'",
  "form-action 'none'",
  "base-uri 'none'",
].join('; ');

const [js, css] = await Promise.all([
  readFile(resolve(assets, 'editor.js'), 'utf8'),
  readFile(resolve(assets, 'editor.css'), 'utf8'),
]);

// `</script>` dentro del bundle cerraria la etiqueta antes de tiempo.
const safeJs = js.replaceAll('</script', '<\\/script');

const html = `<!doctype html>
<html lang="es">
  <head>
    <meta charset="utf-8" />
    <meta http-equiv="Content-Security-Policy" content="${CSP}" />
    <meta name="color-scheme" content="light dark" />
    <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
    <title>Notas</title>
    <style>
${css}
    </style>
  </head>
  <body>
    <div id="app"></div>
    <script>
${safeJs}
    </script>
  </body>
</html>
`;

await mkdir(dirname(out), { recursive: true });
await writeFile(out, html, 'utf8');
console.log(`${out}  ${(html.length / 1024).toFixed(1)} kb`);
