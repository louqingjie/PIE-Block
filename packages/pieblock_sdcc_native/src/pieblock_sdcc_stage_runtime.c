#include "pieblock_sdcc_stage_runtime.h"

#include <errno.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#if defined(__GNUC__)
#define PB_WEAK __attribute__((weak))
#define PB_NORETURN __attribute__((noreturn))
#else
#define PB_WEAK
#define PB_NORETURN
#endif

extern int pb_cpp_main(int argc, char **argv) PB_WEAK;
extern int pb_sdcc_main(int argc, char **argv) PB_WEAK;
extern int pb_sdas251_main(int argc, char **argv) PB_WEAK;
extern int pb_sdld_main(int argc, char **argv) PB_WEAK;
extern const char *pb_sdcc_fullSrcFileName PB_WEAK;
extern char *pb_sdcc_fullDstFileName PB_WEAK;
extern char *pb_sdcc_dstFileName PB_WEAK;
extern char *pb_sdcc_moduleName PB_WEAK;
extern void *pb_sdcc_relFilesSet PB_WEAK;
extern void *pb_sdcc_libFilesSet PB_WEAK;
extern FILE *pb_sdcc_yyin PB_WEAK;
extern FILE *pb_sdcc_yyout PB_WEAK;
extern int pb_sdcc_fatalError PB_WEAK;

typedef struct pb_stage_jump_context {
  jmp_buf target;
  int status;
  struct pb_stage_jump_context *previous;
} pb_stage_jump_context;

static _Thread_local pb_stage_jump_context *g_jump_context;
static _Thread_local FILE *g_cpp_stream;
static _Thread_local int g_cpp_status;

typedef struct pb_stage_arguments {
  int argc;
  char **argv;
  char *storage;
} pb_stage_arguments;

static void pb_free_arguments(pb_stage_arguments *arguments) {
  if (arguments == NULL) return;
  free(arguments->argv);
  free(arguments->storage);
  memset(arguments, 0, sizeof(*arguments));
}

static int pb_has_shell_metacharacters(const char *command) {
  if (command == NULL || *command == '\0') return 1;
  for (const unsigned char *cursor = (const unsigned char *)command;
       *cursor != '\0'; cursor++) {
    if (*cursor < 0x20 || *cursor == ';' || *cursor == '|' ||
        *cursor == '&' || *cursor == '<' || *cursor == '>' ||
        *cursor == '`') {
      return 1;
    }
  }
  return 0;
}

static int pb_parse_arguments(const char *command,
                              pb_stage_arguments *arguments) {
  if (arguments == NULL || pb_has_shell_metacharacters(command)) return 0;
  memset(arguments, 0, sizeof(*arguments));
  const size_t length = strlen(command);
  arguments->storage = malloc(length + 1);
  arguments->argv = calloc(length / 2 + 2, sizeof(*arguments->argv));
  if (arguments->storage == NULL || arguments->argv == NULL) {
    pb_free_arguments(arguments);
    return 0;
  }

  const char *source = command;
  char *destination = arguments->storage;
  while (*source != '\0') {
    while (*source == ' ' || *source == '\t') source++;
    if (*source == '\0') break;
    arguments->argv[arguments->argc++] = destination;
    char quote = '\0';
    while (*source != '\0') {
      const char value = *source++;
      if (quote == '\0' && (value == '\'' || value == '"')) {
        quote = value;
      } else if (quote != '\0' && value == quote) {
        quote = '\0';
      } else if (value == '\\' && *source != '\0' && quote != '\'') {
        *destination++ = *source++;
      } else if (quote == '\0' && (value == ' ' || value == '\t')) {
        break;
      } else {
        *destination++ = value;
      }
    }
    if (quote != '\0') {
      pb_free_arguments(arguments);
      return 0;
    }
    *destination++ = '\0';
  }
  arguments->argv[arguments->argc] = NULL;
  return arguments->argc > 0;
}

static const char *pb_tool_name(const char *path) {
  const char *name = strrchr(path, '/');
  const char *windows_name = strrchr(path, '\\');
  if (windows_name != NULL && (name == NULL || windows_name > name)) {
    name = windows_name;
  }
  return name == NULL ? path : name + 1;
}

static int pb_tool_matches(const char *path, const char *expected) {
  const char *name = pb_tool_name(path);
  const size_t expected_length = strlen(expected);
  return strcmp(name, expected) == 0 ||
         (strncmp(name, expected, expected_length) == 0 &&
          strcmp(name + expected_length, ".exe") == 0);
}

static PB_NORETURN void pb_stage_exit(int status) {
  pb_stage_jump_context *context = g_jump_context;
  if (context == NULL) abort();
  context->status = status;
  longjmp(context->target, 1);
}

int pb_sdcc_stage_entries_available(void) {
  return pb_cpp_main != NULL && pb_sdcc_main != NULL &&
         pb_sdas251_main != NULL && pb_sdld_main != NULL;
}

int pb_sdcc_embedded_host_self_test(void) {
  if (!pb_sdcc_stage_entries_available()) return 0;
  errno = 0;
  return pb_sdcc_system("pieblock-unknown-tool") == -1 && errno == ENOSYS;
}

void pb_sdcc_reset(void) {
  /* These driver-owned values are intentionally abandoned rather than freed:
   * upstream stores a mixture of borrowed and allocated strings in them. A
   * complete build runs in a short-lived service process, so this bounded
   * reset avoids invalid frees while preventing one translation unit from
   * being interpreted as a second input to the next invocation. */
  if (&pb_sdcc_fullSrcFileName != NULL) pb_sdcc_fullSrcFileName = NULL;
  if (&pb_sdcc_fullDstFileName != NULL) pb_sdcc_fullDstFileName = NULL;
  if (&pb_sdcc_dstFileName != NULL) pb_sdcc_dstFileName = NULL;
  if (&pb_sdcc_moduleName != NULL) pb_sdcc_moduleName = NULL;
  if (&pb_sdcc_relFilesSet != NULL) pb_sdcc_relFilesSet = NULL;
  if (&pb_sdcc_libFilesSet != NULL) pb_sdcc_libFilesSet = NULL;
  if (&pb_sdcc_yyin != NULL) pb_sdcc_yyin = NULL;
  if (&pb_sdcc_yyout != NULL) pb_sdcc_yyout = NULL;
  if (&pb_sdcc_fatalError != NULL) pb_sdcc_fatalError = 0;
  if (g_cpp_stream != NULL) {
    fclose(g_cpp_stream);
    g_cpp_stream = NULL;
    g_cpp_status = 0;
  }
}

int pb_sdcc_invoke_stage(pb_sdcc_stage_entry entry, int argc, char **argv) {
  if (entry == NULL || argc <= 0 || argv == NULL) return -1;
  pb_stage_jump_context context = {
      .status = 0,
      .previous = g_jump_context,
  };
  g_jump_context = &context;
  if (setjmp(context.target) == 0) context.status = entry(argc, argv);
  g_jump_context = context.previous;
  return context.status;
}

PB_NORETURN void pb_cpp_exit(int status) { pb_stage_exit(status); }
PB_NORETURN void pb_cpp_abort(void) { pb_stage_exit(134); }
PB_NORETURN void pb_sdcc_exit(int status) { pb_stage_exit(status); }
PB_NORETURN void pb_sdcc_abort(void) { pb_stage_exit(134); }
PB_NORETURN void pb_as_exit(int status) { pb_stage_exit(status); }
PB_NORETURN void pb_as_abort(void) { pb_stage_exit(134); }
PB_NORETURN void pb_ld_exit(int status) { pb_stage_exit(status); }
PB_NORETURN void pb_ld_abort(void) { pb_stage_exit(134); }

int pb_sdcc_system(const char *command) {
  pb_stage_arguments arguments;
  if (!pb_parse_arguments(command, &arguments)) {
    errno = EINVAL;
    return -1;
  }
  pb_sdcc_stage_entry entry = NULL;
  if (pb_tool_matches(arguments.argv[0], "sdas251")) {
    entry = pb_sdas251_main;
  } else if (pb_tool_matches(arguments.argv[0], "sdld")) {
    entry = pb_sdld_main;
  }
  if (entry == NULL) {
    pb_free_arguments(&arguments);
    errno = ENOSYS;
    return -1;
  }
  const int status = pb_sdcc_invoke_stage(entry, arguments.argc, arguments.argv);
  pb_free_arguments(&arguments);
  return status;
}

FILE *pb_sdcc_popen(const char *command, const char *mode) {
  if (mode == NULL || strcmp(mode, "r") != 0) {
    errno = EINVAL;
    return NULL;
  }
  /* A failed/long-jumped driver invocation may skip sdcc_pclose. A new
   * preprocessor request is an unambiguous ownership boundary, so discard a
   * residual stream instead of poisoning the following translation unit. */
  if (g_cpp_stream != NULL) {
    fclose(g_cpp_stream);
    g_cpp_stream = NULL;
    g_cpp_status = 0;
  }
  pb_stage_arguments arguments;
  if (!pb_parse_arguments(command, &arguments)) {
    errno = EINVAL;
    return NULL;
  }
  if (!pb_tool_matches(arguments.argv[0], "sdcpp") || pb_cpp_main == NULL) {
    pb_free_arguments(&arguments);
    errno = ENOSYS;
    return NULL;
  }
  /* SDCC invokes the standalone GCC driver with -xc. The embedded entry is
   * the already-selected C frontend (cc1), where the language is implicit and
   * -xc is a driver-only option. */
  for (int index = 1; index < arguments.argc; index++) {
    if (strcmp(arguments.argv[index], "-xc") == 0) {
      for (int next = index; next < arguments.argc; next++) {
        arguments.argv[next] = arguments.argv[next + 1];
      }
      arguments.argc--;
      break;
    }
  }
  for (int index = arguments.argc + 1; index > 1; index--) {
    arguments.argv[index] = arguments.argv[index - 2];
  }
  arguments.argv[1] = "-E";
  arguments.argv[2] = "-quiet";
  arguments.argc += 2;
  arguments.argv[arguments.argc] = NULL;
  FILE *stream = tmpfile();
  if (stream == NULL) {
    pb_free_arguments(&arguments);
    return NULL;
  }
  fflush(stdout);
  clearerr(stdout);
  const int saved_stdout = dup(STDOUT_FILENO);
  if (saved_stdout < 0 || dup2(fileno(stream), STDOUT_FILENO) < 0) {
    if (saved_stdout >= 0) close(saved_stdout);
    fclose(stream);
    pb_free_arguments(&arguments);
    return NULL;
  }
  g_cpp_status =
      pb_sdcc_invoke_stage(pb_cpp_main, arguments.argc, arguments.argv);
  fflush(stdout);
  (void)dup2(saved_stdout, STDOUT_FILENO);
  clearerr(stdout);
  close(saved_stdout);
  pb_free_arguments(&arguments);
  if (fseek(stream, 0, SEEK_SET) != 0) {
    fclose(stream);
    return NULL;
  }
  g_cpp_stream = stream;
  return stream;
}

int pb_sdcc_pclose(FILE *stream) {
  if (stream == NULL || stream != g_cpp_stream) {
    errno = EINVAL;
    return -1;
  }
  const int status = g_cpp_status;
  fclose(stream);
  g_cpp_stream = NULL;
  g_cpp_status = 0;
  return status;
}
