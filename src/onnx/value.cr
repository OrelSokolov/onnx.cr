module Onnx
  # Wraps an OrtValue tensor. Input tensors own their data buffer
  # (ONNX Runtime references the memory, it does not copy it); output
  # tensors borrow memory owned by the runtime.
  class Value
    getter ptr : LibOnnx::OrtValue*
    @buffer : Void*?
    # Keeps a borrowed data buffer alive (ONNX Runtime references, not copies).
    @owner : Slice(UInt8)?

    def initialize(@ptr : LibOnnx::OrtValue*, @buffer : Void*? = nil, @owner : Slice(UInt8)? = nil)
    end

    # Creates a tensor from a byte buffer (no conversion). `shape` is only
    # used by the runtime; data must contain shape.product * type.bytesize bytes.
    def self.tensor(data : Slice(UInt8), shape : Array(Int64),
                    type : LibOnnx::ElementType) : Value
      buffer = GC.malloc_atomic(data.size)
      data.to_unsafe.copy_to(buffer.as(UInt8*), data.size)

      shape_ptr = Pointer(Int64).malloc(shape.size)
      shape.each_with_index { |v, i| shape_ptr[i] = v }

      out_ptr = uninitialized LibOnnx::OrtValue*
      RT.check RT.api.value.create_tensor_with_data_as_ort_value.call(
        RT.memory_info, buffer, data.size.to_u64!, shape_ptr, shape.size.to_u64!, type.value, pointerof(out_ptr)
      )
      new(out_ptr, buffer)
    end

    # Wraps an existing buffer as a tensor without copying (allocation-free
    # path for streaming: fill `data` in place and recreate the Value).
    # The caller must keep `data` alive as long as the Value exists.
    def self.tensor_nocopy(data : Slice(UInt8), shape : Array(Int64) | Slice(Int64),
                           type : LibOnnx::ElementType) : Value
      shape_ptr = Pointer(Int64).malloc(shape.size)
      shape.each_with_index { |v, i| shape_ptr[i] = v }

      out_ptr = uninitialized LibOnnx::OrtValue*
      RT.check RT.api.value.create_tensor_with_data_as_ort_value.call(
        RT.memory_info, data.to_unsafe.as(Void*), data.size.to_u64!,
        shape_ptr, shape.size.to_u64!, type.value, pointerof(out_ptr)
      )
      new(out_ptr, data.to_unsafe.as(Void*), data)
    end

    def self.i64(values : Array(Int64) | Slice(Int64), shape : Array(Int64)) : Value
      slice = values.is_a?(Slice(Int64)) ? values : Slice.new(values.size) { |i| values[i] }
      bytes = Slice(UInt8).new(slice.to_unsafe.as(Pointer(UInt8)), slice.size * 8)
      tensor(bytes, shape, LibOnnx::ElementType::INT64)
    end

    def self.f32(values : Array(Float32) | Slice(Float32), shape : Array(Int64)) : Value
      slice = values.is_a?(Slice(Float32)) ? values : Slice.new(values.size) { |i| values[i] }
      bytes = Slice(UInt8).new(slice.to_unsafe.as(Pointer(UInt8)), slice.size * 4)
      tensor(bytes, shape, LibOnnx::ElementType::FLOAT)
    end

    private def with_tensor_type_info(& : LibOnnx::OrtTensorTypeAndShapeInfo* -> R) forall R
      type_info = uninitialized LibOnnx::OrtTypeInfo*
      RT.check RT.api.value.get_type_info.call(@ptr, pointerof(type_info))
      tensor_info = uninitialized LibOnnx::OrtTensorTypeAndShapeInfo*
      RT.check RT.api.value.cast_type_info_to_tensor_info.call(type_info, pointerof(tensor_info))
      result = yield tensor_info
      # tensor_info is owned by type_info (see CastTypeInfoToTensorInfo docs:
      # "Do not free this value"), releasing it here would double-free.
      RT.api.value.release_type_info.call(type_info)
      result
    end

    def element_type : LibOnnx::ElementType
      with_tensor_type_info do |tensor_info|
        et = uninitialized Int32
        RT.check RT.api.value.get_tensor_element_type.call(tensor_info, pointerof(et))
        LibOnnx::ElementType.from_value(et)
      end
    end

    def shape : Array(Int64)
      with_tensor_type_info do |tensor_info|
        count = uninitialized LibC::SizeT
        RT.check RT.api.value.get_dimensions_count.call(tensor_info, pointerof(count))
        dims = Pointer(Int64).malloc(count)
        RT.check RT.api.value.get_dimensions.call(tensor_info, dims, count)
        Array(Int64).new(count.to_i32) { |i| dims[i] }
      end
    end

    # Raw pointer to the tensor data (do not free).
    def data : Void*
      out_ptr = uninitialized Void*
      RT.check RT.api.value.get_tensor_mutable_data.call(@ptr, pointerof(out_ptr))
      out_ptr
    end

    # Element count (product of dims).
    def size : Int64
      shape.product
    end

    # Decodes numeric tensors to Float32 (handles FLOAT16, FLOAT, DOUBLE).
    def to_f32s : Array(Float32)
      type = element_type
      count = size
      ptr = data
      Array(Float32).new(count.to_i32) do |i|
        case type
        when .float16?       then Value.f16_to_f32(ptr.as(UInt16*)[i])
        when .float?         then ptr.as(Float32*)[i]
        when .double?        then ptr.as(Float64*)[i].to_f32
        when .int16?         then ptr.as(Int16*)[i].to_f32
        when .int32?         then ptr.as(Int32*)[i].to_f32
        when .int64?         then ptr.as(Int64*)[i].to_f32
        else
          raise Error.new("cannot decode element type #{type} to Float32")
        end
      end
    end

    # Decodes waveform tensors to Int16 PCM (scales float audio from [-1,1]).
    def to_i16s : Array(Int16)
      case element_type
      when .int16?
        ptr = data.as(Pointer(Int16))
        Array(Int16).new(size.to_i32) { |i| ptr[i] }
      when .float16?, .float?, .double?
        to_f32s.map do |f|
          v = (f.clamp(-1.0, 1.0) * 32767.0).round.to_i32
          v.to_i16
        end
      else
        raise Error.new("cannot decode element type #{element_type} to Int16")
      end
    end

    # Decodes waveform tensors to Int16 PCM in place, without allocating:
    # writes into `buf` (grown only when a longer result appears — do not
    # clear it between calls) and returns the sample count. Only the first
    # `count` entries of `buf` are valid. Float audio in [-1,1] is scaled
    # to PCM16.
    def read_i16s_into(buf : Array(Int16)) : Int32
      type = element_type
      count = size.to_i32
      if buf.size < count
        (count - buf.size).times { buf << 0_i16 }
      end
      dst = buf.to_unsafe

      decode = ->(f : Float64) do
        (f.clamp(-1.0, 1.0) * 32767.0).round.to_i16
      end

      case type
      when .int16?
        src = data.as(Pointer(Int16))
        count.times { |i| dst[i] = src[i] }
      when .float16?
        src = data.as(Pointer(UInt16))
        count.times { |i| dst[i] = decode.call(Value.f16_to_f32(src[i]).to_f64) }
      when .float?
        src = data.as(Pointer(Float32))
        count.times { |i| dst[i] = decode.call(src[i].to_f64) }
      when .double?
        src = data.as(Pointer(Float64))
        count.times { |i| dst[i] = decode.call(src[i]) }
      else
        raise Error.new("cannot decode element type #{type} to Int16")
      end
      count
    end

    # IEEE 754 half → float.
    def self.f16_to_f32(h : UInt16) : Float32
      sign = h.bit(15) == 1 ? -1.0_f32 : 1.0_f32
      exp = ((h >> 10) & 0x1F).to_i32
      frac = (h & 0x3FF).to_f32
      case exp
      when 0
        sign * frac * (2.0 ** -24).to_f32
      when 31
        frac == 0 ? sign * Float32::INFINITY : Float32::NAN
      else
        sign * (1.0 + frac / 1024.0).to_f32 * (2.0 ** (exp - 15)).to_f32
      end
    end

    def finalize
      if api = RT.api?
        api.value.release_value.call(@ptr) unless @ptr.null?
      end
    end
  end
end
