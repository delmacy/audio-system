#define _CRT_SECURE_NO_WARNINGS
#define WIN32_LEAN_AND_MEAN
#ifndef FD_SETSIZE
#define FD_SETSIZE 2048
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <gst/gst.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <objbase.h>
#include "storage_writer.h"
#include "event_file_manager.h"

#pragma comment(lib, "Ws2_32.lib")
#pragma comment(lib, "Ole32.lib")

#define RTSP_BUFFER_SIZE 65536
#define RTP_PACKET_MAX 65536
#define DEFAULT_MAX_SECONDS 120
#define MAX_SESSIONS 2048
#define MAX_CLIENTS 2048
#define MAX_SHARED_GROUPS 16
#define SESSION_MAP_FIELDS 16
#define LIVE_COMMIT_INTERVAL_MS 1000
#define LIVE_SAFETY_LAG_MS 1000
#define LIVE_SAFETY_LAG_NS ((guint64)LIVE_SAFETY_LAG_MS * GST_MSECOND)
/* mxfalaw.c uses edit_rate 10/1: one structural A-law edit unit per 100 ms. */
#define SHARED_MXF_AUDIO_EDIT_UNIT_MS 100
#define SHARED_MXF_AUDIO_EDIT_UNIT_NS ((guint64)SHARED_MXF_AUDIO_EDIT_UNIT_MS * GST_MSECOND)
#define SHARED_MXF_AUDIO_SAMPLES_PER_EDIT_UNIT 800ULL

typedef struct RecorderHost RecorderHost;
typedef struct RecorderSession RecorderSession;
typedef struct SharedMuxGroup SharedMuxGroup;

typedef struct SessionConfig {
    char route_key[512];
    char endpoint_id[128];
    char service_id[128];
    char media_flow[32];
    char activity_signal[16];
    char display_name[512];
    char logical_uuid[128];
    char instance_uuid[128];
    char file_id[128];
    char output_partial[4096];
    char output_final[4096];
    char lock_path[4096];
    int rtp_port;
    char window_start_utc[64];
    unsigned int segment_sequence;
    char session_kind[32];
} SessionConfig;

struct RecorderSession {
    RecorderHost *host;
    SessionConfig cfg;
    StorageWriter writer;
    GstElement *pipeline;
    GstElement *appsrc;
    GstElement *mux;
    GstElement *appsink;
    GstBus *bus;
    SOCKET rtp_socket;
    char session_id[128];
    char interaction_id[128];
    char leg_id[128];
    char event_media_start_utc[64];
    char event_last_event_utc[64];
    char event_state[32];
    int event_file_open;
    int event_close_requested;
    int event_rearm_requested;
    int event_answered;
    unsigned int event_sequence;
    int announced;
    int setup_done;
    int recording;
    int media_active;
    int pipeline_error;
    int sink_error;
    int first_rtp_timestamp_valid;
    guint32 first_rtp_timestamp;
    int last_timestamp_valid;
    guint32 last_timestamp;
    int last_payload_len;
    int last_sequence_valid;
    guint16 last_sequence;
    unsigned long long rtp_packets_received;
    unsigned long long rtp_packets_recorded;
    unsigned long long rtp_packets_ignored_not_recording;
    unsigned long long rtp_packets_malformed;
    unsigned long long rtp_packets_wrong_payload_type;
    unsigned long long rtp_packets_duplicate;
    unsigned long long rtp_packets_out_of_order;
    unsigned long long rtp_packets_late;
    unsigned long long rtp_payload_bytes_recorded;
    unsigned long long media_samples_written;
    unsigned long long shared_samples_queued;
    guint64 shared_timeline_position_ns;
    unsigned long long rtp_sequence_gap_packets;
    unsigned long long rtp_timestamp_discontinuities;
    unsigned long long rtp_timestamp_gap_samples;
    unsigned long long mux_bytes_written;
    unsigned int record_commands;
    unsigned int pause_commands;
    unsigned int keepalive_requests;
    unsigned int media_intervals_started;
    unsigned int media_intervals_closed;
    int teardown_received;
    int service_enabled;
    int finalized;
    int final_ok;
    int failed;
    int window_rotation_enabled;
    int rotate_after_pause_count;
    int rotate_max_count;
    int rotations_completed;
    int window_open_count;
    int windows_closed_complete;
    char rotation_stem[4096];
    int client_index;
    volatile LONG finalize_state; /* 0=active, 1=finalizing, 2=finalized */
    HANDLE finalizer_thread;
    char finalize_reason[512];
    SharedMuxGroup *shared_group;
    int track_index;
};
typedef struct ClientConnection {
    SOCKET socket;
    char buffer[RTSP_BUFFER_SIZE + 1];
    int buffer_len;
    RecorderSession *session;
    int close_after_response;
} ClientConnection;

typedef struct HostConfig {
    char bind_ip[64];
    int rtsp_port;
    char audit_path[4096];
    char ready_file[4096];
    char plugin_dll[4096];
    char recorder_id[128];
    char session_map_path[4096];
    int max_seconds;
    int legacy_mode;
    int rotate_window_after_pauses;
    int rotate_window_max_count;
    int shared_mxf_by_output;
    int event_files_mode;
    char recording_root[4096];
    char topology_watch_file[4096];
    unsigned long long topology_revision;
    char shutdown_watch_file[4096];
} HostConfig;

struct SharedMuxGroup {
    RecorderHost *host;
    char output_partial[4096];
    char output_final[4096];
    char lock_path[4096];
    char file_id[128];
    char window_start_utc[64];
    char timeline_origin_utc[64];
    char category[32];
    unsigned int segment_sequence;
    StorageWriter writer;
    GstElement *pipeline;
    GstElement *mux;
    GstElement *appsink;
    GstBus *bus;
    int session_indices[MAX_SESSIONS];
    int session_count;
    ULONGLONG started_tick_ms;
    ULONGLONG last_commit_tick_ms;
    guint64 track_written_end_ns[MAX_SESSIONS];
    guint64 confirmed_position_ns;
    unsigned long long mux_bytes_written;
    int sink_error;
    int pipeline_error;
    int finalized;
    int final_ok;
    volatile LONG finalize_state;
};

struct RecorderHost {
    HostConfig cfg;
    FILE *audit;
    CRITICAL_SECTION audit_lock;
    SOCKET listen_socket;
    ClientConnection clients[MAX_CLIENTS];
    RecorderSession sessions[MAX_SESSIONS];
    int session_count;
    SharedMuxGroup shared_groups[MAX_SHARED_GROUPS];
    int shared_group_count;
    int shutdown_requested;
    int server_failed;
};

static const char *arg_value(int argc, char **argv, const char *name) {
    int i;
    for (i = 1; i + 1 < argc; i++) if (strcmp(argv[i], name) == 0) return argv[i + 1];
    return NULL;
}

static int has_arg(int argc, char **argv, const char *name) {
    int i;
    for (i = 1; i < argc; i++) if (strcmp(argv[i], name) == 0) return 1;
    return 0;
}

static void safe_copy(char *dst, size_t dst_size, const char *src) {
    if (!dst || dst_size == 0) return;
    snprintf(dst, dst_size, "%s", src ? src : "");
}

static void trim_line(char *s) {
    size_t n;
    if (!s) return;
    n = strlen(s);
    while (n && (s[n - 1] == '\r' || s[n - 1] == '\n' || s[n - 1] == ' ' || s[n - 1] == '\t')) s[--n] = 0;
}

static void json_escape(const char *src, char *dst, size_t dst_size) {
    size_t w = 0;
    if (!dst || dst_size == 0) return;
    if (!src) src = "";
    while (*src && w + 2 < dst_size) {
        unsigned char c = (unsigned char)*src++;
        if (c == '\\' || c == '"') {
            dst[w++] = '\\';
            dst[w++] = (char)c;
        } else if (c == '\r' || c == '\n' || c == '\t') {
            dst[w++] = '\\';
            dst[w++] = c == '\r' ? 'r' : (c == '\n' ? 'n' : 't');
        } else if (c >= 0x20) {
            dst[w++] = (char)c;
        }
    }
    dst[w] = 0;
}


static void derive_rotation_stem(const char *final_path, char *stem, size_t stem_size) {
    size_t len;
    safe_copy(stem, stem_size, final_path ? final_path : "");
    len = strlen(stem);
    if (len > 4 && _stricmp(stem + len - 4, ".mxf") == 0) stem[len - 4] = 0;
}

static void make_guid_string(char *dst, size_t dst_size) {
    GUID guid;
    wchar_t wbuf[64];
    char tmp[64];
    int i, wlen;
    if (!dst || dst_size == 0) return;
    if (CoCreateGuid(&guid) != S_OK) {
        snprintf(dst, dst_size, "00000000-0000-4000-8000-%012llu", (unsigned long long)GetTickCount64());
        return;
    }
    wlen = StringFromGUID2(&guid, wbuf, 64);
    if (wlen <= 0) {
        snprintf(dst, dst_size, "00000000-0000-4000-8000-%012llu", (unsigned long long)GetTickCount64());
        return;
    }
    WideCharToMultiByte(CP_UTF8, 0, wbuf, -1, tmp, sizeof(tmp), NULL, NULL);
    /* remove braces and normalize lower-case */
    if (tmp[0] == '{') {
        size_t n = strlen(tmp);
        if (n > 2 && tmp[n-1] == '}') tmp[n-1] = 0;
        safe_copy(dst, dst_size, tmp + 1);
    } else safe_copy(dst, dst_size, tmp);
    for (i = 0; dst[i]; i++) dst[i] = (char)tolower((unsigned char)dst[i]);
}

static void build_segment_paths(RecorderSession *session, unsigned int segment_sequence) {
    if (!session) return;
    snprintf(session->cfg.output_final, sizeof(session->cfg.output_final), "%s.seg%03u.mxf", session->rotation_stem, segment_sequence);
    snprintf(session->cfg.output_partial, sizeof(session->cfg.output_partial), "%s.partial", session->cfg.output_final);
    snprintf(session->cfg.lock_path, sizeof(session->cfg.lock_path), "%s.lock", session->cfg.output_final);
    snprintf(session->cfg.file_id, sizeof(session->cfg.file_id), "P7-%s-seg%03u", session->session_id[0] ? session->session_id : "pending", segment_sequence);
}

static char *stristr(const char *haystack, const char *needle) {
    size_t nlen;
    const char *h;
    if (!haystack || !needle || !*needle) return (char *)haystack;
    nlen = strlen(needle);
    for (h = haystack; *h; h++) {
        size_t i;
        for (i = 0; i < nlen; i++) {
            if (!h[i]) return NULL;
            if (tolower((unsigned char)h[i]) != tolower((unsigned char)needle[i])) break;
        }
        if (i == nlen) return (char *)h;
    }
    return NULL;
}

static void audit_event(RecorderHost *host, RecorderSession *session, const char *event, const char *detail) {
    char now[64], e_event[256], e_detail[4096], e_session[256], e_logical[256], e_instance[256], e_file[256], e_route[1024], e_kind[128], e_interaction[256], e_leg[256], e_media_start[128], e_event_state[128];
    if (!host || !host->audit) return;
    storage_utc_now(now, sizeof(now));
    json_escape(event, e_event, sizeof(e_event));
    json_escape(detail, e_detail, sizeof(e_detail));
    json_escape(session ? session->session_id : "", e_session, sizeof(e_session));
    json_escape(session ? session->cfg.logical_uuid : "", e_logical, sizeof(e_logical));
    json_escape(session ? session->cfg.instance_uuid : "", e_instance, sizeof(e_instance));
    json_escape(session ? session->cfg.file_id : "", e_file, sizeof(e_file));
    json_escape(session ? session->cfg.route_key : "", e_route, sizeof(e_route));
    json_escape(session ? session->cfg.session_kind : "", e_kind, sizeof(e_kind));
    json_escape(session ? session->interaction_id : "", e_interaction, sizeof(e_interaction));
    json_escape(session ? session->leg_id : "", e_leg, sizeof(e_leg));
    json_escape(session ? session->event_media_start_utc : "", e_media_start, sizeof(e_media_start));
    json_escape(session ? session->event_state : "", e_event_state, sizeof(e_event_state));
    EnterCriticalSection(&host->audit_lock);
    fprintf(host->audit,
        "{\"ts_utc\":\"%s\",\"event\":\"%s\",\"session_id\":\"%s\",\"route_key\":\"%s\",\"file_id\":\"%s\",\"logical_track_uuid\":\"%s\",\"track_instance_uuid\":\"%s\",\"track_index\":%d,\"session_kind\":\"%s\",\"interaction_id\":\"%s\",\"leg_id\":\"%s\",\"media_start_utc\":\"%s\",\"event_state\":\"%s\",\"detail\":\"%s\"}\n",
        now, e_event, e_session, e_route, e_file, e_logical, e_instance, session ? session->track_index : -1, e_kind,
        e_interaction, e_leg, e_media_start, e_event_state, e_detail);
    fflush(host->audit);
    LeaveCriticalSection(&host->audit_lock);
}

static void audit_media_boundary(RecorderSession *session, const char *event, const char *reason) {
    char detail[512];
    snprintf(detail, sizeof(detail), "%s recorded_payload_bytes=%llu", reason, session->rtp_payload_bytes_recorded);
    audit_event(session->host, session, event, detail);
}

static int split_tabs(char *line, char **fields, int capacity) {
    int count = 0;
    char *p = line;
    if (!line || !fields || capacity <= 0) return 0;
    fields[count++] = p;
    while (*p && count < capacity) {
        if (*p == '\t') {
            *p = 0;
            fields[count++] = p + 1;
        }
        p++;
    }
    return count;
}

static void derive_paths(SessionConfig *cfg) {
    size_t len;
    if (!cfg->output_final[0]) {
        safe_copy(cfg->output_final, sizeof(cfg->output_final), cfg->output_partial);
        len = strlen(cfg->output_final);
        if (len > 8 && _stricmp(cfg->output_final + len - 8, ".partial") == 0) cfg->output_final[len - 8] = 0;
        else strncat(cfg->output_final, ".mxf", sizeof(cfg->output_final) - strlen(cfg->output_final) - 1);
    }
    if (!cfg->lock_path[0]) {
        safe_copy(cfg->lock_path, sizeof(cfg->lock_path), cfg->output_final);
        strncat(cfg->lock_path, ".lock", sizeof(cfg->lock_path) - strlen(cfg->lock_path) - 1);
    }
}

static int validate_session_config(const SessionConfig *cfg) {
    if (!cfg) return 0;
    if (!cfg->route_key[0] || !cfg->display_name[0] || !cfg->logical_uuid[0] || !cfg->instance_uuid[0]) return 0;
    if (!cfg->file_id[0] || !cfg->output_partial[0] || !cfg->output_final[0] || !cfg->lock_path[0]) return 0;
    if (cfg->rtp_port < 1 || cfg->rtp_port > 65534) return 0;
    return 1;
}

static int load_session_map(RecorderHost *host, const char *path) {
    FILE *fp;
    char line[16384];
    int line_no = 0;
    fp = fopen(path, "rb");
    if (!fp) {
        g_printerr("Could not open session map: %s\n", path);
        return 0;
    }
    while (fgets(line, sizeof(line), fp)) {
        char *fields[SESSION_MAP_FIELDS];
        int count, i;
        SessionConfig *cfg;
        line_no++;
        trim_line(line);
        if (line_no == 1 && strlen(line) >= 3 && (unsigned char)line[0] == 0xEF && (unsigned char)line[1] == 0xBB && (unsigned char)line[2] == 0xBF) memmove(line, line + 3, strlen(line + 3) + 1);
        if (!line[0] || line[0] == '#') continue;
        if (_strnicmp(line, "route_key\t", 10) == 0) continue;
        if (host->session_count >= MAX_SESSIONS) {
            g_printerr("Session map exceeds MAX_SESSIONS=%d.\n", MAX_SESSIONS);
            fclose(fp);
            return 0;
        }
        count = split_tabs(line, fields, SESSION_MAP_FIELDS);
        if (count != SESSION_MAP_FIELDS) {
            g_printerr("Invalid session map line %d: expected %d tab-separated fields, got %d.\n", line_no, SESSION_MAP_FIELDS, count);
            fclose(fp);
            return 0;
        }
        cfg = &host->sessions[host->session_count].cfg;
        memset(cfg, 0, sizeof(*cfg));
        safe_copy(cfg->route_key, sizeof(cfg->route_key), fields[0]);
        safe_copy(cfg->endpoint_id, sizeof(cfg->endpoint_id), fields[1]);
        safe_copy(cfg->service_id, sizeof(cfg->service_id), fields[2]);
        safe_copy(cfg->media_flow, sizeof(cfg->media_flow), fields[3]);
        safe_copy(cfg->activity_signal, sizeof(cfg->activity_signal), fields[4]);
        safe_copy(cfg->display_name, sizeof(cfg->display_name), fields[5]);
        safe_copy(cfg->logical_uuid, sizeof(cfg->logical_uuid), fields[6]);
        safe_copy(cfg->instance_uuid, sizeof(cfg->instance_uuid), fields[7]);
        safe_copy(cfg->file_id, sizeof(cfg->file_id), fields[8]);
        safe_copy(cfg->output_partial, sizeof(cfg->output_partial), fields[9]);
        safe_copy(cfg->output_final, sizeof(cfg->output_final), fields[10]);
        safe_copy(cfg->lock_path, sizeof(cfg->lock_path), fields[11]);
        cfg->rtp_port = atoi(fields[12]);
        safe_copy(cfg->window_start_utc, sizeof(cfg->window_start_utc), fields[13]);
        cfg->segment_sequence = (unsigned int)atoi(fields[14]);
        safe_copy(cfg->session_kind, sizeof(cfg->session_kind), fields[15]);
        if (!cfg->activity_signal[0]) safe_copy(cfg->activity_signal, sizeof(cfg->activity_signal), "none");
        if (!cfg->session_kind[0]) safe_copy(cfg->session_kind, sizeof(cfg->session_kind), "generic");
        derive_paths(cfg);
        if (!validate_session_config(cfg)) {
            g_printerr("Invalid session map line %d for route %s.\n", line_no, cfg->route_key);
            fclose(fp);
            return 0;
        }
        for (i = 0; i < host->session_count; i++) {
            if (_stricmp(host->sessions[i].cfg.route_key, cfg->route_key) == 0) {
                g_printerr("Duplicate route_key in session map: %s\n", cfg->route_key);
                fclose(fp);
                return 0;
            }
            if (host->sessions[i].cfg.rtp_port == cfg->rtp_port) {
                g_printerr("Duplicate RTP port in session map: %d\n", cfg->rtp_port);
                fclose(fp);
                return 0;
            }
            if (_stricmp(host->sessions[i].cfg.instance_uuid, cfg->instance_uuid) == 0) {
                g_printerr("Duplicate TrackInstanceUUID in session map: %s\n", cfg->instance_uuid);
                fclose(fp);
                return 0;
            }
        }
        host->session_count++;
    }
    fclose(fp);
    return host->session_count > 0;
}

static int parse_legacy_session(int argc, char **argv, RecorderHost *host) {
    const char *v;
    SessionConfig *cfg = &host->sessions[0].cfg;
    memset(cfg, 0, sizeof(*cfg));
    safe_copy(cfg->route_key, sizeof(cfg->route_key), "*");
    safe_copy(cfg->output_partial, sizeof(cfg->output_partial), arg_value(argc, argv, "--output"));
    safe_copy(cfg->output_final, sizeof(cfg->output_final), arg_value(argc, argv, "--final"));
    safe_copy(cfg->lock_path, sizeof(cfg->lock_path), arg_value(argc, argv, "--lock"));
    safe_copy(cfg->display_name, sizeof(cfg->display_name), arg_value(argc, argv, "--track-name"));
    safe_copy(cfg->logical_uuid, sizeof(cfg->logical_uuid), arg_value(argc, argv, "--logical-uuid"));
    safe_copy(cfg->instance_uuid, sizeof(cfg->instance_uuid), arg_value(argc, argv, "--instance-uuid"));
    safe_copy(cfg->file_id, sizeof(cfg->file_id), (v = arg_value(argc, argv, "--file-id")) ? v : "legacy-file-001");
    safe_copy(cfg->window_start_utc, sizeof(cfg->window_start_utc), (v = arg_value(argc, argv, "--window-start-utc")) ? v : "");
    safe_copy(cfg->session_kind, sizeof(cfg->session_kind), (v = arg_value(argc, argv, "--session-kind")) ? v : "generic");
    safe_copy(cfg->service_id, sizeof(cfg->service_id), (v = arg_value(argc, argv, "--service-id")) ? v : "");
    safe_copy(cfg->endpoint_id, sizeof(cfg->endpoint_id), (v = arg_value(argc, argv, "--endpoint-id")) ? v : "");
    safe_copy(cfg->media_flow, sizeof(cfg->media_flow), (v = arg_value(argc, argv, "--media-flow")) ? v : ((v = arg_value(argc, argv, "--direction")) ? v : "mono"));
    safe_copy(cfg->activity_signal, sizeof(cfg->activity_signal), (v = arg_value(argc, argv, "--activity-signal")) ? v : "none");
    cfg->segment_sequence = (unsigned int)atoi((v = arg_value(argc, argv, "--segment-sequence")) ? v : "0");
    cfg->rtp_port = atoi((v = arg_value(argc, argv, "--rtp-port")) ? v : "20000");
    derive_paths(cfg);
    if (!validate_session_config(cfg)) return 0;
    host->session_count = 1;
    host->cfg.legacy_mode = 1;
    return 1;
}

static int parse_host_config(int argc, char **argv, RecorderHost *host) {
    const char *v;
    memset(&host->cfg, 0, sizeof(host->cfg));
    safe_copy(host->cfg.bind_ip, sizeof(host->cfg.bind_ip), (v = arg_value(argc, argv, "--bind-ip")) ? v : "127.0.0.1");
    host->cfg.rtsp_port = atoi((v = arg_value(argc, argv, "--rtsp-port")) ? v : "8554");
    safe_copy(host->cfg.audit_path, sizeof(host->cfg.audit_path), arg_value(argc, argv, "--audit"));
    safe_copy(host->cfg.ready_file, sizeof(host->cfg.ready_file), arg_value(argc, argv, "--ready-file"));
    safe_copy(host->cfg.plugin_dll, sizeof(host->cfg.plugin_dll), arg_value(argc, argv, "--plugin-dll"));
    safe_copy(host->cfg.recorder_id, sizeof(host->cfg.recorder_id), (v = arg_value(argc, argv, "--recorder-id")) ? v : "RECORDER-POC-01");
    safe_copy(host->cfg.session_map_path, sizeof(host->cfg.session_map_path), arg_value(argc, argv, "--session-map"));
    host->cfg.max_seconds = atoi((v = arg_value(argc, argv, "--max-seconds")) ? v : "120");
    host->cfg.rotate_window_after_pauses = atoi((v = arg_value(argc, argv, "--rotate-window-after-pauses")) ? v : "0");
    host->cfg.rotate_window_max_count = atoi((v = arg_value(argc, argv, "--rotate-window-max-count")) ? v : "0");
    host->cfg.shared_mxf_by_output = has_arg(argc, argv, "--shared-mxf-by-output");
    host->cfg.event_files_mode = has_arg(argc, argv, "--event-files");
    safe_copy(host->cfg.recording_root, sizeof(host->cfg.recording_root),
        (v = arg_value(argc, argv, "--recording-root")) ? v : "recordings");
    safe_copy(host->cfg.topology_watch_file, sizeof(host->cfg.topology_watch_file),
        (v = arg_value(argc, argv, "--topology-watch-file")) ? v : "");
    host->cfg.topology_revision = _strtoui64(
        (v = arg_value(argc, argv, "--topology-revision")) ? v : "0", NULL, 10);
    safe_copy(host->cfg.shutdown_watch_file, sizeof(host->cfg.shutdown_watch_file),
        (v = arg_value(argc, argv, "--shutdown-watch-file")) ? v : "");
    if (!host->cfg.audit_path[0] || !host->cfg.plugin_dll[0]) return 0;
    if (host->cfg.shared_mxf_by_output && host->cfg.event_files_mode) {
        g_printerr("--shared-mxf-by-output and --event-files are mutually exclusive.\n");
        return 0;
    }
    if (host->cfg.event_files_mode && !host->cfg.recording_root[0]) return 0;
    if (host->cfg.rtsp_port < 1 || host->cfg.rtsp_port > 65535 || host->cfg.max_seconds < 1) return 0;
    if (host->cfg.session_map_path[0]) return load_session_map(host, host->cfg.session_map_path);
    return parse_legacy_session(argc, argv, host);
}

static gboolean load_identity_plugin(const char *path) {
    GError *err = NULL;
    GstPlugin *plugin;
    if (!path || !*path) return FALSE;
    plugin = gst_plugin_load_file(path, &err);
    if (!plugin) {
        g_printerr("Could not load identity plugin %s: %s\n", path, err ? err->message : "unknown");
        g_clear_error(&err);
        return FALSE;
    }
    g_print("IDENTITY PLUGIN LOADED: %s\n", path);
    gst_object_unref(plugin);
    return TRUE;
}


static int is_gc_audio_essence_klv(const unsigned char *data, size_t size, int *track_index) {
    static const unsigned char prefix[12] = {
        0x06, 0x0e, 0x2b, 0x34, 0x01, 0x02, 0x01, 0x01,
        0x0d, 0x01, 0x03, 0x01
    };
    int ordinal;
    if (!data || size < 17 || memcmp(data, prefix, sizeof(prefix)) != 0) return 0;
    if (data[12] != 0x16 || (data[14] != 0x08 && data[14] != 0x09 && data[14] != 0x0a))
        return 0;
    ordinal = (int)data[15];
    if (ordinal < 1) return 0;
    if (track_index) *track_index = ordinal - 1;
    return 1;
}

static int maybe_commit_shared_watermark(
    SharedMuxGroup *group,
    GstBuffer *buffer,
    const unsigned char *data,
    size_t size,
    char *error_text,
    size_t error_text_size) {

    GstClockTime pts, duration;
    guint64 end_ns, min_end = G_MAXUINT64, safe_position;
    ULONGLONG now;
    int track_index, i;

    if (!group || !buffer) return 1;
    if (!is_gc_audio_essence_klv(data, size, &track_index)) return 1;
    if (track_index < 0 || track_index >= group->session_count) return 1;

    pts = GST_BUFFER_PTS(buffer);
    duration = GST_BUFFER_DURATION(buffer);
    if (!GST_CLOCK_TIME_IS_VALID(pts) || !GST_CLOCK_TIME_IS_VALID(duration)) return 1;
    if (duration > G_MAXUINT64 - pts) return 0;
    end_ns = pts + duration;
    if (end_ns > group->track_written_end_ns[track_index])
        group->track_written_end_ns[track_index] = end_ns;

    now = GetTickCount64();
    if (group->last_commit_tick_ms &&
        now - group->last_commit_tick_ms < LIVE_COMMIT_INTERVAL_MS)
        return 1;
    group->last_commit_tick_ms = now;

    /*
     * A shared MXF is only safe through the least-advanced configured track.
     * GAP edit units count as structural progress, so inactive tracks can
     * advance without fabricating recorded audio.
     */
    for (i = 0; i < group->session_count; i++) {
        if (group->track_written_end_ns[i] == 0) {
            min_end = 0;
            break;
        }
        if (group->track_written_end_ns[i] < min_end)
            min_end = group->track_written_end_ns[i];
    }
    if (min_end <= LIVE_SAFETY_LAG_NS) return 1;

    /*
     * Keep one full second behind the structurally complete write head.
     * With the one-second commit cadence this yields the requested ~1-2 s
     * near-live delay while leaving the timeline strictly read-safe.
     */
    safe_position = min_end - LIVE_SAFETY_LAG_NS;
    if (safe_position <= group->confirmed_position_ns) return 1;

    if (!storage_writer_commit(&group->writer, safe_position,
            LIVE_SAFETY_LAG_MS, error_text, error_text_size))
        return 0;

    group->confirmed_position_ns = safe_position;
    return 1;
}

static GstFlowReturn on_shared_mux_sample(GstElement *sink, gpointer user_data) {
    SharedMuxGroup *group = (SharedMuxGroup *)user_data;
    GstSample *sample = NULL;
    GstBuffer *buffer;
    GstMapInfo map;
    char error_text[1024] = {0};
    g_signal_emit_by_name(sink, "pull-sample", &sample);
    if (!sample) return GST_FLOW_ERROR;
    buffer = gst_sample_get_buffer(sample);
    if (!buffer || !gst_buffer_map(buffer, &map, GST_MAP_READ)) {
        gst_sample_unref(sample);
        group->sink_error = 1;
        return GST_FLOW_ERROR;
    }
    if (!storage_writer_write(&group->writer, map.data, map.size, error_text, sizeof(error_text))) {
        group->sink_error = 1;
        g_printerr("Shared StorageWriter failure category=%s: %s\n", group->category, error_text);
        audit_event(group->host, NULL, "INTEGRITY_FAILURE", error_text);
        gst_buffer_unmap(buffer, &map);
        gst_sample_unref(sample);
        return GST_FLOW_ERROR;
    }
    group->mux_bytes_written += map.size;

    if (!maybe_commit_shared_watermark(group, buffer, map.data, map.size,
            error_text, sizeof(error_text))) {
        group->sink_error = 1;
        g_printerr("Growing MXF watermark failure category=%s: %s\n",
            group->category, error_text);
        audit_event(group->host, NULL, "INTEGRITY_FAILURE", error_text);
        gst_buffer_unmap(buffer, &map);
        gst_sample_unref(sample);
        return GST_FLOW_ERROR;
    }

    gst_buffer_unmap(buffer, &map);
    gst_sample_unref(sample);
    return GST_FLOW_OK;
}

static SharedMuxGroup *find_shared_group(RecorderHost *host, const char *output_final) {
    int i;
    if (!host || !output_final) return NULL;
    for (i = 0; i < host->shared_group_count; i++) {
        if (_stricmp(host->shared_groups[i].output_final, output_final) == 0) return &host->shared_groups[i];
    }
    return NULL;
}

static int attach_shared_track(SharedMuxGroup *group, RecorderSession *session, int track_index) {
    GstCaps *caps;
    GstPad *src_pad;
    GstPad *mux_pad;
    if (!group || !session || !group->pipeline || !group->mux) return 0;
    session->appsrc = gst_element_factory_make("appsrc", NULL);
    if (!session->appsrc) return 0;
    caps = gst_caps_from_string("audio/x-alaw,rate=8000,channels=1");
    g_object_set(session->appsrc,
        "caps", caps,
        "format", GST_FORMAT_TIME,
        "is-live", TRUE,
        "block", FALSE,
        "max-bytes", (guint64)(8000 * 5),
        NULL);
    gst_caps_unref(caps);
    gst_bin_add(GST_BIN(group->pipeline), session->appsrc);
    src_pad = gst_element_get_static_pad(session->appsrc, "src");
    mux_pad = gst_element_request_pad_simple(group->mux, "alaw_audio_sink_%u");
    if (!src_pad || !mux_pad || gst_pad_link(src_pad, mux_pad) != GST_PAD_LINK_OK) {
        if (src_pad) gst_object_unref(src_pad);
        if (mux_pad) gst_object_unref(mux_pad);
        return 0;
    }
    g_object_set(G_OBJECT(mux_pad),
        "track-name", session->cfg.display_name,
        "logical-track-uuid", session->cfg.logical_uuid,
        "track-instance-uuid", session->cfg.instance_uuid,
        NULL);
    gst_object_unref(src_pad);
    gst_object_unref(mux_pad);
    session->shared_group = group;
    session->track_index = track_index;
    return 1;
}

static int build_shared_groups(RecorderHost *host) {
    int i, g;
    char error_text[1024] = {0};
    if (!host || !host->cfg.shared_mxf_by_output) return 1;

    for (i = 0; i < host->session_count; i++) {
        RecorderSession *session = &host->sessions[i];
        SharedMuxGroup *group = find_shared_group(host, session->cfg.output_final);
        if (!group) {
            if (host->shared_group_count >= MAX_SHARED_GROUPS) {
                g_printerr("Shared MXF group count exceeds MAX_SHARED_GROUPS=%d.\n", MAX_SHARED_GROUPS);
                return 0;
            }
            group = &host->shared_groups[host->shared_group_count++];
            memset(group, 0, sizeof(*group));
            group->host = host;
            safe_copy(group->output_partial, sizeof(group->output_partial), session->cfg.output_partial);
            safe_copy(group->output_final, sizeof(group->output_final), session->cfg.output_final);
            safe_copy(group->lock_path, sizeof(group->lock_path), session->cfg.lock_path);
            safe_copy(group->file_id, sizeof(group->file_id), session->cfg.file_id);
            safe_copy(group->window_start_utc, sizeof(group->window_start_utc), session->cfg.window_start_utc);
            safe_copy(group->category, sizeof(group->category), session->cfg.session_kind);
            group->segment_sequence = session->cfg.segment_sequence;
            storage_writer_init(&group->writer);
        } else {
            if (_stricmp(group->file_id, session->cfg.file_id) != 0) {
                g_printerr("Routes sharing output_final must share file_id: %s\n", session->cfg.output_final);
                return 0;
            }
            if (_stricmp(group->category, session->cfg.session_kind) != 0) {
                g_printerr("Routes sharing output_final must share session_kind: %s\n", session->cfg.output_final);
                return 0;
            }
        }
        if (group->session_count >= MAX_SESSIONS) return 0;
        group->session_indices[group->session_count++] = i;
        session->shared_group = group;
    }

    for (g = 0; g < host->shared_group_count; g++) {
        SharedMuxGroup *group = &host->shared_groups[g];
        GstStateChangeReturn state_result;
        if (!storage_writer_open(&group->writer,
            group->output_partial,
            group->output_final,
            group->lock_path,
            group->file_id,
            host->cfg.recorder_id,
            group->window_start_utc,
            group->segment_sequence,
            error_text,
            sizeof(error_text))) {
            g_printerr("Shared StorageWriter open failed category=%s: %s\n", group->category, error_text);
            return 0;
        }
        group->pipeline = gst_pipeline_new(NULL);
        group->mux = gst_element_factory_make("mxfidmux", NULL);
        group->appsink = gst_element_factory_make("appsink", NULL);
        if (!group->pipeline || !group->mux || !group->appsink) return 0;
        g_object_set(group->appsink,
            "emit-signals", TRUE,
            "sync", FALSE,
            "async", FALSE,
            "max-buffers", 128,
            "drop", FALSE,
            NULL);
        g_signal_connect(group->appsink, "new-sample", G_CALLBACK(on_shared_mux_sample), group);
        gst_bin_add_many(GST_BIN(group->pipeline), group->mux, group->appsink, NULL);
        if (!gst_element_link(group->mux, group->appsink)) return 0;

        for (i = 0; i < group->session_count; i++) {
            RecorderSession *session = &host->sessions[group->session_indices[i]];
            if (!attach_shared_track(group, session, i)) {
                g_printerr("Could not attach shared MXF track category=%s route=%s index=%d.\n",
                    group->category, session->cfg.route_key, i);
                return 0;
            }
        }
        group->bus = gst_element_get_bus(group->pipeline);
        storage_utc_now(group->timeline_origin_utc, sizeof(group->timeline_origin_utc));
        safe_copy(group->writer.timeline_origin_utc,
            sizeof(group->writer.timeline_origin_utc), group->timeline_origin_utc);
        group->started_tick_ms = GetTickCount64();
        state_result = gst_element_set_state(group->pipeline, GST_STATE_PLAYING);
        if (state_result == GST_STATE_CHANGE_FAILURE) return 0;
        for (i = 0; i < group->session_count; i++) {
            RecorderSession *session = &host->sessions[group->session_indices[i]];
            audit_event(host, session, "MXF_TIMELINE_ORIGIN", group->timeline_origin_utc);
        }
        g_print("SHARED MXF ARMED category=%s tracks=%d file=%s\n",
            group->category, group->session_count, group->output_final);
    }
    return 1;
}

static int shared_group_all_sessions_finalized(SharedMuxGroup *group) {
    int i;
    if (!group || !group->host) return 0;
    for (i = 0; i < group->session_count; i++) {
        RecorderSession *session = &group->host->sessions[group->session_indices[i]];
        if (!session->finalized) return 0;
    }
    return 1;
}

static int finalize_shared_group(SharedMuxGroup *group) {
    GstMessage *msg = NULL;
    int ok = 1;
    int i;
    char error_text[1024] = {0};
    if (!group) return 0;
    if (InterlockedCompareExchange(&group->finalize_state, 1, 0) != 0) return group->final_ok;
    if (group->bus) {
        msg = gst_bus_timed_pop_filtered(group->bus, 10 * GST_SECOND, GST_MESSAGE_EOS | GST_MESSAGE_ERROR);
        if (!msg) ok = 0;
        else if (GST_MESSAGE_TYPE(msg) == GST_MESSAGE_ERROR) ok = 0;
        if (msg) gst_message_unref(msg);
    }
    if (group->pipeline) gst_element_set_state(group->pipeline, GST_STATE_NULL);
    if (group->sink_error || group->pipeline_error || group->writer.had_error) ok = 0;
    if (ok) {
        if (!storage_writer_finalize(&group->writer, error_text, sizeof(error_text))) {
            audit_event(group->host, NULL, "INTEGRITY_FAILURE", error_text);
            ok = 0;
        } else {
            char detail[4600];
            snprintf(detail, sizeof(detail), "category=%s file_id=%s tracks=%d final=%s",
                group->category, group->file_id, group->session_count, group->output_final);
            audit_event(group->host, NULL, "SHARED_MXF_CLOSED_COMPLETE", detail);
        }
    }
    if (!ok) storage_writer_abort(&group->writer);
    group->finalized = 1;
    group->final_ok = ok;
    InterlockedExchange(&group->finalize_state, 2);
    for (i = 0; i < group->session_count; i++) {
        RecorderSession *session = &group->host->sessions[group->session_indices[i]];
        if (ok) session->windows_closed_complete++;
        else {
            session->final_ok = 0;
            session->failed = 1;
        }
    }
    return ok;
}

static void maybe_finalize_shared_group(SharedMuxGroup *group) {
    if (group && !group->finalized && shared_group_all_sessions_finalized(group)) finalize_shared_group(group);
}

static int poll_shared_group_error(SharedMuxGroup *group) {
    GstMessage *msg;
    if (!group || !group->bus || group->finalized) return 0;
    while ((msg = gst_bus_pop_filtered(group->bus, GST_MESSAGE_ERROR | GST_MESSAGE_WARNING)) != NULL) {
        if (GST_MESSAGE_TYPE(msg) == GST_MESSAGE_ERROR) {
            GError *err = NULL;
            gchar *debug = NULL;
            char detail[2048];
            gst_message_parse_error(msg, &err, &debug);
            snprintf(detail, sizeof(detail), "Shared MXF category=%s error: %s debug=%s",
                group->category, err ? err->message : "unknown", debug ? debug : "");
            audit_event(group->host, NULL, "INTEGRITY_FAILURE", detail);
            if (err) g_error_free(err);
            g_free(debug);
            gst_message_unref(msg);
            group->pipeline_error = 1;
            return 1;
        }
        gst_message_unref(msg);
    }
    return 0;
}

static void destroy_shared_groups(RecorderHost *host) {
    int g;
    if (!host) return;
    for (g = 0; g < host->shared_group_count; g++) {
        SharedMuxGroup *group = &host->shared_groups[g];
        if (!group->finalized) {
            int i;
            for (i = 0; i < group->session_count; i++) {
                RecorderSession *session = &host->sessions[group->session_indices[i]];
                if (session->appsrc && !session->finalized) {
                    GstFlowReturn flow = GST_FLOW_OK;
                    g_signal_emit_by_name(session->appsrc, "end-of-stream", &flow);
                    session->finalized = 1;
                }
            }
            finalize_shared_group(group);
        }
        if (group->bus) gst_object_unref(group->bus);
        group->bus = NULL;
        if (group->pipeline) gst_object_unref(group->pipeline);
        group->pipeline = group->mux = group->appsink = NULL;
    }
}

static GstFlowReturn on_mux_sample(GstElement *sink, gpointer user_data) {
    RecorderSession *session = (RecorderSession *)user_data;
    GstSample *sample = NULL;
    GstBuffer *buffer;
    GstMapInfo map;
    char error_text[1024] = {0};
    g_signal_emit_by_name(sink, "pull-sample", &sample);
    if (!sample) return GST_FLOW_ERROR;
    buffer = gst_sample_get_buffer(sample);
    if (!buffer || !gst_buffer_map(buffer, &map, GST_MAP_READ)) {
        gst_sample_unref(sample);
        session->sink_error = 1;
        return GST_FLOW_ERROR;
    }
    if (!storage_writer_write(&session->writer, map.data, map.size, error_text, sizeof(error_text))) {
        session->sink_error = 1;
        g_printerr("StorageWriter write failure route=%s: %s\n", session->cfg.route_key, error_text);
        audit_event(session->host, session, "INTEGRITY_FAILURE", error_text);
        gst_buffer_unmap(buffer, &map);
        gst_sample_unref(sample);
        return GST_FLOW_ERROR;
    }
    session->mux_bytes_written += map.size;
    gst_buffer_unmap(buffer, &map);
    gst_sample_unref(sample);
    return GST_FLOW_OK;
}

static int build_pipeline(RecorderSession *session) {
    GstCaps *caps;
    GstPad *src_pad;
    GstPad *mux_pad;
    GstStateChangeReturn state_result;
    char pipeline_name[128];
    snprintf(pipeline_name, sizeof(pipeline_name), "recorder-session-%d", (int)(session - session->host->sessions));
    session->pipeline = gst_pipeline_new(pipeline_name);
    session->appsrc = gst_element_factory_make("appsrc", NULL);
    session->mux = gst_element_factory_make("mxfidmux", NULL);
    session->appsink = gst_element_factory_make("appsink", NULL);
    if (!session->pipeline || !session->appsrc || !session->mux || !session->appsink) return 0;
    caps = gst_caps_from_string("audio/x-alaw,rate=8000,channels=1");
    g_object_set(session->appsrc,
        "caps", caps,
        "format", GST_FORMAT_TIME,
        "is-live", TRUE,
        "block", FALSE,
        "max-bytes", (guint64)(8000 * 5),
        NULL);
    gst_caps_unref(caps);
    g_object_set(session->appsink,
        "emit-signals", TRUE,
        "sync", FALSE,
        "async", FALSE,
        "max-buffers", 64,
        "drop", FALSE,
        NULL);
    g_signal_connect(session->appsink, "new-sample", G_CALLBACK(on_mux_sample), session);
    gst_bin_add_many(GST_BIN(session->pipeline), session->appsrc, session->mux, session->appsink, NULL);
    if (!gst_element_link(session->mux, session->appsink)) return 0;
    src_pad = gst_element_get_static_pad(session->appsrc, "src");
    mux_pad = gst_element_request_pad_simple(session->mux, "alaw_audio_sink_%u");
    if (!src_pad || !mux_pad || gst_pad_link(src_pad, mux_pad) != GST_PAD_LINK_OK) {
        if (src_pad) gst_object_unref(src_pad);
        if (mux_pad) gst_object_unref(mux_pad);
        return 0;
    }
    g_object_set(G_OBJECT(mux_pad),
        "track-name", session->cfg.display_name,
        "logical-track-uuid", session->cfg.logical_uuid,
        "track-instance-uuid", session->cfg.instance_uuid,
        NULL);
    gst_object_unref(src_pad);
    gst_object_unref(mux_pad);
    session->bus = gst_element_get_bus(session->pipeline);
    state_result = gst_element_set_state(session->pipeline, GST_STATE_PLAYING);
    return state_result != GST_STATE_CHANGE_FAILURE;
}

static int open_bound_socket(const char *ip, int port, int type, int protocol, SOCKET *out_socket) {
    SOCKET s;
    struct sockaddr_in addr;
    int reuse = 1;
    int recvbuf = 131072;
    s = socket(AF_INET, type, protocol);
    if (s == INVALID_SOCKET) return 0;
    setsockopt(s, SOL_SOCKET, SO_REUSEADDR, (const char *)&reuse, sizeof(reuse));
    if (type == SOCK_DGRAM)
        setsockopt(s, SOL_SOCKET, SO_RCVBUF, (const char *)&recvbuf, sizeof(recvbuf));
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons((u_short)port);
    if (inet_pton(AF_INET, ip, &addr.sin_addr) != 1) {
        closesocket(s);
        return 0;
    }
    if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) == SOCKET_ERROR) {
        closesocket(s);
        return 0;
    }
    *out_socket = s;
    return 1;
}

static int init_session(RecorderHost *host, RecorderSession *session, int index) {
    char error_text[1024] = {0};
    session->host = host;
    session->rtp_socket = INVALID_SOCKET;
    session->client_index = -1;
    session->finalize_state = 0;
    session->finalizer_thread = NULL;
    session->finalize_reason[0] = 0;
    storage_writer_init(&session->writer);
    snprintf(session->session_id, sizeof(session->session_id), "P5-%lu-%02d-%llu",
        (unsigned long)GetCurrentProcessId(), index + 1, (unsigned long long)GetTickCount64());
    session->rotate_after_pause_count = host->cfg.rotate_window_after_pauses;
    session->rotate_max_count = host->cfg.rotate_window_max_count;
    session->window_rotation_enabled = (!session->shared_group && session->rotate_after_pause_count > 0 && session->rotate_max_count > 0);
    session->rotations_completed = 0;
    session->windows_closed_complete = 0;
    session->window_open_count = host->cfg.event_files_mode ? 0 : 1;
    session->event_file_open = 0;
    session->event_close_requested = 0;
    session->event_rearm_requested = 0;
    session->event_answered = 0;
    session->event_sequence = 0;
    session->interaction_id[0] = 0;
    session->leg_id[0] = 0;
    session->event_media_start_utc[0] = 0;
    session->event_last_event_utc[0] = 0;
    safe_copy(session->event_state, sizeof(session->event_state), host->cfg.event_files_mode ? "IDLE" : "N/A");
    derive_rotation_stem(session->cfg.output_final, session->rotation_stem, sizeof(session->rotation_stem));
    if (session->window_rotation_enabled) {
        build_segment_paths(session, session->cfg.segment_sequence);
    }
    if (!session->shared_group && !host->cfg.event_files_mode) {
        if (!storage_writer_open(&session->writer,
            session->cfg.output_partial,
            session->cfg.output_final,
            session->cfg.lock_path,
            session->cfg.file_id,
            host->cfg.recorder_id,
            session->cfg.window_start_utc,
            session->cfg.segment_sequence,
            error_text,
            sizeof(error_text))) {
            g_printerr("StorageWriter open failed route=%s: %s\n", session->cfg.route_key, error_text);
            return 0;
        }
        if (!build_pipeline(session)) {
            g_printerr("Pipeline build failed route=%s.\n", session->cfg.route_key);
            storage_writer_abort(&session->writer);
            return 0;
        }
    }
    if (!open_bound_socket(host->cfg.bind_ip, session->cfg.rtp_port, SOCK_DGRAM, IPPROTO_UDP, &session->rtp_socket)) {
        g_printerr("Could not bind RTP route=%s %s:%d WSA=%d.\n", session->cfg.route_key, host->cfg.bind_ip, session->cfg.rtp_port, WSAGetLastError());
        if (session->pipeline) gst_element_set_state(session->pipeline, GST_STATE_NULL);
        if (!session->shared_group && !host->cfg.event_files_mode) storage_writer_abort(&session->writer);
        return 0;
    }
    audit_event(host, session, "NEXT_WINDOW_ARMED",
        host->cfg.event_files_mode
            ? "Event route armed with RTP socket; MXF writer will be materialized from first accepted media timestamp"
            : "Session writer/pipeline/RTP socket prepared before RTSP traffic");
    return 1;
}

static void destroy_pipeline(RecorderSession *session) {
    if (!session) return;
    if (session->shared_group) {
        session->appsrc = NULL;
        session->pipeline = session->mux = session->appsink = NULL;
        session->bus = NULL;
        return;
    }
    if (session->bus) gst_object_unref(session->bus);
    session->bus = NULL;
    if (session->pipeline) gst_object_unref(session->pipeline);
    session->pipeline = session->appsrc = session->mux = session->appsink = NULL;
}

static void audit_activity_signal(RecorderSession *session, int active) {
    if (!session || !session->cfg.activity_signal[0] || _stricmp(session->cfg.activity_signal, "none") == 0) return;
    if (_stricmp(session->cfg.activity_signal, "squ") == 0)
        audit_event(session->host, session, active ? "SQU_ON" : "SQU_OFF", "PoC radio activity state mapped to SQU metadata");
    else if (_stricmp(session->cfg.activity_signal, "ptt") == 0)
        audit_event(session->host, session, active ? "PTT_ON" : "PTT_OFF", "PoC radio activity state mapped to PTT metadata");
}


static int close_current_window_only(RecorderSession *session, const char *reason) {
    GstFlowReturn flow = GST_FLOW_OK;
    GstMessage *msg = NULL;
    int ok = 1;
    char error_text[1024] = {0};
    if (!session || !session->pipeline || !session->appsrc) return 0;
    audit_event(session->host, session, "WINDOW_CLOSING", reason ? reason : "Logical window rollover closing current writer");
    g_signal_emit_by_name(session->appsrc, "end-of-stream", &flow);
    if (flow != GST_FLOW_OK) ok = 0;
    if (session->bus) {
        msg = gst_bus_timed_pop_filtered(session->bus, 10 * GST_SECOND, GST_MESSAGE_EOS | GST_MESSAGE_ERROR);
        if (!msg) ok = 0;
        else if (GST_MESSAGE_TYPE(msg) == GST_MESSAGE_ERROR) {
            GError *err = NULL;
            gchar *debug = NULL;
            char detail[2048];
            gst_message_parse_error(msg, &err, &debug);
            snprintf(detail, sizeof(detail), "GStreamer window rollover error: %s debug=%s", err ? err->message : "unknown", debug ? debug : "");
            audit_event(session->host, session, "INTEGRITY_FAILURE", detail);
            if (err) g_error_free(err);
            g_free(debug);
            ok = 0;
        }
        if (msg) gst_message_unref(msg);
    }
    if (session->pipeline) gst_element_set_state(session->pipeline, GST_STATE_NULL);
    if (session->pipeline_error || session->sink_error || session->writer.had_error) ok = 0;
    if (ok) {
        if (!storage_writer_finalize(&session->writer, error_text, sizeof(error_text))) {
            audit_event(session->host, session, "INTEGRITY_FAILURE", error_text);
            ok = 0;
        } else {
            session->windows_closed_complete++;
            audit_event(session->host, session, "WINDOW_CLOSED_COMPLETE", "MXF window closed cleanly; RTSP session remains alive");
            audit_event(session->host, session, "MEDIA_COMMIT", "Window MXF EOS complete, FlushFileBuffers complete, .partial promoted to .mxf");
        }
    }
    if (!ok) storage_writer_abort(&session->writer);
    destroy_pipeline(session);
    return ok;
}

static int open_next_window_only(RecorderSession *session) {
    char error_text[1024] = {0};
    char detail[2048];
    if (!session) return 0;
    session->cfg.segment_sequence++;
    make_guid_string(session->cfg.instance_uuid, sizeof(session->cfg.instance_uuid));
    build_segment_paths(session, session->cfg.segment_sequence);
    session->pipeline_error = 0;
    session->sink_error = 0;
    storage_writer_init(&session->writer);
    if (!storage_writer_open(&session->writer,
        session->cfg.output_partial,
        session->cfg.output_final,
        session->cfg.lock_path,
        session->cfg.file_id,
        session->host->cfg.recorder_id,
        session->cfg.window_start_utc,
        session->cfg.segment_sequence,
        error_text,
        sizeof(error_text))) {
        audit_event(session->host, session, "INTEGRITY_FAILURE", error_text);
        return 0;
    }
    if (!build_pipeline(session)) {
        audit_event(session->host, session, "INTEGRITY_FAILURE", "Pipeline rebuild failed for next logical window");
        storage_writer_abort(&session->writer);
        return 0;
    }
    session->window_open_count++;
    snprintf(detail, sizeof(detail), "segment_sequence=%u file_id=%s track_instance_uuid=%s final=%s", session->cfg.segment_sequence, session->cfg.file_id, session->cfg.instance_uuid, session->cfg.output_final);
    audit_event(session->host, session, "WINDOW_OPENED", detail);
    return 1;
}

static int maybe_rotate_window_after_pause(RecorderSession *session) {
    if (!session || !session->window_rotation_enabled) return 1;
    if (session->rotate_after_pause_count <= 0) return 1;
    if (session->rotations_completed >= session->rotate_max_count) return 1;
    if ((int)session->pause_commands < session->rotate_after_pause_count * (session->rotations_completed + 1)) return 1;
    if (session->recording || session->media_active) return 1;
    audit_event(session->host, session, "WINDOW_ROTATION_REQUESTED", "PAUSE boundary reached; rotating writer while keeping RTSP Session alive");
    if (!close_current_window_only(session, "PAUSE boundary logical window rotation")) return 0;
    session->rotations_completed++;
    if (!open_next_window_only(session)) return 0;
    audit_event(session->host, session, "WINDOW_ROTATED", "RTSP session continuity preserved; LogicalTrackUUID stable; TrackInstanceUUID renewed");
    return 1;
}

static int finalize_session(RecorderSession *session, const char *reason) {
    GstFlowReturn flow = GST_FLOW_ERROR;
    GstMessage *msg = NULL;
    int ok = 1;
    char error_text[1024] = {0};
    if (!session || session->finalized) return session ? session->final_ok : 0;
    if (session->media_active) {
        audit_media_boundary(session, "MEDIA_END", reason ? reason : "Session finalization closed media interval");
        session->media_active = 0;
        session->media_intervals_closed++;
    }
    session->recording = 0;
    if (session->service_enabled) {
        audit_event(session->host, session, "SERVICE_DISABLED", reason ? reason : "Service session finalized");
        session->service_enabled = 0;
    }
    if (session->keepalive_requests > 0) {
        char detail[256];
        snprintf(detail, sizeof(detail), "Aggregated successful keepalives=%u", session->keepalive_requests);
        audit_event(session->host, session, "KEEPALIVE_OK", detail);
    }
    audit_event(session->host, session, "SESSION_CLOSE", reason ? reason : "Session beginning graceful file finalization");
    if (session->shared_group) {
        if (session->appsrc) g_signal_emit_by_name(session->appsrc, "end-of-stream", &flow);
        if (!session->appsrc || flow != GST_FLOW_OK) ok = 0;
        if (session->rtp_socket != INVALID_SOCKET) {
            closesocket(session->rtp_socket);
            session->rtp_socket = INVALID_SOCKET;
        }
        session->finalized = 1;
        session->final_ok = ok && !session->shared_group->sink_error && !session->shared_group->pipeline_error;
        session->failed = !session->final_ok;
        maybe_finalize_shared_group(session->shared_group);
        return session->final_ok;
    }
    if (session->appsrc) g_signal_emit_by_name(session->appsrc, "end-of-stream", &flow);
    if (!session->appsrc || flow != GST_FLOW_OK) ok = 0;
    if (session->bus) {
        msg = gst_bus_timed_pop_filtered(session->bus, 10 * GST_SECOND, GST_MESSAGE_EOS | GST_MESSAGE_ERROR);
        if (!msg) ok = 0;
        else if (GST_MESSAGE_TYPE(msg) == GST_MESSAGE_ERROR) {
            GError *err = NULL;
            gchar *debug = NULL;
            char detail[2048];
            gst_message_parse_error(msg, &err, &debug);
            snprintf(detail, sizeof(detail), "GStreamer finalization error: %s debug=%s", err ? err->message : "unknown", debug ? debug : "");
            audit_event(session->host, session, "INTEGRITY_FAILURE", detail);
            if (err) g_error_free(err);
            g_free(debug);
            ok = 0;
        }
        if (msg) gst_message_unref(msg);
    }
    if (session->pipeline) gst_element_set_state(session->pipeline, GST_STATE_NULL);
    if (session->pipeline_error || session->sink_error || session->writer.had_error) ok = 0;
    if (ok) {
        if (!storage_writer_finalize(&session->writer, error_text, sizeof(error_text))) {
            audit_event(session->host, session, "INTEGRITY_FAILURE", error_text);
            ok = 0;
        } else {
            session->windows_closed_complete++;
            audit_event(session->host, session, "WINDOW_CLOSED_COMPLETE", "Final session window closed cleanly");
            audit_event(session->host, session, "MEDIA_COMMIT", "MXF EOS complete, FlushFileBuffers complete, .partial promoted to .mxf");
        }
    }
    if (!ok) storage_writer_abort(&session->writer);
    if (session->rtp_socket != INVALID_SOCKET) {
        closesocket(session->rtp_socket);
        session->rtp_socket = INVALID_SOCKET;
    }
    destroy_pipeline(session);
    session->finalized = 1;
    session->final_ok = ok;
    session->failed = !ok;
    return ok;
}

static DWORD WINAPI finalize_session_thread_proc(LPVOID param) {
    RecorderSession *session = (RecorderSession *)param;
    int ok = finalize_session(session, session->finalize_reason[0] ? session->finalize_reason : "Asynchronous route-local finalization");
    InterlockedExchange(&session->finalize_state, 2);
    return ok ? 0 : 1;
}

static int begin_finalize_session(RecorderSession *session, const char *reason) {
    DWORD thread_id = 0;
    if (!session) return 0;
    if (InterlockedCompareExchange(&session->finalize_state, 1, 0) != 0) return 1;
    safe_copy(session->finalize_reason, sizeof(session->finalize_reason), reason ? reason : "Route-local TEARDOWN finalization");
    if (session->rtp_socket != INVALID_SOCKET) {
        closesocket(session->rtp_socket);
        session->rtp_socket = INVALID_SOCKET;
    }
    session->finalizer_thread = CreateThread(NULL, 0, finalize_session_thread_proc, session, 0, &thread_id);
    if (!session->finalizer_thread) {
        int ok;
        audit_event(session->host, session, "INTEGRITY_WARNING", "CreateThread for route finalizer failed; using synchronous fallback");
        ok = finalize_session(session, session->finalize_reason);
        InterlockedExchange(&session->finalize_state, 2);
        return ok;
    }
    audit_event(session->host, session, "FINALIZATION_QUEUED", "Route detached from RTP hot path; MXF finalization continues on dedicated worker");
    return 1;
}

static void abort_session(RecorderSession *session, const char *reason) {
    if (!session || session->finalized) return;
    audit_event(session->host, session, "CONNECTION_LOST", reason ? reason : "Session aborted");
    if (session->shared_group) {
        if (session->appsrc) {
            GstFlowReturn flow = GST_FLOW_OK;
            g_signal_emit_by_name(session->appsrc, "end-of-stream", &flow);
        }
        if (session->rtp_socket != INVALID_SOCKET) closesocket(session->rtp_socket);
        session->rtp_socket = INVALID_SOCKET;
        session->finalized = 1;
        session->final_ok = 0;
        session->failed = 1;
        InterlockedExchange(&session->finalize_state, 2);
        maybe_finalize_shared_group(session->shared_group);
        return;
    }
    if (session->pipeline) gst_element_set_state(session->pipeline, GST_STATE_NULL);
    storage_writer_abort(&session->writer);
    if (session->rtp_socket != INVALID_SOCKET) closesocket(session->rtp_socket);
    session->rtp_socket = INVALID_SOCKET;
    destroy_pipeline(session);
    session->finalized = 1;
    session->final_ok = 0;
    session->failed = 1;
    InterlockedExchange(&session->finalize_state, 2);
}

static int all_sessions_finalized(RecorderHost *host) {
    int i;
    if (!host || host->session_count <= 0) return 0;
    for (i = 0; i < host->session_count; i++) if (!host->sessions[i].finalized) return 0;
    return 1;
}

static int poll_pipeline_error(RecorderSession *session) {
    GstMessage *msg;
    if (!session || session->shared_group || !session->bus || session->finalized || session->finalize_state != 0) return 0;
    while ((msg = gst_bus_pop_filtered(session->bus, GST_MESSAGE_ERROR | GST_MESSAGE_WARNING)) != NULL) {
        if (GST_MESSAGE_TYPE(msg) == GST_MESSAGE_ERROR) {
            GError *err = NULL;
            gchar *debug = NULL;
            char detail[2048];
            gst_message_parse_error(msg, &err, &debug);
            snprintf(detail, sizeof(detail), "GStreamer error: %s debug=%s", err ? err->message : "unknown", debug ? debug : "");
            audit_event(session->host, session, "INTEGRITY_FAILURE", detail);
            if (err) g_error_free(err);
            g_free(debug);
            gst_message_unref(msg);
            session->pipeline_error = 1;
            return 1;
        }
        gst_message_unref(msg);
    }
    return 0;
}

static int get_header_value(const char *request, const char *header, char *out, size_t out_size) {
    char needle[256];
    char *p, *end;
    size_t len;
    if (!request || !header || !out || out_size == 0) return 0;
    snprintf(needle, sizeof(needle), "\n%s:", header);
    p = stristr(request, needle);
    if (!p) {
        if (_strnicmp(request, header, strlen(header)) == 0 && request[strlen(header)] == ':') p = (char *)request - 1;
        else return 0;
    }
    p += strlen(needle);
    while (*p == ' ' || *p == '\t') p++;
    end = strstr(p, "\r\n");
    if (!end) end = strchr(p, '\n');
    if (!end) end = p + strlen(p);
    len = (size_t)(end - p);
    while (len && (p[len - 1] == '\r' || p[len - 1] == ' ' || p[len - 1] == '\t')) len--;
    if (len >= out_size) len = out_size - 1;
    memcpy(out, p, len);
    out[len] = 0;
    return 1;
}

static int parse_content_length(const char *headers) {
    char v[64];
    if (!get_header_value(headers, "Content-Length", v, sizeof(v))) return 0;
    return atoi(v);
}

static int send_all(SOCKET s, const char *data, int len) {
    int sent = 0;
    while (sent < len) {
        int n = send(s, data + sent, len - sent, 0);
        if (n <= 0) return 0;
        sent += n;
    }
    return 1;
}

static int send_rtsp_response(SOCKET s, int code, const char *reason, const char *cseq, const char *session, const char *extra) {
    char response[4096];
    int n = snprintf(response, sizeof(response),
        "RTSP/1.0 %d %s\r\nCSeq: %s\r\n%s%s%s%sContent-Length: 0\r\n\r\n",
        code, reason ? reason : "OK", cseq && *cseq ? cseq : "0",
        session && *session ? "Session: " : "", session && *session ? session : "", session && *session ? "\r\n" : "", extra ? extra : "");
    if (n <= 0 || n >= (int)sizeof(response)) return 0;
    return send_all(s, response, n);
}

static int parse_rtsp_request(char *request, char *method, size_t method_size, char *uri, size_t uri_size) {
    char version[32];
    if (sscanf(request, "%63s %2047s %31s", method, uri, version) != 3) return 0;
    method[method_size - 1] = 0;
    uri[uri_size - 1] = 0;
    return _strnicmp(version, "RTSP/1.0", 8) == 0;
}

static int extract_one_request(char *buffer, int *buffer_len, char *request, int request_capacity) {
    char *header_end;
    int header_len, content_length, total;
    if (!buffer || !buffer_len || *buffer_len <= 0) return 0;
    buffer[*buffer_len] = 0;
    header_end = strstr(buffer, "\r\n\r\n");
    if (!header_end) return 0;
    header_len = (int)(header_end - buffer) + 4;
    content_length = parse_content_length(buffer);
    if (content_length < 0 || content_length > request_capacity - header_len - 1) return -1;
    total = header_len + content_length;
    if (*buffer_len < total) return 0;
    if (total >= request_capacity) return -1;
    memcpy(request, buffer, total);
    request[total] = 0;
    memmove(buffer, buffer + total, *buffer_len - total);
    *buffer_len -= total;
    buffer[*buffer_len] = 0;
    return 1;
}

static RecorderSession *find_session_for_uri(RecorderHost *host, const char *uri) {
    int i;
    if (!host || !uri) return NULL;
    if (host->cfg.legacy_mode && host->session_count == 1) return &host->sessions[0];
    for (i = 0; i < host->session_count; i++) {
        const char *p = strstr(uri, host->sessions[i].cfg.route_key);
        if (p && strcmp(p, host->sessions[i].cfg.route_key) == 0) return &host->sessions[i];
    }
    return NULL;
}

static int request_session_matches(RecorderSession *session, const char *request) {
    char value[256] = {0};
    char *semicolon;
    if (!session || !session->setup_done) return 1;
    if (!get_header_value(request, "Session", value, sizeof(value))) return 0;
    semicolon = strchr(value, ';');
    if (semicolon) *semicolon = 0;
    return strcmp(value, session->session_id) == 0;
}

static void rearm_shared_route(RecorderSession *session, const char *reason) {
    if (!session || !session->shared_group) return;
    session->announced = 0;
    session->setup_done = 0;
    session->recording = 0;
    session->media_active = 0;
    session->service_enabled = 0;
    session->first_rtp_timestamp_valid = 0;
    session->last_timestamp_valid = 0;
    session->last_sequence_valid = 0;
    session->last_payload_len = 0;
    snprintf(session->session_id, sizeof(session->session_id), "P5-%lu-%02d-%llu",
        (unsigned long)GetCurrentProcessId(),
        (int)(session - session->host->sessions) + 1,
        (unsigned long long)GetTickCount64());
    audit_event(session->host, session, "ROUTE_REARMED",
        reason ? reason : "Shared MXF route rearmed for another RTSP call inside the same recording window");
}

static int handle_rtsp_request(RecorderHost *host, ClientConnection *client, char *request) {
    char method[64] = {0}, uri[2048] = {0}, cseq[64] = {0}, detail[4096] = {0}, extra[1024] = {0};
    char *body = strstr(request, "\r\n\r\n");
    RecorderSession *session = client->session;
    if (body) body += 4;
    if (!parse_rtsp_request(request, method, sizeof(method), uri, sizeof(uri))) {
        send_rtsp_response(client->socket, 400, "Bad Request", "0", NULL, NULL);
        return 1;
    }
    get_header_value(request, "CSeq", cseq, sizeof(cseq));
    if (_stricmp(method, "OPTIONS") == 0) {
        snprintf(extra, sizeof(extra), "Public: OPTIONS, ANNOUNCE, SETUP, RECORD, PAUSE, GET_PARAMETER, TEARDOWN\r\n");
        return send_rtsp_response(client->socket, 200, "OK", cseq, session ? session->session_id : NULL, extra);
    }
    if (_stricmp(method, "ANNOUNCE") == 0) {
        if (client->session) return send_rtsp_response(client->socket, 455, "Method Not Valid in This State", cseq, client->session->session_id, NULL);
        session = find_session_for_uri(host, uri);
        if (!session || session->finalized) {
            audit_event(host, NULL, "ROUTE_REJECTED", uri);
            return send_rtsp_response(client->socket, 404, "Not Found", cseq, NULL, NULL);
        }
        if (session->client_index >= 0 || session->announced) {
            audit_event(host, session, "ROUTE_COLLISION", "Second RTSP client attempted to claim an active route");
            return send_rtsp_response(client->socket, 453, "Not Enough Bandwidth", cseq, NULL, NULL);
        }
        if (!body || (!stristr(body, "PCMA/8000") && !stristr(body, "RTP/AVP 8"))) {
            audit_event(host, session, "INTEGRITY_WARNING", "ANNOUNCE rejected: SDP does not declare PCMA/8000 payload 8");
            return send_rtsp_response(client->socket, 415, "Unsupported Media Type", cseq, NULL, NULL);
        }
        client->session = session;
        session->client_index = (int)(client - host->clients);
        session->announced = 1;
        snprintf(detail, sizeof(detail), "ANNOUNCE route=%s uri=%s service=%s endpoint=%s media_flow=%s rtp_port=%d",
            session->cfg.route_key, uri, session->cfg.service_id, session->cfg.endpoint_id, session->cfg.media_flow, session->cfg.rtp_port);
        audit_event(host, session, "SESSION_OPEN", detail);
        audit_event(host, session, "ROUTE_BOUND", "RTSP connection bound to preconfigured logical track and RTP socket");
        return send_rtsp_response(client->socket, 200, "OK", cseq, session->session_id, NULL);
    }
    if (!session) return send_rtsp_response(client->socket, 454, "Session Not Found", cseq, NULL, NULL);
    if (_stricmp(method, "SETUP") == 0) {
        if (!session->announced || session->setup_done) return send_rtsp_response(client->socket, 455, "Method Not Valid in This State", cseq, session->session_id, NULL);
        session->setup_done = 1;
        snprintf(extra, sizeof(extra), "Transport: RTP/AVP;unicast;server_port=%d-%d;mode=record\r\n", session->cfg.rtp_port, session->cfg.rtp_port + 1);
        snprintf(detail, sizeof(detail), "SETUP route=%s rtp_port=%d", session->cfg.route_key, session->cfg.rtp_port);
        audit_event(host, session, "SETUP", detail);
        if (_stricmp(session->cfg.session_kind, "radio") == 0) {
            session->service_enabled = 1;
            audit_event(host, session, "SERVICE_ENABLED", "Radio service/frequency session remains open across PAUSE periods");
        }
        audit_event(host, session, "READY", "Session ready for RECORD on isolated route/writer");
        return send_rtsp_response(client->socket, 200, "OK", cseq, session->session_id, extra);
    }
    if (!request_session_matches(session, request)) {
        audit_event(host, session, "INTEGRITY_WARNING", "RTSP request rejected because Session header is missing or does not match route session");
        return send_rtsp_response(client->socket, 454, "Session Not Found", cseq, session->session_id, NULL);
    }
    if (_stricmp(method, "RECORD") == 0) {
        if (!session->setup_done) return send_rtsp_response(client->socket, 455, "Method Not Valid in This State", cseq, session->session_id, NULL);
        if (!session->recording) {
            session->recording = 1;
            session->record_commands++;
            audit_event(host, session, "RECORD", "Media gate opened on isolated session route");
            audit_activity_signal(session, 1);
        }
        return send_rtsp_response(client->socket, 200, "OK", cseq, session->session_id, NULL);
    }
    if (_stricmp(method, "PAUSE") == 0) {
        if (!session->setup_done) return send_rtsp_response(client->socket, 455, "Method Not Valid in This State", cseq, session->session_id, NULL);
        if (session->recording) {
            session->recording = 0;
            session->pause_commands++;
            if (session->media_active) {
                audit_media_boundary(session, "MEDIA_END", "PAUSE closed media interval; session/file remain open");
                session->media_active = 0;
                session->media_intervals_closed++;
            }
            audit_activity_signal(session, 0);
            audit_event(host, session, "PAUSE", "Media gate closed without affecting other sessions");
            if (!maybe_rotate_window_after_pause(session)) {
                host->server_failed = 1;
                audit_event(host, session, "INTEGRITY_FAILURE", "Window rotation failed at PAUSE boundary");
                return send_rtsp_response(client->socket, 500, "Internal Server Error", cseq, session->session_id, NULL);
            }
        }
        return send_rtsp_response(client->socket, 200, "OK", cseq, session->session_id, NULL);
    }
    if (_stricmp(method, "GET_PARAMETER") == 0) {
        if (!session->setup_done) return send_rtsp_response(client->socket, 455, "Method Not Valid in This State", cseq, session->session_id, NULL);
        session->keepalive_requests++;
        return send_rtsp_response(client->socket, 200, "OK", cseq, session->session_id, NULL);
    }
    if (_stricmp(method, "TEARDOWN") == 0) {
        int was_recording;
        if (!session->setup_done) return send_rtsp_response(client->socket, 455, "Method Not Valid in This State", cseq, session->session_id, NULL);
        was_recording = session->recording;
        session->recording = 0;
        if (session->media_active) {
            audit_media_boundary(session, "MEDIA_END", "TEARDOWN closed active media interval");
            session->media_active = 0;
            session->media_intervals_closed++;
        }
        if (was_recording) audit_activity_signal(session, 0);
        if (session->service_enabled) {
            audit_event(host, session, "SERVICE_DISABLED", "Service disabled; only this route will finalize");
            session->service_enabled = 0;
        }
        session->teardown_received = 1;
        audit_event(host, session, "TEARDOWN",
            session->shared_group
                ? "Graceful RTSP teardown; shared MXF track remains armed and route will be reusable"
                : "Graceful route-local RTSP teardown");
        send_rtsp_response(client->socket, 200, "OK", cseq, session->session_id, NULL);
        if (session->shared_group) {
            rearm_shared_route(session, "TEARDOWN released reusable shared-MXF route");
        } else {
            if (!begin_finalize_session(session, "TEARDOWN finalized only this session route")) host->server_failed = 1;
        }
        client->close_after_response = 1;
        return 1;
    }
    return send_rtsp_response(client->socket, 405, "Method Not Allowed", cseq, session->session_id, NULL);
}

static guint64 shared_group_now_ns(SharedMuxGroup *group) {
    ULONGLONG elapsed_ms;
    if (!group || !group->started_tick_ms) return 0;
    elapsed_ms = GetTickCount64() - group->started_tick_ms;
    return ((guint64)elapsed_ms) * GST_MSECOND;
}

static int push_shared_gap_buffer(RecorderSession *session, guint64 target_ns) {
    guint64 start_ns;

    if (!session || !session->appsrc || !session->shared_group) return 0;
    start_ns = session->shared_timeline_position_ns;
    if (target_ns <= start_ns) return 1;

    /*
     * mxf_alaw_write_func maps every GAP buffer to exactly one zero-payload
     * structural edit unit. Its A-law edit rate is 10/1 (100 ms), so never
     * send an arbitrary-duration GAP here: doing so would make one KLV claim
     * e.g. 20 ms of source time while pad->pos advances a full 100 ms.
     *
     * Accumulate sub-edit-unit wall-clock progress and emit only complete
     * 100 ms units. Any remainder stays pending in shared_timeline_position_ns
     * until later media/gap progress reaches the next structural boundary.
     */
    while (target_ns - start_ns >= SHARED_MXF_AUDIO_EDIT_UNIT_NS) {
        GstBuffer *gap = gst_buffer_new();
        GstFlowReturn flow = GST_FLOW_ERROR;
        if (!gap) return 0;

        GST_BUFFER_PTS(gap) = start_ns;
        GST_BUFFER_DTS(gap) = GST_CLOCK_TIME_NONE;
        GST_BUFFER_DURATION(gap) = SHARED_MXF_AUDIO_EDIT_UNIT_NS;
        GST_BUFFER_FLAG_SET(gap, GST_BUFFER_FLAG_GAP);
        GST_BUFFER_FLAG_SET(gap, GST_BUFFER_FLAG_DROPPABLE);

        g_signal_emit_by_name(session->appsrc, "push-buffer", gap, &flow);
        gst_buffer_unref(gap);
        if (flow != GST_FLOW_OK) return 0;

        session->shared_samples_queued += SHARED_MXF_AUDIO_SAMPLES_PER_EDIT_UNIT;
        start_ns += SHARED_MXF_AUDIO_EDIT_UNIT_NS;
        session->shared_timeline_position_ns = start_ns;
    }
    return 1;
}

static int push_shared_structural_samples(
    RecorderSession *session,
    unsigned long long sample_count
) {
    while (sample_count > 0) {
        unsigned long long chunk =
            sample_count > SHARED_MXF_AUDIO_SAMPLES_PER_EDIT_UNIT
                ? SHARED_MXF_AUDIO_SAMPLES_PER_EDIT_UNIT
                : sample_count;
        GstBuffer *gap;
        GstFlowReturn flow = GST_FLOW_ERROR;
        guint64 duration_ns;

        if (!session || !session->appsrc || !session->shared_group)
            return 0;
        gap = gst_buffer_new();
        if (!gap) return 0;

        duration_ns = gst_util_uint64_scale(
            (guint64)chunk, GST_SECOND, 8000);

        GST_BUFFER_PTS(gap) = session->shared_timeline_position_ns;
        GST_BUFFER_DTS(gap) = GST_CLOCK_TIME_NONE;
        GST_BUFFER_DURATION(gap) = duration_ns;
        GST_BUFFER_FLAG_SET(gap, GST_BUFFER_FLAG_GAP);
        GST_BUFFER_FLAG_SET(gap, GST_BUFFER_FLAG_DROPPABLE);

        g_signal_emit_by_name(session->appsrc, "push-buffer", gap, &flow);
        gst_buffer_unref(gap);
        if (flow != GST_FLOW_OK) return 0;

        session->shared_samples_queued += chunk;
        session->shared_timeline_position_ns += duration_ns;
        sample_count -= chunk;
    }
    return 1;
}

static int align_shared_group_tail(SharedMuxGroup *group) {
    unsigned long long target_samples = 0;
    unsigned long long edit_units;
    int i;
    char detail[512];

    if (!group || !group->host || group->finalized) return 1;

    for (i = 0; i < group->session_count; i++) {
        RecorderSession *session =
            &group->host->sessions[group->session_indices[i]];
        if (session->shared_samples_queued > target_samples)
            target_samples = session->shared_samples_queued;
    }

    if (target_samples == 0) return 1;

    edit_units =
        (target_samples + SHARED_MXF_AUDIO_SAMPLES_PER_EDIT_UNIT - 1) /
        SHARED_MXF_AUDIO_SAMPLES_PER_EDIT_UNIT;
    target_samples = edit_units * SHARED_MXF_AUDIO_SAMPLES_PER_EDIT_UNIT;

    for (i = 0; i < group->session_count; i++) {
        RecorderSession *session =
            &group->host->sessions[group->session_indices[i]];
        unsigned long long missing;

        if (session->finalized) continue;
        if (session->shared_samples_queued > target_samples) {
            audit_event(group->host, session, "INTEGRITY_FAILURE",
                "Shared MXF sample counter exceeded common close target");
            return 0;
        }

        missing = target_samples - session->shared_samples_queued;
        if (missing > 0 &&
            !push_shared_structural_samples(session, missing)) {
            audit_event(group->host, session, "INTEGRITY_FAILURE",
                "Could not align shared-MXF tail with structural A-law padding");
            return 0;
        }
    }

    snprintf(detail, sizeof(detail),
        "category=%s target_samples=%llu edit_units=%llu tracks=%d",
        group->category,
        target_samples,
        edit_units,
        group->session_count);
    audit_event(group->host, NULL, "SHARED_MXF_TAIL_ALIGNED", detail);
    return 1;
}

static int align_all_shared_group_tails(RecorderHost *host) {
    int g;
    if (!host || !host->cfg.shared_mxf_by_output) return 1;
    for (g = 0; g < host->shared_group_count; g++) {
        if (!align_shared_group_tail(&host->shared_groups[g]))
            return 0;
    }
    return 1;
}

static int advance_idle_shared_tracks(
    SharedMuxGroup *group,
    RecorderSession *active,
    guint64 target_end_ns
) {
    int i;
    if (!group || !group->host) return 0;

    for (i = 0; i < group->session_count; i++) {
        RecorderSession *candidate =
            &group->host->sessions[group->session_indices[i]];

        if (candidate == active) continue;
        if (candidate->finalized) continue;

        /*
         * A route already under RTSP RECORD is expected to deliver its own RTP.
         * Do not pre-fill that route with a GAP because a sibling leg of the
         * same SIP call may arrive a few milliseconds later with real media.
         */
        if (candidate->recording) continue;

        if (!push_shared_gap_buffer(candidate, target_end_ns)) {
            audit_event(candidate->host, candidate, "INTEGRITY_FAILURE",
                "Could not advance idle shared-MXF track with GAP buffer");
            candidate->pipeline_error = 1;
            return 0;
        }
    }
    return 1;
}

static int push_rtp_payload(RecorderSession *session, const unsigned char *payload, int payload_len, guint32 timestamp) {
    GstBuffer *buffer;
    GstFlowReturn flow = GST_FLOW_ERROR;
    guint32 delta;
    guint64 pts_ns, duration_ns, end_ns;

    if (!session->first_rtp_timestamp_valid) {
        session->first_rtp_timestamp = timestamp;
        session->first_rtp_timestamp_valid = 1;
    }
    delta = timestamp - session->first_rtp_timestamp;
    duration_ns = gst_util_uint64_scale((guint64)payload_len, GST_SECOND, 8000);

    if (session->shared_group) {
        /*
         * Shared MXF uses the window's monotonic clock. This preserves real
         * temporal gaps between calls/bursts without writing synthetic audio.
         */
        pts_ns = shared_group_now_ns(session->shared_group);
        if (pts_ns < session->shared_timeline_position_ns)
            pts_ns = session->shared_timeline_position_ns;
        end_ns = pts_ns + duration_ns;

        /* Advance this sparse track up to the real media start. */
        if (!push_shared_gap_buffer(session, pts_ns)) return 0;

        /*
         * Keep completely idle sibling tracks moving past this buffer so the
         * aggregator/mux never waits forever for an unused configured track.
         */
        if (!advance_idle_shared_tracks(session->shared_group, session, end_ns))
            return 0;
    } else {
        pts_ns = gst_util_uint64_scale((guint64)delta, GST_SECOND, 8000);
        end_ns = pts_ns + duration_ns;
    }

    buffer = gst_buffer_new_allocate(NULL, payload_len, NULL);
    if (!buffer) return 0;
    gst_buffer_fill(buffer, 0, payload, payload_len);
    GST_BUFFER_PTS(buffer) = pts_ns;
    GST_BUFFER_DTS(buffer) = GST_CLOCK_TIME_NONE;
    GST_BUFFER_DURATION(buffer) = duration_ns;

    g_signal_emit_by_name(session->appsrc, "push-buffer", buffer, &flow);
    gst_buffer_unref(buffer);

    if (flow == GST_FLOW_OK && session->shared_group) {
        session->media_samples_written += (unsigned long long)payload_len;
        session->shared_samples_queued += (unsigned long long)payload_len;
        session->shared_timeline_position_ns = end_ns;
    }
    return flow == GST_FLOW_OK;
}

static int handle_rtp_packet(RecorderSession *session, unsigned char *packet, int len) {
    int cc, has_ext, has_padding, offset, payload_len, pt;
    guint16 seq;
    guint32 ts;
    if (!session || session->finalized) return 1;
    if (len < 12) {
        session->rtp_packets_malformed++;
        audit_event(session->host, session, "RTP_MALFORMED_DROPPED", "RTP packet shorter than fixed header");
        return 1;
    }
    if ((packet[0] >> 6) != 2) {
        session->rtp_packets_malformed++;
        audit_event(session->host, session, "RTP_MALFORMED_DROPPED", "Unsupported RTP version");
        return 1;
    }
    cc = packet[0] & 0x0f;
    has_ext = (packet[0] & 0x10) != 0;
    has_padding = (packet[0] & 0x20) != 0;
    pt = packet[1] & 0x7f;
    if (pt != 8) {
        session->rtp_packets_wrong_payload_type++;
        audit_event(session->host, session, "RTP_UNSUPPORTED_PAYLOAD_DROPPED", "Only PCMA payload type 8 is accepted in this PoC phase");
        return 1;
    }
    offset = 12 + cc * 4;
    if (offset > len) {
        session->rtp_packets_malformed++;
        audit_event(session->host, session, "RTP_MALFORMED_DROPPED", "RTP CSRC list exceeds packet length");
        return 1;
    }
    if (has_ext) {
        int words;
        if (offset + 4 > len) {
            session->rtp_packets_malformed++;
            audit_event(session->host, session, "RTP_MALFORMED_DROPPED", "RTP extension header truncated");
            return 1;
        }
        words = ((int)packet[offset + 2] << 8) | packet[offset + 3];
        offset += 4 + words * 4;
        if (offset > len) {
            session->rtp_packets_malformed++;
            audit_event(session->host, session, "RTP_MALFORMED_DROPPED", "RTP extension data exceeds packet length");
            return 1;
        }
    }
    payload_len = len - offset;
    if (has_padding && payload_len > 0) {
        int padding = packet[len - 1];
        if (padding <= 0 || padding > payload_len) {
            session->rtp_packets_malformed++;
            audit_event(session->host, session, "RTP_MALFORMED_DROPPED", "Invalid RTP padding length");
            return 1;
        }
        payload_len -= padding;
    }
    if (payload_len <= 0) {
        session->rtp_packets_malformed++;
        audit_event(session->host, session, "RTP_MALFORMED_DROPPED", "RTP packet has no payload");
        return 1;
    }
    seq = (guint16)(((guint16)packet[2] << 8) | packet[3]);
    ts = ((guint32)packet[4] << 24) | ((guint32)packet[5] << 16) | ((guint32)packet[6] << 8) | packet[7];
    session->rtp_packets_received++;
    if (session->rtp_packets_received == 1) {
        char route_detail[512];
        snprintf(route_detail, sizeof(route_detail), "First RTP packet routed by bound UDP socket rtp_port=%d route=%s", session->cfg.rtp_port, session->cfg.route_key);
        audit_event(session->host, session, "RTP_ROUTE_ACTIVE", route_detail);
    }
    if (session->last_sequence_valid) {
        guint16 expected = (guint16)(session->last_sequence + 1);
        guint16 forward = (guint16)(seq - expected);
        guint16 backward = (guint16)(session->last_sequence - seq);
        if (seq == session->last_sequence) {
            char detail[256];
            session->rtp_packets_duplicate++;
            snprintf(detail, sizeof(detail), "Duplicate RTP sequence dropped seq=%u", seq);
            audit_event(session->host, session, "RTP_DUPLICATE_DROPPED", detail);
            return 1;
        }
        if (seq != expected) {
            char detail[256];
            if (forward < 0x8000u) {
                guint16 missing = forward;
                session->rtp_sequence_gap_packets += missing;
                snprintf(detail, sizeof(detail), "RTP sequence gap expected=%u received=%u inferred_missing=%u", expected, seq, missing);
                audit_event(session->host, session, "GAP_START", detail);
                audit_event(session->host, session, "GAP_END", "RTP packet flow resumed after sequence gap");
            } else {
                session->rtp_packets_out_of_order++;
                session->rtp_packets_late += backward ? backward : 1;
                snprintf(detail, sizeof(detail), "Late/out-of-order RTP packet dropped last=%u received=%u", session->last_sequence, seq);
                audit_event(session->host, session, "RTP_OUT_OF_ORDER_DROPPED", detail);
                return 1;
            }
        }
    }
    if (session->last_timestamp_valid && session->media_active && session->recording) {
        guint32 expected_ts = session->last_timestamp + (guint32)session->last_payload_len;
        if (ts != expected_ts) {
            guint32 delta = ts - expected_ts;
            char detail[256];
            session->rtp_timestamp_discontinuities++;
            if (delta < 8000u) session->rtp_timestamp_gap_samples += delta;
            snprintf(detail, sizeof(detail), "RTP timestamp discontinuity expected=%u received=%u delta_samples=%u", expected_ts, ts, delta);
            audit_event(session->host, session, "RTP_TIMESTAMP_DISCONTINUITY", detail);
        }
    }
    session->last_sequence = seq;
    session->last_sequence_valid = 1;
    session->last_timestamp = ts;
    session->last_timestamp_valid = 1;
    session->last_payload_len = payload_len;
    if (!session->recording) {
        session->rtp_packets_ignored_not_recording++;
        return 1;
    }
    if (!session->media_active) {
        audit_media_boundary(session, "MEDIA_START", "First RTP payload accepted on route after RECORD");
        session->media_active = 1;
        session->media_intervals_started++;
    }
    if (!push_rtp_payload(session, packet + offset, payload_len, ts)) {
        audit_event(session->host, session, "INTEGRITY_FAILURE", "appsrc push-buffer failed");
        session->pipeline_error = 1;
        return 0;
    }
    session->rtp_packets_recorded++;
    session->rtp_payload_bytes_recorded += payload_len;
    return 1;
}

static void close_client(RecorderHost *host, int index, int unexpected) {
    ClientConnection *client;
    RecorderSession *session;
    if (!host || index < 0 || index >= MAX_CLIENTS) return;
    client = &host->clients[index];
    if (client->socket == INVALID_SOCKET) return;
    session = client->session;
    closesocket(client->socket);
    client->socket = INVALID_SOCKET;
    client->buffer_len = 0;
    client->close_after_response = 0;
    client->session = NULL;
    if (session && session->client_index == index) session->client_index = -1;
    if (unexpected && session && !session->finalized) {
        if (session->shared_group) {
            if (session->media_active) {
                audit_media_boundary(session, "MEDIA_END", "Unexpected RTSP disconnect closed active media interval");
                session->media_active = 0;
                session->media_intervals_closed++;
            }
            if (session->recording) audit_activity_signal(session, 0);
            session->recording = 0;
            if (session->service_enabled) {
                audit_event(host, session, "SERVICE_DISABLED", "Unexpected RTSP disconnect released shared route");
                session->service_enabled = 0;
            }
            audit_event(host, session, "CONNECTION_LOST",
                "RTSP client disconnected; shared MXF route was rearmed without closing the category writer");
            rearm_shared_route(session, "Unexpected disconnect released reusable shared-MXF route");
        } else {
            abort_session(session, "RTSP TCP connection closed without TEARDOWN; route moved to recovery-required state");
            host->server_failed = 1;
        }
    }
}

static int accept_client(RecorderHost *host) {
    SOCKET s;
    int i;
    s = accept(host->listen_socket, NULL, NULL);
    if (s == INVALID_SOCKET) return 0;
    for (i = 0; i < MAX_CLIENTS; i++) {
        if (host->clients[i].socket == INVALID_SOCKET) {
            host->clients[i].socket = s;
            host->clients[i].buffer_len = 0;
            host->clients[i].session = NULL;
            host->clients[i].close_after_response = 0;
            audit_event(host, NULL, "CONNECTED", "RTSP TCP client accepted; route not yet bound");
            return 1;
        }
    }
    closesocket(s);
    audit_event(host, NULL, "CAPACITY_REJECTED", "RTSP client rejected because MAX_CLIENTS was reached");
    return 0;
}

static void write_ready_file(RecorderHost *host) {
    FILE *fp;
    char now[64];
    int i;
    if (!host || !host->cfg.ready_file[0]) return;
    fp = fopen(host->cfg.ready_file, "wb");
    if (!fp) return;
    storage_utc_now(now, sizeof(now));
    fprintf(fp, "{\n  \"ready\": true,\n  \"schema\": \"recorder-poc.multisession-ready.v1\",\n  \"ts_utc\": \"%s\",\n  \"bind_ip\": \"%s\",\n  \"rtsp_port\": %d,\n  \"session_count\": %d,\n  \"sessions\": [\n", now, host->cfg.bind_ip, host->cfg.rtsp_port, host->session_count);
    for (i = 0; i < host->session_count; i++) {
        RecorderSession *s = &host->sessions[i];
        fprintf(fp, "    {\"route_key\":\"%s\",\"rtp_port\":%d,\"logical_track_uuid\":\"%s\",\"track_instance_uuid\":\"%s\",\"file_id\":\"%s\",\"track_index\":%d,\"category\":\"%s\",\"output_final\":\"%s\"}%s\n",
            s->cfg.route_key, s->cfg.rtp_port, s->cfg.logical_uuid, s->cfg.instance_uuid,
            s->cfg.file_id, s->track_index, s->cfg.session_kind, s->cfg.output_final,
            i + 1 == host->session_count ? "" : ",");
    }
    fprintf(fp, "  ]\n}\n");
    fclose(fp);
}

static unsigned long long unix_time_ms(void) {
    FILETIME ft;
    ULARGE_INTEGER value;
    const unsigned long long EPOCH_DIFF_100NS = 116444736000000000ULL;
    GetSystemTimeAsFileTime(&ft);
    value.LowPart = ft.dwLowDateTime;
    value.HighPart = ft.dwHighDateTime;
    if (value.QuadPart <= EPOCH_DIFF_100NS) return 0;
    return (value.QuadPart - EPOCH_DIFF_100NS) / 10000ULL;
}

static int topology_change_due(RecorderHost *host, unsigned long long *revision_out) {
    FILE *fp;
    unsigned long long revision = 0, effective_ms = 0;
    if (!host || !host->cfg.topology_watch_file[0]) return 0;
    fp = fopen(host->cfg.topology_watch_file, "rb");
    if (!fp) return 0;
    if (fscanf(fp, "%llu\t%llu", &revision, &effective_ms) != 2) {
        fclose(fp);
        return 0;
    }
    fclose(fp);
    if (revision <= host->cfg.topology_revision) return 0;
    if (unix_time_ms() < effective_ms) return 0;
    if (revision_out) *revision_out = revision;
    return 1;
}

static int shutdown_requested_by_file(RecorderHost *host) {
    DWORD attrs;
    if (!host || !host->cfg.shutdown_watch_file[0]) return 0;
    attrs = GetFileAttributesA(host->cfg.shutdown_watch_file);
    return attrs != INVALID_FILE_ATTRIBUTES && !(attrs & FILE_ATTRIBUTE_DIRECTORY);
}

static int run_server(RecorderHost *host) {
    ULONGLONG started = GetTickCount64();
    int timeout_finalization_started = 0;
    int i;
    write_ready_file(host);
    g_print("RECORDER MULTI READY rtsp=%s:%d sessions=%d\n", host->cfg.bind_ip, host->cfg.rtsp_port, host->session_count);
    while (!host->shutdown_requested) {
        fd_set readfds;
        struct timeval tv;
        int sel;
        FD_ZERO(&readfds);
        FD_SET(host->listen_socket, &readfds);
        for (i = 0; i < MAX_CLIENTS; i++) if (host->clients[i].socket != INVALID_SOCKET) FD_SET(host->clients[i].socket, &readfds);
        for (i = 0; i < host->session_count; i++) if (host->sessions[i].rtp_socket != INVALID_SOCKET && !host->sessions[i].finalized && host->sessions[i].finalize_state == 0) FD_SET(host->sessions[i].rtp_socket, &readfds);
        tv.tv_sec = 0;
        tv.tv_usec = 100000;
        sel = select(0, &readfds, NULL, NULL, &tv);
        if (sel == SOCKET_ERROR) {
            g_printerr("select failed WSA=%d\n", WSAGetLastError());
            return 0;
        }
        if (FD_ISSET(host->listen_socket, &readfds)) accept_client(host);
        for (i = 0; i < MAX_CLIENTS; i++) {
            ClientConnection *client = &host->clients[i];
            if (client->socket == INVALID_SOCKET || !FD_ISSET(client->socket, &readfds)) continue;
            {
                int n = recv(client->socket, client->buffer + client->buffer_len, RTSP_BUFFER_SIZE - client->buffer_len, 0);
                if (n <= 0) {
                    close_client(host, i, 1);
                    continue;
                }
                client->buffer_len += n;
                if (client->buffer_len >= RTSP_BUFFER_SIZE) {
                    if (client->session) audit_event(host, client->session, "INTEGRITY_FAILURE", "RTSP receive buffer overflow");
                    close_client(host, i, 1);
                    continue;
                }
                while (client->socket != INVALID_SOCKET) {
                    char one_request[RTSP_BUFFER_SIZE + 1];
                    int ex = extract_one_request(client->buffer, &client->buffer_len, one_request, sizeof(one_request));
                    if (ex == 0) break;
                    if (ex < 0) {
                        if (client->session) audit_event(host, client->session, "INTEGRITY_FAILURE", "Invalid RTSP Content-Length/request size");
                        close_client(host, i, 1);
                        break;
                    }
                    if (!handle_rtsp_request(host, client, one_request)) {
                        close_client(host, i, 1);
                        break;
                    }
                    if (client->close_after_response) {
                        close_client(host, i, 0);
                        break;
                    }
                }
            }
        }
        for (i = 0; i < host->session_count; i++) {
            RecorderSession *session = &host->sessions[i];
            if (session->rtp_socket != INVALID_SOCKET && !session->finalized && session->finalize_state == 0 && FD_ISSET(session->rtp_socket, &readfds)) {
                unsigned char packet[RTP_PACKET_MAX];
                int n = recvfrom(session->rtp_socket, (char *)packet, sizeof(packet), 0, NULL, NULL);
                if (n > 0 && !handle_rtp_packet(session, packet, n)) {
                    abort_session(session, "RTP pipeline failure");
                    host->server_failed = 1;
                }
            }
            if (!session->finalized && poll_pipeline_error(session)) {
                abort_session(session, "GStreamer pipeline failure");
                host->server_failed = 1;
            }
        }
        if (host->cfg.shared_mxf_by_output) {
            int g;
            for (g = 0; g < host->shared_group_count; g++) {
                if (poll_shared_group_error(&host->shared_groups[g])) {
                    int j;
                    host->server_failed = 1;
                    for (j = 0; j < host->shared_groups[g].session_count; j++) {
                        RecorderSession *s = &host->sessions[host->shared_groups[g].session_indices[j]];
                        if (!s->finalized) abort_session(s, "Shared MXF pipeline failure");
                    }
                }
            }
        }
        if (all_sessions_finalized(host)) host->shutdown_requested = 1;

        if (!timeout_finalization_started && shutdown_requested_by_file(host)) {
            timeout_finalization_started = 1;
            audit_event(host, NULL, "SHUTDOWN_REQUESTED",
                "External shutdown requested; gracefully finalizing every active recorder route");
            if (host->cfg.shared_mxf_by_output &&
                !align_all_shared_group_tails(host)) {
                audit_event(host, NULL, "INTEGRITY_FAILURE",
                    "Could not align shared-MXF tracks before external shutdown");
                host->server_failed = 1;
            }
            for (i = 0; i < host->session_count; i++) {
                if (!host->sessions[i].finalized && host->sessions[i].finalize_state == 0) {
                    begin_finalize_session(&host->sessions[i],
                        "External recorder shutdown requested");
                }
            }
        }

        if (!timeout_finalization_started && host->cfg.shared_mxf_by_output) {
            unsigned long long requested_revision = 0;
            if (topology_change_due(host, &requested_revision)) {
                char detail[256];
                timeout_finalization_started = 1;
                snprintf(detail, sizeof(detail),
                    "Topology revision changed current=%llu requested=%llu; closing shared MXF window",
                    host->cfg.topology_revision, requested_revision);
                audit_event(host, NULL, "TOPOLOGY_CHANGE_ROTATION", detail);
                if (!align_all_shared_group_tails(host)) {
                    audit_event(host, NULL, "INTEGRITY_FAILURE",
                        "Could not align shared-MXF tracks before topology rotation");
                    host->server_failed = 1;
                }
                for (i = 0; i < host->session_count; i++) {
                    if (!host->sessions[i].finalized && host->sessions[i].finalize_state == 0) {
                        begin_finalize_session(&host->sessions[i], "Topology change requested shared MXF rollover");
                    }
                }
            }
        }
        if (!timeout_finalization_started && (int)((GetTickCount64() - started) / 1000) >= host->cfg.max_seconds) {
            timeout_finalization_started = 1;
            audit_event(host, NULL,
                host->cfg.shared_mxf_by_output ? "WINDOW_ROTATION_REQUESTED" : "CONNECTION_SUSPECT",
                host->cfg.shared_mxf_by_output
                    ? "Scheduled shared-MXF window boundary reached; remaining routes queued for normal finalization"
                    : "Recorder host max-seconds timeout reached; remaining routes queued for finalization");
            if (host->cfg.shared_mxf_by_output &&
                !align_all_shared_group_tails(host)) {
                audit_event(host, NULL, "INTEGRITY_FAILURE",
                    "Could not align shared-MXF tracks before scheduled close");
                host->server_failed = 1;
            }
            for (i = 0; i < host->session_count; i++) {
                if (!host->sessions[i].finalized && host->sessions[i].finalize_state == 0) {
                    begin_finalize_session(&host->sessions[i],
                        host->cfg.shared_mxf_by_output
                            ? "Scheduled recording window rotation"
                            : "Host timeout finalized remaining session");
                    if (!host->cfg.shared_mxf_by_output) host->server_failed = 1;
                }
            }
        }
    }
    return 1;
}

static int open_host_network(RecorderHost *host) {
    if (!open_bound_socket(host->cfg.bind_ip, host->cfg.rtsp_port, SOCK_STREAM, IPPROTO_TCP, &host->listen_socket)) {
        g_printerr("Could not bind RTSP TCP %s:%d WSA=%d.\n", host->cfg.bind_ip, host->cfg.rtsp_port, WSAGetLastError());
        return 0;
    }
    if (listen(host->listen_socket, MAX_CLIENTS) == SOCKET_ERROR) {
        g_printerr("Could not listen RTSP socket WSA=%d.\n", WSAGetLastError());
        return 0;
    }
    return 1;
}

static void print_summaries(RecorderHost *host) {
    int i, closed = 0, failed = 0;
    unsigned long long received = 0, recorded = 0, ignored = 0;
    for (i = 0; i < host->session_count; i++) {
        RecorderSession *s = &host->sessions[i];
        if (s->finalized && s->final_ok) closed++;
        if (s->failed || !s->final_ok) failed++;
        received += s->rtp_packets_received;
        recorded += s->rtp_packets_recorded;
        ignored += s->rtp_packets_ignored_not_recording;
        g_print("RECORDER SESSION SUMMARY route=%s session=%s packets_received=%llu packets_recorded=%llu payload_bytes=%llu shared_samples_queued=%llu sequence_gap_packets=%llu duplicates=%llu out_of_order=%llu malformed=%llu wrong_pt=%llu timestamp_discontinuities=%llu timestamp_gap_samples=%llu mux_bytes=%llu final=%s record_commands=%u pause_commands=%u keepalives=%u media_intervals_started=%u media_intervals_closed=%u packets_ignored_not_recording=%llu teardown=%d window_open_count=%d windows_closed_complete=%d rotations_completed=%d segment_sequence=%u\n",
            s->cfg.route_key, s->session_id, s->rtp_packets_received, s->rtp_packets_recorded, s->rtp_payload_bytes_recorded,
            s->shared_samples_queued, s->rtp_sequence_gap_packets, s->rtp_packets_duplicate, s->rtp_packets_out_of_order, s->rtp_packets_malformed,
            s->rtp_packets_wrong_payload_type, s->rtp_timestamp_discontinuities, s->rtp_timestamp_gap_samples,
            s->mux_bytes_written, s->final_ok ? "CLOSED_COMPLETE" : "RECOVERY_REQUIRED",
            s->record_commands, s->pause_commands, s->keepalive_requests, s->media_intervals_started, s->media_intervals_closed,
            s->rtp_packets_ignored_not_recording, s->teardown_received, s->window_open_count, s->windows_closed_complete, s->rotations_completed, s->cfg.segment_sequence);
        if (host->session_count == 1) {
            g_print("RECORDER SUMMARY packets_received=%llu packets_recorded=%llu payload_bytes=%llu shared_samples_queued=%llu sequence_gap_packets=%llu duplicates=%llu out_of_order=%llu malformed=%llu wrong_pt=%llu timestamp_discontinuities=%llu timestamp_gap_samples=%llu mux_bytes=%llu final=%s record_commands=%u pause_commands=%u keepalives=%u media_intervals_started=%u media_intervals_closed=%u packets_ignored_not_recording=%llu teardown=%d window_open_count=%d windows_closed_complete=%d rotations_completed=%d segment_sequence=%u\n",
                s->rtp_packets_received, s->rtp_packets_recorded, s->rtp_payload_bytes_recorded, s->shared_samples_queued, s->rtp_sequence_gap_packets,
                s->rtp_packets_duplicate, s->rtp_packets_out_of_order, s->rtp_packets_malformed, s->rtp_packets_wrong_payload_type,
                s->rtp_timestamp_discontinuities, s->rtp_timestamp_gap_samples, s->mux_bytes_written,
                s->final_ok ? "CLOSED_COMPLETE" : "RECOVERY_REQUIRED", s->record_commands, s->pause_commands, s->keepalive_requests,
                s->media_intervals_started, s->media_intervals_closed, s->rtp_packets_ignored_not_recording, s->teardown_received, s->window_open_count, s->windows_closed_complete, s->rotations_completed, s->cfg.segment_sequence);
        }
    }
    {
        unsigned long long gaps = 0, duplicates = 0, out_of_order = 0, malformed = 0, wrong_pt = 0, tsdisc = 0;
        for (i = 0; i < host->session_count; i++) {
            gaps += host->sessions[i].rtp_sequence_gap_packets;
            duplicates += host->sessions[i].rtp_packets_duplicate;
            out_of_order += host->sessions[i].rtp_packets_out_of_order;
            malformed += host->sessions[i].rtp_packets_malformed;
            wrong_pt += host->sessions[i].rtp_packets_wrong_payload_type;
            tsdisc += host->sessions[i].rtp_timestamp_discontinuities;
        }
        g_print("RECORDER HOST SUMMARY sessions=%d closed_complete=%d failed=%d packets_received=%llu packets_recorded=%llu packets_ignored_not_recording=%llu sequence_gap_packets=%llu duplicates=%llu out_of_order=%llu malformed=%llu wrong_pt=%llu timestamp_discontinuities=%llu\n",
            host->session_count, closed, failed, received, recorded, ignored, gaps, duplicates, out_of_order, malformed, wrong_pt, tsdisc);
    }
}

static void cleanup_host(RecorderHost *host) {
    int i;
    if (!host) return;
    for (i = 0; i < MAX_CLIENTS; i++) if (host->clients[i].socket != INVALID_SOCKET) closesocket(host->clients[i].socket);
    if (host->listen_socket != INVALID_SOCKET) closesocket(host->listen_socket);
    for (i = 0; i < host->session_count; i++) {
        RecorderSession *s = &host->sessions[i];
        if (s->finalizer_thread) {
            WaitForSingleObject(s->finalizer_thread, INFINITE);
            CloseHandle(s->finalizer_thread);
            s->finalizer_thread = NULL;
        }
        if (!s->finalized) abort_session(s, "Recorder host cleanup before graceful completion");
        else {
            if (s->rtp_socket != INVALID_SOCKET) closesocket(s->rtp_socket);
            s->rtp_socket = INVALID_SOCKET;
            destroy_pipeline(s);
        }
    }
    if (host->cfg.shared_mxf_by_output) destroy_shared_groups(host);
    if (host->audit) fclose(host->audit);
    host->audit = NULL;
    DeleteCriticalSection(&host->audit_lock);
    WSACleanup();
}

static int selftest(int argc, char **argv) {
    const char *dll = arg_value(argc, argv, "--plugin-dll");
    const char *required[] = {"appsrc", "appsink", NULL};
    int i;
    if (!dll || !*dll) {
        g_printerr("selftest requires --plugin-dll <path>.\n");
        return 2;
    }
    if (!load_identity_plugin(dll)) return 3;
    for (i = 0; required[i]; i++) {
        GstElementFactory *f = gst_element_factory_find(required[i]);
        if (!f) return 4;
        g_print("FOUND: %s\n", required[i]);
        gst_object_unref(f);
    }
    {
        GstElementFactory *f = gst_element_factory_find("mxfidmux");
        if (!f) return 5;
        g_print("FOUND: mxfidmux\n");
        gst_object_unref(f);
    }
    g_print("RECORDER-HOST SELFTEST: PASS\n");
    return 0;
}

int main(int argc, char **argv) {
    static RecorderHost host;
    WSADATA wsa;
    int i, server_ok;
    memset(&host, 0, sizeof(host));
    host.listen_socket = INVALID_SOCKET;
    for (i = 0; i < MAX_CLIENTS; i++) host.clients[i].socket = INVALID_SOCKET;
    for (i = 0; i < MAX_SESSIONS; i++) host.sessions[i].rtp_socket = INVALID_SOCKET;
    gst_init(&argc, &argv);
    if (has_arg(argc, argv, "selftest") || (argc > 1 && strcmp(argv[1], "selftest") == 0)) return selftest(argc, argv);
    if (!parse_host_config(argc, argv, &host)) {
        g_printerr("Usage multi: recorder-host --bind-ip IP --rtsp-port PORT --session-map sessions.tsv --audit audit.jsonl --plugin-dll gstmxfidentity.dll [--ready-file FILE] [--recorder-id ID] [--max-seconds N] [--rotate-window-after-pauses N --rotate-window-max-count N] [--shared-mxf-by-output] [--topology-watch-file FILE --topology-revision N] [--shutdown-watch-file FILE]\n");
        g_printerr("Legacy single-session arguments from Phase 3/4 remain supported when --session-map is omitted.\n");
        return 2;
    }
    if (WSAStartup(MAKEWORD(2, 2), &wsa) != 0) return 3;
    InitializeCriticalSection(&host.audit_lock);
    host.audit = fopen(host.cfg.audit_path, "ab");
    if (!host.audit) {
        g_printerr("Could not open audit log: %s\n", host.cfg.audit_path);
        DeleteCriticalSection(&host.audit_lock);
        WSACleanup();
        return 4;
    }
    if (!load_identity_plugin(host.cfg.plugin_dll)) {
        cleanup_host(&host);
        return 5;
    }
    if (host.cfg.shared_mxf_by_output && !build_shared_groups(&host)) {
        host.server_failed = 1;
        cleanup_host(&host);
        return 6;
    }
    for (i = 0; i < host.session_count; i++) {
        if (!init_session(&host, &host.sessions[i], i)) {
            host.server_failed = 1;
            cleanup_host(&host);
            return 6;
        }
    }
    if (!open_host_network(&host)) {
        host.server_failed = 1;
        cleanup_host(&host);
        return 7;
    }
    audit_event(&host, NULL, "HOST_READY", "All configured session writers, pipelines, RTP sockets and RTSP listener are armed");
    server_ok = run_server(&host);
    print_summaries(&host);
    if (!server_ok) host.server_failed = 1;
    {
        int exit_code = host.server_failed ? 8 : 0;
        cleanup_host(&host);
        return exit_code;
    }
}
