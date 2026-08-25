cmake_minimum_required(VERSION 3.22.1)
project(pieblock_sdcc_native VERSION 0.1.0 LANGUAGES C)

add_library(pieblock_sdcc_native SHARED
  pieblock_sdcc_native.c
  pieblock_sdcc_pipeline.c
  pieblock_sdcc_stage_runtime.c
)

target_compile_features(pieblock_sdcc_native PRIVATE c_std_17)
target_compile_definitions(pieblock_sdcc_native PRIVATE
  DART_SHARED_LIB
  PB_SDCC_ANDROID_ABI="${ANDROID_ABI}"
)
target_compile_options(pieblock_sdcc_native PRIVATE
  -Wall
  -Wextra
  -Werror=return-type
  -fvisibility=hidden
)
target_link_libraries(pieblock_sdcc_native PRIVATE log)
target_link_options(pieblock_sdcc_native PRIVATE "-Wl,-z,max-page-size=16384")

set_target_properties(pieblock_sdcc_native PROPERTIES
  OUTPUT_NAME "pieblock_sdcc_native"
  PUBLIC_HEADER pieblock_sdcc_native.h
)
