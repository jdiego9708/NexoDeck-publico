# Visión y potencial de NexoDeck

> **Aviso de lectura.** Este documento es **opinión y dirección**, no una lista de lo ya
> construido. Lo construido está en el [`README`](../README.md) y en
> [`ESTADO-DEL-PROYECTO.md`](./ESTADO-DEL-PROYECTO.md). Aquí no hay cifras de mercado inventadas.

## La idea original

Un stream deck físico es una pieza de hardware dedicada, con botones fijos y sin saber nada del
equipo en el que trabaja. Mi idea fue **la versión de software**: la pantalla que ya tienes (el
móvil, una tableta o un rincón del monitor) convertida en un panel que **conoce tu equipo**, ejecuta
acciones por ti y se puede extender.

Lo que empezó como "botones en el móvil" se volvió algo más ambicioso: un **centro de control**
donde el PC se observa, se opera y, cada vez más, se delega.

## Por qué creo que tiene recorrido

Cuatro razones, todas verificables en el código:

1. **Una sola base para tres plataformas.** Un core en Rust compartido y una única interfaz en
   Flutter para Windows, Linux y Android. Lo difícil se escribe una vez.
2. **Local primero y seguro por diseño.** Emparejamiento con confirmación en ambos extremos, TLS
   con *certificate pinning*, secretos cifrados que no pasan por la interfaz y un relay que solo
   empalma bytes. No hay nube obligatoria ni cuenta que crear.
3. **Se puede operar con agentes de IA.** El servidor MCP local convierte NexoDeck en una
   superficie que otros agentes pueden usar de forma controlada, con token y comprobaciones
   contra ataques de navegador. Cuantos más agentes trabajen en un equipo, más valor tiene un punto
   único y seguro desde el que verlos y gobernarlos.
4. **La IA propone, la persona aprueba.** El asistente de notas y de acciones no escribe nada sin
   mostrar el antes y el después. Esa regla de producto, hecha cumplir en código, es lo que hace
   confiable darle más autonomía con el tiempo.

## Hacia dónde apuntan las ideas ya pensadas

Cada una tiene su nota de diseño en [`docs/ideas/`](./ideas):

| Línea | Qué busca |
|---|---|
| Conexión fuera de la red local | Que el teléfono siga conectado con datos móviles. La parte interactiva ya está implementada; faltan las notificaciones con la app cerrada |
| Centro de control | Chat al centro, con métricas y acciones acopladas alrededor (ya hecho en escritorio) |
| Notas ligadas al trabajo | Que cada nota se relacione con el código, los commits y lo ya hablado (primera iteración hecha) |
| Límites de recursos por proceso | Ponerle un tope de CPU y RAM a una aplicación, con los *Job Objects* de Windows. Investigado, sin implementar |
| Varios PC con un mismo teléfono | Emparejar varios equipos con un solo móvil, con una sesión por cada ordenador |
| Sidecar consumible desde fuera | Que otros programas de la máquina usen el motor de lenguaje local (hoy ninguno de los motores locales lo permite) |
| Varios agentes | Anotada como idea, sin diseño todavía |

## Qué haría falta para convertirlo en producto

Honestamente, estas piezas no existen todavía:

- Una **versión publicada** con instalador y actualizaciones.
- Cerrar el transporte por **USB** de punta a punta.
- Vincular el PIN de emparejamiento criptográficamente a la sesión (limitación conocida).
- Probar con **usuarios que no sean yo**, que es lo único que valida si el problema es de otros.

## Cómo medir si la idea funciona

No con una promesa, sino con señales concretas: cuánta gente lo instala sin ayuda, cuánto tarda en
emparejar un teléfono por primera vez, cuántas acciones y macros crea cada persona y si vuelve a
abrirlo a la semana. Ese es el siguiente paso real del proyecto.
