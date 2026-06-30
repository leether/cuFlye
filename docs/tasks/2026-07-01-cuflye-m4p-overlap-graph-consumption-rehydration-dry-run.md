# Task Card: cuFlye M4p Overlap Graph Consumption Rehydration Dry Run

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Build the first no-mutation adapter that rehydrates validated CUDA overlap
worker TSV output into Flye-side overlap objects or an equivalent typed
structure, then proves it matches the CPU overlap vector before graph mutation.

## Background

M4o defines the guard contract for future graph consumption, but it still stops
at audit metadata. The next risk is representational: worker TSV records must
be converted into the exact in-memory shape that downstream Flye graph code
would consume. That conversion must be deterministic, checked against the CPU
vector, and auditable before any graph mutation path is allowed to use it.

## In Scope

- Add an explicit rehydration dry-run mode gated behind the M4o guard.
- Rehydrate worker `overlap-range-v1` records into a Flye-side typed structure
  that preserves ids, ranges, scores, and divergence.
- Compare the rehydrated worker vector against the CPU overlap vector after
  validation and shadow success.
- Write a compact rehydration audit JSON.
- Keep graph mutation on CPU output only.
- Include a negative proof where rehydration or typed-vector equivalence fails
  closed before graph mutation.
- Include a plain-language CUDA benefit assessment after proof.

## Out of Scope

- No default GPU mode.
- No worker output used by graph mutation.
- No end-to-end speed claim.
- No broad production dataset compatibility claim.
- No silent CPU fallback.

## Acceptance Gates

- [x] Rehydration dry-run mode is documented and disabled by default.
- [x] The mode requires M4o guard eligibility before running.
- [x] Rehydrated worker vectors match CPU overlap vectors on the selected fixture
  matrix.
- [x] Negative rehydration mismatch fails closed before graph mutation.
- [x] Audit metadata records eligible, not-consumed, failed-closed, and mismatch
  details.
- [x] Default CPU Flye fixture output remains unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Use standard containers and stack objects for typed overlap data.
- Do not add raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Keep conversion logic local to the seam until a later milestone explicitly
  enables graph mutation.

## Deliverables

- [x] Rehydration dry-run ABI/design documentation.
- [x] Flye seam patch or helper code for typed overlap rehydration.
- [x] DGX proof manifest for positive and negative rehydration dry-runs.
- [x] Roadmap, Task Card, golden index, and plain-language benefit assessment.

## Completion Notes

- Added `CUFLYE_OVERLAP_REHYDRATION_MODE=typed-overlap-v0`.
- Added proof-only negative selector
  `CUFLYE_OVERLAP_REHYDRATION_PROOF_FAULT=drop-first-worker-record`.
- Added `worker-rehydration.json` with schema
  `cuflye-overlap-rehydration-dry-run-v0`.
- Added seam summary fields:
  `overlap_rehydration_mode`, `overlap_rehydration_json`,
  `overlap_rehydration_status`, `overlap_rehydration_state`,
  `overlap_rehydration_decision`, and `overlap_rehydration_eligible`.
- Positive DGX proof used the M4n 12-fixture heterogeneous matrix with
  validation, shadow comparison, and M4o guard enabled. Rehydration wrote
  `status=passed`, `state=not-consumed`, `eligible=true`, and
  `graph_mutation_consumed_worker_output=false`.
- Negative DGX proof used the same matrix and proof fault. Validation, shadow,
  and guard still passed, but typed-vector comparison produced `12` mismatching
  fixtures and wrote `status=rehydration-failed-before-graph-mutation` before
  graph mutation.
- Default CPU `toy-hifi` output remained unchanged against the M0 DGX golden
  manifest: `9` of `9` canonical artifacts matched.
- Proof manifest:
  `tests/golden/cuflye-m4p-overlap-rehydration-dry-run-dgx-aarch64.json`.

## Plain-Language CUDA Benefit Assessment

This step still does not make Flye faster. Its benefit is safety: CUDA overlap
worker output now has to survive a Flye-side typed-vector conversion and match
CPU in-memory overlap records before any future graph construction path can
consider using it. In practical terms, M4p reduces integration risk; it is not a
performance milestone.

Implementation commit:

- `d0bbd7b6fe80dc1d663c114ba47e693ee9958796`
