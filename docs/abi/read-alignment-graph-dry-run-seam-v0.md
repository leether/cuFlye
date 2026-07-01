# Read Alignment Graph Dry-Run Seam v0

Status: accepted in M5j

Introduced: M5j

Scope: Flye-side dry-run seam for validating CUDA read-alignment replay output
before any future graph mutation consumption path.

## Purpose

`cuflye-read-alignment-graph-dry-run-seam-v0` is a safety contract. It lets a
patched Flye run call the CUDA read-alignment replay backend, validate the
backend output against the CPU oracle emitted from the same run, and write
guard metadata. It must not replace Flye's in-memory `_readAlignments`, and it
must not feed CUDA output into graph mutation.

## Selectors

The seam is disabled by default. It is enabled only when:

```text
CUFLYE_READ_ALIGNMENT_WORKER_MODE=cuda-bulk-persistent-v0
CUFLYE_READ_ALIGNMENT_GRAPH_CONSUMPTION_MODE=dry-run-v0
```

Required environment variables when enabled:

| Variable | Meaning |
| --- | --- |
| `CUFLYE_READ_ALIGNMENT_WORKER_BIN` | Path to `cuflye-cuda-read-alignment-chain-replay`. |
| `CUFLYE_READ_ALIGNMENT_WORKER_OUTPUT_DIR` | Directory where Flye writes fixture list, worker output, validation, guard, and summary JSON. |
| `CUFLYE_READ_ALIGNMENT_REPLAY_DUMP_DIR` | Existing replay fixture dump root. |
| `CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS` | Comma-separated positive read ids to dump and send to the worker. |

Optional variables:

| Variable | Default | Meaning |
| --- | --- | --- |
| `CUFLYE_READ_ALIGNMENT_WORKER_DEVICE` | `0` | CUDA device passed to the worker. |
| `CUFLYE_READ_ALIGNMENT_WORKER_WARMUP_RUNS` | `0` | Worker warmup runs. |
| `CUFLYE_READ_ALIGNMENT_WORKER_BENCHMARK_RUNS` | `1` | Worker timed runs. |
| `CUFLYE_READ_ALIGNMENT_WORKER_MEMORY_BUDGET_BYTES` | unset | Optional CUDA memory budget passed to the worker. |
| `CUFLYE_READ_ALIGNMENT_WORKER_VALIDATION_MODE` | `oracle-diff-v0` | Validation mode. Only `oracle-diff-v0` is supported in M5j. |

Unsupported values fail closed. There is no silent CPU fallback.

## Worker Invocation

The M5j seam writes a newline-delimited fixture list under the worker output
directory, then invokes:

```text
cuflye-cuda-read-alignment-chain-replay
  --backend cuda
  --device <device>
  --batch-fixtures-file <fixture-list>
  --batch-output-dir <worker-output/read-alignment-output>
  --batch-json-output <worker-output/read-alignment-worker-batch.json>
  --allow-heterogeneous-batch
  --cuda-persistent-arena
  --cuda-persistent-bulk-output
```

The seam appends warmup, benchmark, and memory-budget options when configured.

## Validation

`oracle-diff-v0` validates every selected fixture by comparing the worker TSV
against the fixture's `oracle.read-alignment.tsv` as sorted canonical rows.

A passing validation writes `read-alignment-worker-validation.json` with:

```json
{
  "schema": "cuflye-read-alignment-worker-validation-v0",
  "status": "passed",
  "worker_output_consumption_eligible": true,
  "fixture_count": 4,
  "validated_fixture_count": 4,
  "mismatched_fixture_count": 0
}
```

## Graph Guard

When `CUFLYE_READ_ALIGNMENT_GRAPH_CONSUMPTION_MODE=dry-run-v0`, Flye writes:

```text
read-alignment-graph-consumption-guard.json
```

with schema:

```json
{
  "schema": "cuflye-read-alignment-graph-consumption-guard-v0",
  "status": "passed",
  "mode": "dry-run-v0",
  "guard_eligibility": "eligible",
  "graph_consumption_state": "not-consumed",
  "decision": "dry-run-not-consumed",
  "eligible": true,
  "consumed": false,
  "not_consumed": true,
  "failed_closed": false,
  "graph_mutation_consumed_worker_output": false
}
```

The seam summary also records these fields and the worker paths in:

```text
read-alignment-seam-summary.json
```

## Failure Semantics

If the worker command fails, validation fails, guard preconditions fail, or a
required input is missing, Flye writes the available audit metadata and exits
non-zero before graph mutation.

Successful M5j dry-run also exits non-zero after writing the guard because the
milestone intentionally stops before graph mutation. The only successful graph
state in M5j is:

```text
graph_consumption_state=not-consumed
graph_mutation_consumed_worker_output=false
```

## M5j Benefit Assessment

In plain terms, M5j is not expected to make full Flye faster. Its value is
reducing integration risk: CUDA read-alignment output can now be produced and
checked from inside a Flye run, but the code still refuses to let that output
change graph state.
