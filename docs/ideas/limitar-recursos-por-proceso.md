# Idea: limitar CPU, RAM y GPU por aplicación

**Estado: investigado, sin implementar.** Nace del panel de procesos (2026-08-26):
si el deck ya sabe *quién* consume, el paso natural es *ponerle un tope*. Se
documenta acá lo que se puede y lo que no, para no volver a investigarlo.

## Lo que SÍ se puede: CPU y RAM

**Job Objects** de Windows es la vía nativa, y encaja con lo que ya tenemos: el
panel agrupa por aplicación y ya lleva todos los pids del grupo, que es
exactamente lo que un job necesita.

- **RAM** — `JOBOBJECT_EXTENDED_LIMIT_INFORMATION`:
  `ProcessMemoryLimit` (por proceso) o `JobMemoryLimit` (el grupo entero). El
  caso "Chrome máximo 6 GB" es `JobMemoryLimit` sobre el job con sus ~34
  procesos.
- **CPU** — `JOBOBJECT_CPU_RATE_CONTROL_INFORMATION` (Windows 8+), con tres
  modos: tope duro (un 30% real), banda mín/máx, o peso relativo. Es un límite
  de verdad, no una prioridad.

Cosas que hay que tener en cuenta **antes** de prometer nada:

- **El límite de RAM es duro y no hay swap que lo amortigüe.** Al pasarse, la
  asignación *falla*. Chrome lo maneja (mata pestañas); un entrenamiento en
  Python probablemente muera con un error de allocación. No es un cgroup.
- **Los hijos heredan el job**, así que asignando el proceso raíz se atrapan
  los que arranquen después. Pero Chrome ya usa jobs para su sandbox: hay que
  anidar (Windows 8+ lo soporta) y probarlo.
- **`KILL_ON_JOB_CLOSE` hay que limpiarlo sí o sí**, o cerrar NexoDeck mataría
  todo lo que administra. Ya está documentado en `CLAUDE.md` como el motivo por
  el que la cancelación de comandos usa `taskkill /T` en vez de un job.
- Para que un límite **sobreviva a reiniciar la app** hacen falta jobs **con
  nombre**, que se puedan reabrir con `OpenJobObject`.

Alternativa suave y sin riesgo, por si el tope duro asusta: **afinidad de
núcleos** (`SetProcessAffinityMask`) y prioridad. Limitar a 4 de 16 hilos es un
tope efectivo del 25% y no rompe nada.

## Lo que NO se puede: porcentaje de GPU

**Windows no expone ninguna API pública para limitar el uso de GPU de un
proceso.** No hay equivalente al control de tasa de CPU. Lo que existe es
parcial y no aplica acá:

- **MPS de NVIDIA** (`CUDA_MPS_ACTIVE_THREAD_PERCENTAGE`) es **solo Linux**.
- **MIG** particiona la GPU de verdad, pero es A100/H100: ninguna GeForce.
- **nvidia-smi** limita potencia y relojes, pero de **toda la GPU**, no de un
  proceso.

Lo que sí funciona es la **memoria** de GPU, y solo controlando el lanzamiento:
`torch.cuda.set_per_process_memory_fraction(...)` en PyTorch, o el límite por
dispositivo lógico en TensorFlow. NexoDeck podría inyectarlo como variable de
entorno **al lanzar** el proceso, nunca imponérselo a uno ya corriendo.

Resumen: **memoria de GPU sí (al lanzar), porcentaje de GPU no.**

## Extra: ancho de banda de red por aplicación

`New-NetQosPolicy` de Windows limita ancho de banda **por ejecutable**. Es poco
conocido y encajaría bien como acción del deck.

## Por dónde entraría en la app

Menú contextual en la fila del panel de procesos ("Limitar a…"), con el límite
guardado **por nombre de aplicación** para reaplicarlo cuando esa app vuelva a
abrirse. El panel ya tiene los pids agrupados, así que la parte de datos está.
