// Streaming playback bridge over miniaudio (0.11.x).
//
// A single playback device runs a data callback that drains a lock-free
// SPSC ring buffer: the producer (Crystal) pushes PCM16 frames, the
// consumer (miniaudio audio thread) pulls them. All audio-path memory is
// malloc'd once at start — zero allocation on the hot path.
//
// Ring size is rounded up to a power of two so head/tail are free-running
// counters masked on access.

#include <stdlib.h>
#include <string.h>
#include <stdatomic.h>
#include <unistd.h>

#include "miniaudio.h"

static ma_device g_device;
static int g_running = 0;
static short *g_ring = NULL;
static unsigned g_ring_frames = 0; // power of two
static unsigned g_channels = 1;

static atomic_size_t g_head; // consumer position (free-running)
static atomic_size_t g_tail; // producer position (free-running)

static unsigned ring_count(void) {
  size_t head = atomic_load_explicit(&g_head, memory_order_acquire);
  size_t tail = atomic_load_explicit(&g_tail, memory_order_acquire);
  return (unsigned)((tail - head) & (size_t)(g_ring_frames - 1));
}

static unsigned ring_free(void) {
  size_t head = atomic_load_explicit(&g_head, memory_order_acquire);
  size_t tail = atomic_load_explicit(&g_tail, memory_order_acquire);
  return (unsigned)((head - tail - 1) & (size_t)(g_ring_frames - 1));
}

static void data_callback(ma_device *pDevice, void *pOutput, const void *pInput,
                          ma_uint32 frameCount) {
  (void)pDevice;
  (void)pInput;
  short *out = (short *)pOutput;
  unsigned frames = frameCount;

  while (frames > 0 && ring_count() > 0) {
    unsigned avail = ring_count();
    unsigned n = frames < avail ? frames : avail;
    size_t head = atomic_load_explicit(&g_head, memory_order_relaxed);
    size_t pos = head & (size_t)(g_ring_frames - 1);
    unsigned first = (unsigned)(g_ring_frames - pos);
    if (first > n)
      first = n;
    memcpy(out, g_ring + pos * g_channels, (size_t)first * g_channels * sizeof(short));
    if (n > first)
      memcpy(out + (size_t)first * g_channels, g_ring,
             (size_t)(n - first) * g_channels * sizeof(short));
    atomic_store_explicit(&g_head, head + n, memory_order_release);
    out += (size_t)n * g_channels;
    frames -= n;
  }

  if (frames > 0)
    memset(out, 0, (size_t)frames * g_channels * sizeof(short));
}

int ma_stream_start(unsigned rate, unsigned channels, unsigned buffer_ms) {
  if (g_running)
    return 0;
  g_channels = channels;

  unsigned frames = rate * buffer_ms / 1000;
  unsigned p2 = 1;
  while (p2 < frames)
    p2 <<= 1;
  g_ring_frames = p2;
  g_ring = (short *)malloc((size_t)p2 * channels * sizeof(short));
  if (!g_ring)
    return -1;
  atomic_store(&g_head, 0);
  atomic_store(&g_tail, 0);

  ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
  cfg.sampleRate = rate;
  cfg.playback.format = ma_format_s16;
  cfg.playback.channels = channels;
  cfg.dataCallback = data_callback;
  // Default periods: tiny (~10 ms) periods made the PulseAudio backend stall
  // for seconds after long idle-silence before consuming the ring.

  if (ma_device_init(NULL, &cfg, &g_device) != MA_SUCCESS) {
    free(g_ring);
    g_ring = NULL;
    return -2;
  }
  if (ma_device_start(&g_device) != MA_SUCCESS) {
    ma_device_uninit(&g_device);
    free(g_ring);
    g_ring = NULL;
    return -3;
  }
  g_running = 1;
  return 0;
}

// Returns the number of frames actually enqueued (0 if the ring is full).
unsigned ma_stream_push(const short *data, unsigned frames) {
  unsigned written = 0;
  while (written < frames) {
    unsigned space = ring_free();
    if (space == 0)
      break;
    unsigned n = frames - written;
    if (n > space)
      n = space;
    size_t tail = atomic_load_explicit(&g_tail, memory_order_relaxed);
    size_t pos = tail & (size_t)(g_ring_frames - 1);
    unsigned first = (unsigned)(g_ring_frames - pos);
    if (first > n)
      first = n;
    memcpy(g_ring + pos * g_channels, data + (size_t)written * g_channels,
           (size_t)first * g_channels * sizeof(short));
    if (n > first)
      memcpy(g_ring, data + (size_t)(written + first) * g_channels,
             (size_t)(n - first) * g_channels * sizeof(short));
    atomic_store_explicit(&g_tail, tail + n, memory_order_release);
    written += n;
  }
  return written;
}

unsigned ma_stream_queued(void) { return ring_count(); }
unsigned ma_stream_free(void) { return ring_free(); }

void ma_stream_drain(void) {
  // Wait until the consumer has played everything out.
  while (ring_count() > 0)
    usleep(10 * 1000);
}

void ma_stream_stop(void) {
  if (g_running) {
    ma_device_uninit(&g_device);
    free(g_ring);
    g_ring = NULL;
    g_running = 0;
  }
}
