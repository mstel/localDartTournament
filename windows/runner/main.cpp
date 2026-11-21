#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cstdlib>
#include <string>
#include <thread>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  // Native file dialogs run a nested Win32 message loop. Keep Dart execution
  // separate from that loop while using the synchronous file_selector plugin.
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  const bool is_second_screen =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--second-screen") != command_line_arguments.end();
  const bool is_team_game_display =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--team-game-display") != command_line_arguments.end();
  const bool is_secondary_display = is_second_screen || is_team_game_display;

  constexpr wchar_t second_screen_title[] = L"Dart Tournament Second Screen";
  constexpr wchar_t team_game_display_title[] =
      L"Dart Tournament Team Game Display";
  const wchar_t* secondary_display_title =
      is_team_game_display ? team_game_display_title : second_screen_title;

  HANDLE secondary_display_mutex = nullptr;
  if (is_secondary_display) {
    const wchar_t* mutex_name =
        is_team_game_display ? L"Local\\DartTournamentTeamGameDisplay"
                             : L"Local\\DartTournamentSecondScreen";
    secondary_display_mutex = ::CreateMutexW(nullptr, FALSE, mutex_name);
    if (secondary_display_mutex == nullptr) {
      ::CoUninitialize();
      return EXIT_FAILURE;
    }
    if (::GetLastError() == ERROR_ALREADY_EXISTS) {
      HWND existing_window = nullptr;
      for (int attempt = 0; attempt < 30 && existing_window == nullptr;
           ++attempt) {
        existing_window = ::FindWindowW(nullptr, secondary_display_title);
        if (existing_window == nullptr) ::Sleep(100);
      }
      if (existing_window != nullptr) {
        ::ShowWindowAsync(existing_window, SW_RESTORE);
        const DWORD foreground_thread =
            ::GetWindowThreadProcessId(::GetForegroundWindow(), nullptr);
        const DWORD current_thread = ::GetCurrentThreadId();
        const bool attached =
            foreground_thread != 0 && foreground_thread != current_thread &&
            ::AttachThreadInput(current_thread, foreground_thread, TRUE);
        ::BringWindowToTop(existing_window);
        ::SetForegroundWindow(existing_window);
        if (attached) {
          ::AttachThreadInput(current_thread, foreground_thread, FALSE);
        }
        ::FlashWindow(existing_window, TRUE);
      }
      ::CloseHandle(secondary_display_mutex);
      ::CoUninitialize();
      return EXIT_SUCCESS;
    }
  }

  DWORD parent_pid = 0;
  constexpr char parent_pid_prefix[] = "--parent-pid=";
  for (const auto& argument : command_line_arguments) {
    if (argument.rfind(parent_pid_prefix, 0) != 0) continue;
    char* end = nullptr;
    const auto parsed = std::strtoul(
        argument.c_str() + sizeof(parent_pid_prefix) - 1, &end, 10);
    if (end != nullptr && *end == '\0' && parsed > 0 &&
        parsed <= MAXDWORD) {
      parent_pid = static_cast<DWORD>(parsed);
    }
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  const wchar_t* window_title =
      is_secondary_display ? secondary_display_title : L"dart_tournament_manager";
  if (!window.Create(window_title, origin, size)) {
    if (secondary_display_mutex != nullptr) {
      ::CloseHandle(secondary_display_mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  HANDLE parent_close_event = nullptr;
  std::thread parent_monitor;
  if (is_secondary_display && parent_pid != 0) {
    HANDLE parent_process =
        ::OpenProcess(SYNCHRONIZE, FALSE, parent_pid);
    if (parent_process != nullptr) {
      parent_close_event = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
      if (parent_close_event != nullptr) {
        const HWND display_window = window.GetHandle();
        parent_monitor = std::thread(
            [parent_process, parent_close_event, display_window]() {
              HANDLE wait_handles[] = {parent_process, parent_close_event};
              const DWORD wait_result =
                  ::WaitForMultipleObjects(2, wait_handles, FALSE, INFINITE);
              if (wait_result == WAIT_OBJECT_0) {
                DWORD window_process_id = 0;
                if (::IsWindow(display_window) &&
                    ::GetWindowThreadProcessId(display_window,
                                               &window_process_id) != 0 &&
                    window_process_id == ::GetCurrentProcessId()) {
                  ::PostMessageW(display_window, WM_CLOSE, 0, 0);
                }
              }
              ::CloseHandle(parent_process);
            });
      } else {
        ::CloseHandle(parent_process);
        ::MessageBoxW(
            window.GetHandle(),
            L"The display window could not monitor the main application. "
            L"It may remain open after the main application closes.",
            L"Secondary-display lifetime warning", MB_OK | MB_ICONWARNING);
      }
    } else {
      ::MessageBoxW(
          window.GetHandle(),
          L"The display window could not monitor the main application. "
          L"It may remain open after the main application closes.",
          L"Secondary-display lifetime warning", MB_OK | MB_ICONWARNING);
    }
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (parent_close_event != nullptr) {
    ::SetEvent(parent_close_event);
    if (parent_monitor.joinable()) parent_monitor.join();
    ::CloseHandle(parent_close_event);
  }
  if (secondary_display_mutex != nullptr) {
    ::CloseHandle(secondary_display_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
