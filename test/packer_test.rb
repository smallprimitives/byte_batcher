# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/byte_batcher"

class PackerTest < Minitest::Test
  IDENTITY = ->(item) { item }

  def test_exact_fit_counts_framing_and_utf8_bytes
    batches = ByteBatcher.pack(%w[é 界 x], max_bytes: 8, encode: IDENTITY,
                             prefix: "[", separator: ",", suffix: "]").to_a

    assert_equal ["[é,界]".b, "[x]".b], batches
    assert_equal [8, 3], batches.map(&:bytesize)
    assert_equal Encoding::BINARY, batches.first.encoding
  end

  def test_one_byte_over_starts_a_new_batch
    assert_equal ["[é]".b, "[界,x]".b],
                 ByteBatcher.pack(%w[é 界 x], max_bytes: 7, encode: IDENTITY,
                                  prefix: "[", separator: ",", suffix: "]").to_a
  end

  def test_byte_and_count_limits_apply_together
    assert_equal %w[a|b cccc d|e f],
                 ByteBatcher.pack(%w[a b cccc d e f], max_bytes: 5, max_items: 2,
                                  separator: "|", encode: IDENTITY).to_a
  end

  def test_empty_input_and_empty_encoded_items
    assert_empty ByteBatcher.pack([], max_bytes: 2, encode: IDENTITY, prefix: "[", suffix: "]").to_a
    assert_equal [".", ""], ByteBatcher.pack(["", "", ""], max_bytes: 1, max_items: 2,
                                              encode: IDENTITY, separator: ".").to_a
    assert_equal ["[]"], ByteBatcher.pack(["", ""], max_bytes: 2, encode: IDENTITY,
                                         prefix: "[", suffix: "]").to_a
  end

  def test_rejects_invalid_options_before_reading_the_source
    source = Enumerator.new { raise "source was read" }
    valid = {max_bytes: 2, encode: IDENTITY}
    invalid = [{max_bytes: 0}, {max_bytes: 1.5}, {max_items: -1}, {max_items: false},
               {encode: nil}, {prefix: nil}, {separator: 1}, {suffix: "123"}]

    invalid.each do |options|
      assert_raises(ArgumentError) { ByteBatcher.pack(source, **valid.merge(options)) }
    end
    assert_raises(ArgumentError) { ByteBatcher.pack(Object.new, **valid) }
  end

  def test_oversized_item_reports_sizes_without_emitting_pending_batch
    encoded = []
    encoder = lambda do |item|
      encoded << item
      item
    end
    batches = ByteBatcher.pack(["a", "bb", "c", "private"], max_bytes: 4, encode: encoder,
                             prefix: "[", suffix: "]", separator: ",")

    assert_equal "[a]", batches.next
    assert_equal "[bb]", batches.next
    error = assert_raises(ByteBatcher::OversizedItemError) { batches.next }
    assert_equal [3, 7, 9, 4], [error.index, error.encoded_bytes, error.framed_bytes, error.max_bytes]
    refute_includes error.message, "private"
    assert_equal ["a", "bb", "c", "private"], encoded
  end

  def test_byte_limited_iteration_uses_at_most_one_encoded_lookahead
    seen = []
    encoder = lambda do |item|
      seen << item
      item.to_s
    end
    batches = ByteBatcher.pack(0.step, max_bytes: 3, separator: ",", encode: encoder)

    assert_empty seen
    assert_equal ["0,1", "2,3"], batches.take(2)
    assert_equal [0, 1, 2, 3, 4], seen
  end

  def test_count_limit_can_yield_without_reading_ahead
    seen = []
    source = Enumerator.new do |output|
      4.times do |item|
        seen << item
        output << item.to_s
      end
    end
    batches = ByteBatcher.pack(source, max_bytes: 3, max_items: 2, encode: IDENTITY)

    assert_equal "01", batches.next
    assert_equal [0, 1], seen
    assert_equal "23", batches.next
    assert_raises(StopIteration) { batches.next }
  end

  def test_custom_framing_uses_bytes_and_leaves_caller_strings_alone
    prefix = +"é"
    encoder_buffer = +""
    encoder = ->(item) { encoder_buffer.replace(item) }
    batches = ByteBatcher.pack(["\x00".b, "\xFF".b], max_bytes: 3, encode: encoder, prefix: prefix)
    prefix.replace("changed")

    assert_equal ["é\x00".b, "é\xFF".b], batches.to_a
    assert_equal "changed", prefix
    assert_equal "\xFF".b, encoder_buffer
  end

  def test_accepts_each_only_sources_and_preserves_multi_yield_entries
    source = Object.new
    def source.each
      yield "a", "b"
      yield "c"
    end

    assert_equal ["ab,c"], ByteBatcher.pack(source, max_bytes: 4, separator: ",",
                                            encode: ->(item) { Array(item).join }).to_a
  end

  def test_caller_cannot_change_the_lookahead_while_a_batch_is_yielded
    lookahead = +"b"
    batches = ByteBatcher.pack(["a", lookahead], max_bytes: 1, encode: IDENTITY)

    assert_equal "a", batches.next
    lookahead.replace("changed")
    assert_equal "b", batches.next
  end

  def test_validates_encoder_output_and_propagates_failures
    type_error = assert_raises(TypeError) do
      ByteBatcher.pack([1], max_bytes: 8, encode: IDENTITY).to_a
    end
    assert_includes type_error.message, "index 0"
    failure = RuntimeError.new("failed")
    source = Enumerator.new do |output|
      output << "a"
      raise failure
    end

    source_error = assert_raises(RuntimeError) do
      ByteBatcher.pack(source, max_bytes: 8, encode: IDENTITY).to_a
    end
    encoder_error = assert_raises(RuntimeError) do
      ByteBatcher.pack(["a"], max_bytes: 8, encode: ->(_) { raise failure }).to_a
    end
    assert_same failure, source_error
    assert_same failure, encoder_error
  end
end
