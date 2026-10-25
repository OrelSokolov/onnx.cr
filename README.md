# onnx.cr

ONNX Runtime bindings for [Crystal](https://crystal-lang.org), loaded via
`dlopen` at runtime — no link-time dependency, no `-dev` package required.
Includes a high-level inference API and a working end-to-end
[Piper TTS](https://github.com/rhasspy/piper) synthesis example.

## Requirements

- Crystal >= 1.10
- ONNX Runtime shared library (`libonnxruntime.so`), any build >= 1.13
- For the Piper example: `libespeak-ng.so` and a voice model

Both libraries are located through `dlopen` in this order (set
`ONNX_RUNTIME_LIB` / see `examples/piper_speak.cr` to override):

```
libonnxruntime.so.1.21 → libonnxruntime.so.1 → libonnxruntime.so
```

## Usage

```crystal
require "onnx"

session = Onnx::Session.new("model.onnx", threads: 1)

input = Onnx::Value.i64([1, 2, 3], shape: [1_i64, 3_i64])
scales = Onnx::Value.f32([0.667, 1.0, 0.8], shape: [3_i64])

outputs = session.run({"input" => input, "scales" => scales})
outputs["output"].to_f32s  # decodes FLOAT/FLOAT16/DOUBLE tensors
```

### API

| Class / Module | Purpose |
|---|---|
| `Onnx::Session` | Load `.onnx` model, list `input_names`/`output_names`, `#run` |
| `Onnx::Value` | Create Int64/Float32 tensors, read back `#shape`, `#element_type`, `#to_f32s`, `#to_i16s` (waveform: handles Float16 → PCM16) |
| `Onnx::RT` | Runtime loader: `#api`, `#reset!`, `lib_paths`; raises `Onnx::Error` with a clear message if the library is missing |
| `Onnx::Value.f16_to_f32` | IEEE 754 half decoder (exposed for tests) |

Covered C API surface: `CreateEnv`, `CreateSessionOptions`,
`SetIntraOpNumThreads`, `CreateSession`, `GetAllocatorWithDefaultOptions`,
session input/output metadata, `CreateCpuMemoryInfo`,
`CreateTensorWithDataAsOrtValue`, `Run`, tensor type/shape queries,
`GetTensorMutableData`, and the matching `Release*` calls. The full `OrtApi`
struct (285 members, ORT_API_VERSION 21) is laid out in header order —
`ext/reference/onnxruntime_c_api.h` is kept as the reference for offsets.

## Piper TTS example

Full speech-synthesis pipeline in Crystal, mirroring
[piper-phonemize](https://github.com/rhasspy/piper-phonemize) +
[piper](https://github.com/rhasspy/piper):

```
text → espeak-ng IPA phonemes (clause terminators, NFD, (lang) filtering)
     → phoneme ids (BOS ^, pad _ after every phoneme, EOS $)
     → ONNX VITS inference (scales: noise/length/noise_w)
     → PCM16 WAV / real-time streaming
```

### Cross-platform demo tasks (Linux / macOS / Windows)

```
rake build                     # miniaudio bridge + bin/piper_stream, bin/piper_speak
rake play TEXT="Привет!"       # real-time streaming to the speakers
rake play TEXT="..." SPEED=1.5 # faster (pitch stays natural)
rake play TEXT="..." TARGET=2.0  # dubbing mode: hard 2s slot
rake wav TEXT="..."            # synthesize to out.wav and play it
rake spec                      # unit specs (TAGS=piper adds integration)
rake clean
```

The first `rake build` compiles the miniaudio implementation TU (~1 min,
cached). The irina voice is downloaded automatically on first play. Windows
builds use MSVC through Git-for-Windows bash (same scheme as h2code's
`scripts/build_miniaudio.sh`); onnxruntime and espeak-ng are located at
runtime via `LoadLibraryA`/`dlopen`, so the binaries carry no link-time
dependency on them.

### Manual runs (Unix)

```
crystal run examples/piper_speak.cr -- "Привет, мир. Это синтез речи!" --play
```

Measured on one CPU core: phonemize ~7 ms, inference RTF ~0.08
(≈12× faster than real time), full pipeline for a two-sentence phrase
under 1 second. `PIPER_MODEL=/path/to/voice.onnx` selects another voice.

### Real-time streaming (no WAV file)

`examples/piper_stream.cr` synthesizes straight to the speakers through
miniaudio (`ext/miniaudio/` — single-header lib + a small C bridge):

```
./examples/run_stream.sh "Привет! Это живой синтез без записи в файл."
# startup: 960 ms (model + device, one-time)
# phonemize: 2 sentence(s), 13.2 ms
# first audio on air: 115.5 ms        ← text → sound latency
# synthesis: 678.7 ms (RTF 0.137)
```

Latency architecture:

- miniaudio data callback runs on the audio thread as **pure C** and drains
  a lock-free SPSC ring buffer (malloc'd once, ~10 ms device periods);
  it never touches Crystal code or the GC.
- The Crystal producer reuses preallocated buffers end-to-end:
  `Value.tensor_nocopy` (wrap an existing buffer as a tensor, no copy),
  `Value#read_i16s_into` (decode Float16/Float32 → PCM16 into a grow-only
  array), and a scales tensor built once. Per sentence the only heap
  traffic is a couple of tiny `Value` objects — no GC pauses on the
  synthesis path.

First run compiles the miniaudio implementation TU (~1 min, cached in
`ext/miniaudio/*.o`). Requires an audio device reachable via
ALSA/PulseAudio/JACK (miniaudio dlopens the backend at runtime).

### Speed control & dubbing mode

```
# fixed rate: >1 faster, <1 slower (pitch stays natural — VITS length_scale)
./examples/run_stream.sh --speed 1.5 "текст"

# dubbing: fit the phrase into a hard time slot
./examples/run_stream.sh --target-duration 2.0 "длинная реплика"
# fit: 4 pass(es), speed 3.0, speech 2.02s + pauses 0.2s → TRUNCATED → slot 2.0s
# played: 44100 frames, 2.0s
```

`--target-duration` synthesizes a trial pass first (VITS reveals the
duration only after inference), auto-solves the needed speed from the
measured length (duration ≈ speech / speed) and re-synthesizes — converging
in 1–2 passes. If the text still cannot fit even at `max_speed` (3× by
default, quality dies beyond that), the audio is **truncated at the slot
boundary** — the limit is never crossed. A phrase that already fits stays
natural (1 pass, no stretching). Fit mode trades latency for the guarantee:
the full trial synthesis must finish before the first sample plays.

## FastSpeech2 / HiFi-GAN

The runtime is model-agnostic: a FastSpeech2 acoustic model (phoneme ids →
mel) and a HiFi-GAN vocoder (mel → waveform) are just two more
`Onnx::Session`s with the same `#run`. Float32 mel tensors in, Int16/Float
waveforms out — `Value#to_i16s` already handles both output conventions.

## Specs

```
crystal spec              # unit: error paths, fp16 decoder
crystal spec --tag piper  # integration: real model download + inference
```

## License

MIT
