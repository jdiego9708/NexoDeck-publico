# Cómo se construyó NexoDeck

**Resumen:** la idea, el producto y las decisiones son mías. La mayor parte del código la escribe un
agente de IA (Claude Code) trabajando bajo reglas que yo escribo, y yo lo dirijo y verifico. Este
documento explica qué parte es de quién y deja pruebas en el propio repositorio.

Lo digo sin rodeos porque en 2026 "lo hice con IA" ya no es un secreto ni un defecto: lo que
distingue un proyecto es si quien lo dirige sabe **qué construir, por qué, y cómo comprobar que
funciona**. Eso es lo que muestra este repo.

---

## Qué es mío y qué hace la IA

| Mío | De la IA, bajo mi dirección |
|---|---|
| La idea y el problema que resuelve | Escribir gran parte del código y de las pruebas |
| Qué entra y qué no (alcance) | Proponer alternativas y compararlas |
| La arquitectura y sus límites de seguridad | Investigar documentación y detectar inconsistencias |
| Las decisiones, con su razón (los ADR) | Reescribir, refactorizar y corregir cuando se lo pido |
| Las reglas de trabajo (`CLAUDE.md`, *skills*) | Dejar documentado lo que aprende, en el sitio acordado |
| Probar en hardware real y decidir si está bien | Ejecutar las comprobaciones que le encargo |

**Transparencia en el historial.** 71 de los 96 commits declaran en su mensaje la coautoría de
Claude (Opus y Sonnet). Puedes comprobarlo con:

```sh
git log --grep="Co-Authored-By" -i --oneline | wc -l
```

## Las reglas que fijo yo

Un agente rinde según las reglas que le des. Las mías están escritas y versionadas:

- [`CLAUDE.md`](../CLAUDE.md): reglas de arquitectura "no negociables", comandos canónicos y,
  sobre todo, **trampas documentadas** para no repetirlas. Es un fichero largo a propósito.
- [`.claude/skills/`](../.claude/skills): cinco procedimientos reutilizables (migración de Drift,
  mensajes de protocolo, puente Rust↔Dart, plugin de Kotlin, features de Flutter con Riverpod).
- [`docs/architecture-decision-records/`](./architecture-decision-records): cuatro decisiones
  con contexto, alternativas descartadas y consecuencias.
- [`docs/ideas/`](./ideas): diez notas donde pienso una función antes de pedir una línea de código.

## Pruebas de criterio (lo que no se puede delegar)

Estos casos están documentados en [`ESTADO-DEL-PROYECTO.md`](./ESTADO-DEL-PROYECTO.md) y son lo
que más me importa enseñar, porque son decisiones de verificación, no de escritura.

1. **Probar en un teléfono real, no solo compilar.** La ejecución de punta a punta contra un
   teléfono Android físico destapó **tres fallos reales que fallaban en silencio**: el teléfono se
   quedaba para siempre en "Reconectando…", los errores de conexión nunca llegaban a la interfaz y
   el rechazo de reconexión era invisible. Ninguno lo habría detectado una compilación en verde.
2. **Un APK "correcto" que no lo era.** Durante meses el APK se generaba con éxito **sin la
   librería nativa dentro**, porque una dependencia no tenía backend de Android y Gradle no falla
   por eso. Salió a la luz al comprobar el contenido del APK en las tres arquitecturas, y desde
   entonces esa comprobación es parte de la verificación.
3. **Decidir antes de construir.** En el transporte USB, el plan original usaba el puente de
   depuración de Android. Antes de escribir código revisé el plan, hice una prueba real contra un
   teléfono y cambié a Android Open Accessory, porque lo otro obligaba al usuario final a activar
   el Modo Desarrollador. Quedó en el [ADR 0002](./architecture-decision-records/0002-aoa-sobre-adb.md).
4. **Lo que la IA cita tiene que existir.** En el asistente de notas, que una nota citada exista y
   que lo privado no salga **se comprueba en Rust**; no confío en que el modelo obedezca.
5. **Elegir no recortar el alcance, sabiendo el coste.** El transporte WiFi se hizo completo
   (WebSocket sobre TLS, mDNS y *certificate pinning* desde el primer emparejamiento) por decisión
   explícita, y las simplificaciones que sí se aceptaron están listadas como tales, no escondidas.

## Cómo trabajo con el agente, en la práctica

1. **Pienso primero por escrito** (una nota en `docs/ideas/` o un ADR) y después pido el código.
2. **Le doy las reglas y las trampas conocidas** (`CLAUDE.md` y *skills*) para que no empiece de cero.
3. **Exijo verificación real:** pruebas, hardware y capturas, no "debería funcionar".
4. **Cada fallo se convierte en una regla escrita**, para que ni el agente ni yo lo repitamos.

## Lo que esto no es

No digo que cada línea la haya tecleado yo, y no hace falta. Digo que sé construir esto, qué
decisiones lo sostienen y cómo se comprueba que funciona. Trabajo con IA porque es la forma más
seria de construir algo de este tamaño siendo una sola persona, y porque diez años escribiendo
código a mano me permiten juzgar con criterio lo que produce.
