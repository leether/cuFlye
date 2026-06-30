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
--memory-budget-bytes BYTES
```

`--memory-budget-bytes` is CUDA-only and must fail before device allocation if
the bounded replay buffers exceed the budget.

## Supported Shape

- Fixture schema must be `cuflye-read-alignment-replay-fixture-v0`.
- `reads_base_alignment` may be `true` or `false`; the binary does not replay
  edlib/base alignment and instead consumes `chain-divergence.tsv` as the
  already-decided Flye divergence acceptance input.
- `alignment_input_records` must be non-empty and at most `2048`.
- `chain-divergence.tsv` must have contiguous chain ids starting at zero and
  must match the replayed pre-divergence chain count.

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

## Determinism

CPU and CUDA output must canonical-diff `match` against
`oracle.read-alignment.tsv` for the same fixture before any downstream Flye
integration can consume the result.
