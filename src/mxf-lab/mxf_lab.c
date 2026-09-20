#include <gst/gst.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#endif

typedef struct {
    GMainLoop *loop;
    guint pads;
    guint expected_pads;
    gboolean timed_out;
    gboolean no_more_pads;
    gboolean structural_complete;
    gboolean had_error;
    guint timeout_ms;
} InspectCtx;

static gboolean bus_cb(GstBus *bus, GstMessage *msg, gpointer data) {
    GMainLoop *loop = (GMainLoop*)data;
    switch (GST_MESSAGE_TYPE(msg)) {
        case GST_MESSAGE_ERROR: {
            GError *err = NULL; gchar *dbg = NULL;
            gst_message_parse_error(msg, &err, &dbg);
            g_printerr("ERROR: %s\n", err ? err->message : "unknown");
            if (dbg) g_printerr("DEBUG: %s\n", dbg);
            g_clear_error(&err); g_free(dbg);
            g_main_loop_quit(loop);
            break;
        }
        case GST_MESSAGE_EOS:
            g_main_loop_quit(loop);
            break;
        default: break;
    }
    return TRUE;
}

#ifdef _WIN32
static gboolean crash_cb(gpointer user_data) {
    (void)user_data;
    fflush(stdout); fflush(stderr);
    TerminateProcess(GetCurrentProcess(), 77);
    return G_SOURCE_REMOVE;
}
#endif

static int write_mxf(int tracks, int seconds, const char *path, int crash_ms) {
    GstElement *pipeline = gst_pipeline_new("mxf-lab-write");
    GstElement *mux = gst_element_factory_make("mxfmux", "mux");
    GstElement *sink = gst_element_factory_make("filesink", "sink");
    if (!pipeline || !mux || !sink) {
        g_printerr("Missing pipeline/mxfmux/filesink.\n");
        return 2;
    }
    g_object_set(sink, "location", path, NULL);
    gst_bin_add_many(GST_BIN(pipeline), mux, sink, NULL);
    if (!gst_element_link(mux, sink)) {
        g_printerr("Could not link mxfmux -> filesink.\n");
        return 3;
    }

    for (int i=0; i<tracks; i++) {
        gchar n1[64], n2[64], n3[64], n4[64];
        g_snprintf(n1,sizeof(n1),"src_%d",i);
        g_snprintf(n2,sizeof(n2),"caps_%d",i);
        g_snprintf(n3,sizeof(n3),"alaw_%d",i);
        g_snprintf(n4,sizeof(n4),"q_%d",i);
        GstElement *src = gst_element_factory_make("audiotestsrc", n1);
        GstElement *capsf = gst_element_factory_make("capsfilter", n2);
        GstElement *enc = gst_element_factory_make("alawenc", n3);
        GstElement *q = gst_element_factory_make("queue", n4);
        if (!src || !capsf || !enc || !q) {
            g_printerr("Could not create elements for track %d.\n", i);
            return 4;
        }
        GstCaps *caps = gst_caps_from_string("audio/x-raw,format=S16LE,rate=8000,channels=1");
        g_object_set(capsf, "caps", caps, NULL);
        gst_caps_unref(caps);
        g_object_set(src,
            "is-live", FALSE,
            "num-buffers", seconds * 50,
            "samplesperbuffer", 160,
            "freq", 300.0 + (double)((i * 37) % 900),
            NULL);
        g_object_set(q, "max-size-buffers", 100, NULL);
        gst_bin_add_many(GST_BIN(pipeline), src, capsf, enc, q, NULL);
        if (!gst_element_link_many(src, capsf, enc, q, NULL)) {
            g_printerr("Could not link source chain %d.\n", i);
            return 5;
        }
        GstPad *qsrc = gst_element_get_static_pad(q, "src");
        GstPad *msink = gst_element_request_pad_simple(mux, "alaw_audio_sink_%u");
        if (!qsrc || !msink || gst_pad_link(qsrc, msink) != GST_PAD_LINK_OK) {
            g_printerr("Could not request/link MXF A-law pad for track %d.\n", i);
            if (qsrc) gst_object_unref(qsrc);
            if (msink) gst_object_unref(msink);
            return 6;
        }
        gst_object_unref(qsrc);
        gst_object_unref(msink);
    }

    GMainLoop *loop = g_main_loop_new(NULL, FALSE);
    GstBus *bus = gst_element_get_bus(pipeline);
    gst_bus_add_watch(bus, bus_cb, loop);
    gst_object_unref(bus);
#ifdef _WIN32
    if (crash_ms > 0) g_timeout_add((guint)crash_ms, crash_cb, NULL);
#else
    (void)crash_ms;
#endif
    g_print("MXF-LAB write: tracks=%d seconds=%d output=%s crash_ms=%d\n", tracks, seconds, path, crash_ms);
    GstStateChangeReturn sr = gst_element_set_state(pipeline, GST_STATE_PLAYING);
    if (sr == GST_STATE_CHANGE_FAILURE) {
        g_printerr("Failed to set PLAYING.\n");
        return 7;
    }
    g_main_loop_run(loop);
    gst_element_set_state(pipeline, GST_STATE_NULL);
    gst_object_unref(pipeline);
    g_main_loop_unref(loop);
    g_print("MXF-LAB write complete.\n");
    return 0;
}

static gboolean load_pattern_file(const char *path, guint8 **data, gsize *len) {
    gchar *contents = NULL;
    gsize size = 0;
    GError *err = NULL;
    if (!g_file_get_contents(path, &contents, &size, &err)) {
        g_printerr("Could not read PCMA sample %s: %s\n", path, err ? err->message : "unknown");
        g_clear_error(&err);
        return FALSE;
    }
    if (size == 0) {
        g_printerr("PCMA sample is empty: %s\n", path);
        g_free(contents);
        return FALSE;
    }
    *data = (guint8*)contents;
    *len = size;
    return TRUE;
}

typedef struct {
    GMainLoop *loop;
    gboolean had_error;
} PreencodedWriteCtx;

static gboolean preencoded_bus_cb(GstBus *bus, GstMessage *msg, gpointer data) {
    (void)bus;
    PreencodedWriteCtx *ctx = (PreencodedWriteCtx*)data;
    switch (GST_MESSAGE_TYPE(msg)) {
        case GST_MESSAGE_ERROR: {
            GError *err = NULL; gchar *dbg = NULL;
            gst_message_parse_error(msg, &err, &dbg);
            ctx->had_error = TRUE;
            g_printerr("PREENCODED ERROR: %s\n", err ? err->message : "unknown");
            if (dbg) g_printerr("PREENCODED DEBUG: %s\n", dbg);
            g_clear_error(&err); g_free(dbg);
            g_main_loop_quit(ctx->loop);
            break;
        }
        case GST_MESSAGE_EOS:
            g_main_loop_quit(ctx->loop);
            break;
        default:
            break;
    }
    return TRUE;
}

static GstFlowReturn push_pcma_chunk(GstElement *src, const guint8 *pattern, gsize pattern_len,
                                     gsize byte_offset, gsize bytes, guint track_seed) {
    GstBuffer *buf = gst_buffer_new_allocate(NULL, bytes, NULL);
    if (!buf) return GST_FLOW_ERROR;
    GstMapInfo map;
    if (!gst_buffer_map(buf, &map, GST_MAP_WRITE)) {
        gst_buffer_unref(buf);
        return GST_FLOW_ERROR;
    }
    for (gsize i = 0; i < bytes; i++) {
        map.data[i] = pattern[(byte_offset + i + ((gsize)track_seed * 17u)) % pattern_len];
    }
    gst_buffer_unmap(buf, &map);
    GST_BUFFER_PTS(buf) = gst_util_uint64_scale(byte_offset, GST_SECOND, 8000);
    GST_BUFFER_DTS(buf) = GST_BUFFER_PTS(buf);
    GST_BUFFER_DURATION(buf) = gst_util_uint64_scale(bytes, GST_SECOND, 8000);

    GstFlowReturn flow = GST_FLOW_ERROR;
    g_signal_emit_by_name(src, "push-buffer", buf, &flow);
    gst_buffer_unref(buf);
    return flow;
}

static int write_preencoded_mxf(int tracks, int active_tracks, int seconds, const char *path,
                                const char *pcma_path, int chunk_ms, int anchor_ms) {
    if (tracks < 1 || active_tracks < 0 || active_tracks > tracks || seconds < 1 || chunk_ms < 20 || anchor_ms < 0) {
        g_printerr("Invalid preencoded arguments.\n");
        return 1;
    }

    guint8 *pattern = NULL;
    gsize pattern_len = 0;
    if (!load_pattern_file(pcma_path, &pattern, &pattern_len)) return 2;

    GstElement *pipeline = gst_pipeline_new("mxf-lab-preencoded");
    GstElement *mux = gst_element_factory_make("mxfmux", "mux");
    GstElement *sink = gst_element_factory_make("filesink", "sink");
    if (!pipeline || !mux || !sink) {
        g_printerr("Missing pipeline/mxfmux/filesink.\n");
        g_free(pattern);
        return 3;
    }

    g_object_set(sink, "location", path, NULL);
    gst_bin_add_many(GST_BIN(pipeline), mux, sink, NULL);
    if (!gst_element_link(mux, sink)) {
        g_printerr("Could not link mxfmux -> filesink.\n");
        g_free(pattern);
        return 4;
    }

    GstElement **sources = g_new0(GstElement*, tracks);
    GstCaps *caps = gst_caps_from_string("audio/x-alaw,rate=8000,channels=1");
    for (int i = 0; i < tracks; i++) {
        gchar name[64];
        g_snprintf(name, sizeof(name), "appsrc_%d", i);
        GstElement *src = gst_element_factory_make("appsrc", name);
        if (!src) {
            g_printerr("Could not create appsrc for track %d.\n", i);
            gst_caps_unref(caps);
            g_free(sources);
            g_free(pattern);
            return 5;
        }
        g_object_set(src,
            "caps", caps,
            "format", GST_FORMAT_TIME,
            "is-live", FALSE,
            "block", FALSE,
            "max-bytes", (guint64)0,
            NULL);
        gst_bin_add(GST_BIN(pipeline), src);

        GstPad *ssrc = gst_element_get_static_pad(src, "src");
        GstPad *msink = gst_element_request_pad_simple(mux, "alaw_audio_sink_%u");
        if (!ssrc || !msink || gst_pad_link(ssrc, msink) != GST_PAD_LINK_OK) {
            g_printerr("Could not link appsrc to MXF A-law pad for track %d.\n", i);
            if (ssrc) gst_object_unref(ssrc);
            if (msink) gst_object_unref(msink);
            gst_caps_unref(caps);
            g_free(sources);
            g_free(pattern);
            return 6;
        }
        gst_object_unref(ssrc);
        gst_object_unref(msink);
        sources[i] = src;
    }
    gst_caps_unref(caps);

    GMainLoop *loop = g_main_loop_new(NULL, FALSE);
    PreencodedWriteCtx write_ctx = { loop, FALSE };
    GstBus *bus = gst_element_get_bus(pipeline);
    gst_bus_add_watch(bus, preencoded_bus_cb, &write_ctx);
    gst_object_unref(bus);

    gsize chunk_bytes = (gsize)chunk_ms * 8u;
    gsize active_bytes = (gsize)seconds * 8000u;
    gsize anchor_bytes = (gsize)anchor_ms * 8u;
    guint64 logical_payload = (guint64)active_tracks * active_bytes +
                              (guint64)(tracks - active_tracks) * anchor_bytes;

    g_print("MXF-LAB preencoded: declared=%d active=%d seconds=%d chunk_ms=%d anchor_ms=%d payload_bytes=%" G_GUINT64_FORMAT " output=%s\n",
            tracks, active_tracks, seconds, chunk_ms, anchor_ms, logical_payload, path);

    GstStateChangeReturn sr = gst_element_set_state(pipeline, GST_STATE_PLAYING);
    if (sr == GST_STATE_CHANGE_FAILURE) {
        g_printerr("Failed to set preencoded pipeline PLAYING.\n");
        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(pipeline);
        g_main_loop_unref(loop);
        g_free(sources);
        g_free(pattern);
        return 7;
    }

    for (int i = 0; i < tracks; i++) {
        gsize total = (i < active_tracks) ? active_bytes : anchor_bytes;
        gsize offset = 0;
        while (offset < total) {
            gsize remain = total - offset;
            gsize nbytes = remain < chunk_bytes ? remain : chunk_bytes;
            GstFlowReturn flow = push_pcma_chunk(sources[i], pattern, pattern_len, offset, nbytes, (guint)i);
            if (flow != GST_FLOW_OK) {
                g_printerr("push-buffer failed track=%d offset=%zu flow=%s\n", i, offset, gst_flow_get_name(flow));
                gst_element_set_state(pipeline, GST_STATE_NULL);
                gst_object_unref(pipeline);
                g_main_loop_unref(loop);
                g_free(sources);
                g_free(pattern);
                return 8;
            }
            offset += nbytes;
        }
        GstFlowReturn eos_ret = GST_FLOW_ERROR;
        g_signal_emit_by_name(sources[i], "end-of-stream", &eos_ret);
        if (eos_ret != GST_FLOW_OK) {
            g_printerr("end-of-stream failed track=%d flow=%s\n", i, gst_flow_get_name(eos_ret));
            gst_element_set_state(pipeline, GST_STATE_NULL);
            gst_object_unref(pipeline);
            g_main_loop_unref(loop);
            g_free(sources);
            g_free(pattern);
            return 9;
        }
    }

    g_main_loop_run(loop);
    gst_element_set_state(pipeline, GST_STATE_NULL);
    gst_object_unref(pipeline);
    g_main_loop_unref(loop);
    g_free(sources);
    g_free(pattern);
    if (write_ctx.had_error) return 10;
    g_print("MXF-LAB preencoded write complete.\n");
    return 0;
}

static gboolean inspect_bus_cb(GstBus *bus, GstMessage *msg, gpointer data) {
    (void)bus;
    InspectCtx *ctx = (InspectCtx*)data;
    switch (GST_MESSAGE_TYPE(msg)) {
        case GST_MESSAGE_ERROR: {
            GError *err = NULL; gchar *dbg = NULL;
            gst_message_parse_error(msg, &err, &dbg);
            ctx->had_error = TRUE;
            g_printerr("INSPECT ERROR: %s\n", err ? err->message : "unknown");
            if (dbg) g_printerr("INSPECT DEBUG: %s\n", dbg);
            g_clear_error(&err); g_free(dbg);
            g_main_loop_quit(ctx->loop);
            break;
        }
        case GST_MESSAGE_EOS:
            if (!ctx->structural_complete) {
                ctx->structural_complete =
                    (ctx->pads > 0 &&
                     (ctx->expected_pads == 0 || ctx->pads == ctx->expected_pads));
            }
            g_main_loop_quit(ctx->loop);
            break;
        default:
            break;
    }
    return TRUE;
}

static void no_more_pads_cb(GstElement *demux, gpointer user_data) {
    (void)demux;
    InspectCtx *ctx = (InspectCtx*)user_data;
    ctx->no_more_pads = TRUE;
    ctx->structural_complete =
        (ctx->pads > 0 &&
         (ctx->expected_pads == 0 || ctx->pads == ctx->expected_pads));
    g_print("NO_MORE_PADS pads=%u expected=%u structural_complete=%s; waiting for EOS before teardown\n",
            ctx->pads, ctx->expected_pads,
            ctx->structural_complete ? "true" : "false");
}

static gboolean inspect_timeout_cb(gpointer user_data) {
    InspectCtx *ctx = (InspectCtx*)user_data;
    ctx->timed_out = TRUE;
    g_printerr("INSPECT TIMEOUT after %u ms (pads=%u expected=%u no_more_pads=%s)\n",
               ctx->timeout_ms, ctx->pads, ctx->expected_pads,
               ctx->no_more_pads ? "true" : "false");
    g_main_loop_quit(ctx->loop);
    return G_SOURCE_REMOVE;
}

static void pad_added_cb(GstElement *demux, GstPad *pad, gpointer user_data) {
    InspectCtx *ctx = (InspectCtx*)user_data;
    GstElement *pipeline = GST_ELEMENT(gst_element_get_parent(demux));
    GstElement *q = gst_element_factory_make("queue", NULL);
    GstElement *sink = gst_element_factory_make("fakesink", NULL);
    if (!pipeline || !q || !sink) {
        g_printerr("Could not create dynamic inspect sink for pad %s.\n", GST_PAD_NAME(pad));
        if (pipeline) gst_object_unref(pipeline);
        if (q) gst_object_unref(q);
        if (sink) gst_object_unref(sink);
        return;
    }

    /* Inspection must run as fast as possible; never wait on media timestamps. */
    g_object_set(sink, "sync", FALSE, "async", FALSE, NULL);
    g_object_set(q, "max-size-buffers", 0, "max-size-bytes", 0, "max-size-time", (guint64)0, NULL);

    gst_bin_add_many(GST_BIN(pipeline), q, sink, NULL);
    if (!gst_element_link(q, sink)) {
        g_printerr("Could not link inspect queue -> fakesink for pad %s.\n", GST_PAD_NAME(pad));
        gst_object_unref(pipeline);
        return;
    }

    GstPad *qsink = gst_element_get_static_pad(q, "sink");
    if (qsink && gst_pad_link(pad, qsink) == GST_PAD_LINK_OK) {
        ctx->pads++;
        GstCaps *caps = gst_pad_get_current_caps(pad);
        if (!caps) caps = gst_pad_query_caps(pad, NULL);
        gchar *s = caps ? gst_caps_to_string(caps) : g_strdup("unknown");
        g_print("TRACK %u pad=%s caps=%s\n", ctx->pads, GST_PAD_NAME(pad), s);
        g_free(s);
        if (caps) gst_caps_unref(caps);
        gst_element_sync_state_with_parent(q);
        gst_element_sync_state_with_parent(sink);
    } else {
        g_printerr("Could not link MXF pad %s to inspect sink.\n", GST_PAD_NAME(pad));
    }
    if (qsink) gst_object_unref(qsink);
    gst_object_unref(pipeline);
}

static int inspect_mxf(const char *path, guint expected_pads, guint timeout_ms) {
    GstElement *pipeline = gst_pipeline_new("mxf-lab-inspect");
    GstElement *src = gst_element_factory_make("filesrc", "src");
    GstElement *demux = gst_element_factory_make("mxfdemux", "demux");
    if (!pipeline || !src || !demux) {
        g_printerr("Missing filesrc/mxfdemux.\n");
        return 2;
    }
    g_object_set(src, "location", path, NULL);
    gst_bin_add_many(GST_BIN(pipeline), src, demux, NULL);
    if (!gst_element_link(src, demux)) {
        g_printerr("Could not link filesrc -> mxfdemux.\n");
        return 3;
    }

    GMainLoop *loop = g_main_loop_new(NULL, FALSE);
    InspectCtx ctx = { loop, 0, expected_pads, FALSE, FALSE, FALSE, FALSE, timeout_ms };
    g_signal_connect(demux, "pad-added", G_CALLBACK(pad_added_cb), &ctx);
    g_signal_connect(demux, "no-more-pads", G_CALLBACK(no_more_pads_cb), &ctx);

    GstBus *bus = gst_element_get_bus(pipeline);
    gst_bus_add_watch(bus, inspect_bus_cb, &ctx);
    gst_object_unref(bus);

    /* PLAYING is intentional: mxfdemux parses enough data to resolve its
     * dynamic pads. We exit on no-more-pads rather than waiting for media EOS. */
    GstStateChangeReturn sr = gst_element_set_state(pipeline, GST_STATE_PLAYING);
    if (sr == GST_STATE_CHANGE_FAILURE) {
        g_printerr("Failed to set inspect pipeline PLAYING.\n");
        gst_element_set_state(pipeline, GST_STATE_NULL);
        gst_object_unref(pipeline);
        g_main_loop_unref(loop);
        return 5;
    }

    guint timeout_source = g_timeout_add(timeout_ms, inspect_timeout_cb, &ctx);
    g_main_loop_run(loop);
    if (!ctx.timed_out && timeout_source != 0) g_source_remove(timeout_source);

    /* no-more-pads confirms the dynamic track set, but MXF metadata objects
     * may still be under construction. Wait for EOS/error/timeout before
     * tearing down the pipeline to avoid GLib finalized-while-in-construction
     * warnings from mxfdemux. */
    gst_element_set_state(pipeline, GST_STATE_NULL);
    gst_element_get_state(pipeline, NULL, NULL, 2 * GST_SECOND);

    g_print("MXF-LAB inspect: tracks=%u expected=%u file=%s timed_out=%s no_more_pads=%s structural_complete=%s\n",
            ctx.pads, ctx.expected_pads, path,
            ctx.timed_out ? "true" : "false",
            ctx.no_more_pads ? "true" : "false",
            ctx.structural_complete ? "true" : "false");

    gst_object_unref(pipeline);
    g_main_loop_unref(loop);

    if (ctx.had_error) return 6;
    if (ctx.timed_out) return 8;
    if (!ctx.no_more_pads) return 9;
    if (!ctx.structural_complete) return 10;
    return 0;
}


typedef struct {
    gchar *display_name;
    gchar *logical_uuid;
    gchar *instance_uuid;
    gdouble frequency_hz;
    gint duration_ms;
} IdentityRow;

static void identity_row_free(gpointer p) {
    IdentityRow *r = (IdentityRow*)p;
    if (!r) return;
    g_free(r->display_name); g_free(r->logical_uuid); g_free(r->instance_uuid); g_free(r);
}

static GPtrArray *load_identity_file(const char *path) {
    gchar *contents = NULL; gsize len = 0; GError *err = NULL;
    if (!g_file_get_contents(path, &contents, &len, &err)) {
        g_printerr("Could not read identity file %s: %s\n", path, err ? err->message : "unknown");
        g_clear_error(&err); return NULL;
    }
    GPtrArray *rows = g_ptr_array_new_with_free_func(identity_row_free);
    gchar **lines = g_strsplit(contents, "\n", -1);
    for (gint i=0; lines[i]; i++) {
        gchar *line = g_strstrip(lines[i]);
        if (i == 0 && g_str_has_prefix(line, "\xEF\xBB\xBF")) line += 3;
        if (!*line || *line == '#') continue;
        gchar **parts = g_strsplit(line, "\t", 5);
        if (!parts[0] || !parts[1] || !parts[2]) {
            g_printerr("Invalid identity row %d; expected DISPLAY<TAB>LOGICAL_UUID<TAB>INSTANCE_UUID[<TAB>FREQUENCY_HZ<TAB>DURATION_MS]\n", i+1);
            g_strfreev(parts); g_strfreev(lines); g_free(contents); g_ptr_array_unref(rows); return NULL;
        }
        IdentityRow *r = g_new0(IdentityRow,1);
        r->display_name = g_strdup(g_strstrip(parts[0]));
        r->logical_uuid = g_strdup(g_strstrip(parts[1]));
        r->instance_uuid = g_strdup(g_strstrip(parts[2]));
        r->frequency_hz = (parts[3] && *g_strstrip(parts[3])) ? g_ascii_strtod(parts[3], NULL) : 0.0;
        r->duration_ms = (parts[4] && *g_strstrip(parts[4])) ? atoi(parts[4]) : 0;
        if (r->frequency_hz < 0.0 || r->duration_ms < 0) {
            g_printerr("Invalid frequency/duration in identity row %d.\n", i+1);
            identity_row_free(r); g_strfreev(parts); g_strfreev(lines); g_free(contents); g_ptr_array_unref(rows); return NULL;
        }
        g_ptr_array_add(rows,r); g_strfreev(parts);
    }
    g_strfreev(lines); g_free(contents);
    return rows;
}

static gboolean load_identity_plugin_file(const char *plugin_dll) {
    if (!plugin_dll || !*plugin_dll) {
        g_printerr("Identity plugin DLL path was not provided.\n");
        return FALSE;
    }
    GError *err = NULL;
    GstPlugin *plugin = gst_plugin_load_file(plugin_dll, &err);
    if (!plugin) {
        g_printerr("Could not load identity plugin %s: %s\n",
            plugin_dll, err ? err->message : "unknown");
        g_clear_error(&err);
        return FALSE;
    }
    g_print("IDENTITY PLUGIN LOADED: %s\n", plugin_dll);
    gst_object_unref(plugin);
    return TRUE;
}

static int write_identity_mxf(const char *path, const char *identity_file, int seconds, const char *plugin_dll) {
    if (!load_identity_plugin_file(plugin_dll)) return 11;
    GPtrArray *rows = load_identity_file(identity_file);
    if (!rows || rows->len == 0) { if (rows) g_ptr_array_unref(rows); return 2; }
    GstElement *pipeline = gst_pipeline_new("mxf-lab-identity-write");
    GstElement *mux = gst_element_factory_make("mxfidmux", "mux");
    GstElement *sink = gst_element_factory_make("filesink", "sink");
    if (!pipeline || !mux || !sink) {
        g_printerr("Missing mxfidmux/filesink after explicit plugin load.\n");
        if (pipeline) gst_object_unref(pipeline); g_ptr_array_unref(rows); return 3;
    }
    g_object_set(sink, "location", path, NULL);
    gst_bin_add_many(GST_BIN(pipeline), mux, sink, NULL);
    if (!gst_element_link(mux, sink)) { g_printerr("Could not link mxfidmux -> filesink.\n"); g_ptr_array_unref(rows); return 4; }

    for (guint i=0; i<rows->len; i++) {
        IdentityRow *r = g_ptr_array_index(rows,i);
        gchar n1[64],n2[64],n3[64],n4[64];
        g_snprintf(n1,sizeof(n1),"idsrc_%u",i); g_snprintf(n2,sizeof(n2),"idcaps_%u",i);
        g_snprintf(n3,sizeof(n3),"idalaw_%u",i); g_snprintf(n4,sizeof(n4),"idq_%u",i);
        GstElement *src=gst_element_factory_make("audiotestsrc",n1), *capsf=gst_element_factory_make("capsfilter",n2),
                   *enc=gst_element_factory_make("alawenc",n3), *q=gst_element_factory_make("queue",n4);
        if (!src || !capsf || !enc || !q) { g_printerr("Could not create identity source %u.\n",i); g_ptr_array_unref(rows); return 5; }
        GstCaps *caps=gst_caps_from_string("audio/x-raw,format=S16LE,rate=8000,channels=1");
        g_object_set(capsf,"caps",caps,NULL); gst_caps_unref(caps);
        gint duration_ms = r->duration_ms > 0 ? r->duration_ms : seconds * 1000;
        gint buffers = duration_ms / 20;
        if (buffers < 1) buffers = 1;
        gdouble frequency_hz = r->frequency_hz > 0.0 ? r->frequency_hz : 350.0 + (double)(i*113);
        g_object_set(src,"is-live",FALSE,"num-buffers",buffers,"samplesperbuffer",160,"freq",frequency_hz,NULL);
        gst_bin_add_many(GST_BIN(pipeline),src,capsf,enc,q,NULL);
        if (!gst_element_link_many(src,capsf,enc,q,NULL)) { g_printerr("Could not link identity chain %u.\n",i); g_ptr_array_unref(rows); return 6; }
        GstPad *qsrc=gst_element_get_static_pad(q,"src");
        GstPad *msink=gst_element_request_pad_simple(mux,"alaw_audio_sink_%u");
        if (!qsrc || !msink || gst_pad_link(qsrc,msink)!=GST_PAD_LINK_OK) {
            g_printerr("Could not link identity MXF pad %u.\n",i); if(qsrc)gst_object_unref(qsrc); if(msink)gst_object_unref(msink); g_ptr_array_unref(rows); return 7;
        }
        g_object_set(G_OBJECT(msink),
            "track-name", r->display_name,
            "logical-track-uuid", r->logical_uuid,
            "track-instance-uuid", r->instance_uuid,
            NULL);
        g_print("IDENTITY WRITE track=%u name=%s LT=%s TI=%s freq=%.1fHz duration_ms=%d\n",
            i+1, r->display_name, r->logical_uuid, r->instance_uuid,
            r->frequency_hz > 0.0 ? r->frequency_hz : 350.0 + (double)(i*113),
            r->duration_ms > 0 ? r->duration_ms : seconds * 1000);
        gst_object_unref(qsrc); gst_object_unref(msink);
    }

    GMainLoop *loop=g_main_loop_new(NULL,FALSE); GstBus *bus=gst_element_get_bus(pipeline);
    gst_bus_add_watch(bus,bus_cb,loop); gst_object_unref(bus);
    if (gst_element_set_state(pipeline,GST_STATE_PLAYING)==GST_STATE_CHANGE_FAILURE) { g_printerr("Identity pipeline PLAYING failed.\n"); g_ptr_array_unref(rows); return 8; }
    g_main_loop_run(loop); gst_element_set_state(pipeline,GST_STATE_NULL); gst_object_unref(pipeline); g_main_loop_unref(loop);
    g_print("MXF-LAB identity write complete: tracks=%u file=%s\n", rows->len, path); g_ptr_array_unref(rows); return 0;
}

typedef struct {
    GMainLoop *loop;
    guint pads;
    guint structures;
    gboolean had_error;
    gboolean timed_out;
    guint timeout_ms;
} IdentityInspectCtx;

static GstPadProbeReturn identity_tag_probe(GstPad *pad, GstPadProbeInfo *info, gpointer user_data) {
    (void)pad; IdentityInspectCtx *ctx=(IdentityInspectCtx*)user_data;
    GstEvent *ev=GST_PAD_PROBE_INFO_EVENT(info);
    if (!ev || GST_EVENT_TYPE(ev)!=GST_EVENT_TAG) return GST_PAD_PROBE_OK;
    GstTagList *tags=NULL; gst_event_parse_tag(ev,&tags);
    if (!tags) return GST_PAD_PROBE_OK;
    guint n=gst_tag_list_get_tag_size(tags,"mxf-structure");
    for (guint i=0;i<n;i++) {
        const GValue *v=gst_tag_list_get_value_index(tags,"mxf-structure",i);
        if (v && GST_VALUE_HOLDS_STRUCTURE(v)) {
            const GstStructure *st=gst_value_get_structure(v);
            gchar *s=gst_structure_to_string(st);
            ctx->structures++;
            g_print("MXF_STRUCTURE %s\n",s);
            g_free(s);
        }
    }
    return GST_PAD_PROBE_OK;
}

static void identity_pad_added(GstElement *demux, GstPad *pad, gpointer user_data) {
    IdentityInspectCtx *ctx=(IdentityInspectCtx*)user_data;
    GstElement *pipeline=GST_ELEMENT(gst_element_get_parent(demux));
    GstElement *sink=gst_element_factory_make("fakesink",NULL);
    if (!pipeline || !sink) { if(pipeline)gst_object_unref(pipeline); return; }
    g_object_set(sink,"sync",FALSE,"async",FALSE,NULL); gst_bin_add(GST_BIN(pipeline),sink);
    GstPad *ssink=gst_element_get_static_pad(sink,"sink");
    gst_pad_add_probe(pad,GST_PAD_PROBE_TYPE_EVENT_DOWNSTREAM,identity_tag_probe,ctx,NULL);
    if (ssink && gst_pad_link(pad,ssink)==GST_PAD_LINK_OK) { ctx->pads++; gst_element_sync_state_with_parent(sink); }
    else g_printerr("Could not link identity inspect pad %s.\n",GST_PAD_NAME(pad));
    if(ssink)gst_object_unref(ssink); gst_object_unref(pipeline);
}

static gboolean identity_inspect_bus(GstBus *bus, GstMessage *msg, gpointer data) {
    (void)bus; IdentityInspectCtx *ctx=(IdentityInspectCtx*)data;
    if (GST_MESSAGE_TYPE(msg)==GST_MESSAGE_ERROR) {
        GError *err=NULL; gchar *dbg=NULL; gst_message_parse_error(msg,&err,&dbg); ctx->had_error=TRUE;
        g_printerr("IDENTITY INSPECT ERROR: %s\n",err?err->message:"unknown"); if(dbg)g_printerr("DEBUG: %s\n",dbg);
        g_clear_error(&err);g_free(dbg);g_main_loop_quit(ctx->loop);
    } else if (GST_MESSAGE_TYPE(msg)==GST_MESSAGE_EOS) g_main_loop_quit(ctx->loop);
    return TRUE;
}

static gboolean identity_timeout(gpointer data) {
    IdentityInspectCtx *ctx=(IdentityInspectCtx*)data; ctx->timed_out=TRUE;
    g_printerr("IDENTITY INSPECT TIMEOUT after %u ms\n",ctx->timeout_ms); g_main_loop_quit(ctx->loop); return G_SOURCE_REMOVE;
}

static int inspect_identity_mxf(const char *path, guint timeout_ms) {
    GstElement *pipeline=gst_pipeline_new("mxf-lab-identity-inspect"), *src=gst_element_factory_make("filesrc","src"), *demux=gst_element_factory_make("mxfdemux","demux");
    if(!pipeline||!src||!demux){
        if(!pipeline) g_printerr("MISSING: pipeline\n");
        if(!src) g_printerr("MISSING: filesrc\n");
        if(!demux) g_printerr("MISSING: mxfdemux\n");
        return 2;
    }
    g_object_set(src,"location",path,NULL);gst_bin_add_many(GST_BIN(pipeline),src,demux,NULL);
    if(!gst_element_link(src,demux)){g_printerr("Could not link filesrc -> mxfdemux.\n");return 3;}
    GMainLoop *loop=g_main_loop_new(NULL,FALSE);IdentityInspectCtx ctx={loop,0,0,FALSE,FALSE,timeout_ms};
    g_signal_connect(demux,"pad-added",G_CALLBACK(identity_pad_added),&ctx);
    GstBus *bus=gst_element_get_bus(pipeline);gst_bus_add_watch(bus,identity_inspect_bus,&ctx);gst_object_unref(bus);
    if(gst_element_set_state(pipeline,GST_STATE_PLAYING)==GST_STATE_CHANGE_FAILURE){g_printerr("Identity inspect PLAYING failed.\n");return 4;}
    guint timer=g_timeout_add(timeout_ms,identity_timeout,&ctx);g_main_loop_run(loop);if(!ctx.timed_out&&timer)g_source_remove(timer);
    gst_element_set_state(pipeline,GST_STATE_NULL);gst_element_get_state(pipeline,NULL,NULL,2*GST_SECOND);
    g_print("MXF-LAB identity inspect: pads=%u structures=%u file=%s timed_out=%s\n",ctx.pads,ctx.structures,path,ctx.timed_out?"true":"false");
    gst_object_unref(pipeline);g_main_loop_unref(loop);if(ctx.had_error)return 5;if(ctx.timed_out)return 8;if(ctx.structures==0)return 9;return 0;
}

static int selftest(void) {
    const char *required[] = {"mxfmux", "mxfdemux", "alawenc", "alawdec", "audiotestsrc", "appsrc", "queue", "filesrc", "filesink", "fakesink"};
    g_print("MXF-LAB runtime self-test\n");
    g_print("GStreamer: %s\n", gst_version_string());
    for (guint i = 0; i < G_N_ELEMENTS(required); i++) {
        GstElementFactory *factory = gst_element_factory_find(required[i]);
        if (!factory) {
            g_printerr("MISSING ELEMENT: %s\n", required[i]);
            return 10;
        }
        gst_object_unref(factory);
        g_print("FOUND: %s\n", required[i]);
    }
    g_print("MXF-LAB RUNTIME SELF-TEST: PASS\n");
    return 0;
}

static void usage(const char *exe) {
    g_print("Usage:\n");
    g_print("  %s write --tracks N --seconds N --out FILE [--crash-after-ms N]\n", exe);
    g_print("  %s write-preencoded --tracks N --active N --seconds N --out FILE --pcma FILE [--chunk-ms N] [--anchor-ms N]\n", exe);
    g_print("  %s inspect FILE [--expected-tracks N] [--timeout-ms N]\n", exe);
    g_print("  %s write-identity --out FILE --identity-file TSV --plugin-dll FILE [--seconds N]\n", exe);
    g_print("  %s inspect-identity FILE [--timeout-ms N]\n", exe);
    g_print("  %s selftest\n", exe);
}

int main(int argc, char **argv) {
    gst_init(&argc, &argv);
    if (argc < 2) { usage(argv[0]); return 1; }
    if (strcmp(argv[1], "selftest") == 0) return selftest();
    if (strcmp(argv[1], "write") == 0) {
        int tracks=2, seconds=5, crash_ms=0; const char *out="mxf-lab.mxf";
        for (int i=2; i<argc; i++) {
            if (strcmp(argv[i],"--tracks")==0 && i+1<argc) tracks=atoi(argv[++i]);
            else if (strcmp(argv[i],"--seconds")==0 && i+1<argc) seconds=atoi(argv[++i]);
            else if (strcmp(argv[i],"--out")==0 && i+1<argc) out=argv[++i];
            else if (strcmp(argv[i],"--crash-after-ms")==0 && i+1<argc) crash_ms=atoi(argv[++i]);
            else { usage(argv[0]); return 1; }
        }
        if (tracks < 1 || tracks > 2000 || seconds < 1) return 1;
        return write_mxf(tracks, seconds, out, crash_ms);
    }
    if (strcmp(argv[1], "write-preencoded") == 0) {
        int tracks=1000, active=100, seconds=5, chunk_ms=100, anchor_ms=20;
        const char *out="mxf-preencoded.mxf";
        const char *pcma=NULL;
        for (int i=2; i<argc; i++) {
            if (strcmp(argv[i],"--tracks")==0 && i+1<argc) tracks=atoi(argv[++i]);
            else if (strcmp(argv[i],"--active")==0 && i+1<argc) active=atoi(argv[++i]);
            else if (strcmp(argv[i],"--seconds")==0 && i+1<argc) seconds=atoi(argv[++i]);
            else if (strcmp(argv[i],"--out")==0 && i+1<argc) out=argv[++i];
            else if (strcmp(argv[i],"--pcma")==0 && i+1<argc) pcma=argv[++i];
            else if (strcmp(argv[i],"--chunk-ms")==0 && i+1<argc) chunk_ms=atoi(argv[++i]);
            else if (strcmp(argv[i],"--anchor-ms")==0 && i+1<argc) anchor_ms=atoi(argv[++i]);
            else { usage(argv[0]); return 1; }
        }
        if (!pcma || tracks < 1 || tracks > 2000 || active < 0 || active > tracks || seconds < 1) {
            usage(argv[0]);
            return 1;
        }
        return write_preencoded_mxf(tracks, active, seconds, out, pcma, chunk_ms, anchor_ms);
    }
    if (strcmp(argv[1], "write-identity") == 0) {
        const char *out="mxf-identity.mxf", *identity_file=NULL, *plugin_dll=NULL; int seconds=2;
        for (int i=2;i<argc;i++) {
            if(strcmp(argv[i],"--out")==0 && i+1<argc) out=argv[++i];
            else if(strcmp(argv[i],"--identity-file")==0 && i+1<argc) identity_file=argv[++i];
            else if(strcmp(argv[i],"--plugin-dll")==0 && i+1<argc) plugin_dll=argv[++i];
            else if(strcmp(argv[i],"--seconds")==0 && i+1<argc) seconds=atoi(argv[++i]);
            else { usage(argv[0]); return 1; }
        }
        if(!plugin_dll) plugin_dll = g_getenv("RECORDER_MXF_IDENTITY_PLUGIN");
        if(!identity_file || !plugin_dll || seconds<1){usage(argv[0]);return 1;}
        return write_identity_mxf(out,identity_file,seconds,plugin_dll);
    }
    if (strcmp(argv[1], "inspect-identity") == 0 && argc >= 3) {
        guint timeout_ms=15000;
        for(int i=3;i<argc;i++) {
            if(strcmp(argv[i],"--timeout-ms")==0 && i+1<argc) timeout_ms=(guint)atoi(argv[++i]);
            else { usage(argv[0]); return 1; }
        }
        if(timeout_ms<1000)timeout_ms=1000;
        return inspect_identity_mxf(argv[2],timeout_ms);
    }
    if (strcmp(argv[1], "inspect") == 0 && argc >= 3) {
        guint timeout_ms = 30000;
        guint expected_tracks = 0;
        for (int i=3; i<argc; i++) {
            if (strcmp(argv[i],"--timeout-ms")==0 && i+1<argc) timeout_ms=(guint)atoi(argv[++i]);
            else if (strcmp(argv[i],"--expected-tracks")==0 && i+1<argc) expected_tracks=(guint)atoi(argv[++i]);
            else { usage(argv[0]); return 1; }
        }
        if (timeout_ms < 1000) timeout_ms = 1000;
        return inspect_mxf(argv[2], expected_tracks, timeout_ms);
    }
    usage(argv[0]);
    return 1;
}
