# frozen_string_literal: true

require "json"

module ByteBatcher
  def self.json(items, max_bytes:, max_items: nil)
    json_batches(items, max_bytes: max_bytes, max_items: max_items, prefix: "[", separator: ",", suffix: "]")
  end

  def self.ndjson(items, max_bytes:, max_items: nil)
    json_batches(items, max_bytes: max_bytes, max_items: max_items, separator: "\n", suffix: "\n")
  end

  def self.json_batches(items, **options)
    batches = pack(items, encode: method(:encode_json), **options)

    Enumerator.new do |output|
      batches.each { |payload| output << payload.force_encoding(Encoding::UTF_8) }
    end
  end
  private_class_method :json_batches

  def self.encode_json(item)
    encoded = JSON.generate(item, strict: true)
    reject_raw_fragments(item) if defined?(JSON::Fragment)
    encoded
  end
  private_class_method :encode_json

  # JSON's strict generator still copies raw fragments verbatim on versions that support them.
  def self.reject_raw_fragments(item)
    case item
    when JSON::Fragment
      raise JSON::GeneratorError, "raw JSON fragments are not supported"
    when Array
      item.each { |value| reject_raw_fragments(value) }
    when Hash
      item.each_value { |value| reject_raw_fragments(value) }
    end
  end
  private_class_method :reject_raw_fragments
end
