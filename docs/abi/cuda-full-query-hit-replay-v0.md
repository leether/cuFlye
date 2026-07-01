# cuFlye CUDA Full Query-Hit Replay v0

Status: accepted

Introduced: M6h

Scope: standalone CUDA replay of selected M6f/M6g read-to-graph source packs.

## Purpose

`cuflye-cuda-full-query-hit-replay-v0` is the first CUDA consumer for the
`full-query-hits.tsv` source stream captured at the read-to-graph overlap
boundary. It consumes a validated
`cuflye-read-to-graph-minimizer-source-pack-v0` directory and emits raw-overlap
records with row keys compatible with the M6g CPU replay oracle.

M6h is a correctness boundary. M6i adds an optional `parallel-score` kernel
mode for the same ABI. M6j adds a bounded `--repeat-count` warm-session
benchmark mode for the same selected source-pack shape. None of these modes
feed CUDA output into Flye graph logic or claim whole-Flye acceleration.

## Command

```text
cuflye-cuda-full-query-hit-replay \
  --source-pack-dir DIR \
  --output-tsv PATH \
  [--json-output PATH] \
  [--kernel-mode serial|parallel-score] \
  [--device ID] \
  [--repeat-count N] \
  [--memory-budget-bytes N]
```

## Input

The input directory must contain selected query directories with
`full-query-hits.tsv`, `edge-sequences.tsv`, `query.tsv`, `manifest.json`, and
the M6 source-pack companion files. The M6h prototype uses host parsing and
Flye-compatible host-side ordering before launching CUDA.

Unsupported shapes fail closed. M6h explicitly rejects any active ext group
with more than `4096` query-hit records, empty active replay groups, memory
budget violations, and malformed source-pack files.

## CUDA Work

Two kernel modes are currently accepted:

- `serial`: one CUDA block with one active thread per ext group. This is the
  M6h correctness mode.
- `parallel-score`: one CUDA block with `128` threads per ext group. Threads
  split predecessor scoring for each DP row and reduce to a deterministic best
  predecessor. Backtracking, overlap geometry checks, sorting, and
  primary-overlap filtering remain serial inside the block.

For each active ext group, both modes replay:

- Flye-style gap-aware chain DP;
- DP backtracking from descending score order;
- overlap geometry checks for the read-to-graph detector shape;
- primary-overlap containment filtering.

This remains intentionally conservative. The accepted proof requires CPU vs
CUDA and serial vs parallel canonical row-key `match` before any stronger claim
is allowed.

`--repeat-count N` keeps parsed input, CUDA context, and device buffers alive
inside one process, then launches the selected kernel `N` times. It writes only
the final request's TSV output, and JSON records per-request reset, kernel,
device-to-host, and request-total timings. This is a benchmark harness for the
future worker boundary, not a long-lived JSONL worker.

## Output TSV

`--output-tsv` writes `cuflye-read-to-graph-raw-overlap-v0` rows. The M6h
equivalence key is:

```text
query_id, read_id, read_begin, read_end, read_len,
edge_seq_id, edge_begin, edge_end, edge_len, score
```

This is compared with `tools/diff_read_to_graph_raw_overlap_row_keys.py`, which
canonicalizes row keys before hashing and also reports `ordered_match`.

M6h accepted proof has canonical CPU-vs-CUDA row-key `match` for all `36` rows.
Direct CPU-vs-CUDA row order is not identical because one equal-score row pair
uses a different tie order; CUDA A/B row order is deterministic.

## JSON Summary

`--json-output` writes:

```json
{
  "schema": "cuflye-cuda-full-query-hit-replay-v0",
  "status": "ok",
  "backend": "cuda",
  "kernel_mode": "parallel-score",
  "parallel_threads": 128,
  "repeat_count": 5,
  "source_pack_dir": "...",
  "output_tsv": "...",
  "device": 0,
  "device_name": "NVIDIA GB10",
  "query_count": 8,
  "source_match_records": 7747,
  "source_ext_groups": 33,
  "active_ext_groups": 22,
  "output_records": 36,
  "max_supported_group_matches": 4096,
  "required_bytes": 1142052,
  "timing_ms": {
    "kernel": 52.542531,
    "total": 311.103565
  },
  "request_timings_ms": [
    {
      "request_ordinal": 0,
      "reset": 0.003760,
      "kernel": 52.544731,
      "device_to_host": 0.031712,
      "request_total": 52.580331,
      "output_records": 36
    }
  ]
}
```

On fail-closed errors, JSON uses the same schema with `status: "error"` and an
`error` string. Error JSON also includes `kernel_mode` so rejected requests can
be attributed to the selected backend shape.

## Non-Goals

M6h/M6i/M6j do not:

- reproduce non-key raw-overlap fields such as `edge_id` or full
  `seq_divergence` parity;
- preserve direct CPU raw row order for equal-score ties;
- consume CUDA output inside Flye;
- prove whole-Flye speedup.
