module Onnx
  # An inference session over a .onnx model file.
  class Session
    getter ptr : LibOnnx::OrtSession*
    @options : LibOnnx::OrtSessionOptions*
    @input_names : Array(String)?
    @output_names : Array(String)?

    def initialize(path : String, threads : Int32 = 1)
      unless File.exists?(path)
        raise Error.new("model file not found: #{path}")
      end

      options = uninitialized LibOnnx::OrtSessionOptions*
      RT.check RT.api.value.create_session_options.call(pointerof(options))
      RT.check RT.api.value.set_intra_op_num_threads.call(options, threads)

      session = uninitialized LibOnnx::OrtSession*
      RT.check RT.api.value.create_session.call(
        RT.env, path.to_unsafe, options, pointerof(session)
      )

      @ptr = session
      @options = options
    end

    def input_count : Int32
      count = uninitialized LibC::SizeT
      RT.check RT.api.value.session_get_input_count.call(@ptr, pointerof(count))
      count.to_i32
    end

    def output_count : Int32
      count = uninitialized LibC::SizeT
      RT.check RT.api.value.session_get_output_count.call(@ptr, pointerof(count))
      count.to_i32
    end

    def input_names : Array(String)
      @input_names ||= names_of(:input)
    end

    def output_names : Array(String)
      @output_names ||= names_of(:output)
    end

    def run(inputs : Hash(String, Value)) : Hash(String, Value)
      out_names = output_names
      in_names = inputs.keys

      name_ptrs = in_names.map(&.to_unsafe)
      value_ptrs = inputs.values.map(&.ptr)
      out_name_ptrs = out_names.map(&.to_unsafe)
      outputs = Pointer(Pointer(LibOnnx::OrtValue)).malloc(out_names.size)

      RT.check RT.api.value.run.call(
        @ptr,
        Pointer(LibOnnx::OrtRunOptions).null,
        name_ptrs.to_unsafe, value_ptrs.to_unsafe, inputs.size.to_u64!,
        out_name_ptrs.to_unsafe, out_names.size.to_u64!, outputs
      )

      result = Hash(String, Value).new
      out_names.each_with_index do |name, i|
        result[name] = Value.new(outputs[i])
      end
      result
    end

    private def names_of(kind : Symbol) : Array(String)
      count = kind == :input ? input_count : output_count
      Array(String).new(count) do |i|
        name_ptr = uninitialized UInt8*
        index = LibC::SizeT.new(i)
        if kind == :input
          RT.check RT.api.value.session_get_input_name.call(@ptr, index, RT.allocator, pointerof(name_ptr))
        else
          RT.check RT.api.value.session_get_output_name.call(@ptr, index, RT.allocator, pointerof(name_ptr))
        end
        name = String.new(name_ptr)
        RT.allocator.value.free.call(RT.allocator, name_ptr.as(Void*))
        name
      end
    end

    def finalize
      if api = RT.api?
        api.value.release_session.call(@ptr) unless @ptr.null?
        api.value.release_session_options.call(@options) unless @options.null?
      end
    end
  end
end
