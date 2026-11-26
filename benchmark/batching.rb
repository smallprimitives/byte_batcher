# frozen_string_literal: true

require "json"
require_relative "../lib/byte_batcher"

MAX_BYTES = 4_096
COUNT_LIMIT = 50
REPETITIONS = 5

def reencode_batches(records)
  Enumerator.new do |output|
    batch = []
    payload = nil
    records.each do |record|
      candidate = JSON.generate(batch + [record])
      if candidate.bytesize > MAX_BYTES
        output << payload
        batch = [record]
        payload = JSON.generate(batch)
      else
        batch << record
        payload = candidate
      end
    end
    output << payload if payload
  end
end

def measure(label, record_count)
  peak = 0
  oversized = 0
  GC.start
  allocations = GC.stat(:total_allocated_objects)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  REPETITIONS.times do
    yield.each do |payload|
      size = payload.bytesize
      peak = size if size > peak
      oversized += 1 if size > MAX_BYTES
    end
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
  allocations = GC.stat(:total_allocated_objects) - allocations
  total = REPETITIONS * record_count
  printf "%-21s %10.0f records/s %6.2f alloc/record %5d peak payload bytes %4d oversized payloads\n",
         label, total / elapsed, allocations.fdiv(total), peak, oversized
end

workloads = {
  "small" => ->(i) { {"id" => i, "label" => "record"} },
  "mixed" => ->(i) { {"id" => i, "label" => "x" * (i % 15 == 0 ? 350 : i % 90)} },
  "multibyte and escaped" => ->(i) { {"id" => i, "label" => "界é\"\n\\" * (1 + i % 20)} }
}

puts RUBY_DESCRIPTION
puts "2,000 records per workload, #{REPETITIONS} repetitions, #{MAX_BYTES}-byte limit"
workloads.each do |name, record|
  records = Array.new(2_000, &record)
  pack = -> { ByteBatcher.json(records, max_bytes: MAX_BYTES) }
  reference = -> { reencode_batches(records) }
  count_only = -> { records.each_slice(COUNT_LIMIT).lazy.map { |batch| JSON.generate(batch) } }

  unless records.all? { |item| JSON.generate([item]).bytesize <= MAX_BYTES }
    abort "benchmark records must fit individually"
  end
  abort "reference disagrees with packer on #{name}" unless pack.call.to_a == reference.call.to_a

  puts "\n#{name}"
  measure("byte_batcher", records.size, &pack)
  measure("whole-batch encode", records.size, &reference)
  measure("each_slice(#{COUNT_LIMIT})", records.size, &count_only)
end
