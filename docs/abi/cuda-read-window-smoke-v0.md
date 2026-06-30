# cuFlye CUDA Read Window Smoke Prototype v0

Status: active

Introduced: M1i

Scope: standalone CUDA kernel that slides windows across packed read
sequences, computes Flye-style k-mers and standard-form lookup keys, and
generates a candidate-record-v1 TSV against a flattened index fixture.

## Purpose

M1i moves one step beyond M1h. Instead of supplying one DNA k-mer string per
query row, the fixture supplies short read sequences. CUDA computes the query
k-mer stream by sliding a window across those reads, matching the core behavior
of Flye's `IterKmers` at a bounded fixture scale.

It remains standalone and does not replace the Flye backend stub.

## Runtime Contract

Required arguments:

- `--kmer-size N`, supported range `1..32`;
- `--reads-tsv PATH`;
- `--index-tsv PATH`;
- `--output-tsv PATH`.

Optional arguments:

- `--repetitive-kmers-tsv PATH`;
- `--cpu-output-tsv PATH`: write a host oracle generated from the same fixture;
- `--device N`: CUDA device id, default from `CUFLYE_CUDA_DEVICE` or `0`;
- `--memory-budget-bytes N`: maximum allowed device allocation;
- `--json-output PATH`: compact runtime manifest.

The prototype must:

- parse packed read sequences into read metadata plus a flat base buffer;
- compute query windows on device;
- compute forward k-mer representation, reverse complement, and standard form
  on device;
- preserve the forward query representation in ABI field `kmer`;
- skip repetitive standard-form lookup keys;
- skip trivial same-read/same-position hits;
- preserve duplicate candidate records;
- pass `tools/validate_candidate_dump.py`;
- pass `tools/diff_candidate_dumps.py` against the host oracle and expected
  fixture.

## Non-Goals

M1i does not:

- parse FASTQ/FASTA files;
- build or upload Flye's full `VertexIndex`;
- transform reverse-complement target coordinates during index construction;
- replace the Flye backend stub;
- claim performance improvement.

## M2c Extension

M2c removes the original fixed `MAX_READ_SIZE=256` read storage limit. The
backend still accepts the same `reads.tsv` format, but internally uploads:

- `QueryReadMeta[]`: query id, read length, and sequence offset;
- `char[]`: concatenated read bases.

Runtime JSON includes:

- `dynamic_read_bases: true`;
- `read_base_bytes`;
- `max_read_length`;
- `read_meta_record_size_bytes`.

The host CPU oracle is generated only when `--cpu-output-tsv` is supplied. This
keeps proof runs able to compare CPU/GPU output while avoiding hidden CPU oracle
work when Flye invokes the external CUDA backend.

The correctness claim after M2c is that CUDA device code can perform
read-window generation on both bounded fixtures and one real `pack-dump-v0`
query bundle before candidate equality join.

## M2e Extension

M2e adds runtime timing metadata to the JSON manifest. The candidate-record-v1
TSV ABI is unchanged.

Runtime JSON includes:

- `cpu_oracle_enabled`;
- `timing_ms.input_parse`;
- `timing_ms.cpu_oracle`;
- `timing_ms.cuda_setup`;
- `timing_ms.device_allocation`;
- `timing_ms.host_to_device`;
- `timing_ms.kernel`;
- `timing_ms.host_output_allocation`;
- `timing_ms.device_to_host`;
- `timing_ms.compact`;
- `timing_ms.write_output`;
- `timing_ms.total_before_json`.

`total_before_json` measures through candidate TSV writing and excludes the JSON
manifest write itself. Timing values are evidence for the measured pack shape
only; they are not a full Flye assembly speed claim.

## M2f Extension

M2f changes the backend output strategy from dense pair materialization to sparse
offset compaction. The candidate-record-v1 TSV ABI and canonical ordering remain
unchanged.

Runtime JSON includes:

- `output_strategy: sparse-offsets-v1`;
- `dense_pair_output_materialized: false`;
- `timing_ms.mark_kernel`;
- `timing_ms.flag_device_to_host`;
- `timing_ms.host_prefix_sum`;
- `timing_ms.offsets_host_to_device`;
- `timing_ms.emit_kernel`;
- `timing_ms.sparse_output_allocation`;
- `timing_ms.output_device_to_host`.

The broad compatibility fields remain:

- `timing_ms.kernel` is `mark_kernel + emit_kernel`;
- `timing_ms.device_to_host` is `flag_device_to_host + output_device_to_host`;
- `timing_ms.compact` is the host prefix-sum compaction step.

## M3c Extension

M3c keeps `output_strategy: sparse-offsets-v1` but moves prefix/offset
generation to a device-side exclusive scan. The candidate-record-v1 TSV ABI and
canonical ordering remain unchanged.

Runtime JSON adds:

- `prefix_strategy: device-exclusive-scan-v1`;
- `host_prefix_offsets_materialized: false`;
- `timing_ms.device_prefix_sum`;
- `timing_ms.output_count_device_to_host`.

Compatibility timing fields remain present:

- `timing_ms.host_prefix_sum` is `0.000` for the device-prefix path;
- `timing_ms.flag_device_to_host` is `0.000` because the full flag array is not
  copied back to host;
- `timing_ms.offsets_host_to_device` is `0.000` because output offsets are
  generated on device;
- `timing_ms.device_to_host` includes output-count readback plus compact output
  readback;
- `timing_ms.compact` is the device prefix-sum compaction step.

## M3d Extension

M3d adds optional worker-side device-buffer reuse. The read-window smoke CLI still
uses one-shot local buffers; worker requests may reuse typed device buffers across
requests with stable or smaller shapes.

Runtime JSON adds:

- `worker_device_arena_enabled`;
- `worker_device_arena_allocations`;
- `worker_device_arena_reuses`;
- `worker_device_arena_capacity_bytes`.

These fields are diagnostics only. They do not change candidate-record-v1 output
semantics.
