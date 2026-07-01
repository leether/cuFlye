# Task Card: cuFlye M8f Selected Object-Vector Handoff Contract

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M8e object-vector smoke result into a tighter no-mutation graph-facing
handoff contract for the same M8 selected source pack.

M8e proved that `18` selected rows can bind to live `GraphEdge` objects and be
accounted as object-vector smoke rows while preserving the selected CUDA
advantage. M8f should define the exact handoff record shape that a later
mutation canary would consume, without enabling unguarded graph mutation.

## In Scope

- Reuse the exact M8 selected source pack and query ids.
- Keep `session-file-v0`, row-key diff, raw-overlap rehydration, shadow ledger,
  graph-edge binding, and object-vector smoke gates enabled.
- Define a compact graph-facing handoff summary for the selected object-vector
  rows, including query id, edge id, read id, source order, and deterministic
  ordering.
- Add timing attribution for the handoff contract build and validation.
- Add a negative proof fault that corrupts the handoff accounting and fails
  closed before graph mutation.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation.
- No object-vector substitution into Flye graph update logic.
- No whole-Flye speed claim.
- No expansion beyond the M8 selected source-pack shape.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Reuse existing graph-facing object helpers and non-owning `GraphEdge*`
  conventions.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs outside approved low-level RAII wrappers.
- Keep every worker-derived handoff record behind row-key, rehydration,
  shadow-ledger, graph-edge binding, object-vector, and handoff diff gates.
- Unsupported or mismatched output must fail closed before graph mutation.

## Deliverables

- DGX proof manifest under `tests/golden/`.
- ABI notes for the selected object-vector handoff contract.
- Timing attribution showing whether the handoff contract preserves the M8e
  warm no-mutation advantage.
- Task Card, ABI, and ROADMAP updates with allowed and forbidden claims.

## Acceptance Gates

- [ ] Reuses the exact M8 selected source pack and records the same canonical
      source-pack SHA.
- [ ] Worker row-key output, raw-overlap rehydration, shadow ledger,
      graph-edge binding, and object-vector smoke pass.
- [ ] Handoff rows equal M8e selected object-vector rows and remain
      deterministically ordered.
- [ ] M8a chain-input oracle pack replay remains `match`.
- [ ] Canonical Flye artifacts remain unchanged.
- [ ] Timing separates handoff build/validation from worker and prior
      graph-facing gate costs.
- [ ] Negative handoff proof fails closed before unguarded graph mutation.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
