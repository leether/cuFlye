# Task Card: cuFlye M4q OverlapRange Object Rehydration Dry Run

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Convert M4p's typed overlap records into actual Flye `OverlapRange` objects in
a no-mutation dry-run, then prove the object vector canonicalizes back to the
CPU overlap vector before any graph-consumption path is enabled.

## Background

M4p proves that worker `overlap-range-v1` rows can be converted into a safe
typed Flye-side structure without losing ids, ranges, scores, or divergence.
The next representational risk is Flye's real downstream object type:
`OverlapRange`. Before CUDA output can be substituted into any graph-facing
path, cuFlye should prove that it can construct that object vector under
upstream Flye ownership rules and still match the CPU oracle.

## In Scope

- Add an explicit `OverlapRange` object dry-run mode gated behind M4p success.
- Convert rehydrated typed records into `std::vector<OverlapRange>`.
- Keep `kmerMatches` unset unless a later milestone proves it is required.
- Canonicalize the object vector back to `overlap-range-v1` and compare it
  against CPU overlap records captured in memory.
- Write a compact object-rehydration audit JSON.
- Keep graph mutation on CPU output only.
- Include a negative proof where object-vector equivalence fails closed before
  graph mutation.
- Include a plain-language CUDA benefit assessment after proof.

## Out of Scope

- No default GPU mode.
- No worker output used by graph mutation.
- No end-to-end speed claim.
- No broad production dataset compatibility claim.
- No silent CPU fallback.

## Acceptance Gates

- Object rehydration dry-run mode is documented and disabled by default.
- The mode requires M4p typed rehydration success before running.
- Rehydrated `OverlapRange` vectors match CPU overlap vectors on the selected
  fixture matrix.
- Negative object-vector mismatch fails closed before graph mutation.
- Audit metadata records eligible, not-consumed, failed-closed, and mismatch
  details.
- Default CPU Flye fixture output remains unchanged.
- Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Do not introduce raw owning pointers in cuFlye seam code.
- Use upstream `OverlapRange` through `std::vector<OverlapRange>` and stack
  objects only.
- Keep conversion logic local to the seam until a later milestone explicitly
  enables graph mutation.

## Deliverables

- Object rehydration dry-run ABI/design documentation.
- Flye seam patch for `OverlapRange` object rehydration.
- DGX proof manifest for positive and negative object dry-runs.
- Roadmap, Task Card, golden index, and plain-language benefit assessment.
