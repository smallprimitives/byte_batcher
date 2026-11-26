# Byte Batcher

Byte Batcher groups records into serialized payloads that fit a byte limit. It preserves input order and yields batches as you iterate.

## Usage

Requires Ruby 3.4 or newer. The JSON formats use Ruby's standard `json` library. Byte Batcher adds no third-party runtime dependencies.

```ruby
require "byte_batcher"

records = [{"name" => "Ada"}, {"name" => "Renée"}]

ByteBatcher.json(records, max_bytes: 64, max_items: 100).each do |payload|
  # payload is a compact UTF-8 JSON array
  puts payload
end

ByteBatcher.ndjson(records, max_bytes: 64).each do |payload|
  # payload has one compact UTF-8 JSON value per line
  print payload
end

ByteBatcher.pack(records.map { |record| record.fetch("name") },
                 max_bytes: 12, encode: ->(name) { name },
                 prefix: "<", separator: "|", suffix: ">").each do |payload|
  puts payload
end
```

- `max_bytes` and the optional `max_items` must be positive integers. The byte limit includes brackets, separators, and suffixes. NDJSON ends each payload with a newline.
- `json` and `ndjson` accept JSON-compatible Ruby values such as strings, numbers, booleans, `nil`, arrays, and hashes with string keys. Convert custom objects to those values before batching.
- `pack` accepts an encoder that returns a string and emits binary strings. The caller defines and validates the custom format.
- Empty input yields zero batches. Use each payload unchanged to preserve the byte limit. Any transport overhead outside the payload belongs in the caller's budget.
- An item that exceeds the byte limit on its own raises `ByteBatcher::OversizedItemError`. The error exposes a zero-based `index`, `encoded_bytes`, `framed_bytes`, and `max_bytes`.
- A source, encoder, or oversized-item error stops iteration and discards the batch still being built. Previously yielded payloads stay with the caller.
- To find a byte boundary, the enumerator may encode one item ahead. It buffers the current payload and that item. An exceptionally large item can allocate its serialized form before the limit is checked. Each enumerator is for one consumer.

## Tests

```sh
ruby -Ilib -Itest -e 'Dir["test/*_test.rb"].sort.each { |file| require_relative file }'
```

The tests use Minitest, which ships with standard Ruby releases.
