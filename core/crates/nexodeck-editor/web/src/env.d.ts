// esbuild convierte `import './styles.css'` en `editor.css`; TypeScript solo
// necesita saber que ese import existe.
declare module '*.css';
