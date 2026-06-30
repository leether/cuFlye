# Task Card: cuFlye M4c CUDA Overlap Chain DP Prototype

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Implement the first CUDA overlap-chain DP prototype for the M4b supported
fixture shape and prove that it reproduces the CPU replay oracle at the
`overlap-range-v1` boundary.

The core question this card must answer is:

```text
Can CUDA reproduce Flye's candidate-to-overlap chain DP for one bounded,
non-base-alignment replay fixture without changing overlap semantics?
```

## Background

M4a defined and validated `overlap-range-v1`. M4b isolated one raw-read replay
fixture where base-level alignment, bad-mapping trimming, and stored k-mer
alignment payloads are disabled. The CPU replay output now exactly matches
Flye's oracle for query `-71`.

M4c is the first CUDA step in overlap chaining. It must stay outside Flye graph
logic and compare only at the replay boundary.

## In Scope

- Consume the M4b `overlap-replay-fixture-v0` files.
- Implement a CUDA prototype for the supported chain DP shape.
- Preserve Flye's score, gap-cost, jump, overhang, primary-overlap, and
  k-mer-divergence semantics for the supported fixture.
- Emit `overlap-range-v1`.
- Compare CUDA output against the CPU replay oracle with canonical diff.
- Record compact DGX proof under `tests/golden/`.

## Out of Scope

- No Flye graph integration.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No support for `keep_alignment=true`.
- No end-to-end Flye speedup claim.
- No large candidate or overlap TSV committed.

## C++/CUDA Style Constraints

- Keep CUDA code CUDA C++14 unless a later Task Card justifies a change.
- Use existing move-only RAII helpers for CUDA allocations and events.
- Do not introduce direct `cudaMalloc`, `cudaFree`, `cudaEventCreate`, or
  `cudaEventDestroy` outside approved RAII wrappers.
- Do not introduce raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Use explicit-width integer types at file-format, host/device transfer, and
  kernel boundaries.
- Fail closed on unsupported fixture shapes and memory-budget violations.
- Keep Flye patches unchanged unless a separate Task Card is opened.

## Deliverables

- CUDA overlap-chain prototype source or worker mode.
- Build script for the prototype.
- DGX proof manifest under `tests/golden/`.
- Documentation of supported fixture shape and unsupported cases.

## Acceptance Gates

- CUDA prototype builds on DGX.
- Unsupported fixture shapes fail closed before kernel launch.
- CUDA output validates as `overlap-range-v1`.
- CUDA output canonical-diffs `match` against the M4b CPU replay oracle for
  query `-71`.
- Local syntax/style gates pass.
- CUDA ownership scan shows no new direct resource APIs outside RAII wrappers.
- DGX proof is compact and does not include large TSV outputs.

## Execution Checklist

- [x] Inspect M4b replay fixture and CPU replay code paths.
- [x] Design CUDA prototype input/output layout.
- [x] Implement CUDA chain DP for the supported fixture shape.
- [x] Add build script and local syntax/style gates.
- [x] Run CUDA output validation on DGX.
- [x] Diff CUDA output against the CPU replay oracle.
- [x] Run ownership/resource scan.
- [x] Record compact DGX proof and close this card.

## Merge Note

Implementation commits:

- `dec0ce07497d9d5eb8b049e4bbec9d13ddb683fe`
- `0dc2e9b8a4546b032f6d43aaeb4591cb77cbe9c1`

DGX proof manifest:
`tests/golden/cuflye-m4c-cuda-overlap-chain-dp-dgx-aarch64.json`

Proof summary:

- Host: `edgexpert-45d2` (`aarch64`)
- GPU: `NVIDIA GB10`, CUDA arch `sm_121`
- CUDA compiler: `/usr/local/cuda/bin/nvcc`, CUDA `13.0`
- Fixture: M4b `query_neg71`
- Candidate records: `7,859`
- Target groups: `120`
- CUDA overlap records: `51`
- Canonical overlap SHA-256:
  `1a3347f96c74e0297a80871b32fa6cce2bccbf2731a7facb95e9333185c23e73`
- Canonical diff vs M4b CPU replay oracle: `match`
- CUDA kernel time for the single supported fixture: `4.80657 ms`
- Unsupported shape negative gate: base-alignment/trim fixture rejected before
  kernel launch
- Memory-budget negative gate: `required=461407`, `budget=1`, rejected before
  allocation
- Ownership scan: no new direct `cudaMalloc`, `cudaFree`,
  `cudaEventCreate`, or `cudaEventDestroy` outside RAII wrappers

This card proves correctness for one bounded CUDA overlap-chain replay shape.
It does not claim Flye graph integration, base-level alignment replay, trim
replay, or end-to-end GPU speedup.
