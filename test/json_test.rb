# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/byte_batcher"

class JsonTest < Minitest::Test
  def test_json_arrays_include_exact_utf8_and_framing_bytes
    batches = ByteBatcher.json(["é", "x", nil], max_bytes: 10).to_a

    assert_equal ['["é","x"]', "[null]"], batches
    assert_equal [10, 6], batches.map(&:bytesize)
    assert_equal [["é", "x"], [nil]], batches.map { |payload| JSON.parse(payload) }
    assert batches.all? { |payload| payload.encoding == Encoding::UTF_8 && payload.valid_encoding? }
  end

  def test_ndjson_counts_final_newline_and_escapes_embedded_newlines
    batches = ByteBatcher.ndjson(["a\nb", false, "é"], max_bytes: 7).to_a

    assert_equal ["\"a\\nb\"\n", "false\n", "\"é\"\n"], batches
    assert_equal [7, 6, 5], batches.map(&:bytesize)
    decoded = batches.flat_map do |payload|
      payload.lines.map { |line| JSON.parse(line) }
    end
    assert_equal ["a\nb", false, "é"], decoded
    assert batches.all? { |payload| payload.encoding == Encoding::UTF_8 && payload.valid_encoding? }
  end

  def test_empty_and_count_limited_batches
    assert_empty ByteBatcher.json([], max_bytes: 2).to_a
    assert_empty ByteBatcher.ndjson([], max_bytes: 1).to_a
    assert_equal ["[1]", "[2]"], ByteBatcher.json([1, 2], max_bytes: 10, max_items: 1).to_a
    assert_equal ["1\n", "2\n"], ByteBatcher.ndjson([1, 2], max_bytes: 10, max_items: 1).to_a
  end

  def test_json_and_ndjson_raise_when_single_value_with_framing_cannot_fit
    json = ByteBatcher.json(["é"], max_bytes: 5)
    ndjson = ByteBatcher.ndjson(["é"], max_bytes: 4)

    assert_equal 6, assert_raises(ByteBatcher::OversizedItemError) { json.next }.framed_bytes
    assert_equal 5, assert_raises(ByteBatcher::OversizedItemError) { ndjson.next }.framed_bytes
  end

  def test_adapters_are_lazy_and_propagate_encoding_errors
    seen = []
    source = Enumerator.new do |output|
      seen << :first
      output << "first"
      seen << :invalid
      output << Float::NAN
    end
    batches = ByteBatcher.ndjson(source, max_bytes: 20, max_items: 1)

    assert_empty seen
    assert_equal "\"first\"\n", batches.next
    assert_equal [:first], seen
    assert_raises(JSON::GeneratorError) { batches.next }
    assert_equal [:first, :invalid], seen
  end

  def test_custom_json_is_rejected_in_json_modes
    object = Object.new
    def object.to_json(*)
      "invalid\n"
    end

    assert_raises(JSON::GeneratorError) { ByteBatcher.json([object], max_bytes: 100).next }
    return unless defined?(JSON::Fragment)

    nested_fragment = { "data" => [JSON::Fragment.new("true\nfalse")] }
    assert_raises(JSON::GeneratorError) { ByteBatcher.ndjson([nested_fragment], max_bytes: 100).next }
  end

  def test_randomized_batches_round_trip_without_exceeding_the_limit
    random = Random.new(89)
    values = [nil, true, false, 123, "𐐷", "\"é\n\\", [nil, "字"], { "é" => 1 }]
    records = Array.new(200) { values.sample(random: random) }

    10.times do
      limit = random.rand(16..48)
      max_items = random.rand(1..9)
      arrays = ByteBatcher.json(records, max_bytes: limit, max_items: max_items).to_a
      lines = ByteBatcher.ndjson(records, max_bytes: limit, max_items: max_items).to_a

      assert arrays.all? { |payload| payload.bytesize <= limit }
      assert lines.all? { |payload| payload.bytesize <= limit && payload.end_with?("\n") }
      decoded_arrays = arrays.map { |payload| JSON.parse(payload) }
      decoded_lines = lines.map { |payload| payload.lines.map { |line| JSON.parse(line) } }
      assert decoded_arrays.all? { |batch| batch.size <= max_items }
      assert decoded_lines.all? { |batch| batch.size <= max_items }
      assert_equal records, decoded_arrays.flatten(1)
      assert_equal records, decoded_lines.flatten(1)
    end
  end
end
