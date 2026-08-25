cmake_minimum_required(VERSION 3.22.1)
project(pieblock_sdcc_native VERSION 0.1.0 LANGUAGES C)

set(PB_SDCC_STAGE_ROOT "" CACHE PATH "Directory containing per-ABI SDCC stage objects")
set(PB_SDCC_STAGE_OBJECT "${PB_SDCC_STAGE_ROOT}/${ANDROID_ABI}/pieblock_sdcc_stages.o")

set(PB_SDCC_NATIVE_SOURCES
  pieblock_sdcc_native.c
  pieblock_sdcc_pipeline.c
  pieblock_sdcc_jni.c
  pieblock_sdcc_stage_runtime.c
)
if(EXISTS "${PB_SDCC_STAGE_OBJECT}")
  set_source_files_properties("${PB_SDCC_STAGE_OBJECT}" PROPERTIES
    EXTERNAL_OBJECT TRUE
    GENERATED TRUE
  )
  list(APPEND PB_SDCC_NATIVE_SOURCES "${PB_SDCC_STAGE_OBJECT}")
  set(PB_SDCC_STAGES_LINKED 1)
  file(SHA256 "${PB_SDCC_STAGE_OBJECT}" PB_SDCC_STAGE_SHA256)
else()
  set(PB_SDCC_STAGES_LINKED 0)
  set(PB_SDCC_STAGE_SHA256 "unavailable")
endif()

add_library(pieblock_sdcc_native SHARED
  ${PB_SDCC_NATIVE_SOURCES}
)

target_compile_features(pieblock_sdcc_native PRIVATE c_std_17)
target_compile_definitions(pieblock_sdcc_native PRIVATE
  DART_SHARED_LIB
  PB_SDCC_ANDROID_ABI="${ANDROID_ABI}"
  PB_SDCC_STAGES_LINKED=${PB_SDCC_STAGES_LINKED}
  PB_SDCC_STAGE_SHA256="${PB_SDCC_STAGE_SHA256}"
  $<$<CONFIG:Debug>:PB_SDCC_PIPELINE_ENABLED=1>
)
target_compile_options(pieblock_sdcc_native PRIVATE
  -Wall
  -Wextra
  -Werror=return-type
  -fvisibility=hidden
)
target_link_libraries(pieblock_sdcc_native PRIVATE log m z c++_shared)
target_link_options(pieblock_sdcc_native PRIVATE
  "-Wl,-z,max-page-size=16384"
  "-Wl,--version-script=${CMAKE_CURRENT_SOURCE_DIR}/pieblock_sdcc.exports.map"
)

set_target_properties(pieblock_sdcc_native PROPERTIES
  OUTPUT_NAME "pieblock_sdcc_native"
  PUBLIC_HEADER pieblock_sdcc_native.h
)
