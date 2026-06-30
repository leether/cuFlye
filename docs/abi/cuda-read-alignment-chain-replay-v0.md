# cuFlye CUDA Read Alignment Chain Replay v0

Status: accepted

Introduced: M5c

Scope: standalone benchmark binary for `read-alignment-replay-fixture-v0`.

## Purpose

`cuflye-cuda-read-alignment-chain-replay` replays Flye's bounded
`ReadAligner::chainReadAlignments` contract from an M5b fixture with either a
CPU backend or a CUDA backend. It emits the same `read-alignment-v1` TSV that
the CPU replay oracle emits.

## CLI Contract

Required arguments:

```text
--fixture-dir DIR
--output-tsv PATH
--json-output PATH
```

Optional arguments:

```text
--backend cpu|cuda
--device ID
--warmup-runs N
--benchmark-runs N
--replicate-fixture N
--memory-budget-bytes BYTES
```

`--memory-budget-bytes` is CUDA-only and must fail before device allocation if
the bounded replay buffers exceed the budget.

`--replicate-fixture` is a benchmark-only occupancy control. It runs the same
fixture contract `N` independent times in one benchmark call. The output TSV
contains the first representative fixture only; JSON records `batch_size` and
`total_input_records`.

M5e adds real multi-fixture batch mode:

```text
--batch-fixtures-file FILE
--batch-output-dir DIR
--batch-json-output PATH
--allow-heterogeneous-batch
```

The fixture list is a newline-delimited file of
`read-alignment-replay-fixture-v0` directories. Blank lines are ignored and
lines starting with `#` are comments. Batch mode emits one
`read-alignment-v1` TSV per fixture under:

```text
<batch-output-dir>/<fixture-basename>/read-alignment.tsv
```

Batch mode does not allow `--replicate-fixture`; it is for real multiple
fixtures, not copies of one fixture.

By default, batch mode still requires one same-shape fixture group and fails
closed if input record counts, chain-divergence row counts, or replay
parameters differ. `--allow-heterogeneous-batch` explicitly enables grouped
execution: fixtures are partitioned by the same shape key, each group is run as
one packed CPU/CUDA batch, and outputs are written back per original fixture.

## Supported Shape

- Fixture schema must be `cuflye-read-alignment-replay-fixture-v0`.
- `reads_base_alignment` may be `true` or `false`; the binary does not replay
  edlib/base alignment and instead consumes `chain-divergence.tsv` as the
  already-decided Flye divergence acceptance input.
- `alignment_input_records` must be non-empty and at most `2048`.
- `chain-divergence.tsv` must have contiguous chain ids starting at zero and
  must match the replayed pre-divergence chain count.
- In M5e batch mode, all fixtures must have the same
  `alignment_input_records`, the same `chain-divergence.tsv` row count, and the
  same replay parameters. Heterogeneous batches fail closed until a later
  scheduler/packing contract exists.
- In M5f grouped mode, a heterogeneous fixture list is supported only when
  `--allow-heterogeneous-batch` is set. Every group must still satisfy the
  same-shape CUDA kernel contract internally.

Unsupported shapes must fail closed before writing a successful JSON summary.

## Output

The TSV output is `read-alignment-v1`.

The JSON summary uses schema
`cuflye-cuda-read-alignment-chain-replay-v0` and records:

- backend, fixture path, query id, input records, candidate chains, accepted
  chains, and output records;
- CUDA device and memory fields when backend is CUDA;
- setup, allocation, host-to-device, kernel, CPU-chain, device-to-host,
  finalize, write, and benchmark timing fields;
- warmup and timed run counts.
- representative-output-only batch metadata when `--replicate-fixture` is
  greater than one.

Batch JSON uses schema
`cuflye-cuda-read-alignment-chain-replay-batch-v0` and records:

- backend, fixture count, input records per fixture, total input records,
  candidate chains, accepted chains, and output records;
- batch fixture list path and batch output directory;
- one fixture entry per selected read with fixture dir, output TSV, query id,
  input record count, chain-divergence row count, and output record count;
- `heterogeneous_batch`, `shape_group_count`, min/max input records per
  fixture, and a `shape_groups` array with query ids and replay parameters for
  every group;
- CUDA device, memory, timing, and benchmark fields when backend is CUDA;
- supported-shape flags documenting same-shape requirements and that the output
  is not representative-only.

## Determinism

CPU and CUDA output must canonical-diff `match` against
`oracle.read-alignment.tsv` for the same fixture before any downstream Flye
integration can consume the result.
