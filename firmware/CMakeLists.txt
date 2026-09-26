cmake_minimum_required(VERSION 3.16)

set(MACTOUCH_VERSION "0.2.2")
# A rollback test image names itself so it cannot pass for a real release.
if(MACTOUCH_CRASH_TEST)
  string(APPEND MACTOUCH_VERSION "-crash")
endif()
set(PROJECT_VER "${MACTOUCH_VERSION}")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
if(NOT (IDF_VERSION_MAJOR EQUAL 5 AND IDF_VERSION_MINOR GREATER_EQUAL 5))
  message(FATAL_ERROR "mactouch targets ESP-IDF 5.5 or later 5.x; found ${IDF_VERSION}.")
endif()
project(mactouch)
