cmake_minimum_required(VERSION 3.10)
project(fdlauncher)

add_library(fdlauncher SHARED fdlauncher.c)

# Android's logcat, so a failed spawn is visible with `adb logcat -s fdlauncher`.
find_library(log-lib log)
if (log-lib)
    target_link_libraries(fdlauncher ${log-lib})
endif ()
