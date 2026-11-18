# Idea: endurecer la seguridad cuando la sesión sale de la LAN

**Estado: anotado, sin implementar.** Preguntado por el usuario el 2026-08-28,
mientras se construía el [relay para conexión fuera de la
LAN](conexion-fuera-de-la-lan.md): *"¿para cuando esté con datos móviles será
posible implementar alguna seguridad mayor, algún cifrado de extremo a extremo
o a nivel profesional?"*. Decisión explícita de dejarlo pendiente hasta que el
túnel funcione tal como se diseñó.

## Primero, lo que ya está resuelto y no hay que rehacer

**El cifrado de extremo a extremo ya existe.** La sesión va por TLS con el
certificado del host *pinneado* desde el primer emparejamiento (`tls.rs`), y el
relay **nunca lo termina**: sólo copia bytes opacos. Ni el VPS, ni el
proveedor, ni el operador móvil pueden leer ni modificar el contenido, y TLS
1.3 aporta *forward secrecy* — capturar el tráfico hoy y robar la clave mañana
no lo descifra.

O sea que la pregunta correcta no es "cómo ciframos", sino **"cómo probamos que
quien llama es de verdad el teléfono"**.

## El agujero real: la autenticación del cliente

Hoy el teléfono se identifica con `MessageV1::Reconnect { device_id }`, un UUID.
Eso tiene dos problemas cuando la sesión deja de vivir en una LAN:

- **Un UUID no es un secreto criptográfico.** No se puede rotar sin re-emparejar,
  viaja en cada reconexión, y quien lo obtenga puede presentarse como ese
  dispositivo.
- **El TLS es unilateral**: autentica al servidor (la PC) contra el teléfono,
  pero no al revés. La única barrera que hoy separa a un tercero de la PC por
  internet es el token del relay.

En la LAN eso era proporcionado: el atacante ya tenía que estar en tu red. Por
internet, no.

## La respuesta profesional: TLS mutuo (mTLS)

Es la solución estándar y encaja con lo que ya hay, porque el pinning ya
implementa media pieza:

1. En el emparejamiento, el **teléfono genera su propio par de claves** y su
   certificado autofirmado, igual que hace hoy la PC.
2. Manda su *fingerprint* junto con el `PairHello`; la PC lo guarda en
   `devices.cert_fingerprint` (la columna ya existe, hoy guarda el del host).
3. En cada reconexión, la PC exige certificado de cliente
   (`with_client_cert_verifier`) y lo compara contra el fingerprint guardado.

Lo que se gana: el dispositivo pasa a probar su identidad con una **clave
privada que nunca sale del teléfono**, en vez de con un identificador que
cualquiera puede repetir. Revocar un dispositivo pasa a ser efectivo de verdad
—hoy `is_authorized = false` se puede revertir, pero el secreto no cambia—, y
`Reconnect { device_id }` queda como una pista de enrutado, no como credencial.

Coste estimado: medio, y contenido. Toca `tls.rs`, el pairing de las dos puntas
y una migración de Drift. No toca el protocolo de mensajes.

## Lo demás, por orden de valor

- **Aprobación explícita para sesiones que llegan por el relay.** Una conexión
  desde internet no merece la misma confianza que una de tu casa; la PC podría
  pedir confirmación la primera vez que un dispositivo entra por ese camino.
  Barato y muy visible para el usuario.
- **Límite de intentos y registro.** Hoy un tercero puede reintentar
  `Reconnect` indefinidamente sin dejar rastro. Un contador con espera
  creciente y una línea de log por rechazo convierten un ataque silencioso en
  uno ruidoso.
- **Token del relay rotable y por dispositivo.** Hoy sería uno solo y fijo.
  Poder rotarlo sin re-emparejar, y tener uno por teléfono, permite cortarle el
  acceso a un dispositivo perdido sin afectar a los demás.
- **Rotación del certificado del host.** El par de claves de la PC se persiste y
  vive para siempre. Si esa clave privada se filtra, el pinning deja de
  proteger y no hay forma de rotarla sin re-emparejar todo.
- **Lo que NO hace falta:** cambiar TLS por Noise o por un handshake tipo
  WireGuard. Se propone seguido en foros, pero acá no compra nada que TLS 1.3
  con pinning no dé ya, y sí agrega criptografía propia que auditar. La regla
  de siempre: no escribir protocolos criptográficos nuevos si uno estándar
  alcanza.

## Cuándo retomarlo

Después de que el túnel funcione de punta a punta con datos móviles. Antes no:
mTLS sobre un camino que todavía no se probó mezcla dos fuentes de fallo, y
depurar "no conecta" con las dos cambiando a la vez es exactamente el tipo de
sesión que se va en horas.
