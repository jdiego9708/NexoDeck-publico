// Construye la pagina del editor en ../assets, que es lo que Rust embebe con
// include_bytes!. El resultado se commitea: `flutter build` no necesita Node.
//
// La salida tiene que ser reproducible (mismo fuente, mismos bytes), para poder
// comprobar que el bundle commiteado corresponde al fuente.

import { build } from 'esbuild';
import { copyFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';

const outdir = fileURLToPath(new URL('../assets/', import.meta.url));
await mkdir(outdir, { recursive: true });

await build({
  entryPoints: { editor: 'src/main.ts' },
  bundle: true,
  minify: true,
  format: 'iife',
  // WebView2 es Chromium actual; no hace falta transpilar a nada viejo.
  target: ['chrome120'],
  outdir,
  legalComments: 'eof',
  charset: 'utf8',
  logLevel: 'info',
});

await copyFile('index.html', new URL('../assets/index.html', import.meta.url));
