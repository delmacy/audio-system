#define _CRT_SECURE_NO_WARNINGS
#include "storage_writer.h"
#include <stdio.h>
#include <string.h>


static void json_escape(const char *src, char *dst, size_t dst_size) {
    size_t w = 0;
    if (!dst || dst_size == 0) return;
    if (!src) src = "";
    for (; *src && w + 2 < dst_size; src++) {
        unsigned char c = (unsigned char)*src;
        if (c == '\\' || c == '"') {
            if (w + 2 >= dst_size) break;
            dst[w++] = '\\';
            dst[w++] = (char)c;
        } else if (c == '\r' || c == '\n' || c == '\t') {
            if (w + 2 >= dst_size) break;
            dst[w++] = '\\';
            dst[w++] = c == '\r' ? 'r' : (c == '\n' ? 'n' : 't');
        } else if (c >= 0x20) {
            dst[w++] = (char)c;
        }
    }
    dst[w] = 0;
}

static void set_error(char *dst, size_t dst_size, const char *prefix, DWORD code) {
    char sys[512] = {0};
    if (!dst || dst_size == 0) return;
    FormatMessageA(
        FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS,
        NULL,
        code,
        MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
        sys,
        (DWORD)sizeof(sys),
        NULL);
    snprintf(dst, dst_size, "%s (win32=%lu: %s)", prefix ? prefix : "Win32 error", (unsigned long)code, sys);
}

void storage_utc_now(char *buffer, size_t size) {
    SYSTEMTIME st;
    if (!buffer || size == 0) return;
    GetSystemTime(&st);
    snprintf(buffer, size, "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond, st.wMilliseconds);
}

void storage_writer_init(StorageWriter *writer) {
    if (!writer) return;
    memset(writer, 0, sizeof(*writer));
    writer->handle = INVALID_HANDLE_VALUE;
}

int storage_writer_write_lock_state(StorageWriter *writer, const char *state, char *error_text, size_t error_text_size) {
    FILE *fp;
    char now[64];
    char temp_path[4352];
    char e_file_id[256], e_recorder_id[256], e_partial[8192], e_final[8192], e_window[128];
    if (!writer || !writer->lock_path[0]) return 1;
    storage_utc_now(now, sizeof(now));
    json_escape(writer->file_id, e_file_id, sizeof(e_file_id));
    json_escape(writer->recorder_id, e_recorder_id, sizeof(e_recorder_id));
    json_escape(writer->partial_path, e_partial, sizeof(e_partial));
    json_escape(writer->final_path, e_final, sizeof(e_final));
    json_escape(writer->window_start_utc, e_window, sizeof(e_window));

    /*
     * Readers poll this sidecar while the recorder is running. Write a sibling
     * temporary file and atomically replace the public sidecar so a reader can
     * never observe half-written JSON.
     */
    snprintf(temp_path, sizeof(temp_path), "%s.tmp.%lu", writer->lock_path,
        (unsigned long)GetCurrentProcessId());
    fp = fopen(temp_path, "wb");
    if (!fp) {
        if (error_text && error_text_size) snprintf(error_text, error_text_size,
            "Could not write temporary lock sidecar: %s", temp_path);
        return 0;
    }
    fprintf(fp,
        "{\n"
        "  \"schema\": \"recorder-poc.file-lock.v2\",\n"
        "  \"file_id\": \"%s\",\n"
        "  \"recorder_id\": \"%s\",\n"
        "  \"pid\": %lu,\n"
        "  \"state\": \"%s\",\n"
        "  \"partial_path\": \"%s\",\n"
        "  \"expected_final_name\": \"%s\",\n"
        "  \"recording_window_start_utc\": \"%s\",\n"
        "  \"segment_sequence\": %u,\n"
        "  \"last_heartbeat_utc\": \"%s\",\n"
        "  \"bytes_written\": %llu,\n"
        "  \"flushed_bytes\": %llu,\n"
        "  \"committed_position_ns\": %llu,\n"
        "  \"commit_generation\": %u,\n"
        "  \"commit_lag_target_ms\": %u,\n"
        "  \"read_safe\": %s\n"
        "}\n",
        e_file_id,
        e_recorder_id,
        (unsigned long)GetCurrentProcessId(),
        state ? state : "UNKNOWN",
        e_partial,
        e_final,
        e_window,
        writer->segment_sequence,
        now,
        writer->bytes_written,
        writer->flushed_bytes,
        writer->committed_position_ns,
        writer->commit_generation,
        writer->commit_lag_target_ms,
        writer->committed_position_ns > 0 ? "true" : "false");
    if (fflush(fp) != 0 || fclose(fp) != 0) {
        DeleteFileA(temp_path);
        if (error_text && error_text_size) snprintf(error_text, error_text_size,
            "Could not flush temporary lock sidecar: %s", temp_path);
        return 0;
    }
    if (!MoveFileExA(temp_path, writer->lock_path,
            MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        DWORD err = GetLastError();
        DeleteFileA(temp_path);
        set_error(error_text, error_text_size, "Atomic lock sidecar replace failed", err);
        return 0;
    }
    return 1;
}

int storage_writer_open(
    StorageWriter *writer,
    const char *partial_path,
    const char *final_path,
    const char *lock_path,
    const char *file_id,
    const char *recorder_id,
    const char *window_start_utc,
    unsigned int segment_sequence,
    char *error_text,
    size_t error_text_size) {

    DWORD err;
    if (!writer || !partial_path || !*partial_path || !final_path || !*final_path || !lock_path || !*lock_path) {
        if (error_text && error_text_size) snprintf(error_text, error_text_size, "Invalid StorageWriter arguments.");
        return 0;
    }
    storage_writer_init(writer);
    snprintf(writer->partial_path, sizeof(writer->partial_path), "%s", partial_path);
    snprintf(writer->final_path, sizeof(writer->final_path), "%s", final_path);
    snprintf(writer->lock_path, sizeof(writer->lock_path), "%s", lock_path);
    snprintf(writer->file_id, sizeof(writer->file_id), "%s", file_id ? file_id : "unknown-file");
    snprintf(writer->recorder_id, sizeof(writer->recorder_id), "%s", recorder_id ? recorder_id : "recorder-unknown");
    snprintf(writer->window_start_utc, sizeof(writer->window_start_utc), "%s", window_start_utc ? window_start_utc : "");
    writer->segment_sequence = segment_sequence;

    writer->handle = CreateFileA(
        writer->partial_path,
        GENERIC_WRITE,
        FILE_SHARE_READ,
        NULL,
        CREATE_ALWAYS,
        FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN,
        NULL);
    if (writer->handle == INVALID_HANDLE_VALUE) {
        err = GetLastError();
        set_error(error_text, error_text_size, "CreateFileA failed", err);
        return 0;
    }
    writer->opened = 1;
    if (!storage_writer_write_lock_state(writer, "RECORDING_LOCKED", error_text, error_text_size)) {
        CloseHandle(writer->handle);
        writer->handle = INVALID_HANDLE_VALUE;
        writer->opened = 0;
        return 0;
    }
    return 1;
}

int storage_writer_write(StorageWriter *writer, const unsigned char *data, size_t size, char *error_text, size_t error_text_size) {
    size_t offset = 0;
    if (!writer || !writer->opened || writer->handle == INVALID_HANDLE_VALUE || writer->had_error) {
        if (error_text && error_text_size) snprintf(error_text, error_text_size, "StorageWriter is not writable.");
        return 0;
    }
    while (offset < size) {
        DWORD chunk = (DWORD)((size - offset) > 0x7ffff000u ? 0x7ffff000u : (size - offset));
        DWORD wrote = 0;
        if (!WriteFile(writer->handle, data + offset, chunk, &wrote, NULL)) {
            DWORD err = GetLastError();
            writer->had_error = 1;
            set_error(error_text, error_text_size, "WriteFile failed", err);
            return 0;
        }
        if (wrote == 0) {
            writer->had_error = 1;
            if (error_text && error_text_size) snprintf(error_text, error_text_size, "WriteFile wrote zero bytes.");
            return 0;
        }
        offset += wrote;
        writer->bytes_written += wrote;
    }
    return 1;
}

int storage_writer_flush(StorageWriter *writer, char *error_text, size_t error_text_size) {
    if (!writer || !writer->opened || writer->handle == INVALID_HANDLE_VALUE) return 0;
    if (!FlushFileBuffers(writer->handle)) {
        set_error(error_text, error_text_size, "FlushFileBuffers failed", GetLastError());
        writer->had_error = 1;
        return 0;
    }
    writer->flushed_bytes = writer->bytes_written;
    return 1;
}

int storage_writer_commit(
    StorageWriter *writer,
    unsigned long long committed_position_ns,
    unsigned int commit_lag_target_ms,
    char *error_text,
    size_t error_text_size) {

    if (!writer || !writer->opened || writer->handle == INVALID_HANDLE_VALUE || writer->had_error) {
        if (error_text && error_text_size) snprintf(error_text, error_text_size,
            "StorageWriter cannot publish a commit watermark from current state.");
        return 0;
    }
    if (committed_position_ns <= writer->committed_position_ns) return 1;

    /*
     * The watermark is published only after all preceding MXF bytes have been
     * forced through the Windows file cache. A reader may therefore trust
     * committed_position_ns as a durable, read-safe presentation boundary.
     */
    if (!storage_writer_flush(writer, error_text, error_text_size)) return 0;
    writer->committed_position_ns = committed_position_ns;
    writer->commit_lag_target_ms = commit_lag_target_ms;
    writer->commit_generation++;
    if (!storage_writer_write_lock_state(writer, "RECORDING_LOCKED",
            error_text, error_text_size)) return 0;
    return 1;
}

int storage_writer_finalize(StorageWriter *writer, char *error_text, size_t error_text_size) {
    if (!writer || !writer->opened || writer->handle == INVALID_HANDLE_VALUE || writer->finalized || writer->had_error) {
        if (error_text && error_text_size) snprintf(error_text, error_text_size, "StorageWriter cannot finalize from current state.");
        return 0;
    }
    if (!storage_writer_write_lock_state(writer, "FINALIZING", error_text, error_text_size)) return 0;
    if (!storage_writer_flush(writer, error_text, error_text_size)) return 0;
    if (!CloseHandle(writer->handle)) {
        set_error(error_text, error_text_size, "CloseHandle failed", GetLastError());
        writer->handle = INVALID_HANDLE_VALUE;
        writer->opened = 0;
        writer->had_error = 1;
        return 0;
    }
    writer->handle = INVALID_HANDLE_VALUE;
    writer->opened = 0;

    if (!MoveFileExA(writer->partial_path, writer->final_path, MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
        set_error(error_text, error_text_size, "MoveFileExA finalization rename failed", GetLastError());
        writer->had_error = 1;
        return 0;
    }
    DeleteFileA(writer->lock_path);
    writer->finalized = 1;
    return 1;
}

void storage_writer_abort(StorageWriter *writer) {
    char ignored[256];
    if (!writer) return;
    if (writer->opened && writer->handle != INVALID_HANDLE_VALUE) {
        storage_writer_write_lock_state(writer, "RECOVERY_REQUIRED", ignored, sizeof(ignored));
        FlushFileBuffers(writer->handle);
        CloseHandle(writer->handle);
    }
    writer->handle = INVALID_HANDLE_VALUE;
    writer->opened = 0;
}
