# Task Card: cuFlye M4p Overlap Graph Consumption Rehydration Dry Run

Status: proposed

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

- Rehydration dry-run mode is documented and disabled by default.
- The mode requires M4o guard eligibility before running.
- Rehydrated worker vectors match CPU overlap vectors on the selected fixture
  matrix.
- Negative rehydration mismatch fails closed before graph mutation.
- Audit metadata records eligible, not-consumed, failed-closed, and mismatch
  details.
- Default CPU Flye fixture output remains unchanged.
- Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Use standard containers and stack objects for typed overlap data.
- Do not add raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Keep conversion logic local to the seam until a later milestone explicitly
  enables graph mutation.

## Deliverables

- Rehydration dry-run ABI/design documentation.
- Flye seam patch or helper code for typed overlap rehydration.
- DGX proof manifest for positive and negative rehydration dry-runs.
- Roadmap, Task Card, golden index, and plain-language benefit assessment.
