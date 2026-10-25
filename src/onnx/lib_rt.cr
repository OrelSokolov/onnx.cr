# Raw ONNX Runtime C API bindings.
#
# Generated against onnxruntime_c_api.h v1.21.0 (ORT_API_VERSION 21).
# `struct OrtApi` fields follow the exact header order; unused members are
# `Void*` padding so that typed members land on the correct offsets.
#
# The library is loaded at runtime (`dlopen` on Unix, `LoadLibraryA` on
# Windows), so no link-time dependency on libonnxruntime (and no -dev
# package) is required.

{% unless flag?(:windows) %}
  @[Link("dl")]
  lib LibDL
    fun dlopen = dlopen(filename : UInt8*, flag : Int32) : Void*
    fun dlsym = dlsym(handle : Void*, symbol : UInt8*) : Void*
    fun dlerror = dlerror : UInt8*
  end
{% else %}
  @[Link("kernel32")]
  lib LibKernel32
    fun load_library_a = LoadLibraryA(name : UInt8*) : Void*
    fun get_proc_address = GetProcAddress(module : Void*, name : UInt8*) : Void*
  end
{% end %}

lib LibOnnx
  RTLD_NOW = 2

  type OrtStatus = Void
  type OrtEnv = Void
  type OrtSession = Void
  type OrtSessionOptions = Void
  type OrtMemoryInfo = Void
  type OrtValue = Void
  type OrtTypeInfo = Void
  type OrtTensorTypeAndShapeInfo = Void
  type OrtRunOptions = Void

  struct OrtApiBase
    get_api : UInt32 -> OrtApi*
    get_version_string : -> UInt8*
  end

  # ONNXTensorElementDataType
  enum ElementType : Int32
    UNDEFINED = 0
    FLOAT     = 1
    UINT8     = 2
    INT8      = 3
    UINT16    = 4
    INT16     = 5
    INT32     = 6
    INT64     = 7
    STRING    = 8
    BOOL      = 9
    FLOAT16   = 10
    DOUBLE    = 11
    UINT32    = 12
    UINT64    = 13
    BFLOAT16  = 16

    def bytesize : Int32
      case self
      when FLOAT, INT32, UINT32               then 4
      when FLOAT16, BFLOAT16, INT16, UINT16   then 2
      when INT8, UINT8, BOOL                  then 1
      when INT64, UINT64, DOUBLE              then 8
      else raise Error.new("unsupported element type #{self}")
      end
    end
  end

  struct OrtAllocator
    version : UInt32
    alloc : OrtAllocator*, LibC::SizeT -> Void*
    free : OrtAllocator*, Void* -> Void
    info : OrtAllocator* -> OrtMemoryInfo*
    reserve : OrtAllocator*, LibC::SizeT -> Void*
  end

  struct OrtApi
    m0_create_status : Void*
    m1_get_error_code : Void*
    get_error_message : OrtStatus* -> UInt8*
    create_env : Int32, UInt8*, OrtEnv** -> OrtStatus*
    m4_create_env_with_custom_logger : Void*
    m5_enable_telemetry_events : Void*
    m6_disable_telemetry_events : Void*
    create_session : OrtEnv*, UInt8*, OrtSessionOptions*, OrtSession** -> OrtStatus*
    m8_create_session_from_array : Void*
    run : OrtSession*, OrtRunOptions*, UInt8**, OrtValue**, LibC::SizeT, UInt8**, LibC::SizeT, OrtValue** -> OrtStatus*
    create_session_options : OrtSessionOptions** -> OrtStatus*
    m11_set_optimized_model_file_path : Void*
    m12_clone_session_options : Void*
    m13_set_session_execution_mode : Void*
    m14_enable_profiling : Void*
    m15_disable_profiling : Void*
    m16_enable_mem_pattern : Void*
    m17_disable_mem_pattern : Void*
    m18_enable_cpu_mem_arena : Void*
    m19_disable_cpu_mem_arena : Void*
    m20_set_session_log_id : Void*
    m21_set_session_log_verbosity_level : Void*
    m22_set_session_log_severity_level : Void*
    m23_set_session_graph_optimization_level : Void*
    set_intra_op_num_threads : OrtSessionOptions*, Int32 -> OrtStatus*
    m25_set_inter_op_num_threads : Void*
    m26_create_custom_op_domain : Void*
    m27_custom_op_domain__add : Void*
    m28_add_custom_op_domain : Void*
    m29_register_custom_ops_library : Void*
    session_get_input_count : OrtSession*, LibC::SizeT* -> OrtStatus*
    session_get_output_count : OrtSession*, LibC::SizeT* -> OrtStatus*
    m32_session_get_overridable_initializer_count : Void*
    m33_session_get_input_type_info : Void*
    m34_session_get_output_type_info : Void*
    m35_session_get_overridable_initializer_type_info : Void*
    session_get_input_name : OrtSession*, LibC::SizeT, OrtAllocator*, UInt8** -> OrtStatus*
    session_get_output_name : OrtSession*, LibC::SizeT, OrtAllocator*, UInt8** -> OrtStatus*
    m38_session_get_overridable_initializer_name : Void*
    m39_create_run_options : Void*
    m40_run_options_set_run_log_verbosity_level : Void*
    m41_run_options_set_run_log_severity_level : Void*
    m42_run_options_set_run_tag : Void*
    m43_run_options_get_run_log_verbosity_level : Void*
    m44_run_options_get_run_log_severity_level : Void*
    m45_run_options_get_run_tag : Void*
    m46_run_options_set_terminate : Void*
    m47_run_options_unset_terminate : Void*
    m48_create_tensor_as_ort_value : Void*
    create_tensor_with_data_as_ort_value : OrtMemoryInfo*, Void*, LibC::SizeT, Int64*, LibC::SizeT, Int32, OrtValue** -> OrtStatus*
    m50_is_tensor : Void*
    get_tensor_mutable_data : OrtValue*, Void** -> OrtStatus*
    m52_fill_string_tensor : Void*
    m53_get_string_tensor_data_length : Void*
    m54_get_string_tensor_content : Void*
    cast_type_info_to_tensor_info : OrtTypeInfo*, OrtTensorTypeAndShapeInfo** -> OrtStatus*
    m56_get_onnx_type_from_type_info : Void*
    m57_create_tensor_type_and_shape_info : Void*
    m58_set_tensor_element_type : Void*
    m59_set_dimensions : Void*
    get_tensor_element_type : OrtTensorTypeAndShapeInfo*, Int32* -> OrtStatus*
    get_dimensions_count : OrtTensorTypeAndShapeInfo*, LibC::SizeT* -> OrtStatus*
    get_dimensions : OrtTensorTypeAndShapeInfo*, Int64*, LibC::SizeT -> OrtStatus*
    m63_get_symbolic_dimensions : Void*
    m64_get_tensor_shape_element_count : Void*
    m65_get_tensor_type_and_shape : Void*
    get_type_info : OrtValue*, OrtTypeInfo** -> OrtStatus*
    m67_get_value_type : Void*
    m68_create_memory_info : Void*
    create_cpu_memory_info : Int32, Int32, OrtMemoryInfo** -> OrtStatus*
    m70_compare_memory_info : Void*
    m71_memory_info_get_name : Void*
    m72_memory_info_get_id : Void*
    m73_memory_info_get_mem_type : Void*
    m74_memory_info_get_type : Void*
    m75_allocator_alloc : Void*
    m76_allocator_free : Void*
    m77_allocator_get_info : Void*
    get_allocator_with_default_options : OrtAllocator** -> OrtStatus*
    m79_add_free_dimension_override : Void*
    m80_get_value : Void*
    m81_get_value_count : Void*
    m82_create_value : Void*
    m83_create_opaque_value : Void*
    m84_get_opaque_value : Void*
    m85_kernel_info_get_attribute_float : Void*
    m86_kernel_info_get_attribute_int64 : Void*
    m87_kernel_info_get_attribute_string : Void*
    m88_kernel_context__get_input_count : Void*
    m89_kernel_context__get_output_count : Void*
    m90_kernel_context__get_input : Void*
    m91_kernel_context__get_output : Void*
    release_env : OrtEnv* -> Void
    release_status : OrtStatus* -> Void
    release_memory_info : OrtMemoryInfo* -> Void
    release_session : OrtSession* -> Void
    release_value : OrtValue* -> Void
    m97_release_run_options : Void*
    release_type_info : OrtTypeInfo* -> Void
    release_tensor_type_and_shape_info : OrtTensorTypeAndShapeInfo* -> Void
    release_session_options : OrtSessionOptions* -> Void
    m101_release_custom_op_domain : Void*
    m102_get_denotation_from_type_info : Void*
    m103_cast_type_info_to_map_type_info : Void*
    m104_cast_type_info_to_sequence_type_info : Void*
    m105_get_map_key_type : Void*
    m106_get_map_value_type : Void*
    m107_get_sequence_element_type : Void*
    m108_release_map_type_info : Void*
    m109_release_sequence_type_info : Void*
    m110_session_end_profiling : Void*
    m111_session_get_model_metadata : Void*
    m112_model_metadata_get_producer_name : Void*
    m113_model_metadata_get_graph_name : Void*
    m114_model_metadata_get_domain : Void*
    m115_model_metadata_get_description : Void*
    m116_model_metadata_lookup_custom_metadata_map : Void*
    m117_model_metadata_get_version : Void*
    m118_release_model_metadata : Void*
    m119_create_env_with_global_thread_pools : Void*
    m120_disable_per_session_threads : Void*
    m121_create_threading_options : Void*
    m122_release_threading_options : Void*
    m123_model_metadata_get_custom_metadata_map_keys : Void*
    m124_add_free_dimension_override_by_name : Void*
    m125_get_available_providers : Void*
    m126_release_available_providers : Void*
    m127_get_string_tensor_element_length : Void*
    m128_get_string_tensor_element : Void*
    m129_fill_string_tensor_element : Void*
    m130_add_session_config_entry : Void*
    m131_create_allocator : Void*
    m132_release_allocator : Void*
    m133_run_with_binding : Void*
    m134_create_io_binding : Void*
    m135_release_io_binding : Void*
    m136_bind_input : Void*
    m137_bind_output : Void*
    m138_bind_output_to_device : Void*
    m139_get_bound_output_names : Void*
    m140_get_bound_output_values : Void*
    m141_clear_bound_inputs : Void*
    m142_clear_bound_outputs : Void*
    m143_tensor_at : Void*
    m144_create_and_register_allocator : Void*
    m145_set_language_projection : Void*
    m146_session_get_profiling_start_time_ns : Void*
    m147_set_global_intra_op_num_threads : Void*
    m148_set_global_inter_op_num_threads : Void*
    m149_set_global_spin_control : Void*
    m150_add_initializer : Void*
    m151_create_env_with_custom_logger_and_global_thread_pools : Void*
    m152_session_options_append_execution_provider__c_u_d_a : Void*
    m153_session_options_append_execution_provider__r_o_c_m : Void*
    m154_session_options_append_execution_provider__open_v_i_n_o : Void*
    m155_set_global_denormal_as_zero : Void*
    m156_create_arena_cfg : Void*
    m157_release_arena_cfg : Void*
    m158_model_metadata_get_graph_description : Void*
    m159_session_options_append_execution_provider__tensor_r_t : Void*
    m160_set_current_gpu_device_id : Void*
    m161_get_current_gpu_device_id : Void*
    m162_kernel_info_get_attribute_array_float : Void*
    m163_kernel_info_get_attribute_array_int64 : Void*
    m164_create_arena_cfg_v2 : Void*
    m165_add_run_config_entry : Void*
    m166_create_prepacked_weights_container : Void*
    m167_release_prepacked_weights_container : Void*
    m168_create_session_with_prepacked_weights_container : Void*
    m169_create_session_from_array_with_prepacked_weights_container : Void*
    m170_session_options_append_execution_provider__tensor_r_t__v2 : Void*
    m171_create_tensor_r_t_provider_options : Void*
    m172_update_tensor_r_t_provider_options : Void*
    m173_get_tensor_r_t_provider_options_as_string : Void*
    m174_release_tensor_r_t_provider_options : Void*
    m175_enable_ort_custom_ops : Void*
    m176_register_allocator : Void*
    m177_unregister_allocator : Void*
    m178_is_sparse_tensor : Void*
    m179_create_sparse_tensor_as_ort_value : Void*
    m180_fill_sparse_tensor_coo : Void*
    m181_fill_sparse_tensor_csr : Void*
    m182_fill_sparse_tensor_block_sparse : Void*
    m183_create_sparse_tensor_with_values_as_ort_value : Void*
    m184_use_coo_indices : Void*
    m185_use_csr_indices : Void*
    m186_use_block_sparse_indices : Void*
    m187_get_sparse_tensor_format : Void*
    m188_get_sparse_tensor_values_type_and_shape : Void*
    m189_get_sparse_tensor_values : Void*
    m190_get_sparse_tensor_indices_type_shape : Void*
    m191_get_sparse_tensor_indices : Void*
    m192_has_value : Void*
    m193_kernel_context__get_g_p_u_compute_stream : Void*
    m194_get_tensor_memory_info : Void*
    m195_get_execution_provider_api : Void*
    m196_session_options_set_custom_create_thread_fn : Void*
    m197_session_options_set_custom_thread_creation_options : Void*
    m198_session_options_set_custom_join_thread_fn : Void*
    m199_set_global_custom_create_thread_fn : Void*
    m200_set_global_custom_thread_creation_options : Void*
    m201_set_global_custom_join_thread_fn : Void*
    m202_synchronize_bound_inputs : Void*
    m203_synchronize_bound_outputs : Void*
    m204_session_options_append_execution_provider__c_u_d_a__v2 : Void*
    m205_create_c_u_d_a_provider_options : Void*
    m206_update_c_u_d_a_provider_options : Void*
    m207_get_c_u_d_a_provider_options_as_string : Void*
    m208_release_c_u_d_a_provider_options : Void*
    m209_session_options_append_execution_provider__m_i_graph_x : Void*
    m210_add_external_initializers : Void*
    m211_create_op_attr : Void*
    m212_release_op_attr : Void*
    m213_create_op : Void*
    m214_invoke_op : Void*
    m215_release_op : Void*
    m216_session_options_append_execution_provider : Void*
    m217_copy_kernel_info : Void*
    m218_release_kernel_info : Void*
    m219_get_training_api : Void*
    m220_session_options_append_execution_provider__c_a_n_n : Void*
    m221_create_c_a_n_n_provider_options : Void*
    m222_update_c_a_n_n_provider_options : Void*
    m223_get_c_a_n_n_provider_options_as_string : Void*
    m224_release_c_a_n_n_provider_options : Void*
    m225_memory_info_get_device_type : Void*
    m226_update_env_with_custom_log_level : Void*
    m227_set_global_intra_op_thread_affinity : Void*
    m228_register_custom_ops_library__v2 : Void*
    m229_register_custom_ops_using_function : Void*
    m230_kernel_info__get_input_count : Void*
    m231_kernel_info__get_output_count : Void*
    m232_kernel_info__get_input_name : Void*
    m233_kernel_info__get_output_name : Void*
    m234_kernel_info__get_input_type_info : Void*
    m235_kernel_info__get_output_type_info : Void*
    m236_kernel_info_get_attribute_tensor : Void*
    m237_has_session_config_entry : Void*
    m238_get_session_config_entry : Void*
    m239_session_options_append_execution_provider__dnnl : Void*
    m240_create_dnnl_provider_options : Void*
    m241_update_dnnl_provider_options : Void*
    m242_get_dnnl_provider_options_as_string : Void*
    m243_release_dnnl_provider_options : Void*
    m244_kernel_info__get_node_name : Void*
    m245_kernel_info__get_logger : Void*
    m246_kernel_context__get_logger : Void*
    m247_logger__log_message : Void*
    m248_logger__get_logging_severity_level : Void*
    m249_kernel_info_get_constant_input_tensor : Void*
    m250_cast_type_info_to_optional_type_info : Void*
    m251_get_optional_contained_type_info : Void*
    m252_get_resized_string_tensor_element_buffer : Void*
    m253_kernel_context__get_allocator : Void*
    m254_get_build_info_string : Void*
    m255_create_r_o_c_m_provider_options : Void*
    m256_update_r_o_c_m_provider_options : Void*
    m257_get_r_o_c_m_provider_options_as_string : Void*
    m258_release_r_o_c_m_provider_options : Void*
    m259_create_and_register_allocator_v2 : Void*
    m260_run_async : Void*
    m261_update_tensor_r_t_provider_options_with_value : Void*
    m262_get_tensor_r_t_provider_options_by_name : Void*
    m263_update_c_u_d_a_provider_options_with_value : Void*
    m264_get_c_u_d_a_provider_options_by_name : Void*
    m265_kernel_context__get_resource : Void*
    m266_set_user_logging_function : Void*
    m267_shape_infer_context__get_input_count : Void*
    m268_shape_infer_context__get_input_type_shape : Void*
    m269_shape_infer_context__get_attribute : Void*
    m270_shape_infer_context__set_output_type_shape : Void*
    m271_set_symbolic_dimensions : Void*
    m272_read_op_attr : Void*
    m273_set_deterministic_compute : Void*
    m274_kernel_context__parallel_for : Void*
    m275_session_options_append_execution_provider__open_v_i_n_o__v2 : Void*
    m276_session_options_append_execution_provider__vitis_a_i : Void*
    m277_kernel_context__get_scratch_buffer : Void*
    m278_kernel_info_get_allocator : Void*
    m279_add_external_initializers_from_files_in_memory : Void*
    m280_create_lora_adapter : Void*
    m281_create_lora_adapter_from_array : Void*
    m282_release_lora_adapter : Void*
    m283_run_options_add_active_lora_adapter : Void*
    m284_set_ep_dynamic_options : Void*
  end
end

module Onnx
  # Loads libonnxruntime through `dlopen` and exposes the OrtApi struct.
  module RT
    DEFAULT_LIBS = %w(libonnxruntime.so.1.21 libonnxruntime.so.1 libonnxruntime.so)

    # ORT_LOGGING_LEVEL_ERROR
    private LOG_LEVEL_ERROR = 3

    @@handle : Void*?
    @@api : LibOnnx::OrtApi*?
    @@env : LibOnnx::OrtEnv*?
    @@allocator : LibOnnx::OrtAllocator*?
    @@memory_info : LibOnnx::OrtMemoryInfo*?

    def self.lib_paths : Array(String)
      if env = ENV["ONNX_RUNTIME_LIB"]?
        [env]
      else
        DEFAULT_LIBS.dup
      end
    end

    # Resets the cached handle (useful in specs).
    def self.reset! : Nil
      @@api = nil
      @@handle = nil
      @@env = nil
      @@allocator = nil
      @@memory_info = nil
    end

    def self.api : LibOnnx::OrtApi*
      @@api ||= load_api
    end

    # Cached api without loading (safe from finalizers).
    def self.api? : LibOnnx::OrtApi*?
      @@api
    end

    # Loads the first library in `paths` that opens successfully
    # (dlopen on Unix, LoadLibraryA on Windows). Raises with the full
    # candidate list otherwise — the shared entry point used by this shard
    # and by examples binding their own libraries (espeak-ng, ...).
    def self.open_library(paths : Array(String), what : String = "library") : Void*
      paths.each do |path|
        handle : Void*
        {% if flag?(:windows) %}
          handle = LibKernel32.load_library_a(path.to_unsafe)
        {% else %}
          handle = LibDL.dlopen(path, LibOnnx::RTLD_NOW)
        {% end %}
        return handle unless handle.null?
      end
      raise Error.new("#{what} not found (tried: #{paths.join(", ")})")
    end

    # Resolves a symbol in a library handle; raises when missing.
    def self.library_symbol(handle : Void*, name : String, what : String = "library") : Void*
      sym : Void*
      {% if flag?(:windows) %}
        sym = LibKernel32.get_proc_address(handle, name.to_unsafe)
      {% else %}
        sym = LibDL.dlsym(handle, name.to_unsafe)
      {% end %}
      raise Error.new("symbol #{name} not found in #{what}") if sym.null?
      sym
    end

    private def self.load_api : LibOnnx::OrtApi*
      handle = open_library(lib_paths, "onnxruntime shared library" +
        {% unless flag?(:windows) %} "; set ONNX_RUNTIME_LIB to override" {% else %} "" {% end %})
      @@handle = handle

      base_sym = library_symbol(handle, "OrtGetApiBase", "onnxruntime library")
      get_base = Proc(LibOnnx::OrtApiBase*).new(base_sym, Pointer(Void).null)
      base = get_base.call

      # Request the newest API we know; older libraries serve the newest they can.
      21.downto(13) do |version|
        api_ptr = base.value.get_api.call(version.to_u32!)
        return api_ptr unless api_ptr.null?
      end
      raise Error.new("onnxruntime is too old: no compatible C API (need >= 1.13)")
    end

    def self.env : LibOnnx::OrtEnv*
      @@env ||= begin
        out_ptr = uninitialized LibOnnx::OrtEnv*
        check api.value.create_env.call(LOG_LEVEL_ERROR, "onnx.cr".to_unsafe, pointerof(out_ptr))
        out_ptr
      end
    end

    def self.allocator : LibOnnx::OrtAllocator*
      @@allocator ||= begin
        out_ptr = uninitialized LibOnnx::OrtAllocator*
        check api.value.get_allocator_with_default_options.call(pointerof(out_ptr))
        out_ptr
      end
    end

    def self.memory_info : LibOnnx::OrtMemoryInfo*
      @@memory_info ||= begin
        out_ptr = uninitialized LibOnnx::OrtMemoryInfo*
        # OrtDeviceAllocator, OrtMemTypeDefault
        check api.value.create_cpu_memory_info.call(0, 0, pointerof(out_ptr))
        out_ptr
      end
    end
  end
end
