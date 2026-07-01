# Task Card: cuFlye M5u Read Alignment Compact Binary Flye Rehydration

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M5t `compact-binary-v0` payload from standalone proof tooling into a
Flye-side dry-run validation and rehydration seam.

The core question for this card is:

```text
Can Flye request compact-binary-v0 pre-divergence read-alignment chains from
the CUDA session, validate and rehydrate them inside the Flye seam, apply the
existing CPU divergence filter, and still preserve exact artifacts while
failing closed on payload corruption?
```

## In Scope

- Add Flye-side or patch-level parsing for `compact-binary-v0` in the existing
  read-alignment pre-divergence dry-run path.
- Validate magic, version, record size, fixture count, output count, payload
  length, and checksum before rehydration.
- Rehydrate binary records into the same internal pre-divergence chain shape
  currently used by the JSON/TSV proof path.
- Compare GPU-derived `goodChains` against CPU `goodChains` before graph
  mutation.
- Preserve M5t's standalone validator as an external audit tool.

## Out of Scope

- No default GPU mode.
- No broad `_readAlignments` replacement beyond an allowlisted dry-run seam.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib/base-alignment replacement.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and narrow.
- Use RAII containers and checked bounds before allocation or indexing.
- Do not introduce direct owning `new`, `delete`, `malloc`, `free`, or direct
  CUDA resource ownership outside approved RAII wrappers.
- Unsupported payloads, checksum mismatches, count mismatches, and truncated
  files must fail closed.

## Deliverables

- Flye-side compact binary validation/rehydration implementation.
- ABI note update if Flye-side constraints differ from standalone M5t.
- Positive DGX proof preserving exact artifacts.
- Negative DGX proof for corrupted binary payload before graph mutation.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with Flye-side timing and benefit assessment.

## Acceptance Gates

- [ ] Patch series applies and patched Flye builds on DGX.
- [ ] CUDA worker builds on DGX.
- [ ] Positive Flye dry-run validates and rehydrates `compact-binary-v0`.
- [ ] GPU-derived `goodChains` match CPU `goodChains`.
- [ ] Positive canonical Flye artifacts match CPU.
- [ ] Negative schema/count/checksum/truncation case fails closed before graph
      mutation.
- [ ] Local and DGX syntax/style gates pass.
- [ ] Ownership scan shows no new direct owning heap/resource APIs.

## Completion Notes

Pending implementation.
