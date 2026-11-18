/// Frecuencia actual del CPU como texto, en GHz con dos decimales ("4.35 GHz").
///
/// GHz y no MHz porque es como la muestra el Administrador de tareas, que es
/// contra lo que el usuario la compara: "4351 MHz" obliga a correr la coma de
/// cabeza para ver que es lo mismo que "4.35 GHz". Dos decimales porque el
/// turbo se mueve de a decenas de MHz; con uno, 4.20 y 4.24 se verian iguales.
///
/// El punto decimal es el mismo que usan el resto de las cifras de las
/// metricas ("2.8 GB/15.9 GB").
String formatCpuFrequency(int mhz) => '${(mhz / 1000).toStringAsFixed(2)} GHz';
