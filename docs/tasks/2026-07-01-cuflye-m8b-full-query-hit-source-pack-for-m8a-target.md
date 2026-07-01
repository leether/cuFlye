# Task Card: cuFlye M8b Full-Query-Hit Source Pack for M8a Target

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Run the existing full-query-hit source-pack and warm CUDA replay path on the
M8a selected quick-overlap target, so any CUDA speed claim is measured against
the same Flye CPU quick-overlap baseline.

M8a selected 16 replayable query ids with `79.294112 ms` of Flye CPU
quick-overlap work. M8b should decide whether the M6j-style warm CUDA
full-query-hit session can beat that exact target.

## In Scope

- Capture a full-query-hit source pack for the M8a selected query ids.
- Validate source-pack completeness and run CPU full-query-hit replay.
- Run the existing CUDA full-query-hit replay warm-session path against the
  same selected pack.
- Compare CPU replay, CUDA replay, M8a M6b chain-input pack, and Flye
  canonical artifacts.
- Record whether hot CUDA request time is below the selected Flye CPU
  quick-overlap baseline.

## Out of Scope

- No Flye graph mutation.
- No default GPU mode.
- No whole-Flye speed claim.
- No unsupported shape expansion unless the selected M8a pack fails closed and
  a narrower supported pack is explicitly recorded.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing CUDA full-query-hit replay worker/session code and RAII
  wrappers.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep row-key and chain-input comparisons deterministic through canonical
  diff gates.
- Unsupported source-pack shapes must fail closed without silent CPU fallback.

## Deliverables

- DGX full-query-hit source-pack proof for the M8a selected query ids.
- CPU replay and CUDA warm-session timing summary.
- Golden proof manifest under `tests/golden/`.
- ROADMAP and Task Card updates stating whether M8b proves a bounded hot-path
  CUDA advantage against the matched Flye quick-overlap baseline.

## Acceptance Gates

- [ ] Full-query-hit source pack captures exactly the M8a selected query ids or
      records a fail-closed narrowed target.
- [ ] CPU source-pack replay reaches accepted row-key parity for the selected
      pack.
- [ ] CUDA replay row-key diff matches CPU replay.
- [ ] M8a chain-input oracle pack replay remains `match`.
- [ ] Flye canonical artifacts match CPU golden with capture enabled.
- [ ] Hot CUDA request time is compared against
      `selected_quick_overlap_ms=79.294112`; any speed claim is limited to this
      bounded hot path.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
