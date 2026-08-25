#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../src/pieblock_sdcc_native.h"

static char *join(const char *root, const char *suffix) {
  const size_t size = strlen(root) + strlen(suffix) + 2;
  char *value = malloc(size);
  if (value != NULL) snprintf(value, size, "%s/%s", root, suffix);
  return value;
}

static int execute(const pb_sdcc_request *request) {
  pb_sdcc_operation *operation = NULL;
  const pb_sdcc_status started = pb_sdcc_start(request, &operation);
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

int main(int argc, char **argv) {
  if (argc < 7 || (strcmp(argv[1], "compile") != 0 &&
                   strcmp(argv[1], "link") != 0)) {
    fprintf(stderr,
            "usage:\n"
            "  %s compile RESOURCE WORK SOURCE OBJECT LOG\n"
            "  %s link RESOURCE WORK HEX MAP LOG OBJECT...\n",
            argv[0], argv[0]);
    return 64;
  }
  if (pb_sdcc_api_version() != 5 || !pb_sdcc_is_available()) {
    fprintf(stderr, "native capability unavailable: %s\n",
            pb_sdcc_build_fingerprint());
    return 65;
  }

  char *include = join(argv[2], "toolchain/include");
  char *include_mcs51 = join(argv[2], "toolchain/include/mcs51");
  char *firmware_include = join(argv[2], "firmware/include");
  char *startup_include = join(argv[2], "firmware/startup");
  char *library = join(argv[2], "toolchain/lib/mcs251-large-stack-auto");
  if (include == NULL || include_mcs51 == NULL || firmware_include == NULL ||
      startup_include == NULL || library == NULL) return 66;
  char include_arg[1024], include_mcs51_arg[1024], firmware_include_arg[1024];
  char startup_include_arg[1024], library_arg[1024];
  snprintf(include_arg, sizeof(include_arg), "-I%s", include);
  snprintf(include_mcs51_arg, sizeof(include_mcs51_arg), "-I%s", include_mcs51);
  snprintf(firmware_include_arg, sizeof(firmware_include_arg), "-I%s",
           firmware_include);
  snprintf(startup_include_arg, sizeof(startup_include_arg), "-I%s",
           startup_include);
  snprintf(library_arg, sizeof(library_arg), "-L%s", library);

  const char *compile_arguments[] = {
      "-mmcs251",       "--model-large", "--stack-auto", "--opt-code-size",
      "--constseg",     "CSEG",          "-c",           include_arg,
      include_mcs51_arg, firmware_include_arg, startup_include_arg};
  const char *link_arguments[] = {
      "-mmcs251",       "--model-large", "--stack-auto", "--constseg",
      "CSEG",           "--nostdlib",    "--iram-size",  "0x1000",
      "--xram-loc",     "0x010000",      "--xram-size",  "0x2000",
      "--code-loc",     "0xff0000",      "-Wl-b GSINIT0=0xfe0000",
      library_arg,       include_arg,      include_mcs51_arg,
      firmware_include_arg, startup_include_arg, "mcs251.lib", "libsdcc.lib",
      "liblong.lib",    "libint.lib",    "libfloat.lib", "liblonglong.lib"};

  pb_sdcc_request request = {
      .working_directory = argv[3],
      .resource_directory = argv[2],
      .project_kind = "minimal",
  };
  if (strcmp(argv[1], "compile") == 0) {
    if (argc != 7) return 64;
    request.operation_kind = PB_SDCC_OPERATION_COMPILE_UNIT;
    request.source_path = argv[4];
    request.object_output_path = argv[5];
    request.arguments = (pb_sdcc_string_list){
        compile_arguments,
        sizeof(compile_arguments) / sizeof(compile_arguments[0]),
    };
    request.log_output_path = argv[6];
  } else {
    if (argc < 8) return 64;
    request.operation_kind = PB_SDCC_OPERATION_LINK;
    request.object_paths = (pb_sdcc_string_list){
        (const char *const *)&argv[7],
        (uint32_t)(argc - 7),
    };
    request.arguments = (pb_sdcc_string_list){
        link_arguments,
        sizeof(link_arguments) / sizeof(link_arguments[0]),
    };
    request.hex_output_path = argv[4];
    request.map_output_path = argv[5];
    request.log_output_path = argv[6];
  }
  const int result = execute(&request);
  free(include);
  free(include_mcs51);
  free(firmware_include);
  free(startup_include);
  free(library);
  return result;
}
