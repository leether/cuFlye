# Task Card: cuFlye M2a CUDA Candidate Adapter Shell

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Replace the M1d CUDA backend stub with a real Flye-side adapter shell that can
invoke a CUDA candidate backend on packed toy data while failing closed for
unsupported real Flye shapes.

The core question this card must answer is:

```text
Can Flye's CUDA candidate backend cross from stub to governed adapter shell without risking silent semantic drift?
```

## Background

M1f-M1i proved standalone CUDA candidate generation on bounded fixtures. M1j
proved a bounded CUDA equality-scan core can be faster than the CPU oracle. None
of those prototypes were connected to Flye's candidate backend selector. M2a
connects the selector to an external CUDA backend, but keeps the boundary
restricted to packed toy fixtures until real `VertexIndex` packing is designed.

## In Scope

- Add a Flye patch that replaces `collectCandidateMatchesCudaStub` with an
  external packed adapter shell.
- Require explicit adapter environment variables for packed toy mode.
- Invoke the existing standalone CUDA read-window smoke backend.
- Parse candidate-record-v1 output back into Flye's candidate list container.
- Fail closed when current Flye query id or sequence does not match packed
  reads.
- Extend the fixture runner with adapter environment variables and metadata.
- Prove default/CPU backend behavior still works.
- Prove CUDA adapter invocation on DGX produces ABI-valid packed toy output.
- Prove real Flye toy data is rejected as unsupported rather than silently
  falling back to CPU.

## Out of Scope

- Direct CUDA runtime linkage from Flye.
- Real Flye `VertexIndex` packing.
- Full assembly success under CUDA backend.
- Performance claims beyond previously proved M1j candidate-core speedup.
- Any change to Flye graph, chaining, repeat resolution, or polishing logic.

## Deliverables

- `patches/flye/2.9.6/0004-cuflye-cuda-adapter-shell.patch`
- `docs/abi/cuda-candidate-adapter-shell-v0.md`
- runner support for the M2a adapter environment
- DGX proof that the adapter invokes CUDA and emits ABI-valid candidate TSV
- DGX proof that unsupported real Flye shape fails closed
- compact golden proof under `tests/golden/`

## Acceptance Gates

- Patch series applies through 0004 and builds on DGX.
- Default backend run still completes on the toy fixture.
- Explicit `cpu` backend run still completes on the toy fixture.
- `CUFLYE_CANDIDATE_BACKEND=cuda` with no packed mode fails closed before
  downstream graph logic.
- `CUFLYE_CANDIDATE_BACKEND=cuda` with packed mode invokes the external CUDA
  backend and writes candidate-record-v1 output.
- The packed CUDA output validates with `tools/validate_candidate_dump.py`.
- Packed CUDA output matches `tests/fixtures/read-window-smoke-v0/expected.candidates.tsv`.
- The real Flye toy fixture is rejected with a query id/sequence mismatch rather
  than silently consuming packed candidates.

## Execution Checklist

- [x] Inspect M1d stub and candidate seam.
- [x] Add adapter shell ABI document.
- [x] Add 0004 Flye patch.
- [x] Extend fixture runner environment passthrough.
- [x] Build patched Flye on DGX.
- [x] Build external CUDA read-window backend on DGX.
- [x] Run CPU/default regression on DGX.
- [x] Run CUDA packed adapter invocation proof on DGX.
- [x] Validate and diff packed adapter output.
- [x] Record compact proof and close this card.

## Merge Note

Completed on DGX host `edgexpert-45d2` using a temporary proof checkout at
`/tmp/cuflye-m2a-1782792458`.

Build proof:

- Flye commit: `886b8c17412c`
- Flye version: `2.9.6-b1802`
- Applied patch series:
  - `0001-cuflye-candidate-dump.patch`
  - `0002-cuflye-candidate-backend-seam.patch`
  - `0003-cuflye-cuda-backend-stub.patch`
  - `0004-cuflye-cuda-adapter-shell.patch`
- CUDA backend binary:
  `out/m2a/proof/bin/cuflye-cuda-read-window-smoke`
- CUDA arch: `sm_121`

CPU regression proof:

- Default run: `out/m2a/proof/runs/toy-default`
- Explicit CPU run: `out/m2a/proof/runs/toy-cpu`
- Artifact diff:
  `out/m2a/proof/runs/toy-default-vs-cpu.artifact-diff.json`
- Artifact diff status: `match`
- Candidate diff:
  `out/m2a/proof/runs/toy-default-vs-cpu.candidate-diff.json`
- Candidate records: `29,035,928`
- Candidate canonical SHA-256:
  `97ec5f51c034e5a8a8eaa70d4c3d4ced5513f7ee93ad367671b756814310086b`

CUDA adapter proof:

- Missing packed mode run:
  `out/m2a/proof/runs/toy-cuda-no-mode`
- Missing packed mode status: failed as expected with
  `unsupported real Flye shape`.
- Packed mode run:
  `out/m2a/proof/runs/toy-cuda-packed`
- Packed fixture:
  `tests/fixtures/read-window-smoke-v0`
- GPU candidate output:
  `out/m2a/proof/runs/toy-cuda-packed/gpu-candidates.tsv`
- GPU candidate records: `6`
- GPU candidate SHA-256:
  `f0ef59dafc1a8efa5f007443d4c11191e3f03b2500c87874b40fa89f2803010d`
- Expected-vs-GPU diff:
  `out/m2a/proof/runs/toy-cuda-packed/expected-vs-gpu.candidate-diff.json`
- Expected-vs-GPU status: `match`
- Final CUDA backend status: failed closed after CUDA invocation because the
  real Flye toy query id `-253` is absent from the packed reads TSV.

Tracked compact proof:

- `tests/golden/cuda-candidate-adapter-shell-dgx-aarch64.json`
