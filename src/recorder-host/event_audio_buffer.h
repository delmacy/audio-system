#ifndef RECORDER_EVENT_AUDIO_BUFFER_H
#define RECORDER_EVENT_AUDIO_BUFFER_H

#include <stddef.h>
#include <stdint.h>

#define EVENT_AUDIO_BUFFER_BYTES 131072
#define EVENT_AUDIO_BUFFER_FRAMES 1024

typedef struct EventAudioFrame {
    size_t offset;
    unsigned int length;
    uint32_t rtp_timestamp;
} EventAudioFrame;

typedef struct EventAudioBuffer {
    unsigned char *data;
    EventAudioFrame *frames;
    size_t used;
    unsigned int frame_count;
    char first_ingress_utc[64];
} EventAudioBuffer;

void event_audio_buffer_init(EventAudioBuffer *buffer);
void event_audio_buffer_reset(EventAudioBuffer *buffer);
void event_audio_buffer_free(EventAudioBuffer *buffer);

int event_audio_buffer_push(
    EventAudioBuffer *buffer,
    const unsigned char *payload,
    unsigned int payload_len,
    uint32_t rtp_timestamp,
    const char *ingress_utc);

const EventAudioFrame *event_audio_buffer_frame(
    const EventAudioBuffer *buffer,
    unsigned int index);

#endif
