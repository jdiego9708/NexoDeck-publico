#ifndef RUNNER_SINGLE_INSTANCE_H_
#define RUNNER_SINGLE_INSTANCE_H_

#include <windows.h>

// Instancia unica de NexoDeck en escritorio.
//
// Por que hace falta: con el modo solo telefono la ventana queda oculta, asi
// que abrir el acceso directo "otra vez" lanzaria un segundo proceso que choca
// con el primero en el puerto 58643 (el host de transporte), sin que el
// usuario vea ninguno de los dos. La segunda instancia en cambio le avisa a la
// primera que se muestre, y termina.

// Mutex con nombre que marca "ya hay una instancia". `Local\` lo acota a la
// sesion del usuario. En debug lleva otro nombre para que `flutter run` no
// despierte en silencio a la app instalada que este corriendo en la bandeja:
// ahi conviene el fallo de siempre (puerto ocupado), que se ve.
#ifdef _DEBUG
inline constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\NexoDeck.Desktop.SingleInstance.Debug";
#else
inline constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\NexoDeck.Desktop.SingleInstance";
#endif

// Propiedad que se cuelga de la ventana principal para encontrarla desde otro
// proceso. No se busca por clase: TODAS las apps Flutter de Windows usan
// `FLUTTER_RUNNER_WIN32_WINDOW`, y el titulo es fragil.
inline constexpr wchar_t kInstanceWindowProp[] = L"NexoDeck.Instance";

// Mensaje registrado que la segunda instancia le manda a la primera.
inline constexpr wchar_t kActivateMessageName[] = L"NexoDeck.Desktop.Activate";

#endif  // RUNNER_SINGLE_INSTANCE_H_
