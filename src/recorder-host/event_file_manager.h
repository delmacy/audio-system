#ifndef RECORDER_EVENT_FILE_MANAGER_H
#define RECORDER_EVENT_FILE_MANAGER_H

#include <stddef.h>

#define EVENT_FILE_PATH_MAX 4096
#define EVENT_FILE_ID_MAX 128
#define EVENT_FILE_TOKEN_MAX 256

typedef struct EventFileRequest {
    const char *recording_root;
    const char *service_id;
    const char *endpoint_id;
    const char *interaction_id;
    const char *leg_id;
    const char *media_start_utc;
} EventFileRequest;

typedef struct EventFilePaths {
    char service_token[EVENT_FILE_TOKEN_MAX];
    char directory[EVENT_FILE_PATH_MAX];
    char final_path[EVENT_FILE_PATH_MAX];
    char partial_path[EVENT_FILE_PATH_MAX];
    char lock_path[EVENT_FILE_PATH_MAX];
    char file_id[EVENT_FILE_ID_MAX];
} EventFilePaths;

/*
 * Event-file storage policy:
 *   <root>\YYYY\MM\DD\HH\<service>\HH-MM-SS.mmm_<endpoint>_<leg>.mxf
 *
 * media_start_utc is authoritative. The physical file may be created later.
 */
int event_file_manager_build_paths(
    const EventFileRequest *request,
    EventFilePaths *paths,
    char *error_text,
    size_t error_text_size);

int event_file_manager_ensure_directory(
    const char *directory,
    char *error_text,
    size_t error_text_size);

#endif
