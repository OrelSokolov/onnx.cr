# Piper TTS → WAV file. See piper.cr for the pipeline and piper_stream.cr
# for real-time playback.
#
#   crystal run examples/piper_speak.cr -- "Привет, мир" [--play]
require "./piper"

if ARGV.empty?
  STDERR.puts "usage: piper_speak <text...> [--play]"
  exit 1
end
play = ARGV.delete("--play")
text = ARGV.join(" ")

assets = File.join(__DIR__, "assets")
model_path = ENV["PIPER_MODEL"]? || File.join(assets, "ru_RU-irina-medium.onnx")
config_path = "#{model_path}.json"

t_start = Time.instant

config = PiperConfig.from_json(config_path)
session = Onnx::Session.new(model_path, threads: 1)
Espeak.init!

t0 = Time.instant
sentences = Espeak.phonemize(text, config.voice)
t1 = Time.instant
STDERR.puts "phonemize: #{sentences.size} sentence(s) in #{(t1 - t0).total_milliseconds.round(1)} ms"

audio = Array(Int16).new
silence = (config.sentence_silence * config.sample_rate).to_i
ids = Array(Int64).new

infer_ms = 0.0
sentences.each do |phonemes|
  ids.clear
  next unless config.phonemes_to_ids(phonemes, ids)

  t0 = Time.instant
  run_result = session.run({
    "input"         => Onnx::Value.i64(ids, [1_i64, ids.size.to_i64]),
    "input_lengths" => Onnx::Value.i64([ids.size.to_i64], [1_i64]),
    "scales"        => Onnx::Value.f32(
      [config.noise_scale.to_f32, config.length_scale.to_f32, config.noise_w.to_f32],
      [3_i64]
    ),
  })
  t1 = Time.instant
  infer_ms += (t1 - t0).total_milliseconds

  audio.concat(run_result["output"].to_i16s)
  audio.concat(Array(Int16).new(silence, 0_i16)) if silence > 0
end

WavWriter.write("out.wav", audio, config.sample_rate)
duration = audio.size / config.sample_rate
STDERR.puts "audio: #{audio.size} samples, #{duration.round(2)}s at #{config.sample_rate} Hz"
STDERR.puts "inference: #{infer_ms.round(1)} ms total (RTF #{(infer_ms / 1000 / duration).round(3)})"
STDERR.puts "total: #{((Time.instant - t_start).total_milliseconds).round(1)} ms -> out.wav"

MaPlayer.play(audio, config.sample_rate) if play
