# Changelog

## 0.1.0

- Add lazy batching with exact serialized byte limits, optional item limits, and custom framing.
- Add UTF-8 JSON arrays and NDJSON output with byte accounting for all framing.
- Report oversized items by index and byte counts.
- Support Ruby 3.4 and later with zero third-party runtime dependencies. This is the initial development release.
