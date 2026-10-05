# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "pieblock_app")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "cn.edu.cnu.pieblock_app")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# PIE-Block 的 Linux USB-HID 传输层（hidraw）。协议在 Dart 侧；本库只负责
# 阻塞式 hidraw 读写与跨 isolate 的取消打断，与 windows/CMakeLists.txt 的
# pieblock_hid.dll 保持同一 C ABI（packages/pieblock_hid/src/pieblock_hid.h）。
add_library(pieblock_hid SHARED
  "${CMAKE_CURRENT_SOURCE_DIR}/../packages/pieblock_hid/src/pieblock_hid_hidraw.cpp"
)
target_compile_options(pieblock_hid PRIVATE -Wall)
target_include_directories(pieblock_hid PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../packages/pieblock_hid/src")
set_target_properties(pieblock_hid PROPERTIES CXX_STANDARD 17)


# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

# 安装到 lib/：pieblock_app 的 RUNPATH 为 $ORIGIN/lib，
# Dart 侧 DynamicLibrary.open('libpieblock_hid.so') 由此命中。
install(TARGETS pieblock_hid LIBRARY DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

# 内置编译资源：SDCC 工具链、SDCC 固件模板与 STC32G Keil 工程参考，
# 供 pieblock_toolchain 的 _locateAssets() 在 <bundle>/data/pieblock_runtime
# 下定位；与 windows/CMakeLists.txt 的 pieblock_runtime 安装保持同构。
set(PIEBLOCK_REPO_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
set(PIEBLOCK_RUNTIME_DIR "${INSTALL_BUNDLE_DATA_DIR}/pieblock_runtime")
if(EXISTS "${PIEBLOCK_REPO_ROOT}/vendor/sdcc-toolchain")
  # USE_SOURCE_PERMISSIONS 保留 prepare_sdcc_toolchain.sh 生成的可执行位
  #（bin/sdcc 等）；CMake 默认会把文件权限收敛为 644。
  install(DIRECTORY "${PIEBLOCK_REPO_ROOT}/vendor/sdcc-toolchain"
    DESTINATION "${PIEBLOCK_RUNTIME_DIR}" COMPONENT Runtime
    USE_SOURCE_PERMISSIONS)
endif()
install(DIRECTORY "${PIEBLOCK_REPO_ROOT}/stc32g_sdcc"
  DESTINATION "${PIEBLOCK_RUNTIME_DIR}" COMPONENT Runtime
  PATTERN "build" EXCLUDE)
install(DIRECTORY "${PIEBLOCK_REPO_ROOT}/stc32g/Libraries"
  DESTINATION "${PIEBLOCK_RUNTIME_DIR}/stc32g" COMPONENT Runtime)
install(DIRECTORY
  "${PIEBLOCK_REPO_ROOT}/stc32g/Projects/ROBOMASTER_INFANTRY"
  "${PIEBLOCK_REPO_ROOT}/stc32g/Projects/ROBOMASTER_ENGINEER"
  DESTINATION "${PIEBLOCK_RUNTIME_DIR}/stc32g/Projects" COMPONENT Runtime
  PATTERN "Objects" EXCLUDE PATTERN "Listings" EXCLUDE
  PATTERN "*.hex" EXCLUDE PATTERN "*.log" EXCLUDE)
