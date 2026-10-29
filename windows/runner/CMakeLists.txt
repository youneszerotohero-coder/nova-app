cmake_minimum_required(VERSION 3.14)
project(runner LANGUAGES CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME} WIN32
  "capture_exclusion.cpp"
  "flutter_window.cpp"
  "json_writer.cpp"
  "main.cpp"
  "nova_platform.cpp"
  "protected_player.cpp"
  "utils.cpp"
  "win32_window.cpp"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
  "Runner.rc"
  "runner.exe.manifest"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the build version.
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION=\"${FLUTTER_VERSION}\"")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MAJOR=${FLUTTER_VERSION_MAJOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_MINOR=${FLUTTER_VERSION_MINOR}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_PATCH=${FLUTTER_VERSION_PATCH}")
target_compile_definitions(${BINARY_NAME} PRIVATE "FLUTTER_VERSION_BUILD=${FLUTTER_VERSION_BUILD}")

# Disable Windows macros that collide with C++ standard library functions.
target_compile_definitions(${BINARY_NAME} PRIVATE "NOMINMAX")

# Add dependency libraries and include directories. Add any application-specific
# dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app)
target_link_libraries(${BINARY_NAME} PRIVATE "dwmapi.lib")
target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")

# The NOVA PC player (protected_player.cpp): WebView2 SDK from NuGet, its
# headers and the static loader (no WebView2Loader.dll to ship). The Evergreen
# WebView2 Runtime itself is part of Windows 11 and of updated Windows 10; the
# installer adds it where it is missing.
set(WEBVIEW2_VERSION "1.0.4191.47")
set(WEBVIEW2_DIR "${CMAKE_BINARY_DIR}/webview2/${WEBVIEW2_VERSION}")
if(NOT EXISTS "${WEBVIEW2_DIR}/build/native/include/WebView2.h")
  set(WEBVIEW2_PACKAGE "${CMAKE_BINARY_DIR}/webview2/microsoft.web.webview2.${WEBVIEW2_VERSION}.nupkg")
  file(DOWNLOAD
    "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/${WEBVIEW2_VERSION}"
    "${WEBVIEW2_PACKAGE}"
    STATUS WEBVIEW2_DOWNLOAD TLS_VERIFY ON)
  list(GET WEBVIEW2_DOWNLOAD 0 WEBVIEW2_DOWNLOAD_CODE)
  if(NOT WEBVIEW2_DOWNLOAD_CODE EQUAL 0)
    message(FATAL_ERROR "WebView2 SDK download failed: ${WEBVIEW2_DOWNLOAD}")
  endif()
  file(ARCHIVE_EXTRACT INPUT "${WEBVIEW2_PACKAGE}" DESTINATION "${WEBVIEW2_DIR}")
endif()
target_include_directories(${BINARY_NAME} PRIVATE "${WEBVIEW2_DIR}/build/native/include")
target_link_libraries(${BINARY_NAME} PRIVATE
  "${WEBVIEW2_DIR}/build/native/x64/WebView2LoaderStatic.lib"
  "version.lib"
  "winmm.lib")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)
