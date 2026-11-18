#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "single_instance.h"
#include "utils.h"

namespace {

BOOL CALLBACK FindInstanceWindow(HWND hwnd, LPARAM lparam) {
  if (::GetPropW(hwnd, kInstanceWindowProp) == nullptr) {
    return TRUE;
  }
  *reinterpret_cast<HWND*>(lparam) = hwnd;
  return FALSE;
}

// Le pide a la instancia que ya corre que muestre su ventana.
//
// Reintenta un par de segundos porque la primera instancia puede estar todavia
// arrancando (el mutex ya existe pero la ventana aun no tiene la propiedad).
// `EnumWindows` si ve las ventanas ocultas, que es justo el caso del modo solo
// telefono.
void ActivateRunningInstance() {
  HWND target = nullptr;
  for (int attempt = 0; attempt < 10 && target == nullptr; ++attempt) {
    ::EnumWindows(FindInstanceWindow, reinterpret_cast<LPARAM>(&target));
    if (target == nullptr) {
      ::Sleep(200);
    }
  }
  if (target == nullptr) {
    return;
  }

  // Esta instancia la acaba de lanzar el usuario, asi que tiene derecho a
  // traer una ventana al frente; la otra no. Sin cederselo, el
  // `SetForegroundWindow` de la primera falla y la ventana aparece detras.
  DWORD pid = 0;
  ::GetWindowThreadProcessId(target, &pid);
  ::AllowSetForegroundWindow(pid);
  ::PostMessageW(target, ::RegisterWindowMessageW(kActivateMessageName), 0, 0);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Instancia unica: ver `single_instance.h`. El handle no se cierra a
  // proposito; el mutex tiene que existir mientras viva este proceso.
  HANDLE instance_mutex =
      ::CreateMutexW(nullptr, FALSE, kSingleInstanceMutexName);
  if (instance_mutex != nullptr && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateRunningInstance();
    ::CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"nexodeck", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
