#include "pieblock_sdcc_pipeline.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "pieblock_sdcc_stage_runtime.h"

extern int pb_sdcc_main(int argc, char **argv) __attribute__((weak));

static const char *pb_basename(const char *path) {
  const char *slash = strrchr(path, '/');
  const char *backslash = strrchr(path, '\\');
  if (backslash != NULL && (slash == NULL || backslash > slash)) slash = backslash;
  return slash == NULL ? path : slash + 1;
}

static char *pb_parent_directory(const char *path) {
  char *copy = strdup(path);
  if (copy == NULL) return NULL;
  char *slash = strrchr(copy, '/');
  char *backslash = strrchr(copy, '\\');
  if (backslash != NULL && (slash == NULL || backslash > slash)) slash = backslash;
  if (slash == NULL) strcpy(copy, ".");
  else if (slash == copy) slash[1] = '\0';
  else *slash = '\0';
  return copy;
}

static int pb_ends_with(const char *value, const char *suffix) {
  const size_t value_length = strlen(value);
  const size_t suffix_length = strlen(suffix);
  return value_length >= suffix_length &&
         strcmp(value + value_length - suffix_length, suffix) == 0;
}

static int pb_invoke_sdcc(char **arguments, int count) {
  arguments[count] = NULL;
  pb_sdcc_reset();
  return pb_sdcc_invoke_stage(pb_sdcc_main, count, arguments);
}

int pb_sdcc_compile_unit(const pb_sdcc_request *request,
                         const atomic_bool *cancel_requested,
                         pb_sdcc_pipeline_event_fn emit,
                         void *emit_context,
                         int *warning_count,
                         char *message,
                         unsigned long message_size) {
  if (request == NULL || request->source_path == NULL ||
      request->object_output_path == NULL || emit == NULL ||
      warning_count == NULL || message == NULL || message_size == 0 ||
      !pb_sdcc_stage_entries_available()) return PB_SDCC_INVALID_ARGUMENT;
  *warning_count = 0;
  unlink(request->object_output_path);
  if (atomic_load(cancel_requested)) return PB_SDCC_CANCELED;

  emit(emit_context, PB_SDCC_STAGE_COMPILING, PB_SDCC_LEVEL_INFO,
       1, 1, pb_basename(request->source_path),
       "Compiling one translation unit with embedded SDCC C251");
  const size_t capacity = 1 + request->arguments.count + 3;
  char **arguments = calloc(capacity + 1, sizeof(*arguments));
  if (arguments == NULL) return PB_SDCC_IO_ERROR;
  int count = 0;
  arguments[count++] = "sdcc";
  for (uint32_t index = 0; index < request->arguments.count; index++)
    arguments[count++] = (char *)request->arguments.items[index];
  arguments[count++] = "-o";
  arguments[count++] = (char *)request->object_output_path;
  arguments[count++] = (char *)request->source_path;
  const int status = pb_invoke_sdcc(arguments, count);
  free(arguments);

  if (atomic_load(cancel_requested)) {
    unlink(request->object_output_path);
    snprintf(message, message_size, "Compile canceled");
    return PB_SDCC_CANCELED;
  }
  if (status != 0 || access(request->object_output_path, F_OK) != 0) {
    unlink(request->object_output_path);
    snprintf(message, message_size, "Embedded SDCC failed while compiling %s",
             pb_basename(request->source_path));
    return PB_SDCC_IO_ERROR;
  }
  emit(emit_context, PB_SDCC_STAGE_DONE, PB_SDCC_LEVEL_INFO,
       1, 1, pb_basename(request->source_path), "Translation unit completed");
  snprintf(message, message_size, "Translation unit completed");
  return PB_SDCC_OK;
}

int pb_sdcc_link(const pb_sdcc_request *request,
                 const atomic_bool *cancel_requested,
                 pb_sdcc_pipeline_event_fn emit,
                 void *emit_context,
                 int *warning_count,
                 char *message,
                 unsigned long message_size) {
  if (request == NULL || request->hex_output_path == NULL ||
      request->map_output_path == NULL || emit == NULL ||
      warning_count == NULL || message == NULL || message_size == 0 ||
      !pb_sdcc_stage_entries_available()) return PB_SDCC_INVALID_ARGUMENT;
  *warning_count = 0;
  unlink(request->hex_output_path);
  unlink(request->map_output_path);
  if (atomic_load(cancel_requested)) return PB_SDCC_CANCELED;

  char previous_directory[PATH_MAX] = {0};
  char *output_directory = pb_parent_directory(request->hex_output_path);
  if (output_directory == NULL ||
      getcwd(previous_directory, sizeof(previous_directory)) == NULL ||
      chdir(output_directory) != 0) {
    free(output_directory);
    snprintf(message, message_size, "Cannot enter SDCC output directory");
    return PB_SDCC_IO_ERROR;
  }
  const size_t library_size = strlen(output_directory) + 32;
  char *library_path = malloc(library_size);
  if (library_path == NULL) {
    (void)chdir(previous_directory);
    free(output_directory);
    return PB_SDCC_IO_ERROR;
  }
  snprintf(library_path, library_size, "%s/stc32g_shared.lib", output_directory);
  unlink(library_path);

  int result = PB_SDCC_OK;
  FILE *library = fopen(library_path, "w");
  if (library == NULL) result = PB_SDCC_IO_ERROR;
  else {
    for (uint32_t index = 0; index < request->library_object_paths.count; index++) {
      const char *name = pb_basename(request->library_object_paths.items[index]);
      const char *extension = strrchr(name, '.');
      fprintf(library, "%.*s\n",
              extension == NULL ? (int)strlen(name) : (int)(extension - name),
              name);
    }
    if (fclose(library) != 0) result = PB_SDCC_IO_ERROR;
  }

  if (result == PB_SDCC_OK) {
    emit(emit_context, PB_SDCC_STAGE_LINKING, PB_SDCC_LEVEL_INFO,
         1, 1, NULL, "Linking object files with embedded SDCC C251");
    uint32_t runtime_start = request->arguments.count;
    for (uint32_t index = 0; index < request->arguments.count; index++) {
      if (pb_ends_with(request->arguments.items[index], ".lib")) {
        runtime_start = index;
        break;
      }
    }
    const size_t capacity = 1 + request->arguments.count +
                            request->object_paths.count + 5;
    char **arguments = calloc(capacity + 1, sizeof(*arguments));
    char *library_search = malloc(strlen(output_directory) + 3);
    if (arguments == NULL || library_search == NULL) result = PB_SDCC_IO_ERROR;
    else {
      int count = 0;
      arguments[count++] = "sdcc";
      for (uint32_t index = 0; index < runtime_start; index++)
        arguments[count++] = (char *)request->arguments.items[index];
      sprintf(library_search, "-L%s", output_directory);
      arguments[count++] = library_search;
      for (uint32_t index = 0; index < request->object_paths.count; index++)
        arguments[count++] = (char *)request->object_paths.items[index];
      if (request->library_object_paths.count > 0)
        arguments[count++] = (char *)pb_basename(library_path);
      for (uint32_t index = runtime_start; index < request->arguments.count; index++)
        arguments[count++] = (char *)request->arguments.items[index];
      arguments[count++] = "-o";
      arguments[count++] = (char *)request->hex_output_path;
      const int status = pb_invoke_sdcc(arguments, count);
      if (status != 0 || access(request->hex_output_path, F_OK) != 0) {
        result = PB_SDCC_IO_ERROR;
        snprintf(message, message_size, "Embedded SDCC link failed");
      }
    }
    free(library_search);
    free(arguments);
  }

  if (atomic_load(cancel_requested)) {
    result = PB_SDCC_CANCELED;
    snprintf(message, message_size, "Link canceled");
  }
  if (result == PB_SDCC_OK) {
    emit(emit_context, PB_SDCC_STAGE_DONE, PB_SDCC_LEVEL_INFO,
         1, 1, NULL, "Embedded SDCC link completed");
    snprintf(message, message_size, "Embedded SDCC link completed");
  } else {
    unlink(request->hex_output_path);
    unlink(request->map_output_path);
  }
  unlink(library_path);
  (void)chdir(previous_directory);
  free(library_path);
  free(output_directory);
  return result;
}
