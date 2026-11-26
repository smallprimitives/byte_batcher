# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name = "byte_batcher"
  spec.version = "0.1.0"
  spec.authors = ["Small Primitives"]
  spec.summary = "Lazy batching with exact serialized byte limits"
  spec.homepage = "https://github.com/smallprimitives/byte_batcher"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"
  spec.files = ["LICENSE", "README.md", "lib/byte_batcher.rb", "lib/byte_batcher/json.rb"]
  spec.require_paths = ["lib"]
end
