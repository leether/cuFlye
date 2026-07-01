# Read Alignment Pre-Divergence Flye Dry Run v0

Status: accepted in M5o

Introduced: M5o

Scope: selected-read Flye-side dry run that feeds CUDA-produced pre-divergence
chains into Flye's existing divergence filtering and compares against CPU
`goodChains`.

## Selector

```text
CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_MODE=selected-read-dry-run-v0
```

Required companions:

```text
CUFLYE_READ_ALIGNMENT_WORKER_BIN=/path/to/cuflye-cuda-read-alignment-chain-replay
CUFLYE_READ_ALIGNMENT_REPLAY_DUMP_DIR=/path/to/read-alignment-fixtures
CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS=...
```

The mode requires `--threads 1` in M5o so the selected-read dry-run proof is
deterministic and writes per-query evidence without concurrent races.

## Worker Invocation

For each selected read, Flye writes the usual replay fixture and invokes:

```text
cuflye-cuda-read-alignment-chain-replay \
  --backend cuda \
  --fixture-dir <query_fixture> \
  --output-tsv <query_fixture>/predivergence-worker/read-alignment.tsv \
  --json-output <query_fixture>/predivergence-worker/worker.json \
  --emit-pre-divergence-chains
```

## Flye-Side Check

Flye then:

1. Rehydrates worker TSV rows into `std::vector<GraphAlignment>`.
2. Runs `getChainBaseDivergence` on each GPU-produced chain.
3. Applies the existing `read_align_ovlp_divergence` cutoff.
4. Canonicalizes the GPU-filtered chains and CPU `goodChains`.
5. Passes only if the canonical records match exactly.

No `_readAlignments` replacement is performed by this mode.

## Generated Files

Per selected query:

```text
read-alignment-predivergence-dry-run.json
predivergence-worker/read-alignment.tsv
predivergence-worker/worker.json
predivergence-worker/stdout.log
predivergence-worker/stderr.log
```

## Negative Proof Fault

```text
CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_PROOF_FAULT=drop-first-gpu-good-chain
```

The fault removes the first GPU-filtered good chain after worker output and
divergence filtering, forcing the CPU/GPU good-chain comparison to fail closed.

## Benefit Assessment

M5o still does not prove whole-Flye acceleration. Its benefit is integration
safety: CUDA pre-divergence chain DP output can enter Flye's read-alignment loop
and survive Flye's own divergence/filtering semantics before any future
replacement of `chainReadAlignments`.

## Proof

Accepted DGX proof:

```text
tests/golden/cuflye-m5o-read-alignment-pre-divergence-flye-dry-run-dgx-aarch64.json
```
