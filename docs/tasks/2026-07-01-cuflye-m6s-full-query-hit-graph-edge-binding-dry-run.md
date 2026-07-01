# Task Card: cuFlye M6s Full Query-Hit Graph Edge Binding Dry-Run

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Use the M6r worker output, which now carries nonzero
`passes_chain_input_filter` and resolved `edge_id` values, to prove a
no-mutation Flye-side graph-edge binding audit before any real read-to-graph
graph mutation is allowed.

M6r removed the metadata propagation blocker, but the ledger still reports zero
graph-edge consumption candidates because no `GraphEdge*` object binding has
been attempted. M6s should answer the next narrow question: can every
chain-input-positive CUDA raw-overlap row be deterministically matched back to a
live Flye graph edge object without changing graph state?

## In Scope

- Add a no-mutation graph-edge binding audit mode after M6q shadow ledger
  passes.
- For rehydrated rows with `passes_chain_input_filter=1`, resolve `edge_id`
  against the live Flye graph edge collection.
- Record deterministic per-row/per-query binding counts:
  - chain-input-positive rows inspected;
  - rows with resolved nonzero `edge_id`;
  - rows whose `edge_id` maps to a live `GraphEdge*`;
  - rows rejected because the live graph edge is missing or ambiguous.
- Fail closed if any required row cannot bind cleanly.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No graph mutation from CUDA output.
- No replacement of Flye's CPU read-to-graph path.
- No default GPU mode.
- No whole-Flye speedup claim.
- No attempt to compute chain-input filtering or edge identity on GPU.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs.
- Keep all graph-edge pointer handling non-owning and audit-only.
- Every future-consumption row must remain behind row-key, rehydration, ledger,
  and graph-edge binding gates.

## Deliverables

- Flye patch implementing the opt-in graph-edge binding dry-run audit.
- ABI/design notes for the graph-edge binding audit JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [ ] M6p rehydration and M6q shadow ledger must pass before binding runs.
- [ ] Positive DGX proof records nonzero chain-input-positive rows.
- [ ] Positive DGX proof records nonzero live graph-edge bindings.
- [ ] Binding audit proves graph mutation remains disabled and not consumed.
- [ ] Negative proof fails closed before graph mutation when a binding row is
      intentionally corrupted or dropped.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
