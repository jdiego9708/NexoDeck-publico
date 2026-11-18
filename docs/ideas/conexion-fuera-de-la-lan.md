# Idea: que el teléfono siga conectado fuera de la LAN (datos móviles)

**Estado: la mitad interactiva está implementada (2026-08-28); las
notificaciones con la app cerrada siguen sin empezar.** Preguntado por el
usuario el 2026-08-26: que el móvil siga recibiendo la señal y las
notificaciones del escritorio aunque pase de WiFi a datos móviles.

Lo que ya se puede hacer: emparejar y reconectar con la PC escribiendo su
dirección a mano, sin depender de mDNS. Con Tailscale instalado en las dos
puntas, eso es todo lo que el deck necesita para funcionar con datos móviles.
El detalle de cómo quedó está en `CLAUDE.md`, sección "Fuera de la LAN".

## Punto de partida: el transporte ya sirve

`TransportClient::connect_first_pairing(host, port)` acepta **cualquier** host o
IP, y el pinning de certificado (`tls.rs`) funciona igual venga de donde venga la
conexión. Lo único atado a la red local es el **descubrimiento** por mDNS
(`discovery.rs`), que no cruza redes.

O sea que lo que falta no es motor: es **UI para agregar una PC a mano**
(IP/hostname + puerto) y resolver la alcanzabilidad. Hoy `android_pairing_screen`
solo rellena el host desde lo que anunció mDNS.

## Son DOS problemas distintos

Suenan a uno solo y no lo son. Conviene no mezclarlos al planificar.

### 1. Que el deck siga funcionando (tocar un botón y que se ejecute)

Necesita conexión viva en los dos sentidos. Tres caminos, de menos a más
trabajo:

- **Tailscale / ZeroTier (VPN mesh) — la mejor relación esfuerzo/resultado.**
  Ponen PC y teléfono en una red virtual con IPs estables (`100.x.y.z`) y
  atraviesan NAT solos, incluso con el CGNAT del operador móvil. NexoDeck solo
  necesita permitir conectar a esa IP. Sin abrir puertos, sin infraestructura
  propia, sin costo. **El pinning sigue funcionando**, porque la conexión TLS
  sigue siendo directa de punta a punta.
- **Reenvío de puerto en el router + DNS dinámico. Descartado, y medido.**
  Cero infraestructura y latencia mínima, pero expone el 58643 a internet,
  obliga al usuario a tocar el router, y **no funciona si la conexión tiene
  CGNAT**. En la conexión del equipo principal **la tiene**: el salto siguiente
  al router es `192.0.2.1` —una dirección privada— mientras que internet ve
  `186.82.100.3` (AS10620, Telmex Colombia). O sea que el router no tiene la IP
  pública y reenviar el puerto expondría una WAN que nadie puede alcanzar. No
  es una limitación de permisos sobre el router: no hay nada que configurar que
  lo arregle.
- **Relay propio o Cloudflare Tunnel.** Funciona siempre: los dos extremos hacen
  conexiones **salientes** y el NAT deja de importar. El costo es operar algo (un
  VPS chico) o, con Cloudflare, aceptar que **ellos terminan el TLS** — lo que
  **rompe el pinning actual** y obliga a rediseñar la autenticación o a meter una
  segunda capa de TLS dentro del túnel.

### 2. Las notificaciones con la app cerrada

Ningún túnel resuelve esto. La vía correcta en Android es **Firebase Cloud
Messaging**: la PC manda el aviso a FCM y Google lo entrega aunque la app esté
cerrada y el teléfono en ahorro de batería. Requiere cuenta de Firebase y un
backend mínimo que reenvíe, y conviene cifrar el payload porque pasa por Google.

Es un proyecto aparte, no una variante del túnel.

## El obstáculo que nadie menciona

Aunque el túnel esté resuelto, **Android mata la conexión en segundo plano**:
con la pantalla apagada y en datos móviles, Doze corta los sockets a los pocos
minutos. Mantener el WebSocket vivo obliga a un **foreground service**, o sea una
notificación permanente en la barra y un consumo de batería que se nota. Ese es
el precio real de "que siga recibiendo la señal", y es independiente del túnel
que se elija.

## Recomendación, y qué se hizo con ella

**Tailscale**, y del lado de NexoDeck "conectar a una PC por IP o nombre". Es
poco trabajo, resuelve el caso completo sin infraestructura y sin exponer nada,
y no toca el modelo de seguridad actual.

Los tres puntos que quedaban, ya resueltos:

- **UI de pairing**: hay diálogo de host/puerto manual, y el acceso acompaña a
  la lista de descubrimiento en sus tres estados, no sólo en "no encontré
  nada" — con datos móviles mDNS no encuentra nada nunca, y esperar los 8 s
  del cartel para descubrir la opción era exactamente el camino equivocado.
- **Guardar el host**: `Devices.manualHost`/`manualPort`, en `schemaVersion 7`.
  Se guarda ya desde el pairing cuando el emparejamiento se hizo contra una
  dirección escrita a mano.
- **Orden de la reconexión**: **mDNS primero, dirección manual después**, con
  una gracia de 6 s que se saltea si no hay WiFi. Vive en
  `resolveReconnectTarget`, pura y testeada.

## Lo que sigue pendiente

- **Las notificaciones con la app cerrada** (FCM). Sin empezar.
- **El foreground service de Android**: sin él, Doze corta el WebSocket a los
  pocos minutos con la pantalla apagada. El deck anda mientras la app está
  adelante, que es el caso de uso real, pero "que siga recibiendo la señal" en
  el bolsillo todavía no.
- **Instalar y configurar Tailscale** es responsabilidad del usuario; la app no
  lo detecta ni lo guía.

Endurecer la autenticacion del telefono una vez que el tunel funcione se anoto
aparte, en [seguridad del tunel](seguridad-del-tunel.md).
