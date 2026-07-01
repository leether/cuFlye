# Task Card: cuFlye M8d M8c Guarded Rehydration Shadow Consumption

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M8c selected worker/session seam one step closer to graph-facing
Flye code by adding an M8b/M8c-specific guarded rehydration or shadow
consumption proof.

M8c showed that warm Flye seam wall time remains faster than the matched
CPU quick-overlap baseline before graph mutation. M8d should measure whether
the graph-facing validation and rehydration layer preserves that bounded
advantage when using the same selected source pack and fail-closed contract.

## In Scope

- Reuse the exact M8b/M8c selected full-query-hit source pack and query ids.
- Reuse the `session-file-v0` worker lifecycle and existing Flye-side dry-run
  seam.
- Rehydrate or shadow-consume validated worker rows into the next graph-facing
  representation already used by M6p through M7b.
- Attribute worker session time, row-key diff time, rehydration/shadow ledger
  time, and total no-mutation seam time.
- Keep canonical Flye artifacts unchanged and keep negative proofs fail-closed
  before graph mutation.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation.
- No whole-Flye speed claim.
- No expansion beyond the M8b/M8c selected source-pack shape unless an
  unsupported shape is recorded as a fail-closed result.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing RAII wrappers and graph-facing handoff helpers.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep all worker-derived rows diff-gated before graph-facing conversion.
- Unsupported, incomplete, or mismatched worker output must fail closed before
  any graph mutation path.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- Timing attribution for worker session, validation diff, guarded
  rehydration/shadow consumption, and total no-mutation seam time.
- Task Card, ABI, and ROADMAP updates stating whether graph-facing validation
  overhead preserves or erases the M8c seam advantage.

## Acceptance Gates

- [ ] Reuses the exact M8b/M8c selected source pack and records the same
      canonical source-pack SHA.
- [ ] Worker row-key output matches CPU replay for the selected pack.
- [ ] Rehydrated or shadow-consumed graph-facing row counts match the selected
      CPU oracle shape.
- [ ] M8a chain-input oracle pack replay remains `match`.
- [ ] Canonical Flye artifacts remain unchanged.
- [ ] Timing separates worker session, validation diff,
      rehydration/shadow-consumption, and total no-mutation seam cost.
- [ ] Negative proof fails closed before graph mutation.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
