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
  if (backslash != NULL && (slash == NULL || backslash > slash)) {
    slash = backslash;
  }
  return slash == NULL ? path : slash + 1;
}

static int pb_is_library_source(const pb_sdcc_request *request,
                                const char *source) {
  for (uint32_t index = 0; index < request->library_source_paths.count;
       index++) {
    if (strcmp(request->library_source_paths.items[index], source) == 0) {
      return 1;
    }
  }
  return 0;
}

static int pb_ends_with(const char *value, const char *suffix) {
  const size_t value_length = strlen(value);
  const size_t suffix_length = strlen(suffix);
  return value_length >= suffix_length &&
         strcmp(value + value_length - suffix_length, suffix) == 0;
}

static char *pb_output_path(const char *directory,
                            const char *source,
                            uint32_t index) {
  const char *name = pb_basename(source);
  const char *extension = strrchr(name, '.');
  const size_t stem_length = extension == NULL ? strlen(name)
                                                : (size_t)(extension - name);
  const size_t required = strlen(directory) + stem_length + 32;
  char *path = malloc(required);
  if (path == NULL) return NULL;
  snprintf(path, required, "%s/%.*s_%u.rel", directory,
           (int)stem_length, name, index);
  return path;
}

static char *pb_parent_directory(const char *path) {
  char *copy = strdup(path);
  if (copy == NULL) return NULL;
  char *slash = strrchr(copy, '/');
  char *backslash = strrchr(copy, '\\');
  if (backslash != NULL && (slash == NULL || backslash > slash)) {
    slash = backslash;
  }
  if (slash == NULL) {
    strcpy(copy, ".");
  } else if (slash == copy) {
    slash[1] = '\0';
  } else {
    *slash = '\0';
  }
  return copy;
}

static int pb_invoke_sdcc(char **arguments, int count) {
  arguments[count] = NULL;
  pb_sdcc_reset();
  return pb_sdcc_invoke_stage(pb_sdcc_main, count, arguments);
}

static void pb_remove_outputs(const pb_sdcc_request *request,
                              const char *library_path) {
  unlink(request->hex_output_path);
  unlink(request->map_output_path);
  if (library_path != NULL) unlink(library_path);
}

int pb_sdcc_pipeline_execute(
    const pb_sdcc_request *request,
    const atomic_bool *cancel_requested,
    pb_sdcc_pipeline_event_fn emit,
    void *emit_context,
    int *warning_count,
    char *message,
    unsigned long message_size) {
  if (request == NULL || emit == NULL || warning_count == NULL ||
      message == NULL || message_size == 0 ||
      !pb_sdcc_stage_entries_available()) {
    return PB_SDCC_UNAVAILABLE;
  }
  *warning_count = 0;
  int result = PB_SDCC_OK;
  int changed_directory = 0;
  char previous_directory[PATH_MAX] = {0};
  char *output_directory = pb_parent_directory(request->hex_output_path);
  const size_t library_path_size =
      output_directory == NULL ? 0 : strlen(output_directory) + 32;
  char *library_path = library_path_size == 0 ? NULL : malloc(library_path_size);
  char **objects = calloc(request->source_paths.count, sizeof(*objects));
  unsigned char *library_objects =
      calloc(request->source_paths.count, sizeof(*library_objects));
  if (output_directory == NULL || library_path == NULL || objects == NULL ||
      library_objects == NULL) {
    result = PB_SDCC_IO_ERROR;
    goto cleanup;
  }
  snprintf(library_path, library_path_size, "%s/stc32g_shared.lib",
           output_directory);
  pb_remove_outputs(request, library_path);
  if (getcwd(previous_directory, sizeof(previous_directory)) == NULL ||
      chdir(output_directory) != 0) {
    snprintf(message, message_size, "Cannot enter SDCC output directory");
    result = PB_SDCC_IO_ERROR;
    goto cleanup;
  }
  changed_directory = 1;

  for (uint32_t index = 0; index < request->source_paths.count; index++) {
    if (atomic_load(cancel_requested)) {
      result = PB_SDCC_CANCELED;
      break;
    }
    const char *source = request->source_paths.items[index];
    objects[index] = pb_output_path(output_directory, source, index);
    if (objects[index] == NULL) {
      result = PB_SDCC_IO_ERROR;
      break;
    }
    library_objects[index] = pb_is_library_source(request, source);
    emit(emit_context, PB_SDCC_STAGE_COMPILING, PB_SDCC_LEVEL_INFO,
         (int)index + 1, (int)request->source_paths.count,
         pb_basename(source), "Compiling with embedded SDCC C251");
    const int include_main = strcmp(source, request->main_source_path) == 0;
    const int capacity = 1 + (int)request->compile_arguments.count +
                         (include_main ? 2 : 0) + 3;
    char **arguments = calloc((size_t)capacity + 1, sizeof(*arguments));
    if (arguments == NULL) {
      result = PB_SDCC_IO_ERROR;
      break;
    }
    int argument_count = 0;
    arguments[argument_count++] = "sdcc";
    for (uint32_t flag = 0; flag < request->compile_arguments.count; flag++) {
      arguments[argument_count++] =
          (char *)request->compile_arguments.items[flag];
    }
    if (include_main) {
      arguments[argument_count++] = "--include";
      arguments[argument_count++] = (char *)request->interrupt_header_path;
    }
    arguments[argument_count++] = "-o";
    arguments[argument_count++] = objects[index];
    arguments[argument_count++] = (char *)source;
    const int stage_status = pb_invoke_sdcc(arguments, argument_count);
    free(arguments);
    if (stage_status != 0 || access(objects[index], F_OK) != 0) {
      result = PB_SDCC_IO_ERROR;
      snprintf(message, message_size,
               "Embedded SDCC failed while compiling %s",
               pb_basename(source));
      break;
    }
  }

  if (result == PB_SDCC_OK) {
    FILE *library = fopen(library_path, "w");
    if (library == NULL) {
      result = PB_SDCC_IO_ERROR;
    } else {
      for (uint32_t index = 0; index < request->source_paths.count; index++) {
        if (!library_objects[index]) continue;
        const char *name = pb_basename(objects[index]);
        const char *extension = strrchr(name, '.');
        fprintf(library, "%.*s\n",
                extension == NULL ? (int)strlen(name)
                                  : (int)(extension - name), name);
      }
      if (fclose(library) != 0) result = PB_SDCC_IO_ERROR;
    }
  }

  if (result == PB_SDCC_OK && atomic_load(cancel_requested)) {
    result = PB_SDCC_CANCELED;
  }
  if (result == PB_SDCC_OK) {
    emit(emit_context, PB_SDCC_STAGE_LINKING, PB_SDCC_LEVEL_INFO,
         0, 0, NULL, "Linking with embedded SDCC C251");
    uint32_t runtime_start = request->link_arguments.count;
    for (uint32_t index = 0; index < request->link_arguments.count; index++) {
      if (pb_ends_with(request->link_arguments.items[index], ".lib")) {
        runtime_start = index;
        break;
      }
    }
    const size_t capacity = 1 + request->link_arguments.count +
                            request->source_paths.count + 4;
    char **arguments = calloc(capacity + 1, sizeof(*arguments));
    if (arguments == NULL) {
      result = PB_SDCC_IO_ERROR;
    } else {
      int argument_count = 0;
      arguments[argument_count++] = "sdcc";
      for (uint32_t index = 0; index < runtime_start; index++) {
        arguments[argument_count++] =
            (char *)request->link_arguments.items[index];
      }
      char *library_search = malloc(strlen(output_directory) + 3);
      if (library_search == NULL) {
        result = PB_SDCC_IO_ERROR;
      } else {
        sprintf(library_search, "-L%s", output_directory);
        arguments[argument_count++] = library_search;
        for (uint32_t index = 0; index < request->source_paths.count; index++) {
          if (!library_objects[index]) {
            arguments[argument_count++] = objects[index];
          }
        }
        arguments[argument_count++] = (char *)pb_basename(library_path);
        for (uint32_t index = runtime_start;
             index < request->link_arguments.count; index++) {
          arguments[argument_count++] =
              (char *)request->link_arguments.items[index];
        }
        arguments[argument_count++] = "-o";
        arguments[argument_count++] = (char *)request->hex_output_path;
        const int stage_status = pb_invoke_sdcc(arguments, argument_count);
        if (stage_status != 0 || access(request->hex_output_path, F_OK) != 0) {
          result = PB_SDCC_IO_ERROR;
          snprintf(message, message_size, "Embedded SDCC link failed");
        }
        free(library_search);
      }
      free(arguments);
    }
  }

cleanup:
  if (changed_directory) (void)chdir(previous_directory);
  if (result == PB_SDCC_OK) {
    emit(emit_context, PB_SDCC_STAGE_DONE, PB_SDCC_LEVEL_INFO,
         1, 1, NULL, "Embedded SDCC build completed");
    snprintf(message, message_size, "Embedded SDCC build completed");
  } else {
    pb_remove_outputs(request, library_path);
    if (result == PB_SDCC_CANCELED) {
      snprintf(message, message_size, "Build canceled");
    }
  }
  if (objects != NULL) {
    for (uint32_t index = 0; index < request->source_paths.count; index++) {
      if (result != PB_SDCC_OK && objects[index] != NULL) unlink(objects[index]);
      free(objects[index]);
    }
  }
  free(objects);
  free(library_objects);
  free(library_path);
  free(output_directory);
  return result;
}
