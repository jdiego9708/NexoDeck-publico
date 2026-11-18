// Los colores de NexoDeck en la pagina: el `ColorScheme` de Flutter pasado a
// variables CSS. Sin tema (abierta en un navegador), mandan los valores por
// defecto de styles.css y el modo del sistema.

import type { ThemeDto } from './protocol';

const VARIABLES: Record<keyof Omit<ThemeDto, 'dark'>, string> = {
  surface: '--surface',
  surfaceContainer: '--surface-container',
  surfaceContainerHigh: '--surface-container-high',
  onSurface: '--on-surface',
  onSurfaceVariant: '--on-surface-variant',
  primary: '--primary',
  onPrimary: '--on-primary',
  primaryContainer: '--primary-container',
  outlineVariant: '--outline-variant',
  error: '--error',
  tertiary: '--tertiary',
};

const HEX = /^#[0-9a-fA-F]{6}$/;

export function applyTheme(theme: ThemeDto | null | undefined): void {
  const root = document.documentElement;
  if (!theme) {
    root.dataset.theme = window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    return;
  }
  root.dataset.theme = theme.dark ? 'dark' : 'light';
  for (const [key, variable] of Object.entries(VARIABLES) as Array<[keyof typeof VARIABLES, string]>) {
    const value = theme[key];
    // Solo colores con forma de color: nada de lo que llega se interpreta como CSS.
    if (typeof value === 'string' && HEX.test(value)) {
      root.style.setProperty(variable, value);
    }
  }
}
