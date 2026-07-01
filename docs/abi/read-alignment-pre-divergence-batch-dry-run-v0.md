# Read Alignment Pre-Divergence Batch Dry Run v0

Status: accepted in M5p

Introduced: M5p

Scope: Flye-side batch dry run for selected read-alignment replay fixtures.
Flye captures CPU `goodChains`, invokes one CUDA worker process for the selected
fixture list, rehydrates GPU-produced pre-divergence chains, applies Flye's
existing divergence filter, and compares per-query canonical records.

## Selector

```text
CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_MODE=batch-dry-run-v0
```

Required companions:

```text
CUFLYE_READ_ALIGNMENT_WORKER_BIN=/path/to/cuflye-cuda-read-alignment-chain-replay
CUFLYE_READ_ALIGNMENT_REPLAY_DUMP_DIR=/path/to/read-alignment-fixtures
CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS=...
```

The mode requires `--threads 1` in M5p so the fixture capture and batch audit
are deterministic.

## Worker Invocation

Flye writes each selected query fixture as usual, then writes one fixture list
under:

```text
<replay_dump_dir>/predivergence-batch-worker/read-alignment-fixtures.list
```

Flye invokes one worker process:

```text
cuflye-cuda-read-alignment-chain-replay \
  --backend cuda \
  --batch-fixtures-file <fixture_list> \
  --batch-output-dir <batch_output_dir> \
  --batch-json-output <worker_batch_json> \
  --allow-heterogeneous-batch \
  --emit-pre-divergence-chains
```

The worker batch JSON must report:

```text
supported_shape.output_mode=pre-divergence-chains
supported_shape.uses_fixture_divergence_acceptance=false
```

## Flye-Side Check

For every selected query, Flye:

1. Rehydrates that query's worker TSV into `std::vector<GraphAlignment>`.
2. Runs `getChainBaseDivergence` on each GPU-produced chain.
3. Applies the existing `read_align_ovlp_divergence` cutoff.
4. Canonicalizes GPU-filtered chains and CPU `goodChains`.
5. Passes only if the canonical records match for every selected query.

No `_readAlignments` replacement is performed by this mode.

## Generated Files

Batch root:

```text
<replay_dump_dir>/predivergence-batch-worker/
```

Important files:

```text
read-alignment-fixtures.list
read-alignment-worker-batch.json
read-alignment-predivergence-batch-dry-run.json
read-alignment-worker-stdout.log
read-alignment-worker-stderr.log
read-alignment-output/query_<id>/read-alignment.tsv
```

## Negative Proof Fault

```text
CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_PROOF_FAULT=drop-first-gpu-good-chain
```

The fault removes the first GPU-filtered good chain from the first selected
query with a non-empty GPU good-chain set, forcing the batch comparison to fail
closed after worker output is produced.

## Benefit Assessment

M5p reduces the M5o integration overhead from one worker process per selected
read to one worker process for the selected batch. It does not prove full-Flye
acceleration: on the toy batch, CUDA setup still dominates worker wall time.

## Proof

Accepted DGX proof:

```text
tests/golden/cuflye-m5p-read-alignment-pre-divergence-batch-dry-run-dgx-aarch64.json
```
