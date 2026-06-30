# Task Card: cuFlye M4m Overlap Worker Shadow Consumption

Status: completed

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

- [x] Define shadow mode and seam-summary shadow fields.
- [x] Capture CPU overlap ranges in a Flye-side shadow representation.
- [x] Parse validated worker output into the same shadow representation.
- [x] Compare worker shadow records against captured CPU overlap records.
- [x] Extend fixture runner controls and metadata.
- [x] Build patched Flye on DGX.
- [x] Prove default CPU fixture behavior remains unchanged.
- [x] Prove positive shadow mode validates, shadow-compares, and stops before
  graph mutation.
- [x] Prove negative shadow mismatch fails closed before graph mutation.
- [x] Record compact DGX proof and close this card.

## Merge Note

Implementation commit: `a93f3b01bc7971d85306bb430d9929d8bcfc2075`

DGX proof:
`tests/golden/cuflye-m4m-overlap-worker-shadow-consumption-dgx-aarch64.json`

Results:

- Default `toy-hifi` CPU run completed and all 9 canonical artifact hashes
  matched the M0 golden manifest.
- Positive `toy-raw` shadow run validated 9 worker TSV outputs, parsed them
  into Flye-side canonical shadow overlap records, matched every shadow record
  against CPU overlap ranges captured in memory, and still recorded
  `graph_mutation_consumed_worker_output=false`.
- The positive packed worker request used one CUDA launch per timed run and
  reported `6.847707 ms` backend mean total before write.
- Negative proof used a wrapper that ran the real worker, then removed one
  overlap record from both the first worker output TSV and its disk
  `oracle.overlaps.tsv`. File validation still passed, but shadow comparison
  caught `query_neg71` as `51` CPU records vs `50` worker records, marked
  `shadow_consumption_eligible=false`, and failed closed before graph mutation.
- DGX build, patch-series, syntax/style, and ownership gates passed.
