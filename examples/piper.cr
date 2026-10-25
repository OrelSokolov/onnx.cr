# Shared Piper TTS pipeline for the examples: espeak-ng phonemization,
# voice config, phoneme-id conversion, WAV writing.
#
# Mirrors rhasspy/piper + piper-phonemize:
#   * clause loop with espeak_TextToPhonemesWithTerminator + CLAUSE_* terminators
#   * NFD-normalized codepoints, (lang) flags filtered out
#   * ids: BOS ^ + pad _ after every phoneme + EOS $
require "../src/onnx"
require "json"

# ------------------------------------------------------- miniaudio bridge
# ext/miniaudio/stream_bridge.c — linked in via ext/miniaudio/build.sh
# link flags (rake build wires them in for both examples).

lib LibMA
  fun ma_stream_start(rate : UInt32, channels : UInt32, buffer_ms : UInt32) : Int32
  fun ma_stream_push(data : Int16*, frames : UInt32) : UInt32
  fun ma_stream_queued : UInt32
  fun ma_stream_free : UInt32
  fun ma_stream_drain
  fun ma_stream_stop
end

# One-shot playback of a PCM16 buffer through the miniaudio device
# (no external player process).
module MaPlayer
  RING_MS = 500

  def self.play(samples : Array(Int16), sample_rate : Int32) : Nil
    rc = LibMA.ma_stream_start(sample_rate.to_u32, 1, RING_MS)
    raise Onnx::Error.new("miniaudio device failed (#{rc})") unless rc == 0
    ptr = samples.to_unsafe
    offset = 0
    while offset < samples.size
      written = LibMA.ma_stream_push(ptr + offset, (samples.size - offset).to_u32).to_i32
      if written == 0
        sleep 5.milliseconds
        next
      end
      offset += written
    end
    LibMA.ma_stream_drain
    LibMA.ma_stream_stop
  end
end

# ---------------------------------------------------------------- espeak-ng

lib LibEspeak
  # espeak_AUDIO_OUTPUT
  AUDIO_OUTPUT_SYNCHRONOUS = 2

  EE_OK             = 0
  EE_INTERNAL_ERROR = -1

  fun init = espeak_Initialize(output : Int32, buflength : Int32,
                               path : UInt8*, options : Int32) : Int32
  fun set_voice_by_name = espeak_SetVoiceByName(name : UInt8*) : Int32
  fun text_to_phonemes_with_terminator = espeak_TextToPhonemesWithTerminator(
    textptr : UInt8**, textmode : Int32, phonememode : Int32,
    terminator : Int32*) : UInt8*
end

module Espeak
  ESPEAK_LIBS = {% if flag?(:windows) %}
    %w(espeak-ng.dll)
  {% else %}
    %w(libespeak-ng.so.1 libespeak-ng.so)
  {% end %}
  @@handle : Void*?

  # espeakCHARS_AUTO | espeakPHONEMES_IPA
  CHARS_AUTO   = 0x00
  PHONEMES_IPA = 0x02

  # espeak-ng clause terminator bits (src/libespeak-ng/translate.h)
  CLAUSE_TYPE_SENTENCE = 0x00080000
  CLAUSE_TYPE_EOF      = 0x00010000
  CLAUSE_PERIOD        = 0x00080028
  CLAUSE_COMMA         = 0x00041014
  CLAUSE_QUESTION      = 0x00082028
  CLAUSE_EXCLAMATION   = 0x0008302D
  CLAUSE_COLON         = 0x0004001E
  CLAUSE_SEMICOLON     = 0x0004101E

  def self.load! : Void*
    @@handle ||= Onnx::RT.open_library(ESPEAK_LIBS, "libespeak-ng")
  end

  private def self.sym(name)
    Onnx::RT.library_symbol(load!, name, "libespeak-ng")
  end

  def self.init! : Nil
    fn = Proc(Int32, Int32, UInt8*, Int32, Int32).new(sym("espeak_Initialize"), Pointer(Void).null)
    rate = fn.call(LibEspeak::AUDIO_OUTPUT_SYNCHRONOUS, 0, Pointer(UInt8).null, 0)
    raise Onnx::Error.new("espeak_Initialize failed") if rate == LibEspeak::EE_INTERNAL_ERROR
  end

  def self.set_voice!(name : String) : Nil
    fn = Proc(UInt8*, Int32).new(sym("espeak_SetVoiceByName"), Pointer(Void).null)
    fn.call(name.to_unsafe) == LibEspeak::EE_OK ||
      raise Onnx::Error.new("failed to set espeak-ng voice #{name}")
  end

  # Splits text into sentence phoneme lists (IPA codepoints),
  # following piper-phonemize's phonemize_eSpeak.
  def self.phonemize(text : String, voice : String) : Array(Array(String))
    set_voice!(voice)

    to_phonemes = Proc(UInt8**, Int32, Int32, Int32*, UInt8*)
      .new(sym("espeak_TextToPhonemesWithTerminator"), Pointer(Void).null)

    sentences = [] of Array(String)
    current = [] of String

    # espeak advances this pointer; NULL means done
    text_ptr_box = [text.to_unsafe]
    ptr_ptr = text_ptr_box.to_unsafe.as(UInt8**)

    loop do
      terminator = uninitialized Int32
      phonemes_ptr = to_phonemes.call(ptr_ptr, CHARS_AUTO, PHONEMES_IPA, pointerof(terminator))
      break if ptr_ptr[0].null? && phonemes_ptr.null?
      break if phonemes_ptr.null? && (terminator & CLAUSE_TYPE_EOF) != 0

      clause = phonemes_ptr.null? ? "" : String.new(phonemes_ptr).unicode_normalize(:nfd)

      # Filter out (lang) switch flags
      in_lang_flag = false
      clause.each_char do |ch|
        if in_lang_flag
          in_lang_flag = false if ch == ')'
        elsif ch == '('
          in_lang_flag = true
        else
          current << ch.to_s
        end
      end

      # Punctuation from the clause terminator
      punctuation = terminator & 0x000FFFFF
      case punctuation
      when CLAUSE_PERIOD      then current << "."
      when CLAUSE_QUESTION    then current << "?"
      when CLAUSE_EXCLAMATION then current << "!"
      when CLAUSE_COMMA       then current << ","; current << " "
      when CLAUSE_COLON       then current << ":"; current << " "
      when CLAUSE_SEMICOLON   then current << ";"; current << " "
      end

      if (terminator & CLAUSE_TYPE_SENTENCE) == CLAUSE_TYPE_SENTENCE
        sentences << current unless current.empty?
        current = [] of String
      end

      break if ptr_ptr[0].null?
    end

    sentences << current unless current.empty?
    sentences
  end
end

# ------------------------------------------------------------------ config

struct PiperConfig
  getter sample_rate : Int32
  getter voice : String
  getter noise_scale : Float32
  getter length_scale : Float32
  getter noise_w : Float32
  getter sentence_silence : Float32
  getter phoneme_id_map : Hash(String, Array(Int64))

  def self.from_json(path : String) : PiperConfig
    root = JSON.parse(File.read(path))
    audio = root["audio"]
    inference = root["inference"]?
    espeak = root["espeak"]?

    id_map = Hash(String, Array(Int64)).new
    root["phoneme_id_map"].as_h.each do |phoneme, ids|
      id_map[phoneme] = ids.as_a.map(&.as_i64)
    end

    new(
      sample_rate: audio["sample_rate"].as_i,
      voice: espeak.try &.["voice"]?.try(&.as_s) || "ru",
      noise_scale: (inference.try(&.["noise_scale"]?).try(&.as_f) || 0.667).to_f32,
      length_scale: (inference.try(&.["length_scale"]?).try(&.as_f) || 1.0).to_f32,
      noise_w: (inference.try(&.["noise_w"]?).try(&.as_f) || 0.8).to_f32,
      sentence_silence: (inference.try(&.["sentence_silence"]?).try(&.as_f) || 0.2).to_f32,
      phoneme_id_map: id_map
    )
  end

  def initialize(@sample_rate, @voice, @noise_scale, @length_scale,
                 @noise_w, @sentence_silence, @phoneme_id_map)
  end

  # Appends ids for one sentence into `ids` (reusable buffer) instead of
  # allocating a new array per sentence. Returns false if nothing was added.
  # Piper phonemes_to_ids with addBos/addEos/interspersePad (the defaults):
  # ^ _ (p1 _) (p2 _) ... $
  def phonemes_to_ids(phonemes : Array(String), ids : Array(Int64)) : Bool
    bos = phoneme_id_map["^"]?
    eos = phoneme_id_map["$"]?
    pad = phoneme_id_map["_"]?
    return false unless bos && eos && pad

    start = ids.size
    ids.concat(bos)
    ids.concat(pad)
    phonemes.each do |phoneme|
      mapped = phoneme_id_map[phoneme]?
      next STDERR.puts "warning: unmapped phoneme #{phoneme.inspect}" unless mapped
      ids.concat(mapped)
      ids.concat(pad)
    end
    ids.concat(eos)
    ids.size > start + 2
  end
end

# ------------------------------------------------------------------ wav out

module WavWriter
  def self.write(path : String, samples : Array(Int16), sample_rate : Int32) : Nil
    data_size = samples.size * 2
    File.open(path, "w") do |f|
      f.write "RIFF".to_slice
      f.write_bytes((36 + data_size).to_u32, IO::ByteFormat::LittleEndian)
      f.write "WAVE".to_slice
      f.write "fmt ".to_slice
      f.write_bytes(16.to_u32, IO::ByteFormat::LittleEndian)
      f.write_bytes(1.to_u16, IO::ByteFormat::LittleEndian)      # PCM
      f.write_bytes(1.to_u16, IO::ByteFormat::LittleEndian)      # mono
      f.write_bytes(sample_rate.to_u32, IO::ByteFormat::LittleEndian)
      f.write_bytes((sample_rate * 2).to_u32, IO::ByteFormat::LittleEndian)
      f.write_bytes(2.to_u16, IO::ByteFormat::LittleEndian)      # block align
      f.write_bytes(16.to_u16, IO::ByteFormat::LittleEndian)     # bits
      f.write "data".to_slice
      f.write_bytes(data_size.to_u32, IO::ByteFormat::LittleEndian)
      samples.each { |s| f.write_bytes(s, IO::ByteFormat::LittleEndian) }
    end
  end
end
