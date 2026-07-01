# cuFlye Read Alignment Compact Binary v0

Status: proposed

Introduced: M5t

Scope: compact proof/session payload for pre-divergence read-alignment chain
output.

## Purpose

`compact-binary-v0` is a deterministic single-file payload for the same records
that M5s wrote as compact JSONL. It is intended to remove JSON formatting and
parse overhead while preserving byte-level CPU/CUDA diffability before any
Flye graph mutation can consume CUDA output.

The payload is not a raw C++ struct dump. All integer and float fields are
written explicitly in little-endian order with fixed field widths.

## Header

The first 64 bytes are:

| Offset | Type | Field |
| --- | --- | --- |
| 0 | char[8] | magic `CUFRALB0` |
| 8 | u32 | header bytes, currently `64` |
| 12 | u32 | record bytes, currently `92` |
| 16 | u32 | version major, currently `0` |
| 20 | u32 | version minor, currently `0` |
| 24 | u64 | fixture count |
| 32 | u64 | output record count |
| 40 | u64 | total input overlap records |
| 48 | u32 | minimum input overlap records per fixture |
| 52 | u32 | maximum input overlap records per fixture |
| 56 | u32 | output mode, `1` means pre-divergence chains |
| 60 | u32 | reserved, must be `0` |

## Record

Each 92-byte record is:

| Offset | Type | Field |
| --- | --- | --- |
| 0 | i64 | query id |
| 8 | i32 | chain id |
| 12 | i32 | segment id |
| 16 | i32 | overlap index within the fixture input |
| 20 | i64 | candidate id |
| 28 | i64 | read id |
| 36 | i32 | read begin |
| 40 | i32 | read end |
| 44 | i32 | read length |
| 48 | i64 | edge id |
| 56 | i32 | edge left node |
| 60 | i32 | edge right node |
| 64 | i64 | edge sequence id |
| 72 | i32 | edge begin |
| 76 | i32 | edge end |
| 80 | i32 | edge length |
| 84 | i32 | score |
| 88 | f32 | sequence divergence |

Records are ordered by fixture-list order and then by segment order emitted by
the replay backend. CPU and CUDA payloads must compare byte-for-byte for the
same fixture list before the payload is treated as oracle-equivalent.

## Validation Gate

`tools/validate_read_alignment_binary_payload.py` validates:

- magic and version;
- header and record byte sizes;
- output mode;
- reserved field value;
- file length equals `header_bytes + output_records * record_bytes`;
- optional expected fixture count;
- optional expected output record count;
- optional expected total input record count;
- optional SHA-256 checksum.

Schema, count, checksum, and truncation failures must fail closed before graph
mutation.

## Compatibility

`compact-jsonl-v0` remains available for audit/debug runs. M5t uses
`compact-binary-v0` for the session performance proof because it is smaller
and cheaper to write/read.
