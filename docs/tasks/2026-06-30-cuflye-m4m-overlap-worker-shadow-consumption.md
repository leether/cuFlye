# Task Card: cuFlye M4m Overlap Worker Shadow Consumption

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Read validated CUDA overlap worker output back into a Flye-side shadow overlap
range structure and compare it against the CPU overlap ranges that Flye is about
to use, without changing graph mutation behavior.

## Background

M4l proves the seam can validate every worker TSV as `overlap-range-v1`, diff it
against the captured CPU oracle, mark passing output consumption-eligible, and
fail closed on mismatch. The next integration risk is not file validation; it is
whether Flye can parse validated worker output into the same in-memory overlap
shape used by downstream code.

M4m should add a shadow consumption path: after validation passes, parse worker
output into Flye-side overlap records, compare the shadow records to the CPU
records already held by the current call, write a compact summary, and still
return or stop without feeding GPU output into graph mutation.

## In Scope

- Define a shadow-consumption proof mode for validated worker outputs.
- Parse worker `overlap-range-v1` TSV records into Flye-side overlap range
  records or an equivalent shadow representation.
- Compare the parsed shadow records against the CPU overlap ranges for the same
  captured query.
- Record per-query shadow comparison summaries.
- Fail closed when validation has not passed or the shadow comparison differs.
- Preserve default CPU behavior and keep graph mutation on CPU output.

## Out of Scope

- No GPU output used by graph mutation.
- No default GPU mode.
- No arbitrary dataset claim.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No silent CPU fallback.

## Acceptance Gates

- Default CPU Flye fixture output remains unchanged.
- Explicit worker proof mode requires validation status `passed` before shadow
  parsing is attempted.
- Shadow parsed overlap records match the CPU overlap ranges for every selected
  query.
- A shadow mismatch fails closed before graph mutation and records
  `graph_mutation_consumed_worker_output=false`.
- DGX proof records one passing shadow batch and one negative shadow mismatch
  case.
- Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Use standard containers and stack objects for shadow state.
- Do not add raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Do not silently skip shadow parsing when the mode is explicitly selected.

## Deliverables

- ABI/seam doc update for shadow consumption proof mode.
- Flye `2.9.6` patch-series entry after `0012`.
- Runner controls and metadata for shadow proof mode.
- DGX proof with positive and negative shadow cases.
- This Task Card completed after proof.

## Execution Checklist

- [ ] Define shadow mode and seam-summary shadow fields.
- [ ] Capture CPU overlap ranges in a Flye-side shadow representation.
- [ ] Parse validated worker output into the same shadow representation.
- [ ] Compare worker shadow records against captured CPU overlap records.
- [ ] Extend fixture runner controls and metadata.
- [ ] Build patched Flye on DGX.
- [ ] Prove default CPU fixture behavior remains unchanged.
- [ ] Prove positive shadow mode validates, shadow-compares, and stops before
  graph mutation.
- [ ] Prove negative shadow mismatch fails closed before graph mutation.
- [ ] Record compact DGX proof and close this card.
