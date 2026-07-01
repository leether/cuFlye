# Task Card: cuFlye M8e Selected Graph-Facing Binding Object Proof

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M8d shadow-ledger accounting to the next guarded graph-facing proof
for the same M8b/M8c selected source pack.

M8d showed that row-key diff, raw-overlap rehydration, and shadow ledger
validation add only about `0.210 ms` on warm requests and preserve a bounded
selected CUDA advantage. M8e should test whether the next binding or
object-vector gate can also remain below the matched M8a CPU quick-overlap
baseline while still preventing unguarded graph mutation.

## In Scope

- Reuse the exact M8b/M8c/M8d selected source pack and query ids.
- Reuse `session-file-v0`, raw-overlap rehydration, and shadow ledger gates.
- Enable the next already-defined graph-facing binding or object-vector proof
  path for the selected rows.
- Attribute worker session, row-key diff, rehydration, shadow ledger, next
  graph-facing gate, and total no-mutation seam time.
- Preserve canonical Flye artifacts and fail closed on proof faults before
  unguarded graph mutation.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation.
- No whole-Flye speed claim.
- No expansion beyond the M8 selected source-pack shape.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing graph-facing binding/object helpers and RAII wrappers.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep every worker-derived object behind row-key, rehydration, shadow-ledger,
  and graph-facing diff gates.
- Unsupported or mismatched output must fail closed before unguarded graph
  mutation.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- Timing attribution showing whether the next graph-facing gate preserves the
  M8d warm no-mutation advantage.
- Task Card, ABI, and ROADMAP updates with allowed and forbidden claims.

## Acceptance Gates

- [ ] Reuses the exact M8 selected source pack and records the same canonical
      source-pack SHA.
- [ ] Worker row-key output, raw-overlap rehydration, and shadow ledger pass.
- [ ] The selected graph-facing binding or object-vector proof passes in
      no-unguarded-mutation mode.
- [ ] M8a chain-input oracle pack replay remains `match`.
- [ ] Canonical Flye artifacts remain unchanged.
- [ ] Timing separates the next graph-facing gate from worker and validation
      costs.
- [ ] Negative proof fails closed before unguarded graph mutation.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
