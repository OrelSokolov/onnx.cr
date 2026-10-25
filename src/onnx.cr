require "./onnx/lib_rt"
require "./onnx/error"
require "./onnx/value"
require "./onnx/session"

# Crystal bindings for the ONNX Runtime C API, loaded via `dlopen` at
# runtime so that onnxruntime stays an optional dependency.
#
# Basic usage:
#
# ```
# session = Onnx::Session.new("model.onnx")
# input = Onnx::Value.tensor(Slice(Int64)[1, 2, 3], shape: [1, 3])
# output = session.run({"input" => input})["output"]
# ```
module Onnx
  VERSION = {{ `shards version --shardfile=#{__DIR__}/../shard.yml`.strip.empty? ? "0.1.0" : `shards version --shardfile=#{__DIR__}/../shard.yml`.strip }}
end
