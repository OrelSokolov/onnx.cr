# Cross-platform demo tasks (Linux / macOS / Windows) for the Piper examples.
#
#   rake build            # miniaudio bridge + bin/piper_stream, bin/piper_speak
#   rake play TEXT="..."  # build if needed, stream the text to the speakers
#   rake spec             # unit specs
#   rake clean
#
# Conventions mirror h2code's Rakefile: Ruby rake, the miniaudio bridge is
# built by ext/miniaudio/build.sh (bash — Git for Windows on Windows) which
# prints the link flags on its last line.

require "open3"

MA_DIR = File.expand_path("ext/miniaudio", __dir__)

def windows?
  RUBY_PLATFORM =~ /mingw|mswin|cygwin/i
end

# Build the miniaudio bridge and return the link flags (single source of
# truth: ext/miniaudio/build.sh, shared with manual invocations).
def miniaudio_link_flags
  out, status = Open3.capture2("bash", File.join(MA_DIR, "build.sh"))
  abort "miniaudio bridge build failed (ext/miniaudio/build.sh)" unless status.success?
  out.lines.last.to_s.strip
end

def bin_path(name)
  windows? ? ".\\#{name}.exe" : "./#{name}"
end

# Windows locks a running executable against overwrites; renaming is allowed.
# Move the old binary aside before linking (mirrors h2code's Rakefile).
def rotate_windows_output(output)
  return unless windows?
  exe = File.file?("#{output}.exe") ? "#{output}.exe" : (File.file?(output) ? output : nil)
  return unless exe
  begin
    File.rename(exe, "#{exe}.old") if File.exist?(exe)
  rescue SystemCallError
    warn "warning: could not move #{exe} aside — close it and rebuild."
  end
end

def build_example(source, output)
  mkdir_p File.dirname(output)
  link_flags = miniaudio_link_flags
  rotate_windows_output(output)
  sh "crystal build #{source} -o #{output} --link-flags \"#{link_flags}\""
end

# The irina voice for the demo: download on first use when missing.
def ensure_voice
  model = File.expand_path("examples/assets/ru_RU-irina-medium.onnx", __dir__)
  return model if File.exist?(model)
  mkdir_p File.dirname(model)
  base = "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/irina/medium/ru_RU-irina-medium"
  puts "▶ Downloading irina voice (~63 MB) on first use"
  system("curl", "-sL", "--fail", "-o", model, "#{base}.onnx") || abort("failed to download voice model")
  system("curl", "-sL", "--fail", "-o", "#{model}.json", "#{base}.onnx.json") || abort("failed to download voice config")
  model
end

desc "Build the miniaudio bridge and the demo binaries (bin/piper_stream, bin/piper_speak)"
task :build do
  build_example("examples/piper_stream.cr", "bin/piper_stream")
  build_example("examples/piper_speak.cr", "bin/piper_speak")
end

desc "Stream text to the speakers in real time (rake play TEXT=\"Привет\" SPEED=1.5 TARGET=2.0)"
task :play => :build do |_, args|
  text = ENV["TEXT"] || args.to_a.join(" ")
  abort 'nothing to say: rake play TEXT="Привет"' if text.to_s.strip.empty?
  ensure_voice

  # cmd.exe does not understand the Unix VAR=value prefix — pass flags as
  # plain arguments instead (both examples accept --speed/--target-duration).
  extra = []
  extra += ["--speed", ENV["SPEED"]] if ENV["SPEED"]
  extra += ["--target-duration", ENV["TARGET"]] if ENV["TARGET"]

  sh "#{bin_path("bin/piper_stream")} #{extra.map { |a| %("#{a}") }.join(" ")} #{text.inspect}"
end

# WAV-file variant of the demo (writes out.wav, plays it through miniaudio).
desc "Synthesize TEXT to out.wav and play it (rake wav TEXT=\"Привет\")"
task :wav => :build do |_, args|
  text = ENV["TEXT"] || args.to_a.join(" ")
  abort 'nothing to say: rake wav TEXT="Привет"' if text.to_s.strip.empty?
  ensure_voice
  sh "#{bin_path("bin/piper_speak")} #{text.inspect} --play"
end

desc "Run the unit specs (crystal spec; add TAGS=piper for the integration specs)"
task :spec do
  if ENV["TAGS"]
    sh "crystal spec --tag #{ENV["TAGS"]}"
  else
    sh "crystal spec"
  end
end

desc "Remove build artifacts"
task :clean do
  rm_f Dir.glob("bin/piper_{stream,speak}{,.*}")
  rm_f Dir.glob("#{MA_DIR}/*.{o,obj,a,lib,c}")
end
