require "./spec_helper"

# Integration spec against a real Piper voice (downloads on first run).
# Run with: crystal spec --tag piper

MODEL = File.join(__DIR__, "..", "examples", "assets", "ru_RU-irina-medium.onnx")

def ensure_model : String
  unless File.exists?(MODEL)
    Dir.mkdir_p(File.dirname(MODEL))
    url = "https://huggingface.co/rhasspy/piper-voices/resolve/main/ru/ru_RU/irina/medium/ru_RU-irina-medium.onnx"
    unless system("curl", {"-sL", "--fail", "-o", MODEL, url})
      raise "failed to download test model"
    end
  end
  MODEL
end

describe "piper voice integration", tags: "piper" do
  it "loads and runs the model" do
    session = Onnx::Session.new(ensure_model)
    session.input_names.should eq(["input", "input_lengths", "scales"])
    session.output_names.should eq(["output"])

    ids = [0_i64, 1_i64, 2_i64, 3_i64, 4_i64, 5_i64, 6_i64, 7_i64, 8_i64, 0_i64]
    out = session.run({
      "input"         => Onnx::Value.i64(ids, [1_i64, ids.size.to_i64]),
      "input_lengths" => Onnx::Value.i64([ids.size.to_i64], [1_i64]),
      "scales"        => Onnx::Value.f32([0.667_f32, 1.0_f32, 0.8_f32], [3_i64]),
    })
    audio = out["output"]
    audio.shape.product.should be > 100
    audio.to_i16s.size.should be > 100
  end

  it "decodes without allocating (read_i16s_into, tensor_nocopy)" do
    session = Onnx::Session.new(ensure_model)
    ids = [0_i64, 1_i64, 2_i64, 3_i64, 4_i64, 5_i64, 6_i64, 7_i64, 8_i64, 0_i64]

    # Reusable buffers, as the streaming example uses them.
    ids_bytes = Slice(UInt8).new(ids.size * 8)
    ids.each_with_index { |v, i| ids_bytes.to_unsafe.as(Pointer(Int64))[i] = v }
    shape = Slice(Int64).new(2) { |i| (i == 0 ? 1 : ids.size).to_i64 }

    buf = Array(Int16).new
    2.times do
      input = Onnx::Value.tensor_nocopy(ids_bytes, shape, LibOnnx::ElementType::INT64)
      run_result = session.run({
        "input"         => input,
        "input_lengths" => Onnx::Value.i64([ids.size.to_i64], [1_i64]),
        "scales"        => Onnx::Value.f32([0.667_f32, 1.0_f32, 0.8_f32], [3_i64]),
      })
      count = run_result["output"].read_i16s_into(buf)
      count.should be > 100
      buf.size.should be >= count
      buf[0, count].should eq(run_result["output"].to_i16s)
    end
  end
end
