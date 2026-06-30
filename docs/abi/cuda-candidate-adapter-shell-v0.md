# cuFlye CUDA Candidate Adapter Shell v0

Status: active

Introduced: M2a

Scope: Flye candidate-backend adapter shell for externally generated packed
toy candidate records.

## Purpose

This contract replaces the M1d CUDA stub with the first real Flye-side adapter
shell. It is intentionally narrow: Flye can select `CUFLYE_CANDIDATE_BACKEND=cuda`,
invoke an external CUDA candidate backend on a packed toy fixture, parse
candidate-record-v1 output, and reject unsupported real Flye shapes before
downstream chaining can consume wrong candidates.

## Adapter Mode

The only supported M2a adapter mode is:

```text
CUFLYE_CUDA_ADAPTER_MODE=external-packed-v0
```

Any other mode, including an unset mode, must fail closed.

## Required Inputs

When `CUFLYE_CANDIDATE_BACKEND=cuda` and
`CUFLYE_CUDA_ADAPTER_MODE=external-packed-v0` are selected, the adapter requires:

| Environment variable | Meaning |
| --- | --- |
| `CUFLYE_CUDA_BACKEND_BIN` | Executable CUDA candidate backend. M2a uses `cuflye-cuda-read-window-smoke`. |
| `CUFLYE_CUDA_PACKED_FIXTURE_DIR` | Directory containing `reads.tsv`, `index.tsv`, and `repetitive-kmers.tsv`. |
| `CUFLYE_CUDA_ADAPTER_OUTPUT_TSV` | Candidate-record-v1 TSV written by the external backend. |

Optional inputs:

| Environment variable | Meaning |
| --- | --- |
| `CUFLYE_CUDA_ADAPTER_JSON` | External backend runtime JSON. Defaults to `<output>.json`. |
| `CUFLYE_CUDA_DEVICE` | CUDA device id. Defaults to `0`. |
| `CUFLYE_CUDA_MEMORY_BUDGET_BYTES` | External backend memory budget. |
| `CUFLYE_CUDA_PACKED_KMER_SIZE` | Packed fixture k-mer size. Defaults to Flye's current k-mer size. |
| `CUFLYE_CUDA_STOP_AFTER_PACKED_QUERY` | If set to a true value, stop after records for the current packed query are parsed into Flye's candidate collection. |

## Packed Fixture Format

`reads.tsv`:

```text
query_id<TAB>sequence
```

`index.tsv`:

```text
target_id<TAB>target_pos<TAB>target_strand<TAB>kmer_sequence
```

`repetitive-kmers.tsv`:

```text
kmer_sequence
```

The external backend must emit `candidate-record-v1` as defined in
`docs/abi/candidate-record-v1.md`.

## Flye-Side Semantics

The adapter:

- invokes the external CUDA backend at most once per Flye process;
- parses the emitted candidate-record-v1 TSV;
- validates target id and target strand consistency;
- caches packed reads and candidate records;
- emits records only for the current Flye query id;
- verifies the current Flye query sequence exactly matches the packed
  `reads.tsv` sequence before records can enter CPU chaining.

The exact sequence match is the M2a fail-closed guard. It prevents a packed toy
fixture from being accidentally used as if it represented Flye's real
`VertexIndex`.

## Failure Semantics

The adapter must fail non-zero when:

- the adapter mode is unset or unsupported;
- a required environment variable is missing;
- fixture files or backend binary are unreadable;
- the external backend exits non-zero;
- the external backend emits no candidate records;
- candidate-record-v1 parsing fails;
- the current Flye query id is absent from packed reads;
- the current Flye query sequence differs from packed reads.

There is no silent CPU fallback.

## Non-Goals

M2a does not:

- link CUDA runtime into Flye;
- upload Flye's real `VertexIndex` to GPU;
- replace real Flye candidate generation for assembly runs;
- prove full assembly equivalence;
- claim end-to-end speedup.

## Superseding Contract

M2b adds `CUFLYE_CUDA_ADAPTER_MODE=pack-dump-v0` for extracting real Flye
query/index data into packed candidate-backend input bundles. See
`docs/abi/cuda-real-data-pack-dump-v0.md`.

## M2d Stop-After-Query Proof Mode

M2d extends `external-packed-v0` with
`CUFLYE_CUDA_STOP_AFTER_PACKED_QUERY=1`. In this mode, Flye still invokes the
external CUDA backend, parses the resulting candidate-record-v1 TSV, validates
the packed query id and sequence, and appends matching records to Flye's
candidate collection.

After appending records for the current query, the adapter fails closed with a
diagnostic that includes:

- `adapter=external-packed-v0`;
- `stop_after_packed_query=1`;
- `query_id`;
- `emitted_records`;
- `candidate_tsv`;
- `json`.

This mode exists only to prove the Flye-to-CUDA adapter boundary on one real
packed query. It must not be used to claim full assembly equivalence or
end-to-end speedup.
