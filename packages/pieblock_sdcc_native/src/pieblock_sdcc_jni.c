#include <jni.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "pieblock_sdcc_native.h"

typedef struct pb_jni_strings {
  const char **values;
  jstring *java_values;
  uint32_t count;
} pb_jni_strings;

static const char *pb_get_string(JNIEnv *env, jstring value) {
  return value == NULL ? NULL : (*env)->GetStringUTFChars(env, value, NULL);
}

static void pb_release_string(JNIEnv *env, jstring value, const char *chars) {
  if (value != NULL && chars != NULL) {
    (*env)->ReleaseStringUTFChars(env, value, chars);
  }
}

static int pb_get_strings(JNIEnv *env,
                          jobjectArray source,
                          pb_jni_strings *result) {
  result->count = source == NULL ? 0 : (uint32_t)(*env)->GetArrayLength(env, source);
  if (result->count == 0) return 1;
  result->values = calloc(result->count, sizeof(*result->values));
  result->java_values = calloc(result->count, sizeof(*result->java_values));
  if (result->values == NULL || result->java_values == NULL) return 0;
  for (uint32_t index = 0; index < result->count; index++) {
    jstring value = (jstring)(*env)->GetObjectArrayElement(env, source, index);
    result->java_values[index] = value;
    result->values[index] = pb_get_string(env, value);
    if (result->values[index] == NULL) return 0;
  }
  return 1;
}

static void pb_release_strings(JNIEnv *env, pb_jni_strings *strings) {
  if (strings == NULL) return;
  for (uint32_t index = 0; index < strings->count; index++) {
    pb_release_string(env, strings->java_values[index], strings->values[index]);
    if (strings->java_values[index] != NULL) {
      (*env)->DeleteLocalRef(env, strings->java_values[index]);
    }
  }
  free(strings->values);
  free(strings->java_values);
}

static jobjectArray pb_string_array(JNIEnv *env,
                                    const char *const *values,
                                    uint32_t count) {
  jclass string_class = (*env)->FindClass(env, "java/lang/String");
  if (string_class == NULL) return NULL;
  jobjectArray result =
      (*env)->NewObjectArray(env, (jsize)count, string_class, NULL);
  for (uint32_t index = 0; result != NULL && index < count; index++) {
    jstring value = (*env)->NewStringUTF(env, values[index] == NULL ? "" : values[index]);
    (*env)->SetObjectArrayElement(env, result, (jsize)index, value);
    (*env)->DeleteLocalRef(env, value);
  }
  (*env)->DeleteLocalRef(env, string_class);
  return result;
}

JNIEXPORT jint JNICALL
Java_cn_edu_cnu_pieblock_1app_SdccNativeBridge_apiVersion(JNIEnv *env,
                                                           jobject self) {
  (void)env;
  (void)self;
  return (jint)pb_sdcc_api_version();
}

JNIEXPORT jstring JNICALL
Java_cn_edu_cnu_pieblock_1app_SdccNativeBridge_fingerprint(JNIEnv *env,
                                                            jobject self) {
  (void)self;
  return (*env)->NewStringUTF(env, pb_sdcc_build_fingerprint());
}

JNIEXPORT jboolean JNICALL
Java_cn_edu_cnu_pieblock_1app_SdccNativeBridge_isAvailable(JNIEnv *env,
                                                            jobject self) {
  (void)env;
  (void)self;
  return pb_sdcc_is_available() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL
Java_cn_edu_cnu_pieblock_1app_SdccNativeBridge_start(
    JNIEnv *env,
    jobject self,
    jstring working_directory,
    jstring resource_directory,
    jstring project_kind,
    jstring main_source_path,
    jstring interrupt_header_path,
    jobjectArray source_paths,
    jobjectArray library_source_paths,
    jobjectArray compile_arguments,
    jobjectArray link_arguments,
    jstring hex_output_path,
    jstring map_output_path,
    jstring log_output_path) {
  (void)self;
  const char *working = pb_get_string(env, working_directory);
  const char *resource = pb_get_string(env, resource_directory);
  const char *project = pb_get_string(env, project_kind);
  const char *main_source = pb_get_string(env, main_source_path);
  const char *interrupt = pb_get_string(env, interrupt_header_path);
  const char *hex = pb_get_string(env, hex_output_path);
  const char *map = pb_get_string(env, map_output_path);
  const char *log = pb_get_string(env, log_output_path);
  pb_jni_strings sources = {0};
  pb_jni_strings library_sources = {0};
  pb_jni_strings compile = {0};
  pb_jni_strings link = {0};
  pb_sdcc_operation *operation = NULL;
  pb_sdcc_status status = PB_SDCC_INVALID_ARGUMENT;
  if (working != NULL && resource != NULL && project != NULL &&
      main_source != NULL && interrupt != NULL && hex != NULL && map != NULL &&
      log != NULL && pb_get_strings(env, source_paths, &sources) &&
      pb_get_strings(env, library_source_paths, &library_sources) &&
      pb_get_strings(env, compile_arguments, &compile) &&
      pb_get_strings(env, link_arguments, &link)) {
    const pb_sdcc_request request = {
        .working_directory = working,
        .resource_directory = resource,
        .project_kind = project,
        .main_source_path = main_source,
        .interrupt_header_path = interrupt,
        .source_paths = {sources.values, sources.count},
        .library_source_paths = {library_sources.values, library_sources.count},
        .compile_arguments = {compile.values, compile.count},
        .link_arguments = {link.values, link.count},
        .hex_output_path = hex,
        .map_output_path = map,
        .log_output_path = log,
    };
    status = pb_sdcc_start(&request, &operation);
  }
  pb_release_strings(env, &sources);
  pb_release_strings(env, &library_sources);
  pb_release_strings(env, &compile);
  pb_release_strings(env, &link);
  pb_release_string(env, working_directory, working);
  pb_release_string(env, resource_directory, resource);
  pb_release_string(env, project_kind, project);
  pb_release_string(env, main_source_path, main_source);
  pb_release_string(env, interrupt_header_path, interrupt);
  pb_release_string(env, hex_output_path, hex);
  pb_release_string(env, map_output_path, map);
  pb_release_string(env, log_output_path, log);
  return status == PB_SDCC_OK ? (jlong)(intptr_t)operation
                              : -(jlong)((int)status + 1);
}

JNIEXPORT jobjectArray JNICALL
Java_cn_edu_cnu_pieblock_1app_SdccNativeBridge_poll(JNIEnv *env,
                                                     jobject self,
                                                     jlong handle) {
  (void)self;
  pb_sdcc_event event = {0};
  if (pb_sdcc_poll_event((pb_sdcc_operation *)(intptr_t)handle, &event) !=
      PB_SDCC_EVENT_AVAILABLE) {
    return NULL;
  }
  char stage[16], level[16], current[16], total[16];
  snprintf(stage, sizeof(stage), "%d", event.stage);
  snprintf(level, sizeof(level), "%d", event.level);
  snprintf(current, sizeof(current), "%d", event.current);
  snprintf(total, sizeof(total), "%d", event.total);
  const char *values[] = {stage, level, current, total, event.file_name,
                          event.message};
  return pb_string_array(env, values, 6);
}

JNIEXPORT jobjectArray JNICALL
Java_cn_edu_cnu_pieblock_1app_SdccNativeBridge_result(JNIEnv *env,
                                                       jobject self,
                                                       jlong handle) {
  (void)self;
  pb_sdcc_result result = {0};
  if (pb_sdcc_get_result((pb_sdcc_operation *)(intptr_t)handle, &result) !=
      PB_SDCC_COMPLETE) {
    return NULL;
  }
  char status[16], exit_code[16], errors[16], warnings[16];
  snprintf(status, sizeof(status), "%d", result.status);
  snprintf(exit_code, sizeof(exit_code), "%d", result.exit_code);
  snprintf(errors, sizeof(errors), "%d", result.error_count);
  snprintf(warnings, sizeof(warnings), "%d", result.warning_count);
  const char *values[] = {status,         exit_code,      errors,
                          warnings,       result.hex_path, result.map_path,
                          result.log_path, result.error_code, result.message};
  return pb_string_array(env, values, 9);
}

JNIEXPORT void JNICALL
Java_cn_edu_cnu_pieblock_1app_SdccNativeBridge_cancel(JNIEnv *env,
                                                       jobject self,
                                                       jlong handle) {
  (void)env;
  (void)self;
  (void)pb_sdcc_cancel((pb_sdcc_operation *)(intptr_t)handle);
}

JNIEXPORT void JNICALL
Java_cn_edu_cnu_pieblock_1app_SdccNativeBridge_destroy(JNIEnv *env,
                                                        jobject self,
                                                        jlong handle) {
  (void)env;
  (void)self;
  pb_sdcc_destroy((pb_sdcc_operation *)(intptr_t)handle);
}
