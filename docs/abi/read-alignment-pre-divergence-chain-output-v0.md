# Read Alignment Pre-Divergence Chain Output v0

Status: accepted for M5n

Introduced: M5n

Scope: explicit standalone worker mode for emitting read-alignment chain DP
results before divergence acceptance is applied.

## Purpose

`cuflye-read-alignment-pre-divergence-chain-output-v0` removes a dependency
that blocks future GPU-first read-alignment integration. Before M5n, the CUDA
read-alignment worker required `chain-divergence.tsv`, which is written only
after Flye has already run CPU chain DP and CPU divergence filtering for a
read. That made the worker unsuitable as a true replacement for the chain DP
substage.

M5n adds an explicit pre-divergence output mode. The worker consumes only:

```text
manifest.json
edge-overlaps.tsv
```

and emits all pre-divergence accepted chains.

## Selector

```text
--emit-pre-divergence-chains
```

The selector is supported only in single-fixture mode for M5n.

## Input Contract

Required files:

```text
manifest.json
edge-overlaps.tsv
```

Forbidden dependency:

```text
chain-divergence.tsv
```

The worker must not read `chain-divergence.tsv` in this mode. A proof fixture
may delete or hide the file to demonstrate that the mode is decoupled from CPU
divergence acceptance.

## Output Contract

The existing `read-alignment.tsv` record shape is reused:

```text
chain_id segment_id read_id read_begin read_end read_len edge_id edge_seq_id edge_begin edge_end edge_len score seq_divergence
```

In M5n, `chain_id` enumerates pre-divergence accepted chains. No divergence
filtering is applied.

Worker JSON records:

```json
{
  "schema": "cuflye-cuda-read-alignment-chain-replay-v0",
  "status": "ok",
  "supported_shape": {
    "output_mode": "pre-divergence-chains",
    "uses_fixture_divergence_acceptance": false
  }
}
```

## Unsupported Shapes

The mode fails closed in batch and persistent modes until those paths receive
separate proof.

## M5n Benefit Assessment

M5n does not prove whole-Flye acceleration. Its value is architectural: CUDA can
produce the chain DP output before CPU divergence filtering, using only the
edge-overlap input pack. That is the missing protocol step before selected
Flye reads can skip CPU `chainReadAlignments` and let CPU divergence filtering
run on GPU-produced chains.

Accepted DGX proof:

```text
proof_root=/tmp/cuflye-m5n-proof-20260701T015602Z
fixture=query_3512_no_divergence
chain_divergence_present=false
oracle_read_alignment_present=false
cpu_output_mode=pre-divergence-chains
cuda_output_mode=pre-divergence-chains
uses_fixture_divergence_acceptance=false
cpu_output_records=3
cuda_output_records=3
cpu_vs_cuda_diff=match
negative_batch_mode=failed-closed
```
