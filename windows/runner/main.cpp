#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr wchar_t kSingleInstanceMutexName[] =
    L"Local\\motchiy_todo_single_instance";
constexpr wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";
constexpr wchar_t kWindowTitle[] = L"Motchiy ToDo";
constexpr UINT kActivateExistingInstanceMessage = WM_APP + 1;

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  HANDLE single_instance_mutex =
      ::CreateMutex(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex == nullptr) {
    return EXIT_FAILURE;
  }
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing_window = nullptr;
    for (int attempt = 0; attempt < 50 && existing_window == nullptr;
         ++attempt) {
      existing_window = ::FindWindow(kWindowClassName, kWindowTitle);
      if (existing_window == nullptr) {
        ::Sleep(100);
      }
    }
    if (existing_window != nullptr) {
      DWORD existing_process_id = 0;
      ::GetWindowThreadProcessId(existing_window, &existing_process_id);
      ::AllowSetForegroundWindow(existing_process_id);
      DWORD_PTR message_result = 0;
      ::SendMessageTimeout(existing_window, kActivateExistingInstanceMessage,
                           0, 0, SMTO_ABORTIFHUNG, 2000, &message_result);
    }
    ::CloseHandle(single_instance_mutex);
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
  if (!window.Create(L"Motchiy ToDo", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::ReleaseMutex(single_instance_mutex);
  ::CloseHandle(single_instance_mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
