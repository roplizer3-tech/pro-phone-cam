cmake_minimum_required(VERSION 3.14)
project(pro_phone_cam_windows LANGUAGES CXX)

set(BINARY_NAME "pro_phone_cam_windows")

cmake_policy(SET CMP0063 NEW)

set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Configure build options.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Configuration to build (defaults to Debug)" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Compilation-level warnings.
add_compile_options($<$<CXX_COMPILER_ID:MSVC>:/W4>)

# Application-level configurations.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")

# Flutter framework and plugin targets.
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application target.
add_subdirectory("runner")

# Generated plugin targets.
include("${FLUTTER_MANAGED_DIR}/generated_plugins.cmake")
include("${CMAKE_CURRENT_SOURCE_DIR}/../native/CMakeLists.txt")

# === Installation ===
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")

# Copy the native virtual camera driver DLL alongside the runner executable
add_custom_command(
  TARGET ${BINARY_NAME} POST_BUILD
  COMMAND ${CMAKE_COMMAND} -E copy_if_different
  "$<TARGET_FILE:prophone_cam_driver>"
  "${BUILD_BUNDLE_DIR}/prophone_cam_driver.dll"
)
