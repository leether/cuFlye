# Task Card: cuFlye M2f Sparse Output Compaction

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Remove the dense `pairCount * CandidateRecord` output bottleneck from the real
pack CUDA backend so the GPU-only backend total can beat the measured CPU oracle
for the same query.

The core question this card must answer is:

```text
Can CUDA candidate generation be faster than the CPU oracle after removing dense
output materialization while preserving exact candidate-record-v1 output?
```

## Background

M2e measured the real pack candidate boundary:

- CPU oracle: `947.291 ms`
- CUDA kernel: `5.815 ms`
- GPU-only backend total before JSON: `1245.546 ms`
- Host dense output allocation: `819.391 ms`

The kernel is already fast. The bottleneck is materializing a dense output buffer
for all `51742433` query/index pairs when only `15571` records are emitted.

## In Scope

- Replace dense candidate output with a sparse/compacted path.
- Preserve candidate-record-v1 TSV ordering and contents.
- Keep timing metadata for the new stages.
- Run the same M2b real pack on DGX.
- Validate CPU/GPU candidate equivalence.
- Record compact proof under `tests/golden/`.

## Out of Scope

- No Flye patch changes.
- No multi-query batching.
- No downstream graph logic.
- No full assembly speedup claim.

## C++/CUDA Style Constraints

- Keep the standalone backend in CUDA C++14.
- Use RAII wrappers for CUDA allocations and events.
- Do not add direct CUDA resource creation/destruction outside
  `cuda/cuflye_cuda_raii.hpp`.
- Check output-count conversions before narrowing.
- Keep unsupported shapes fail-closed.

## Deliverables

- `cuda/cuflye_cuda_read_window_smoke.cu` sparse output compaction.
- `docs/abi/cuda-read-window-smoke-v0.md` M2f extension note.
- DGX proof showing exact candidate equivalence and GPU-only backend total below
  the M2e CPU oracle time.
- Compact golden proof under `tests/golden/`.

## Acceptance Gates

- CUDA backend builds on DGX with `nvcc`.
- Real pack GPU output validates as candidate-record-v1.
- Real pack CPU vs GPU canonical diff is `match`.
- Runtime JSON reports `output_strategy=sparse-offsets-v1`.
- Runtime JSON reports no dense pair output materialization.
- GPU-only `timing_ms.total_before_json` is below `947.291 ms` for the measured
  real pack.
- No large TSV output is committed.

## Execution Checklist

- [x] Add sparse output path.
- [x] Update ABI docs.
- [x] Build CUDA backend on DGX.
- [x] Run real-pack sparse timing proof.
- [x] Validate and diff CPU/GPU outputs.
- [x] Record compact golden proof and close this card.

## Merge Note

Implemented in repo commit `f2ad482bbf5a4e08a58d0adf28f32170c5227f23` and
validated on DGX host `edgexpert-45d2` with `/usr/local/cuda/bin/nvcc`
`13.0.88` targeting `sm_121`.

Real pack proof:

- Source pack:
  `/tmp/cuflye-m2b-1782793203/out/m2b/proof/pack/query_neg253`
- Query id: `-253`
- Query length: `3339`
- K-mer size: `17`
- Pair comparisons: `51742433`
- Candidate records: `15571`
- Output strategy: `sparse-offsets-v1`
- Dense pair output materialized: `false`
- CPU oracle time: `943.032 ms`
- GPU-only backend total before JSON: `425.540 ms`
- GPU-only vs CPU oracle speedup: `2.22x`
- Kernel time: `6.361 ms`
- M2e dense GPU-only total before JSON: `1245.546 ms`
- Sparse vs dense GPU-only total speedup: `2.93x`
- Device allocation: `260459496` bytes
- M2e dense device allocation: `2536379140` bytes
- Device allocation reduction: `9.74x`
- Flye external adapter wall time to controlled stop: `0:03.34`
- M2e Flye external adapter wall time: `0:05.73`
- Flye external adapter RSS: `355792 kB`
- M2e Flye external adapter RSS: `2580004 kB`
- CPU/GPU/adapter candidate diffs: `match`
- Canonical SHA-256:
  `5b50c458d82458516662e59daf3638e3534896a3ab1e77791f46dc54b663a1ae`

Tracked compact proof:

- `tests/golden/cuflye-m2f-sparse-output-compaction-dgx-aarch64.json`

This is the first real-pack backend proof where CUDA is faster than the CPU
oracle at the measured candidate-generation boundary. It still does not claim
full Flye assembly speedup.
