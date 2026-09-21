Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Tag = '1.28.7'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Vendor = Join-Path $Here ('vendor-' + $Tag)
$BuildSrc = Join-Path $Here 'buildsrc'
New-Item -ItemType Directory -Force -Path $Vendor | Out-Null

# Exact upstream source set used by gst-plugins-bad/gst/mxf in GStreamer 1.28.7.
$Files = @(
  'mxf.c','gstmxfelement.c','gstmxfelements.h','mxful.c','mxful.h','mxftypes.c','mxftypes.h',
  'mxfmetadata.c','mxfmetadata.h','mxfdms1.h','mxfessence.c','mxfessence.h','mxfquark.c','mxfquark.h',
  'mxfmux.c','mxfmux.h','mxfdemux.c','mxfdemux.h','mxfaes-bwf.c','mxfaes-bwf.h',
  'mxfmpeg.c','mxfmpeg.h','mxfdv-dif.c','mxfdv-dif.h','mxfalaw.c','mxfalaw.h',
  'mxfjpeg2000.c','mxfjpeg2000.h','mxfd10.c','mxfd10.h','mxfup.c','mxfup.h',
  'mxfvc3.c','mxfvc3.h','mxfprores.c','mxfprores.h','mxfvanc.c','mxfvanc.h',
  'mxfcustom.c','mxfcustom.h','mxfffv1.c','mxfffv1.h'
)

$Base = "https://raw.githubusercontent.com/GStreamer/gstreamer/$Tag/subprojects/gst-plugins-bad/gst/mxf"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
foreach ($f in $Files) {
    $dst = Join-Path $Vendor $f
    if (-not (Test-Path $dst)) {
        Write-Host "Downloading upstream $Tag/$f"
        Invoke-WebRequest -UseBasicParsing -Uri ($Base + '/' + $f) -OutFile $dst
    }
    if ((Get-Item $dst).Length -lt 100) { throw "Downloaded source looks invalid: $dst" }
}

if (Test-Path $BuildSrc) { Remove-Item -Recurse -Force $BuildSrc }
New-Item -ItemType Directory -Force -Path $BuildSrc | Out-Null
Copy-Item (Join-Path $Vendor '*') $BuildSrc -Force

$muxPath = Join-Path $BuildSrc 'mxfmux.c'
$mux = Get-Content -Raw -LiteralPath $muxPath

function Replace-Exact([string]$Text,[string]$Old,[string]$New,[string]$Label) {
    if (-not $Text.Contains($Old)) { throw "Patch anchor not found: $Label. Upstream source differs from expected GStreamer 1.28.7." }
    return $Text.Replace($Old,$New)
}

# 1) Give the patched element its own factory name. The GType/symbol stays local to this DLL.
$mux = Replace-Exact $mux `
'GST_ELEMENT_REGISTER_DEFINE_WITH_CODE (mxfmux, "mxfmux", GST_RANK_PRIMARY,' `
'GST_ELEMENT_REGISTER_DEFINE_WITH_CODE (mxfmux, "mxfidmux", GST_RANK_PRIMARY,' 'factory-name'

# 2) Add semantic identity fields to each request pad.
$old = @'
  MXFMetadataSourcePackage *source_package;
  MXFMetadataTimelineTrack *source_track;
} GstMXFMuxPad;
'@
$new = @'
  MXFMetadataSourcePackage *source_package;
  MXFMetadataTimelineTrack *source_track;

  /* Recorder PoC extension: application identity, serialized only through
   * standards-compliant MXF Track Name. Structural TrackID/TrackNumber
   * semantics remain untouched. */
  gchar *track_name;
  gchar *logical_track_uuid;
  gchar *track_instance_uuid;
} GstMXFMuxPad;
'@
$mux = Replace-Exact $mux $old $new 'pad-fields'

# 3) Install per-pad GObject properties and a deterministic TrackName builder.
$old = @'
G_DEFINE_TYPE (GstMXFMuxPad, gst_mxf_mux_pad, GST_TYPE_AGGREGATOR_PAD);

static void
gst_mxf_mux_pad_finalize (GObject * object)
{
'@
$new = @'
G_DEFINE_TYPE (GstMXFMuxPad, gst_mxf_mux_pad, GST_TYPE_AGGREGATOR_PAD);

enum
{
  PAD_PROP_0,
  PAD_PROP_TRACK_NAME,
  PAD_PROP_LOGICAL_TRACK_UUID,
  PAD_PROP_TRACK_INSTANCE_UUID
};

static void
gst_mxf_mux_pad_set_property (GObject * object, guint prop_id,
    const GValue * value, GParamSpec * pspec)
{
  GstMXFMuxPad *pad = GST_MXF_MUX_PAD (object);

  switch (prop_id) {
    case PAD_PROP_TRACK_NAME:
      g_free (pad->track_name);
      pad->track_name = g_value_dup_string (value);
      break;
    case PAD_PROP_LOGICAL_TRACK_UUID:
      g_free (pad->logical_track_uuid);
      pad->logical_track_uuid = g_value_dup_string (value);
      break;
    case PAD_PROP_TRACK_INSTANCE_UUID:
      g_free (pad->track_instance_uuid);
      pad->track_instance_uuid = g_value_dup_string (value);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
      break;
  }
}

static void
gst_mxf_mux_pad_get_property (GObject * object, guint prop_id,
    GValue * value, GParamSpec * pspec)
{
  GstMXFMuxPad *pad = GST_MXF_MUX_PAD (object);

  switch (prop_id) {
    case PAD_PROP_TRACK_NAME:
      g_value_set_string (value, pad->track_name);
      break;
    case PAD_PROP_LOGICAL_TRACK_UUID:
      g_value_set_string (value, pad->logical_track_uuid);
      break;
    case PAD_PROP_TRACK_INSTANCE_UUID:
      g_value_set_string (value, pad->track_instance_uuid);
      break;
    default:
      G_OBJECT_WARN_INVALID_PROPERTY_ID (object, prop_id, pspec);
      break;
  }
}

static gchar *
gst_mxf_mux_pad_build_track_name (GstMXFMuxPad * pad)
{
  const gchar *base = (pad->track_name && *pad->track_name) ?
      pad->track_name : GST_PAD_NAME (pad);

  if (pad->logical_track_uuid && *pad->logical_track_uuid &&
      pad->track_instance_uuid && *pad->track_instance_uuid)
    return g_strdup_printf ("%s | LT=%s | TI=%s", base,
        pad->logical_track_uuid, pad->track_instance_uuid);
  if (pad->logical_track_uuid && *pad->logical_track_uuid)
    return g_strdup_printf ("%s | LT=%s", base, pad->logical_track_uuid);
  return g_strdup (base);
}

static void
gst_mxf_mux_pad_finalize (GObject * object)
{
'@
$mux = Replace-Exact $mux $old $new 'pad-properties-code'

$old = @'
  g_object_unref (pad->adapter);
  g_free (pad->mapping_data);

  G_OBJECT_CLASS (gst_mxf_mux_pad_parent_class)->finalize (object);
'@
$new = @'
  g_object_unref (pad->adapter);
  g_free (pad->mapping_data);
  g_free (pad->track_name);
  g_free (pad->logical_track_uuid);
  g_free (pad->track_instance_uuid);

  G_OBJECT_CLASS (gst_mxf_mux_pad_parent_class)->finalize (object);
'@
$mux = Replace-Exact $mux $old $new 'pad-finalize'

$old = @'
  GObjectClass *object_class = (GObjectClass *) klass;

  object_class->finalize = gst_mxf_mux_pad_finalize;
}
'@
$new = @'
  GObjectClass *object_class = (GObjectClass *) klass;

  object_class->finalize = gst_mxf_mux_pad_finalize;
  object_class->set_property = gst_mxf_mux_pad_set_property;
  object_class->get_property = gst_mxf_mux_pad_get_property;

  g_object_class_install_property (object_class, PAD_PROP_TRACK_NAME,
      g_param_spec_string ("track-name", "Track Name",
          "Human-readable semantic MXF Track Name", NULL,
          G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
  g_object_class_install_property (object_class, PAD_PROP_LOGICAL_TRACK_UUID,
      g_param_spec_string ("logical-track-uuid", "Logical Track UUID",
          "Stable application UUID appended to MXF Track Name", NULL,
          G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
  g_object_class_install_property (object_class, PAD_PROP_TRACK_INSTANCE_UUID,
      g_param_spec_string ("track-instance-uuid", "Track Instance UUID",
          "Physical occurrence UUID appended to MXF Track Name", NULL,
          G_PARAM_READWRITE | G_PARAM_STATIC_STRINGS));
}
'@
$mux = Replace-Exact $mux $old $new 'pad-class-init'

# 4) Persist the composed TrackName in both Source Package and Material Package tracks.
$old = @'
          track->parent.track_number =
              pad->writer->get_track_number_template (pad->descriptor,
              caps, pad->mapping_data);

          /* FIXME: All tracks in a source package must have the same edit
'@
$new = @'
          track->parent.track_number =
              pad->writer->get_track_number_template (pad->descriptor,
              caps, pad->mapping_data);
          track->parent.track_name = gst_mxf_mux_pad_build_track_name (pad);

          /* FIXME: All tracks in a source package must have the same edit
'@
$mux = Replace-Exact $mux $old $new 'source-track-name'

$old = @'
          track->parent.track_id = n + 1;
          track->parent.track_number = 0;

          caps = gst_pad_get_current_caps (GST_PAD_CAST (pad));
'@
$new = @'
          track->parent.track_id = n + 1;
          track->parent.track_number = 0;
          track->parent.track_name = gst_mxf_mux_pad_build_track_name (pad);

          caps = gst_pad_get_current_caps (GST_PAD_CAST (pad));
'@
$mux = Replace-Exact $mux $old $new 'material-track-name'

# 5) Preserve source timing on each complete essence KLV for growing-MXF
# watermark publication. These GstBuffer timestamps are downstream-only
# metadata; they do not change the serialized MXF bytes.
$old = @'
  GstClockTime pts = buf ? GST_BUFFER_PTS (buf) : GST_CLOCK_TIME_NONE;
  GstClockTime dts = buf ? GST_BUFFER_DTS (buf) : GST_CLOCK_TIME_NONE;

  if (pad->have_complete_edit_unit) {
'@
$new = @'
  GstClockTime pts = buf ? GST_BUFFER_PTS (buf) : GST_CLOCK_TIME_NONE;
  GstClockTime dts = buf ? GST_BUFFER_DTS (buf) : GST_CLOCK_TIME_NONE;
  GstClockTime source_pts = pts;
  GstClockTime source_duration =
      buf ? GST_BUFFER_DURATION (buf) : GST_CLOCK_TIME_NONE;

  if (pad->have_complete_edit_unit) {
'@
$mux = Replace-Exact $mux $old $new 'growing-mxf-source-timing-vars'

$old = @'
    if (buf)
      gst_buffer_unref (buf);
    buf = NULL;
  } else if (!flush) {
'@
$new = @'
    if (buf)
      gst_buffer_unref (buf);
    buf = NULL;
    source_pts = GST_CLOCK_TIME_NONE;
    source_duration = GST_CLOCK_TIME_NONE;
  } else if (!flush) {
'@
$mux = Replace-Exact $mux $old $new 'growing-mxf-source-timing-reset'

$old = @'
  gst_buffer_unmap (outbuf, &map);
  outbuf = gst_buffer_append (outbuf, buf);

  GST_DEBUG_OBJECT (pad,
'@
$new = @'
  gst_buffer_unmap (outbuf, &map);
  outbuf = gst_buffer_append (outbuf, buf);

  /*
   * Recorder extension: annotate every complete essence KLV with the source
   * time span that caused it to be emitted. The downstream StorageWriter uses
   * this metadata only to publish a read-safe growing-MXF watermark; it does
   * not alter the MXF bytes.
   */
  if (GST_CLOCK_TIME_IS_VALID (source_pts) &&
      GST_CLOCK_TIME_IS_VALID (source_duration)) {
    GST_BUFFER_PTS (outbuf) =
        gst_segment_to_running_time (&pad->parent.segment, GST_FORMAT_TIME,
        source_pts);
    GST_BUFFER_DURATION (outbuf) = source_duration;
  } else {
    GST_BUFFER_PTS (outbuf) = pad->last_timestamp;
    GST_BUFFER_DURATION (outbuf) =
        gst_util_uint64_scale (GST_SECOND, pad->source_track->edit_rate.d,
        pad->source_track->edit_rate.n);
  }
  GST_BUFFER_DTS (outbuf) = GST_CLOCK_TIME_NONE;
  GST_BUFFER_OFFSET (outbuf) = pad->pos;
  GST_BUFFER_OFFSET_END (outbuf) = pad->pos + 1;

  GST_DEBUG_OBJECT (pad,
'@
$mux = Replace-Exact $mux $old $new 'growing-mxf-klv-watermark-metadata'

Set-Content -Encoding UTF8 -LiteralPath $muxPath -Value $mux

# 6) Sparse A-law tracks must remain decodable by stock MXF readers. Convert
# GStreamer GAP buffers into valid A-law silence bytes before normal edit-unit
# assembly. The recorder audit remains authoritative for evidence/media
# intervals, so these bytes are structural container padding only.
$alawPath = Join-Path $BuildSrc 'mxfalaw.c'
$alaw = Get-Content -Raw -LiteralPath $alawPath
$old = @'
  bytes = speu * md->channels;

  if (buffer)
    gst_adapter_push (adapter, buffer);
'@
$new = @'
  bytes = speu * md->channels;

  /*
   * Recorder extension: keep sparse tracks standards-decodable. A GAP is
   * container padding, not recorded evidence. Encode its elapsed time as
   * valid G.711 A-law silence (0xD5) and feed it through the normal adapter
   * so every MXF edit unit keeps the expected fixed audio payload size.
   *
   * Audit MEDIA_START/MEDIA_END remains authoritative for deciding which
   * timeline regions are recorded media; players must never promote this
   * structural filler to evidence audio.
   */
  if (buffer && GST_BUFFER_FLAG_IS_SET (buffer, GST_BUFFER_FLAG_GAP)) {
    GstClockTime gap_duration = GST_BUFFER_DURATION (buffer);
    guint64 gap_samples = speu;
    GstBuffer *filler;

    if (GST_CLOCK_TIME_IS_VALID (gap_duration) && gap_duration > 0)
      gap_samples = gst_util_uint64_scale_round (gap_duration,
          (guint64) md->rate, GST_SECOND);

    if (gap_samples == 0)
      gap_samples = speu;

    filler = gst_buffer_new_allocate (NULL,
        (gsize) gap_samples * md->channels, NULL);
    if (!filler) {
      gst_buffer_unref (buffer);
      return GST_FLOW_ERROR;
    }

    gst_buffer_memset (filler, 0, 0xD5,
        (gsize) gap_samples * md->channels);
    GST_BUFFER_PTS (filler) = GST_BUFFER_PTS (buffer);
    GST_BUFFER_DTS (filler) = GST_BUFFER_DTS (buffer);
    GST_BUFFER_DURATION (filler) = gap_duration;
    GST_BUFFER_FLAG_SET (filler, GST_BUFFER_FLAG_GAP);
    gst_buffer_unref (buffer);
    buffer = filler;
  }

  if (buffer)
    gst_adapter_push (adapter, buffer);
'@
$alaw = Replace-Exact $alaw $old $new 'sparse-alaw-structural-filler'
Set-Content -Encoding UTF8 -LiteralPath $alawPath -Value $alaw

# 7) Isolate plugin registration: only patched muxer is exposed; stock mxfdemux remains official.
$pluginPath = Join-Path $BuildSrc 'mxf.c'
$pc = Get-Content -Raw -LiteralPath $pluginPath
$old = @'
  /* mxfmux is disabled for now - it compiles but is completely untested */
  ret |= GST_ELEMENT_REGISTER (mxfdemux, plugin);
  ret |= GST_ELEMENT_REGISTER (mxfmux, plugin);
'@
$new = @'
  /* Recorder PoC: expose only the patched muxer under factory mxfidmux.
   * The official GStreamer mxfdemux/mxfmux remain installed and untouched. */
  ret |= GST_ELEMENT_REGISTER (mxfmux, plugin);
'@
$pc = Replace-Exact $pc $old $new 'plugin-register-only-mux'
$pc = Replace-Exact $pc `
'    mxf,' `
'    mxfidentity,' 'plugin-name'
$pc = Replace-Exact $pc `
'    "MXF plugin library",' `
'    "Recorder PoC MXF identity muxer",' 'plugin-description'
Set-Content -Encoding UTF8 -LiteralPath $pluginPath -Value $pc

$marker = Join-Path $BuildSrc 'PATCHED-2.0.14.txt'
@"
Upstream: GStreamer $Tag / subprojects/gst-plugins-bad/gst/mxf
Factory: mxfidmux
Patch: per-request-pad identity + downstream complete-KLV source timing metadata
Sparse audio: GAP time is serialized as valid PCMA 0xD5 structural filler; recorder audit remains the media/evidence authority.
Serialization: MXF Track Name only; structural IDs are not overloaded.
Growing playback: GstBuffer timing metadata is downstream-only and does not alter MXF bytes.
"@ | Set-Content -Encoding UTF8 -LiteralPath $marker

Write-Host "Prepared patched source: $BuildSrc"
