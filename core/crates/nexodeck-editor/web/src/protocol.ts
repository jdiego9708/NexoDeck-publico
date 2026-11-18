// Los mensajes entre la pagina y Rust. Tienen que coincidir uno a uno con
// `nexodeck-editor/src/protocol.rs` (serde con `tag = "type"` y camelCase).

export interface NoteDto {
  path: string;
  title: string;
  text: string;
  /** sha256 del fichero tal como se abrio; `null` en una nota que no existe. */
  hash: string | null;
  private: boolean;
}

export interface LinkTargetDto {
  /** Lo que va dentro de `[[ ]]`: la ruta sin `.md`. */
  target: string;
  title: string;
}

/** Los colores del `ColorScheme` de Flutter, en `#RRGGBB`. */
export interface ThemeDto {
  dark: boolean;
  surface: string;
  surfaceContainer: string;
  surfaceContainerHigh: string;
  onSurface: string;
  onSurfaceVariant: string;
  primary: string;
  onPrimary: string;
  primaryContainer: string;
  outlineVariant: string;
  error: string;
  tertiary: string;
}

export interface NoteSummaryDto {
  /** Virtual: `@<carpeta>/<ruta>` si es de una carpeta local. */
  path: string;
  /** El id de su carpeta local, o `null` si es de la bóveda principal. Puede
   * faltar si el binario es anterior. */
  folder?: string | null;
  /** El id de su agrupación (su carpeta), o `null` si está en `inbox/`. */
  group: string | null;
  title: string;
  /** `note`, `daily` o `hub`. */
  role: string;
  date: string | null;
  tags: string[];
  openTasks: number;
  aiExcluded: boolean;
  /** RFC 3339. */
  modified: string | null;
}

export interface TaskDto {
  path: string;
  /** Linea del fichero, desde 1. */
  line: number;
  text: string;
  done: boolean;
  due: string | null;
}

export interface HitDto {
  id: string;
  /** `note`, `finding` o `commit`. */
  kind: string;
  title: string;
  snippet: string;
  date: string | null;
  path: string | null;
}

export interface AgentStepDto {
  agent: string;
  ok: boolean;
  millis: number;
  output: string | null;
  detail: string | null;
}

export interface CandidateDto {
  id: string;
  kind: string;
  title: string;
  snippet: string;
  date: string | null;
}

export interface DigestDto {
  id: string;
  note: string;
  trigger: string;
  state: string;
  stateDetail: string | null;
  proposalId: string | null;
  createdAt: string;
  modelLabel: string;
  hub: string | null;
  requeried: boolean;
  discardedIds: string[];
  redactions: number;
  candidates: CandidateDto[];
  steps: AgentStepDto[];
}

/** Una agrupación de notas: una carpeta de la bóveda con su nombre y color. */
export interface GroupDto {
  /** El nombre de la carpeta. Es la identidad. */
  id: string;
  name: string;
  /** `#RRGGBB`. Validarlo antes de usarlo: llega de un fichero editable. */
  colorHex: string;
  notes: number;
}

/** Una carpeta de notas: la bóveda principal o una carpeta local, que se lee en
 * su sitio sin copiarse. */
export interface FolderDto {
  /** El id de su proyecto; el prefijo `@id/` de sus notas si es local. */
  id: string;
  name: string;
  /** La ruta real en disco. */
  path: string;
  local: boolean;
  /** `false` si la carpeta no está (un disco desconectado). */
  available: boolean;
}

export interface OverviewDto {
  configured: boolean;
  root: string | null;
  /** La principal primero, después las locales. Puede faltar si el binario es
   * anterior. */
  folders?: FolderDto[];
  /** Ya ordenadas. */
  groups: GroupDto[];
  notes: NoteSummaryDto[];
  tasks: TaskDto[];
  digests: DigestDto[];
  error: string | null;
}

export interface DetailsDto {
  path: string;
  backlinks: string[];
  related: HitDto[];
  digests: DigestDto[];
}

export type HostMessage =
  | { type: 'load'; note: NoteDto; targets: LinkTargetDto[]; theme?: ThemeDto | null }
  | { type: 'saved'; path: string; hash: string }
  | { type: 'conflict'; path: string; diskText: string; diskHash: string }
  | { type: 'error'; message: string }
  | { type: 'targets'; targets: LinkTargetDto[] }
  | { type: 'theme'; theme: ThemeDto }
  | { type: 'overview'; overview: OverviewDto }
  | { type: 'searchResults'; query: string; hits: HitDto[] }
  | { type: 'details'; details: DetailsDto }
  | { type: 'notice'; message: string }
  | { type: 'requestClose' };

export type SaveReason = 'auto' | 'manual' | 'close' | 'overwrite';

export type PageMessage =
  | { type: 'ready' }
  | { type: 'save'; path: string; text: string; baseHash: string | null; reason: SaveReason }
  | { type: 'dirty'; dirty: boolean }
  | { type: 'openLink'; target: string }
  | { type: 'openExternal'; url: string }
  | { type: 'closeReady' }
  | { type: 'openNote'; path: string }
  | { type: 'createNote'; path: string; title: string }
  | { type: 'openDaily' }
  | { type: 'moveNote'; path: string; group: string | null }
  | { type: 'search'; query: string }
  | { type: 'requestDetails'; path: string }
  | { type: 'digest'; path: string }
  | { type: 'showInbox' }
  | { type: 'refresh' }
  // Las carpetas las elige el usuario en un dialogo nativo que abre Rust: la
  // pagina nunca manda una ruta.
  | { type: 'chooseVault' }
  | { type: 'importLocalFolder' }
  | { type: 'importOneNote' }
  | { type: 'removeLocalFolder'; id: string }
  | { type: 'exportVault'; fileName: string }
  // La banda de conflicto se resolvio. Solo lo usa el movil, donde el choque vive
  // en la copia local y hay que decirle cual se quedo.
  | { type: 'conflictResolved'; path: string; kept: 'mine' | 'disk' };
