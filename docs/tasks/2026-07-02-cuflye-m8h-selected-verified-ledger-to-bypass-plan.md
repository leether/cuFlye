# Task Card: cuFlye M8h Selected Verified Ledger To Bypass Plan

Status: proposed

Created: 2026-07-02

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M8g's verified-substitution ledger comparison into an explicit
selected bypass-plan ledger for the same M8 selected source pack.

M8g proved that the `18` selected handoff rows match the CPU-selected handoff
by row key and deterministic order. M8h should classify those rows as
selected-bypass-eligible and explicitly account the remaining CPU-owned rows,
while still preventing any unguarded graph mutation or real CPU skip.

## In Scope

- Reuse the exact M8 selected source pack and query ids.
- Keep `session-file-v0`, row-key diff, raw-overlap rehydration, shadow
  ledger, graph-edge binding, object-vector smoke, substitution guard, and
  verified-substitution gates enabled.
- Add the selected bypass-plan ledger after M8g verified substitution passes.
- Record selected bypass-eligible rows, CPU-owned residual rows, and total
  selected source-pack raw-overlap accounting.
- Attribute bypass-plan timing separately from worker, verified substitution,
  handoff, and prior graph-facing gate costs.
- Add a negative proof fault that corrupts the bypass-plan ledger and fails
  closed before graph mutation.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation.
- No real selected CPU skip or graph update consumption.
- No whole-Flye speed claim.
- No expansion beyond the M8 selected source-pack shape.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing selected bypass-plan helpers and non-owning `GraphEdge*`
  conventions.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep every worker-derived bypass row behind row-key, rehydration,
  shadow-ledger, graph-edge binding, object-vector, handoff,
  verified-substitution, and bypass-plan gates.
- Unsupported or mismatched output must fail closed before graph mutation.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- ABI notes or ABI updates for the selected bypass-plan ledger on the M8 pack.
- Timing attribution showing whether bypass-plan accounting preserves the M8g
  warm no-mutation advantage.
- Task Card, ABI, and ROADMAP updates with allowed and forbidden claims.

## Acceptance Gates

- [ ] Reuses the exact M8 selected source pack and records the same canonical
      source-pack SHA.
- [ ] Worker row-key output, raw-overlap rehydration, shadow ledger,
      graph-edge binding, object-vector smoke, substitution guard, and
      verified substitution pass.
- [ ] Selected bypass-plan ledger rows match the verified-substitution ledger
      rows by row key and deterministic order.
- [ ] CPU-owned residual rows plus selected bypass rows account for the M8
      selected source-pack raw-overlap rows.
- [ ] M8a chain-input oracle pack replay remains `match`.
- [ ] Canonical Flye artifacts remain unchanged.
- [ ] Timing separates bypass-plan accounting from worker, verified
      substitution, handoff, and prior graph-facing gate costs.
- [ ] Negative bypass-plan proof fails closed before unguarded graph mutation.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
