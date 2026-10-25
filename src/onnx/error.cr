module Onnx
  # Raised for any ONNX Runtime failure (status messages, load errors).
  class Error < Exception
  end

  module RT
    # Raises Onnx::Error with the message from an OrtStatus and releases it.
    def self.check(status : LibOnnx::OrtStatus*) : Nil
      return if status.null?
      msg = api.value.get_error_message.call(status)
      message = msg.null? ? "unknown onnxruntime error" : String.new(msg)
      api.value.release_status.call(status)
      raise Error.new(message)
    end
  end
end
