#include "pieblock_sdcc_stage_runtime.h"

#include <errno.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>

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

typedef struct pb_stage_jump_context {
  jmp_buf target;
  int status;
  struct pb_stage_jump_context *previous;
} pb_stage_jump_context;

static _Thread_local pb_stage_jump_context *g_jump_context;

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
  (void)command;
  errno = ENOSYS;
  return -1;
}

FILE *pb_sdcc_popen(const char *command, const char *mode) {
  (void)command;
  (void)mode;
  errno = ENOSYS;
  return NULL;
}

int pb_sdcc_pclose(FILE *stream) {
  (void)stream;
  errno = ENOSYS;
  return -1;
}
