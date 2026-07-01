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

M6h is a correctness boundary. It does not feed CUDA output into Flye graph
logic and does not claim whole-Flye acceleration.

## Command

```text
cuflye-cuda-full-query-hit-replay \
  --source-pack-dir DIR \
  --output-tsv PATH \
  [--json-output PATH] \
  [--device ID] \
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

For each active ext group, one CUDA block serially replays:

- Flye-style gap-aware chain DP;
- DP backtracking from descending score order;
- overlap geometry checks for the read-to-graph detector shape;
- primary-overlap containment filtering.

This is intentionally conservative. It proves the CUDA boundary can reproduce
the selected row-key output before M6i attempts more parallelism.

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
    "kernel": 53.170850,
    "total": 349.315503
  }
}
```

On fail-closed errors, JSON uses the same schema with `status: "error"` and an
`error` string.

## Non-Goals

M6h does not:

- reproduce non-key raw-overlap fields such as `edge_id` or full
  `seq_divergence` parity;
- preserve direct CPU raw row order for equal-score ties;
- consume CUDA output inside Flye;
- prove speedup.
