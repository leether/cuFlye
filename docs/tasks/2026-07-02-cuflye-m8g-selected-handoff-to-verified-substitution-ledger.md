# Task Card: cuFlye M8g Selected Handoff To Verified Substitution Ledger

Status: proposed

Created: 2026-07-02

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M8 selected handoff contract one step closer to a guarded replacement
decision by comparing it with the verified substitution or bypass-plan ledger
shape that later graph-facing milestones expect.

M8f proved that `18` selected object-vector rows can become a deterministic
no-mutation handoff contract while preserving the selected CUDA advantage.
M8g should prove whether that contract can be checked against a later
verified-substitution ledger for the same M8 selected source pack, still
without enabling unguarded graph mutation.

## In Scope

- Reuse the exact M8 selected source pack and query ids.
- Keep `session-file-v0`, row-key diff, raw-overlap rehydration, shadow
  ledger, graph-edge binding, object-vector smoke, and substitution-guard gates
  enabled.
- Add a selected verified-substitution ledger comparison after the M8f handoff
  contract passes.
- Record row-key/order parity, selected ledger rows, and CPU-owned residual
  accounting if the later bypass-plan shape is needed.
- Attribute ledger comparison timing separately from worker, prior
  graph-facing gates, and no-mutation seam total.
- Add a negative proof fault that corrupts the verified substitution ledger and
  fails closed before graph mutation.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation.
- No actual object-vector substitution into Flye graph update logic.
- No selected CPU skip unless the ledger is proven first.
- No whole-Flye speed claim.
- No expansion beyond the M8 selected source-pack shape.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing graph-facing object helpers, verified-substitution helpers,
  and non-owning `GraphEdge*` conventions.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep every worker-derived ledger behind row-key, rehydration, shadow-ledger,
  graph-edge binding, object-vector, handoff, and verified-ledger gates.
- Unsupported or mismatched output must fail closed before graph mutation.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- ABI notes or ABI updates for the selected handoff to verified-ledger
  comparison.
- Timing attribution showing whether the verified-ledger comparison preserves
  the M8f warm no-mutation advantage.
- Task Card, ABI, and ROADMAP updates with allowed and forbidden claims.

## Acceptance Gates

- [ ] Reuses the exact M8 selected source pack and records the same canonical
      source-pack SHA.
- [ ] Worker row-key output, raw-overlap rehydration, shadow ledger,
      graph-edge binding, object-vector smoke, and substitution guard pass.
- [ ] Verified substitution or bypass-plan ledger rows match the M8f handoff
      rows by row key and deterministic order.
- [ ] M8a chain-input oracle pack replay remains `match`.
- [ ] Canonical Flye artifacts remain unchanged.
- [ ] Timing separates verified-ledger comparison from worker, handoff, and
      prior graph-facing gate costs.
- [ ] Negative verified-ledger proof fails closed before unguarded graph
      mutation.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
