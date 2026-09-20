#ifndef RECORDER_STORAGE_WRITER_H
#define RECORDER_STORAGE_WRITER_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stddef.h>

typedef struct StorageWriter {
    HANDLE handle;
    char partial_path[4096];
    char final_path[4096];
    char lock_path[4096];
    char file_id[128];
    char recorder_id[128];
    char window_start_utc[64];
    unsigned int segment_sequence;
    unsigned long long bytes_written;
    int opened;
    int finalized;
    int had_error;
} StorageWriter;

void storage_writer_init(StorageWriter *writer);
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
    size_t error_text_size);
int storage_writer_write(StorageWriter *writer, const unsigned char *data, size_t size, char *error_text, size_t error_text_size);
int storage_writer_flush(StorageWriter *writer, char *error_text, size_t error_text_size);
int storage_writer_finalize(StorageWriter *writer, char *error_text, size_t error_text_size);
void storage_writer_abort(StorageWriter *writer);
int storage_writer_write_lock_state(StorageWriter *writer, const char *state, char *error_text, size_t error_text_size);
void storage_utc_now(char *buffer, size_t size);

#endif
