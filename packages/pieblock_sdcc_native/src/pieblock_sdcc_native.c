#include "pieblock_sdcc_native.h"

#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "pieblock_sdcc_pipeline.h"

#define PB_EVENT_CAPACITY 128
#define PB_MESSAGE_CAPACITY 1024

#ifndef PB_SDCC_ANDROID_ABI
#define PB_SDCC_ANDROID_ABI "unknown"
#endif

typedef struct pb_owned_request {
  char *working_directory;
  char *resource_directory;
  char *project_kind;
  char *main_source_path;
  char *hex_output_path;
  char *map_output_path;
} pb_owned_request;

typedef struct pb_owned_event {
  int32_t stage;
  int32_t level;
  int32_t current;
  int32_t total;
  char message[PB_MESSAGE_CAPACITY];
} pb_owned_event;

struct pb_sdcc_operation {
  pthread_t thread;
  pthread_mutex_t mutex;
  atomic_bool cancel_requested;
  int thread_started;
  int thread_joined;
  int complete;
  int32_t status;
  int32_t exit_code;
  int32_t warning_count;
  pb_owned_request request;
  pb_owned_event events[PB_EVENT_CAPACITY];
  unsigned int event_head;
  unsigned int event_count;
  char last_event_message[PB_MESSAGE_CAPACITY];
  char result_message[PB_MESSAGE_CAPACITY];
};

static pthread_mutex_t g_build_mutex = PTHREAD_MUTEX_INITIALIZER;
static int g_build_active = 0;

static char *pb_copy_string(const char *value) {
  if (value == NULL) return NULL;
  const size_t size = strlen(value) + 1;
  char *copy = malloc(size);
  if (copy != NULL) memcpy(copy, value, size);
  return copy;
}

static void pb_free_request(pb_owned_request *request) {
  free(request->working_directory);
  free(request->resource_directory);
  free(request->project_kind);
  free(request->main_source_path);
  free(request->hex_output_path);
  free(request->map_output_path);
  memset(request, 0, sizeof(*request));
}

static int pb_request_valid(const pb_sdcc_request *request) {
  return request != NULL && request->working_directory != NULL &&
         request->resource_directory != NULL && request->project_kind != NULL &&
         request->main_source_path != NULL && request->hex_output_path != NULL &&
         request->map_output_path != NULL;
}

static int pb_owned_request_valid(const pb_owned_request *request) {
  return request != NULL && request->working_directory != NULL &&
         request->resource_directory != NULL && request->project_kind != NULL &&
         request->main_source_path != NULL && request->hex_output_path != NULL &&
         request->map_output_path != NULL;
}

static void pb_emit(void *context,
                    pb_sdcc_stage stage,
                    pb_sdcc_level level,
                    int current,
                    int total,
                    const char *message) {
  pb_sdcc_operation *operation = context;
  pthread_mutex_lock(&operation->mutex);
  if (operation->event_count == PB_EVENT_CAPACITY) {
    operation->event_head = (operation->event_head + 1) % PB_EVENT_CAPACITY;
    operation->event_count--;
  }
  const unsigned int index =
      (operation->event_head + operation->event_count) % PB_EVENT_CAPACITY;
  pb_owned_event *event = &operation->events[index];
  event->stage = stage;
  event->level = level;
  event->current = current;
  event->total = total;
  snprintf(event->message,
           sizeof(event->message),
           "%s",
           message == NULL ? "" : message);
  operation->event_count++;
  pthread_mutex_unlock(&operation->mutex);
}

static void *pb_worker(void *context) {
  pb_sdcc_operation *operation = context;
  pb_sdcc_request request = {
      operation->request.working_directory,
      operation->request.resource_directory,
      operation->request.project_kind,
      operation->request.main_source_path,
      operation->request.hex_output_path,
      operation->request.map_output_path,
  };
  pb_emit(operation,
          PB_SDCC_STAGE_PREPARING,
          PB_SDCC_LEVEL_INFO,
          0,
          0,
          "Preparing in-process SDCC C251 build");

  int warnings = 0;
  char message[PB_MESSAGE_CAPACITY] = {0};
  int result = pb_sdcc_pipeline_execute(&request,
                                        &operation->cancel_requested,
                                        pb_emit,
                                        operation,
                                        &warnings,
                                        message,
                                        sizeof(message));
  if (atomic_load(&operation->cancel_requested)) {
    result = PB_SDCC_CANCELED;
    snprintf(message, sizeof(message), "%s", "Build canceled");
    unlink(operation->request.hex_output_path);
    unlink(operation->request.map_output_path);
  }

  pthread_mutex_lock(&operation->mutex);
  operation->status = result;
  operation->exit_code = result == PB_SDCC_OK ? 0 : result;
  operation->warning_count = warnings;
  operation->complete = 1;
  snprintf(operation->result_message,
           sizeof(operation->result_message),
           "%s",
           message);
  pthread_mutex_unlock(&operation->mutex);

  pthread_mutex_lock(&g_build_mutex);
  g_build_active = 0;
  pthread_mutex_unlock(&g_build_mutex);
  return NULL;
}

uint32_t pb_sdcc_api_version(void) { return PB_SDCC_API_VERSION; }

const char *pb_sdcc_build_fingerprint(void) {
  return "sdcc-c251:912a589d4080c9cd5c5c1faf871c62dd5023580d;ffi:2;android-abi:"
         PB_SDCC_ANDROID_ABI ";pipeline:unavailable";
}

int32_t pb_sdcc_is_available(void) { return 0; }

pb_sdcc_status pb_sdcc_start(const pb_sdcc_request *request,
                             pb_sdcc_operation **operation) {
  if (!pb_request_valid(request) || operation == NULL) {
    return PB_SDCC_INVALID_ARGUMENT;
  }
  pthread_mutex_lock(&g_build_mutex);
  if (g_build_active) {
    pthread_mutex_unlock(&g_build_mutex);
    return PB_SDCC_BUSY;
  }
  g_build_active = 1;
  pthread_mutex_unlock(&g_build_mutex);

  pb_sdcc_operation *created = calloc(1, sizeof(*created));
  if (created == NULL) goto allocation_failed;
  pthread_mutex_init(&created->mutex, NULL);
  atomic_init(&created->cancel_requested, 0);
  created->status = PB_SDCC_RUNNING;
  created->request.working_directory = pb_copy_string(request->working_directory);
  created->request.resource_directory = pb_copy_string(request->resource_directory);
  created->request.project_kind = pb_copy_string(request->project_kind);
  created->request.main_source_path = pb_copy_string(request->main_source_path);
  created->request.hex_output_path = pb_copy_string(request->hex_output_path);
  created->request.map_output_path = pb_copy_string(request->map_output_path);
  if (!pb_owned_request_valid(&created->request)) {
    pb_free_request(&created->request);
    pthread_mutex_destroy(&created->mutex);
    free(created);
    goto allocation_failed;
  }
  if (pthread_create(&created->thread, NULL, pb_worker, created) != 0) {
    pb_free_request(&created->request);
    pthread_mutex_destroy(&created->mutex);
    free(created);
    goto allocation_failed;
  }
  created->thread_started = 1;
  *operation = created;
  return PB_SDCC_OK;

allocation_failed:
  pthread_mutex_lock(&g_build_mutex);
  g_build_active = 0;
  pthread_mutex_unlock(&g_build_mutex);
  return PB_SDCC_IO_ERROR;
}

pb_sdcc_status pb_sdcc_poll_event(pb_sdcc_operation *operation,
                                  pb_sdcc_event *event) {
  if (operation == NULL || event == NULL) return PB_SDCC_INVALID_ARGUMENT;
  pthread_mutex_lock(&operation->mutex);
  if (operation->event_count == 0) {
    const int complete = operation->complete;
    pthread_mutex_unlock(&operation->mutex);
    return complete ? PB_SDCC_COMPLETE : PB_SDCC_RUNNING;
  }
  pb_owned_event *source = &operation->events[operation->event_head];
  operation->event_head = (operation->event_head + 1) % PB_EVENT_CAPACITY;
  operation->event_count--;
  memcpy(operation->last_event_message,
         source->message,
         sizeof(operation->last_event_message));
  event->stage = source->stage;
  event->level = source->level;
  event->current = source->current;
  event->total = source->total;
  event->message = operation->last_event_message;
  pthread_mutex_unlock(&operation->mutex);
  return PB_SDCC_EVENT_AVAILABLE;
}

pb_sdcc_status pb_sdcc_cancel(pb_sdcc_operation *operation) {
  if (operation == NULL) return PB_SDCC_INVALID_ARGUMENT;
  atomic_store(&operation->cancel_requested, 1);
  return PB_SDCC_OK;
}

pb_sdcc_status pb_sdcc_get_result(pb_sdcc_operation *operation,
                                  pb_sdcc_result *result) {
  if (operation == NULL || result == NULL) return PB_SDCC_INVALID_ARGUMENT;
  pthread_mutex_lock(&operation->mutex);
  if (!operation->complete) {
    pthread_mutex_unlock(&operation->mutex);
    return PB_SDCC_RUNNING;
  }
  result->status = operation->status;
  result->exit_code = operation->exit_code;
  result->warning_count = operation->warning_count;
  result->hex_path = operation->request.hex_output_path;
  result->map_path = operation->request.map_output_path;
  result->message = operation->result_message;
  pthread_mutex_unlock(&operation->mutex);
  return PB_SDCC_COMPLETE;
}

void pb_sdcc_destroy(pb_sdcc_operation *operation) {
  if (operation == NULL) return;
  atomic_store(&operation->cancel_requested, 1);
  if (operation->thread_started && !operation->thread_joined) {
    pthread_join(operation->thread, NULL);
    operation->thread_joined = 1;
  }
  pb_free_request(&operation->request);
  pthread_mutex_destroy(&operation->mutex);
  free(operation);
}
