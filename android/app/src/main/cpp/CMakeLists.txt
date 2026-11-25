cmake_minimum_required(VERSION 3.10)
project(fdlauncher)

add_library(fdlauncher SHARED fdlauncher.c)

# Opt-in debug-only supervisor candidate. No production packaging by default.
option(BLACKOUT_PROCESS_GUARD_EXPERIMENT "Build the experimental process supervisor" OFF)
if(BLACKOUT_PROCESS_GUARD_EXPERIMENT)
    add_executable(process_guard process_guard.c)
    set_target_properties(process_guard PROPERTIES
        OUTPUT_NAME "libprocess_guard.so"
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}"
        LINK_FLAGS "-Wl,-z,relro,-z,now,-z,noexecstack")
    target_compile_options(process_guard PRIVATE -fstack-protector-strong -Wformat -Werror=format-security)
    target_compile_definitions(process_guard PRIVATE _FORTIFY_SOURCE=2)
endif ()

# Explicit C hardening. Do not manufacture unused fortified symbol references.
target_compile_options(fdlauncher PRIVATE -fstack-protector-strong -Wformat -Werror=format-security)
target_compile_definitions(fdlauncher PRIVATE _FORTIFY_SOURCE=2)
set_target_properties(fdlauncher PROPERTIES LINK_FLAGS "-Wl,-z,relro,-z,now,-z,noexecstack")

# Android's logcat, so a failed spawn is visible with `adb logcat -s fdlauncher`.
find_library(log-lib log)
if (log-lib)
    target_link_libraries(fdlauncher ${log-lib})
endif ()
