# frozen_string_literal: true

module ByteBatcher
  class OversizedItemError < StandardError
    attr_reader :index, :encoded_bytes, :framed_bytes, :max_bytes

    def initialize(index:, encoded_bytes:, framed_bytes:, max_bytes:)
      @index = index
      @encoded_bytes = encoded_bytes
      @framed_bytes = framed_bytes
      @max_bytes = max_bytes

      super("item at index #{index} is #{encoded_bytes} encoded bytes " \
            "(#{framed_bytes} with framing), exceeding max_bytes #{max_bytes}")
    end
  end

  def self.pack(items, max_bytes:, encode:, max_items: nil, prefix: "", separator: "", suffix: "")
    unless max_bytes.is_a?(Integer) && max_bytes.positive?
      raise ArgumentError, "max_bytes must be a positive Integer"
    end
    unless max_items.nil? || (max_items.is_a?(Integer) && max_items.positive?)
      raise ArgumentError, "max_items must be a positive Integer or nil"
    end
    raise ArgumentError, "items must respond to each" unless items.respond_to?(:each)
    raise ArgumentError, "encode must respond to call" unless encode.respond_to?(:call)
    unless [prefix, separator, suffix].all? { |part| part.is_a?(String) }
      raise ArgumentError, "prefix, separator, and suffix must be Strings"
    end

    prefix, separator, suffix = [prefix.b, separator.b, suffix.b]
    frame_bytes = prefix.bytesize + suffix.bytesize
    raise ArgumentError, "prefix and suffix exceed max_bytes" if frame_bytes > max_bytes

    Enumerator.new do |output|
      payload = prefix.dup
      count = 0

      items.to_enum(:each).each_entry.with_index do |item, index|
        encoded = encode.call(item)
        raise TypeError, "encoder must return a String for item at index #{index}" unless encoded.is_a?(String)

        framed_bytes = frame_bytes + encoded.bytesize
        if framed_bytes > max_bytes
          raise OversizedItemError.new(index: index, encoded_bytes: encoded.bytesize,
                                       framed_bytes: framed_bytes, max_bytes: max_bytes)
        end
        encoded = encoded.b

        if count.positive? && payload.bytesize + separator.bytesize + encoded.bytesize + suffix.bytesize > max_bytes
          output << (payload << suffix)
          payload = prefix.dup
          count = 0
        end

        payload << separator if count.positive?
        payload << encoded
        count += 1

        if count == max_items
          output << (payload << suffix)
          payload = prefix.dup
          count = 0
        end
      end

      output << (payload << suffix) if count.positive?
    end
  end
end
