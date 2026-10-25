# Real-time Piper TTS: synthesis streamed straight to the speakers through
# miniaudio — no WAV file, no per-sentence allocations.
#
#   ./examples/run_stream.sh "Привет, мир. Слушай, это живой синтез!"
#
# Latency path:
#   text -> espeak-ng (~7 ms) -> ONNX per sentence (~100-200 ms) -> lock-free
#   SPSC ring (C memory, malloc'd once) -> miniaudio callback (~10 ms periods)
#
# The producer (this fiber) reuses preallocated buffers end-to-end:
#   @ids/@ids_bytes (phoneme ids + tensor view), @pcm (decoder output),
#   scales tensor created once. The audio thread is pure C (see
#   ext/miniaudio/stream_bridge.c) and never touches the GC.
require "./piper"

# ------------------------------------------------------------------ runner

class PiperStream
  RING_MS = 500 # ring buffer size; device periods are ~10 ms

  getter first_audio_ms : Float64 = 0.0
  getter synth_ms : Float64 = 0.0
  getter frames_pushed : Int32 = 0

  @ids : Array(Int64) = Array(Int64).new
  @ids_bytes : Slice(UInt8) = Slice(UInt8).new(16)
  @len_bytes : Slice(UInt8) = Slice(UInt8).new(8)
  @shape_input : Slice(Int64) = Slice(Int64).new(2) { 1_i64 }
  @shape_one : Slice(Int64) = Slice(Int64).new(1) { 1_i64 }
  @pcm : Array(Int16) = Array(Int16).new
  @silence : Array(Int16) = Array(Int16).new
  @speak_started_at : Time::Instant = Time.instant

  # speed > 1 → faster speech (length_scale /= speed), speed < 1 → slower.
  # VITS changes phoneme durations, so the pitch stays natural.
  property speed : Float32 = 1.0_f32
  # Hard ceiling for auto-fit (--target-duration): quality dies beyond ~3x.
  property max_speed : Float32 = 3.0_f32

  @fit_audio : Array(Int16) = Array(Int16).new

  def initialize(@config : PiperConfig, @session : Onnx::Session, speed : Float32 = 1.0_f32)
    @speed = speed
    rc = LibMA.ma_stream_start(@config.sample_rate.to_u32, 1, RING_MS)
    raise Onnx::Error.new("miniaudio device failed (#{rc})") unless rc == 0
    silence_frames = (@config.sentence_silence * @config.sample_rate).to_i
    @silence = Array(Int16).new(silence_frames, 0_i16) if silence_frames > 0
  end

  def speak(text : String) : Nil
    t_start = Time.instant
    @speak_started_at = t_start
    sentences = Espeak.phonemize(text, @config.voice)
    STDERR.puts "phonemize: #{sentences.size} sentence(s), #{((Time.instant - t_start).total_milliseconds).round(1)} ms"

    # The scales tensor wraps scale_bytes without copying, so refreshing the
    # buffer before each run applies runtime speed changes per sentence.
    scales_value = Onnx::Value.tensor_nocopy(
      scale_bytes, @shape_three, LibOnnx::ElementType::FLOAT
    )

    sentences.each_with_index do |phonemes, i|
      @ids.clear
      next unless @config.phonemes_to_ids(phonemes, @ids)

      scale_bytes # refresh length_scale in the wrapped buffer
      t0 = Time.instant
      input_value = Onnx::Value.tensor_nocopy(
        ensure_ids_bytes, @shape_input, LibOnnx::ElementType::INT64
      )
      len_value = Onnx::Value.tensor_nocopy(
        @len_bytes, @shape_one, LibOnnx::ElementType::INT64
      )

      run_result = @session.run({
        "input"         => input_value,
        "input_lengths" => len_value,
        "scales"        => scales_value,
      })
      count = run_result["output"].read_i16s_into(@pcm)
      t1 = Time.instant
      @synth_ms += (t1 - t0).total_milliseconds

      push_all(@pcm, count)
      unless @silence.empty?
        push_all(@silence, @silence.size)
      end
    end
    STDERR.puts "synthesis: #{@synth_ms.round(1)} ms across #{sentences.size} sentence(s)" if sentences.size > 0
  end

  # Dubbing mode: fit the whole text into `target_seconds`, a hard limit.
  #
  # Pass 1 synthesizes every sentence at the current speed *without playing*,
  # measures the real duration (VITS reveals it only after inference), then —
  # if the phrase overshoots the slot — solves the needed speed proportionally
  # (duration ≈ speech / speed) and re-synthesizes. Converges in 1-2 passes;
  # if even max_speed cannot fit the text, the audio is truncated to the
  # limit — the slot boundary is never crossed.
  def fit_and_speak(text : String, target_seconds : Float64) : Nil
    t_start = Time.instant
    @speak_started_at = t_start
    sentences = Espeak.phonemize(text, @config.voice)
    rate = @config.sample_rate.to_f
    target_frames = (target_seconds * rate).to_i
    pause_frames = @silence.size * sentences.size

    speed = @speed
    speech_frames = 0
    attempts = 0

    loop do
      attempts += 1
      speech_frames = synth_all(sentences, speed)
      total = speech_frames + pause_frames
      break if total <= target_frames

      available = {target_frames - pause_frames, 1}.max
      needed = speed * speech_frames.to_f / available
      new_speed = needed.clamp(speed, max_speed).to_f32
      if new_speed - speed < 0.01_f32 || attempts >= 4
        # Converged (or out of attempts): one last synthesis at the final
        # speed so what we push matches what we measured.
        speed = new_speed if new_speed > speed
        speech_frames = synth_all(sentences, speed) if speed != @speed || attempts >= 2
        break
      end
      speed = new_speed
    end

    total = speech_frames + pause_frames
    truncated = total > target_frames
    STDERR.puts "fit: #{attempts} pass(es), speed #{speed.round(2)}, " \
                "speech #{(speech_frames / rate).round(2)}s + pauses #{(pause_frames / rate).round(2)}s" \
                "#{" → TRUNCATED" if truncated} → slot #{target_seconds}s"

    # Push the fitted audio, never past the slot boundary.
    budget = target_frames
    take = {speech_frames, budget}.min
    push_slice(@fit_audio.to_unsafe, take)
    budget -= take
    if budget > 0 && !@silence.empty?
      sentences.size.times do
        break if budget <= 0
        n = {@silence.size, budget}.min
        push_slice(@silence.to_unsafe, n)
        budget -= n
      end
    end
  end

  # Synthesizes all sentences into @fit_audio (grow-only buffer, cleared in
  # place) at `speed` and returns the total speech frame count. Nothing is
  # played; used by fit_and_speak for measuring and for the final render.
  private def synth_all(sentences : Array(Array(String)), speed : Float32) : Int32
    @speed = speed
    @fit_audio.clear
    scales_value = Onnx::Value.tensor_nocopy(
      scale_bytes, @shape_three, LibOnnx::ElementType::FLOAT
    )

    total = 0
    sentences.each do |phonemes|
      @ids.clear
      next unless @config.phonemes_to_ids(phonemes, @ids)

      scale_bytes # refresh length_scale for this speed
      input_value = Onnx::Value.tensor_nocopy(
        ensure_ids_bytes, @shape_input, LibOnnx::ElementType::INT64
      )
      len_value = Onnx::Value.tensor_nocopy(
        @len_bytes, @shape_one, LibOnnx::ElementType::INT64
      )

      run_result = @session.run({
        "input"         => input_value,
        "input_lengths" => len_value,
        "scales"        => scales_value,
      })
      t0 = Time.instant
      count = run_result["output"].read_i16s_into(@pcm)
      @synth_ms += (Time.instant - t0).total_milliseconds

      # Append to @fit_audio without allocating (grow-only).
      if @fit_audio.size < total + count
        (total + count - @fit_audio.size).times { @fit_audio << 0_i16 }
      end
      dst = @fit_audio.to_unsafe + total
      src = @pcm.to_unsafe
      count.times { |i| dst[i] = src[i] }
      total += count
    end
    total
  end

  def finish : Nil
    waited = 0
    while LibMA.ma_stream_queued > 0
      sleep 10.milliseconds
      waited += 1
      STDERR.puts "drain wait #{waited * 10}ms: queued=#{LibMA.ma_stream_queued}" if waited % 100 == 0
    end
    LibMA.ma_stream_stop
  end

  private def ensure_ids_bytes : Slice(UInt8)
    needed = @ids.size * 8
    if @ids_bytes.size < needed
      @ids_bytes = Slice(UInt8).new(needed.next_power_of_two)
    end
    ids_ptr = @ids_bytes.to_unsafe.as(Pointer(Int64))
    @ids.each_with_index { |v, i| ids_ptr[i] = v }
    @shape_input[0] = 1
    @shape_input[1] = @ids.size
    @len_bytes.to_unsafe.as(Pointer(Int64))[0] = @ids.size
    # Slice view covering exactly the tensor bytes (buffer may be larger).
    Slice(UInt8).new(@ids_bytes.to_unsafe, needed)
  end

  @scale_bytes : Slice(UInt8) = Slice(UInt8).new(12)
  @shape_three : Slice(Int64) = Slice(Int64).new(1) { 3_i64 }

  private def scale_bytes : Slice(UInt8)
    floats = @scale_bytes.to_unsafe.as(Pointer(Float32))
    floats[0] = @config.noise_scale
    # scales are read once per speak() call, so runtime speed changes apply
    # to the next sentence
    floats[1] = @config.length_scale / @speed
    floats[2] = @config.noise_w
    @scale_bytes
  end

  private def push_all(data : Array(Int16), count : Int32) : Nil
    push_slice(data.to_unsafe, count)
  end

  private def push_slice(ptr : Pointer(Int16), count : Int32) : Nil
    offset = 0
    stalled = 0
    while offset < count
      written = LibMA.ma_stream_push(ptr + offset, (count - offset).to_u32).to_i32
      if written == 0
        # Ring full — let the audio thread drain it.
        stalled += 1
        if stalled % 200 == 1
          STDERR.puts "push stall #{stalled}: queued=#{LibMA.ma_stream_queued} free=#{LibMA.ma_stream_free}"
        end
        sleep 5.milliseconds
        next
      end
      offset += written
      @frames_pushed += written
      if @first_audio_ms == 0.0
        # First samples are in the device: they hit the speakers within
        # one device period (~10 ms) from now.
        @first_audio_ms = (Time.instant - @speak_started_at).total_milliseconds
        STDERR.puts "first audio on air: #{@first_audio_ms.round(1)} ms"
      end
    end
  end
end

# -------------------------------------------------------------------- main

if ARGV.empty?
  STDERR.puts %(usage: run_stream.sh [--speed 1.5 | --target-duration 2.5] "<text>")
  STDERR.puts %(       speed > 1 — faster, < 1 — slower (pitch stays natural))
  STDERR.puts %(       target-duration — dubbing mode: fit the phrase into a)
  STDERR.puts %(       hard time slot, auto-solving the speed (≤3x, then truncate))
  exit 1
end
speed = 1.0_f32
if i = ARGV.index("--speed")
  speed = ARGV[i + 1].to_f32
  ARGV.delete_at(i, 2)
end
target_duration = nil
if i = ARGV.index("--target-duration")
  target_duration = ARGV[i + 1].to_f64
  ARGV.delete_at(i, 2)
end
text = ARGV.join(" ")

assets = File.join(__DIR__, "assets")
model_path = ENV["PIPER_MODEL"]? || File.join(assets, "ru_RU-irina-medium.onnx")

t_start = Time.instant
config = PiperConfig.from_json("#{model_path}.json")
session = Onnx::Session.new(model_path, threads: 1)
Espeak.init!
stream = PiperStream.new(config, session, speed)
STDERR.puts "startup: #{((Time.instant - t_start).total_milliseconds).round(1)} ms (model + device), speed #{speed}"

if td = target_duration
  stream.fit_and_speak(text, td)
else
  stream.speak(text)
end
stream.finish

duration = stream.frames_pushed / config.sample_rate.to_f
STDERR.puts "played: #{stream.frames_pushed} frames, #{duration.round(2)}s"
STDERR.puts "first audio: #{stream.first_audio_ms.round(1)} ms, synthesis: #{stream.synth_ms.round(1)} ms (RTF #{(stream.synth_ms / 1000 / duration).round(3)})"
