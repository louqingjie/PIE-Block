#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../src/pieblock_sdcc_native.h"

static char *join(const char *root, const char *suffix) {
  const size_t size = strlen(root) + strlen(suffix) + 2;
  char *value = malloc(size);
  snprintf(value, size, "%s/%s", root, suffix);
  return value;
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: %s RESOURCE_ROOT WORK_ROOT\n", argv[0]);
    return 64;
  }
  if (pb_sdcc_api_version() != 4 || !pb_sdcc_is_available()) {
    fprintf(stderr, "native capability unavailable: %s\n",
            pb_sdcc_build_fingerprint());
    return 65;
  }
  char *startup = join(argv[1], "firmware/startup/stc32g12k128_startup.c");
  char *main_source = join(argv[2], "main.c");
  char *interrupt = join(argv[2], "generated_interrupt_declarations.h");
  char *hex = join(argv[2], "minimal.hex");
  char *map = join(argv[2], "minimal.map");
  char *log = join(argv[2], "minimal.log");
  char *include = join(argv[1], "toolchain/include");
  char *include_mcs51 = join(argv[1], "toolchain/include/mcs51");
  char *firmware_include = join(argv[1], "firmware/include");
  char *startup_include = join(argv[1], "firmware/startup");
  char *library = join(argv[1], "toolchain/lib/mcs251-large-stack-auto");
  char include_arg[1024], include_mcs51_arg[1024], firmware_include_arg[1024];
  char startup_include_arg[1024], library_arg[1024];
  snprintf(include_arg, sizeof(include_arg), "-I%s", include);
  snprintf(include_mcs51_arg, sizeof(include_mcs51_arg), "-I%s", include_mcs51);
  snprintf(firmware_include_arg, sizeof(firmware_include_arg), "-I%s", firmware_include);
  snprintf(startup_include_arg, sizeof(startup_include_arg), "-I%s", startup_include);
  snprintf(library_arg, sizeof(library_arg), "-L%s", library);
  const char *sources[] = {startup, main_source};
  const char *compile[] = {"-mmcs251", "--model-large", "--stack-auto",
                           "--opt-code-size", "--constseg", "CSEG", "-c",
                           include_arg, include_mcs51_arg, firmware_include_arg,
                           startup_include_arg};
  const char *link[] = {
      "-mmcs251", "--model-large", "--stack-auto", "--constseg", "CSEG",
      "--nostdlib", "--iram-size", "0x1000", "--xram-loc", "0x010000",
      "--xram-size", "0x2000", "--code-loc", "0xff0000",
      "-Wl-b GSINIT0=0xfe0000", library_arg, include_arg, include_mcs51_arg,
      firmware_include_arg, startup_include_arg, "mcs251.lib", "libsdcc.lib",
      "liblong.lib", "libint.lib", "libfloat.lib", "liblonglong.lib"};
  const pb_sdcc_request request = {
      .working_directory = argv[2],
      .resource_directory = argv[1],
      .project_kind = "minimal",
      .main_source_path = main_source,
      .interrupt_header_path = interrupt,
      .source_paths = {sources, 2},
      .library_source_paths = {NULL, 0},
      .compile_arguments = {compile, sizeof(compile) / sizeof(compile[0])},
      .link_arguments = {link, sizeof(link) / sizeof(link[0])},
      .hex_output_path = hex,
      .map_output_path = map,
      .log_output_path = log,
  };
  pb_sdcc_operation *operation = NULL;
  const pb_sdcc_status started = pb_sdcc_start(&request, &operation);
  if (started != PB_SDCC_OK) return 70 + started;
  for (;;) {
    pb_sdcc_event event;
    while (pb_sdcc_poll_event(operation, &event) == PB_SDCC_EVENT_AVAILABLE) {
      fprintf(stderr, "[%d] %s %s\n", event.stage,
              event.file_name == NULL ? "" : event.file_name,
              event.message == NULL ? "" : event.message);
    }
    pb_sdcc_result result;
    if (pb_sdcc_get_result(operation, &result) == PB_SDCC_COMPLETE) {
      fprintf(stderr, "result=%d code=%d message=%s\n", result.status,
              result.exit_code, result.message);
      const int exit_code = result.status == PB_SDCC_OK ? 0 : 1;
      pb_sdcc_destroy(operation);
      return exit_code;
    }
    usleep(10000);
  }
}
