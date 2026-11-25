cmake_minimum_required(VERSION 3.10)
project(fdlauncher)

add_library(fdlauncher SHARED fdlauncher.c)

# Explicit C hardening. Do not manufacture unused fortified symbol references.
target_compile_options(fdlauncher PRIVATE -fstack-protector-strong -Wformat -Werror=format-security)
target_compile_definitions(fdlauncher PRIVATE _FORTIFY_SOURCE=2)
set_target_properties(fdlauncher PROPERTIES LINK_FLAGS "-Wl,-z,relro,-z,now,-z,noexecstack")

# Android's logcat, so a failed spawn is visible with `adb logcat -s fdlauncher`.
find_library(log-lib log)
if (log-lib)
    target_link_libraries(fdlauncher ${log-lib})
endif ()
