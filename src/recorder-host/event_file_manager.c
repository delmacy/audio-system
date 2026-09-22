#define _CRT_SECURE_NO_WARNINGS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "event_file_manager.h"

static void set_error(char *dst, size_t size, const char *message) {
    if (!dst || size == 0) return;
    snprintf(dst, size, "%s", message ? message : "");
}

static void sanitize_token(const char *src, char *dst, size_t size, const char *fallback) {
    size_t w = 0;
    if (!dst || size == 0) return;
    if (!src || !*src) src = fallback ? fallback : "unknown";
    while (*src && w + 1 < size) {
        unsigned char c = (unsigned char)*src++;
        if (isalnum(c) || c == '-' || c == '_' || c == '.')
            dst[w++] = (char)c;
        else
            dst[w++] = '_';
    }
    if (w == 0 && fallback) {
        snprintf(dst, size, "%s", fallback);
        return;
    }
    dst[w] = 0;
}

static int parse_media_utc(
    const char *utc,
    int *year, int *month, int *day, int *hour,
    int *minute, int *second, int *millisecond) {

    int n;
    if (!utc || !*utc) return 0;
    *millisecond = 0;
    n = sscanf(utc, "%4d-%2d-%2dT%2d:%2d:%2d.%3d",
        year, month, day, hour, minute, second, millisecond);
    if (n < 6) {
        *millisecond = 0;
        n = sscanf(utc, "%4d-%2d-%2dT%2d:%2d:%2d",
            year, month, day, hour, minute, second);
    }
    if (n < 6) return 0;
    if (*year < 2000 || *year > 9999 ||
        *month < 1 || *month > 12 ||
        *day < 1 || *day > 31 ||
        *hour < 0 || *hour > 23 ||
        *minute < 0 || *minute > 59 ||
        *second < 0 || *second > 60 ||
        *millisecond < 0 || *millisecond > 999)
        return 0;
    return 1;
}

int event_file_manager_ensure_directory(
    const char *directory,
    char *error_text,
    size_t error_text_size) {

    char path[EVENT_FILE_PATH_MAX];
    char *p;
    DWORD err;

    if (!directory || !*directory) {
        set_error(error_text, error_text_size, "Event directory is empty");
        return 0;
    }
    if (strlen(directory) >= sizeof(path)) {
        set_error(error_text, error_text_size, "Event directory path is too long");
        return 0;
    }
    snprintf(path, sizeof(path), "%s", directory);

    for (p = path; *p; p++) {
        if (*p != '\\' && *p != '/') continue;
        if (p == path) continue;
        if (p == path + 2 && path[1] == ':') continue;
        {
            char saved = *p;
            *p = 0;
            if (!CreateDirectoryA(path, NULL)) {
                err = GetLastError();
                if (err != ERROR_ALREADY_EXISTS) {
                    snprintf(error_text, error_text_size,
                        "CreateDirectory failed path=%s error=%lu",
                        path, (unsigned long)err);
                    *p = saved;
                    return 0;
                }
            }
            *p = saved;
        }
    }

    if (!CreateDirectoryA(path, NULL)) {
        err = GetLastError();
        if (err != ERROR_ALREADY_EXISTS) {
            snprintf(error_text, error_text_size,
                "CreateDirectory failed path=%s error=%lu",
                path, (unsigned long)err);
            return 0;
        }
    }
    return 1;
}

int event_file_manager_build_paths(
    const EventFileRequest *request,
    EventFilePaths *paths,
    char *error_text,
    size_t error_text_size) {

    int year, month, day, hour, minute, second, millisecond;
    char endpoint[EVENT_FILE_TOKEN_MAX];
    char interaction[EVENT_FILE_TOKEN_MAX];
    char leg[EVENT_FILE_TOKEN_MAX];
    int n;

    if (!request || !paths) {
        set_error(error_text, error_text_size, "Event file request/paths is null");
        return 0;
    }
    memset(paths, 0, sizeof(*paths));
    if (!request->recording_root || !*request->recording_root) {
        set_error(error_text, error_text_size, "recording_root is required");
        return 0;
    }
    if (!parse_media_utc(request->media_start_utc,
            &year, &month, &day, &hour, &minute, &second, &millisecond)) {
        set_error(error_text, error_text_size, "media_start_utc is invalid");
        return 0;
    }

    sanitize_token(request->service_id, paths->service_token,
        sizeof(paths->service_token), "service");
    sanitize_token(request->endpoint_id, endpoint, sizeof(endpoint), "endpoint");
    sanitize_token(request->interaction_id, interaction, sizeof(interaction), "interaction");
    sanitize_token(request->leg_id, leg, sizeof(leg), "leg");

    n = snprintf(paths->directory, sizeof(paths->directory),
        "%s\\%04d\\%02d\\%02d\\%02d\\%s",
        request->recording_root, year, month, day, hour, paths->service_token);
    if (n <= 0 || n >= (int)sizeof(paths->directory)) {
        set_error(error_text, error_text_size, "Event directory path overflow");
        return 0;
    }

    if (!event_file_manager_ensure_directory(
            paths->directory, error_text, error_text_size))
        return 0;

    n = snprintf(paths->final_path, sizeof(paths->final_path),
        "%s\\%02d-%02d-%02d.%03d_%s_%s.mxf",
        paths->directory, hour, minute, second, millisecond, endpoint, leg);
    if (n <= 0 || n >= (int)sizeof(paths->final_path)) {
        set_error(error_text, error_text_size, "Event final path overflow");
        return 0;
    }
    n = snprintf(paths->partial_path, sizeof(paths->partial_path),
        "%s.partial", paths->final_path);
    if (n <= 0 || n >= (int)sizeof(paths->partial_path)) {
        set_error(error_text, error_text_size, "Event partial path overflow");
        return 0;
    }
    n = snprintf(paths->lock_path, sizeof(paths->lock_path),
        "%s.lock", paths->final_path);
    if (n <= 0 || n >= (int)sizeof(paths->lock_path)) {
        set_error(error_text, error_text_size, "Event lock path overflow");
        return 0;
    }

    n = snprintf(paths->file_id, sizeof(paths->file_id),
        "EVT-%04d%02d%02d%02d%02d%02d%03d-%.36s-%.36s",
        year, month, day, hour, minute, second, millisecond,
        interaction, leg);
    if (n <= 0 || n >= (int)sizeof(paths->file_id)) {
        set_error(error_text, error_text_size, "Event file id overflow");
        return 0;
    }
    return 1;
}
