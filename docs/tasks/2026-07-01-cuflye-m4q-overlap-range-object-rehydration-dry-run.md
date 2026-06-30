# Task Card: cuFlye M4q OverlapRange Object Rehydration Dry Run

Status: completed

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

- [x] Object rehydration dry-run mode is documented and disabled by default.
- [x] The mode requires M4p typed rehydration success before running.
- [x] Rehydrated `OverlapRange` vectors match CPU overlap vectors on the selected
  fixture matrix.
- [x] Negative object-vector mismatch fails closed before graph mutation.
- [x] Audit metadata records eligible, not-consumed, failed-closed, and mismatch
  details.
- [x] Default CPU Flye fixture output remains unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Do not introduce raw owning pointers in cuFlye seam code.
- Use upstream `OverlapRange` through `std::vector<OverlapRange>` and stack
  objects only.
- Keep conversion logic local to the seam until a later milestone explicitly
  enables graph mutation.

## Deliverables

- [x] Object rehydration dry-run ABI/design documentation.
- [x] Flye seam patch for `OverlapRange` object rehydration.
- [x] DGX proof manifest for positive and negative object dry-runs.
- [x] Roadmap, Task Card, golden index, and plain-language benefit assessment.

## Completion Notes

Implemented in commit `beb6ad6fe00fd6843f9c4c3d2f9f71939b164761`.

M4q adds:

- `CUFLYE_OVERLAP_OBJECT_REHYDRATION_MODE=overlap-range-object-v0`
- `CUFLYE_OVERLAP_OBJECT_REHYDRATION_PROOF_FAULT=drop-first-overlap-range`
- `worker-object-rehydration.json` with schema
  `cuflye-overlap-range-object-rehydration-dry-run-v0`

The DGX positive proof used the M4n 12-fixture heterogeneous matrix with
validation, shadow comparison, graph guard, and M4p typed rehydration enabled.
Object rehydration reported `status=passed`, `state=not-consumed`,
`eligible=true`, and `graph_mutation_consumed_worker_output=false`.

The negative proof used the same matrix plus
`drop-first-overlap-range`. Validation, shadow comparison, graph guard, and
M4p typed rehydration still passed, while object-vector comparison recorded 12
mismatching fixtures and failed closed with
`status=object-rehydration-failed-before-graph-mutation`.

The default CPU `toy-hifi` fixture remained unchanged against the M0 golden
oracle. The proof manifest is
`tests/golden/cuflye-m4q-overlap-range-object-rehydration-dry-run-dgx-aarch64.json`.

## Plain-Language Benefit

M4q still does not make Flye faster. The benefit is safety: cuFlye can now turn
validated CUDA overlap worker output into actual Flye `OverlapRange` objects
and prove those objects still match the CPU overlap vector before graph
construction is allowed to consume anything.
