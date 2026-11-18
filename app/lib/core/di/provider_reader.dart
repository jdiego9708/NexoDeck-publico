import 'package:flutter_riverpod/misc.dart';

/// Lectura de un provider, sin importar de donde venga.
///
/// Existe porque la logica de host se llama desde dos lados que no comparten
/// tipo: los widgets tienen `WidgetRef` y `HostRuntime` tiene un
/// `ProviderContainer`. Los dos exponen un `read` con esta misma firma, asi
/// que una funcion que solo lee recibe `ref.read` o `container.read` y no
/// tiene que saber cual de los dos es.
///
/// Solo sirve para leer: una funcion que necesite `watch` o `BuildContext`
/// sigue recibiendo un `WidgetRef`.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);
