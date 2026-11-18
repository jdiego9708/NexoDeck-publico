import 'dart:convert';
import 'dart:developer' as developer;

import 'package:nexodeck/features/hub_subscriptions/data/hub_subscriptions_repository.dart';

import 'deck_action.dart';

/// Interpreta `outputTail` (la salida de un comando, ej. la respuesta JSON de
/// un `curl`) como JSON y saca el valor de [jsonField]. `null` si la salida
/// no es JSON valido, no es un objeto, no trae el campo, o el campo vino
/// vacio -- ninguno de esos casos es un error de LA ACCION (que ya termino
/// bien), asi que se resuelve en silencio y quien llama decide si lo loguea.
///
/// Pura y separada de [tryAutoSubscribe] justamente para poder testearla sin
/// el bridge de hub subscriptions.
String? extractAutoSubscribeArgument(String outputTail, String jsonField) {
  final Object? decoded;
  try {
    decoded = jsonDecode(outputTail.trim());
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic> || !decoded.containsKey(jsonField)) {
    return null;
  }
  final value = decoded[jsonField];
  if (value == null || value.toString().isEmpty) return null;
  return value.toString();
}

/// Arranca una suscripcion SignalR con el valor de [AutoSubscribeConfig.jsonField]
/// como unico argumento del metodo invocado. Silencioso a proposito: un JSON
/// invalido, un campo ausente o un fallo al conectar no son errores de LA
/// ACCION que disparo el comando -- solo quedan en el log, para poder
/// diagnosticarlos sin ensuciar la notificacion del comando.
///
/// Compartido entre `ActionsRepository` (boton guardado) y
/// `ai_live_runner.dart` (borrador ejecutado en vivo): la logica es la misma,
/// solo cambia de donde sale el `outputTail`.
Future<void> tryAutoSubscribe({
  required HubSubscriptionsRepository hubSubscriptions,
  required String label,
  required AutoSubscribeConfig config,
  required String outputTail,
}) async {
  final argument = extractAutoSubscribeArgument(outputTail, config.jsonField);
  if (argument == null) {
    developer.log(
      'auto-suscripcion de "$label": la salida no trae "${config.jsonField}" '
      'como JSON valido',
      name: 'auto_subscribe',
    );
    return;
  }
  try {
    await hubSubscriptions.createSignalR(
      name: '$label · $argument',
      baseUrl: config.baseUrl,
      hubPath: config.hubPath,
      invokeMethod: config.invokeMethod,
      invokeArgs: [argument],
      allowInvalidCert: config.allowInvalidCert,
    );
  } catch (e) {
    developer.log(
      'auto-suscripcion de "$label" fallo al arrancar: $e',
      name: 'auto_subscribe',
    );
  }
}
