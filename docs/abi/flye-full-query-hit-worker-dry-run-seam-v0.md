# Flye Full Query-Hit Worker Dry-Run Seam v0

Status: active

M6l connects the M6k `cuflye-full-query-hit-worker-request-v0` protocol to a
real Flye read-to-graph run. It is intentionally a dry-run seam: Flye generates
the selected source pack, calls the CUDA worker, validates raw-overlap row-key
parity, writes audit metadata, and stops before graph mutation.

## Environment

Required:

```text
CUFLYE_READ_TO_GRAPH_SOURCE_PACK_DIR=/path/to/source-pack-root
CUFLYE_READ_TO_GRAPH_SOURCE_PACK_QUERY_IDS=5,6,7,8,9,10,11,12
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MODE=full-query-hit-dry-run-v0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_BIN=/path/to/cuflye-cuda-full-query-hit-replay
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_OUTPUT_DIR=/path/to/worker-audit
```

Optional:

```text
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_DEVICE=0
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_KERNEL_MODE=parallel-score
CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_MEMORY_BUDGET_BYTES=<bytes>
```

`parallel-score` is the only supported M6l kernel mode. The mode requires
`--threads 1` because the selected source-pack oracle must be deterministic.

## Worker Request

Flye writes:

```text
$CUFLYE_READ_TO_GRAPH_FULL_QUERY_HIT_WORKER_OUTPUT_DIR/full-query-hit-worker-request.json
```

The request uses:

```text
schema=cuflye-full-query-hit-worker-request-v0
adapter_mode=full-query-hit-replay-v0
raw_overlap_abi=cuflye-read-to-graph-raw-overlap-v0
kernel_mode=parallel-score
```

The worker output is:

```text
full-query-hit-worker.raw-overlaps.tsv
```

## Audit

Flye writes:

```text
full-query-hit-worker-dry-run.json
```

The positive path records:

```json
{
  "schema": "cuflye-read-to-graph-full-query-hit-worker-dry-run-v0",
  "status": "passed",
  "decision": "stopped-before-graph-mutation",
  "row_key_matched": true,
  "worker_output_consumption_eligible": true,
  "graph_mutation_consumed_worker_output": false
}
```

The negative path records:

```json
{
  "status": "failed-before-graph-mutation",
  "decision": "fail-closed-before-graph-mutation",
  "worker_output_consumption_eligible": false,
  "graph_mutation_consumed_worker_output": false,
  "failed_closed": true
}
```

## Row-Key Gate

M6l uses the same row-key contract as
`tools/diff_read_to_graph_raw_overlap_row_keys.py`:

```text
query_id, read_id, read_begin, read_end, read_len,
edge_seq_id, edge_begin, edge_end, edge_len, score
```

`source_order`, `raw_overlap_count`, `chain_input_count`, `edge_id`,
`seq_divergence`, and `passes_chain_input_filter` are not part of this M6l
correctness claim.

## Non-Goals

M6l does not:

- mutate Flye graph state with CUDA output;
- make CUDA the default path;
- claim whole-Flye acceleration;
- prove full raw-overlap field parity beyond the row key.
