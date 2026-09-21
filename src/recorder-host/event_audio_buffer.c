#define _CRT_SECURE_NO_WARNINGS
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "event_audio_buffer.h"

void event_audio_buffer_init(EventAudioBuffer *buffer) {
    if (!buffer) return;
    memset(buffer, 0, sizeof(*buffer));
}

void event_audio_buffer_reset(EventAudioBuffer *buffer) {
    if (!buffer) return;
    buffer->used = 0;
    buffer->frame_count = 0;
    buffer->first_ingress_utc[0] = 0;
}

void event_audio_buffer_free(EventAudioBuffer *buffer) {
    if (!buffer) return;
    free(buffer->data);
    free(buffer->frames);
    memset(buffer, 0, sizeof(*buffer));
}

static int ensure_allocated(EventAudioBuffer *buffer) {
    if (!buffer) return 0;
    if (!buffer->data) {
        buffer->data = (unsigned char *)malloc(EVENT_AUDIO_BUFFER_BYTES);
        if (!buffer->data) return 0;
    }
    if (!buffer->frames) {
        buffer->frames = (EventAudioFrame *)calloc(
            EVENT_AUDIO_BUFFER_FRAMES, sizeof(EventAudioFrame));
        if (!buffer->frames) {
            free(buffer->data);
            buffer->data = NULL;
            return 0;
        }
    }
    return 1;
}

int event_audio_buffer_push(
    EventAudioBuffer *buffer,
    const unsigned char *payload,
    unsigned int payload_len,
    uint32_t rtp_timestamp,
    const char *ingress_utc) {

    EventAudioFrame *frame;
    if (!buffer || !payload || payload_len == 0) return 0;
    if (!ensure_allocated(buffer)) return 0;
    if (buffer->frame_count >= EVENT_AUDIO_BUFFER_FRAMES) return 0;
    if (buffer->used + payload_len > EVENT_AUDIO_BUFFER_BYTES) return 0;

    if (buffer->frame_count == 0 && ingress_utc && *ingress_utc)
        snprintf(buffer->first_ingress_utc,
            sizeof(buffer->first_ingress_utc), "%s", ingress_utc);

    frame = &buffer->frames[buffer->frame_count++];
    frame->offset = buffer->used;
    frame->length = payload_len;
    frame->rtp_timestamp = rtp_timestamp;
    memcpy(buffer->data + buffer->used, payload, payload_len);
    buffer->used += payload_len;
    return 1;
}

const EventAudioFrame *event_audio_buffer_frame(
    const EventAudioBuffer *buffer,
    unsigned int index) {

    if (!buffer || !buffer->frames || index >= buffer->frame_count)
        return NULL;
    return &buffer->frames[index];
}
