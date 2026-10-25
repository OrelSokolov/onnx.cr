require "./spec_helper"

describe Onnx::RT do
  it "raises a clear error when the library cannot be loaded" do
    lib_paths = Onnx::RT.lib_paths
    ENV["ONNX_RUNTIME_LIB"] = "/nonexistent/libonnxruntime.so"
    Onnx::RT.reset!
    expect_raises(Onnx::Error, /not found/) do
      Onnx::RT.api
    end
    ENV.delete("ONNX_RUNTIME_LIB")
    Onnx::RT.reset!
    Onnx::RT.api.should_not be_nil
  end
end

describe Onnx::Session do
  it "raises when the model file does not exist" do
    expect_raises(Onnx::Error, /not found/) do
      Onnx::Session.new("/nonexistent/model.onnx")
    end
  end

  it "raises on a corrupt model file" do
    File.write("/tmp/onnx_cr_bad.onnx", "not an onnx model")
    expect_raises(Onnx::Error) do
      Onnx::Session.new("/tmp/onnx_cr_bad.onnx")
    end
  ensure
    File.delete("/tmp/onnx_cr_bad.onnx") if File.exists?("/tmp/onnx_cr_bad.onnx")
  end
end

describe Onnx::Value do
  it "decodes float16" do
    # 0x3C00 = 1.0, 0x4000 = 2.0, 0x0000 = 0.0, 0x8000 = -0.0
    Onnx::Value.f16_to_f32(0x3C00_u16).should eq(1.0_f32)
    Onnx::Value.f16_to_f32(0x4000_u16).should eq(2.0_f32)
    Onnx::Value.f16_to_f32(0x0000_u16).should eq(0.0_f32)
  end
end
