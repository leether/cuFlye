# Task Card: cuFlye M6r Chain-Input-Positive Full Query-Hit Selection

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move past M6q's zero-chain-input blocker by finding and proving a bounded
read-to-graph full-query-hit selection whose CUDA worker rows include at least
one `passes_chain_input_filter=1` row, while still refusing graph mutation.

## In Scope

- Add a small selector/profiler that scans read-to-graph source-pack
  `raw-overlaps.tsv` files for nonzero chain-input filter rows.
- Choose a deterministic small query-id set with:
  - nonzero raw-overlap rows;
  - nonzero `passes_chain_input_filter=1` rows;
  - bounded row volume suitable for DGX proof.
- Run the existing session-file CUDA full-query-hit worker on that selection.
- Require M6p rehydration and M6q shadow ledger to pass.
- Record chain-input-positive row counts and unresolved/resolved `edge_id`
  counts in a golden proof manifest.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No graph mutation from CUDA output.
- No claim of full-Flye speedup.
- No `GraphEdge*` binding or object-vector consumption yet.
- No unbounded source-pack scan committed to the repo.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Prefer a repo tool/script for selection rather than embedding exploratory
  logic in Flye C++.
- Keep selection deterministic and machine-checkable.
- Do not add owning raw memory or direct CUDA resource APIs.
- Keep all GPU output behind existing row-key, rehydration, and ledger gates.

## Deliverables

- Deterministic selector/profiler for chain-input-positive full-query-hit packs.
- DGX golden manifest for a chain-input-positive selection.
- Updated ROADMAP, golden index, and this Task Card.
- Next Task Card based on whether `edge_id` remains unresolved after the new
  selection.

## Acceptance Gates

- [ ] Selected proof has at least one `passes_chain_input_filter=1` row.
- [ ] CUDA full-query-hit worker row-key diff matches the CPU oracle.
- [ ] M6p rehydration passes for the selected query set.
- [ ] M6q shadow ledger passes and records nonzero
      `chain_input_filter_rows`.
- [ ] Graph mutation remains disabled and audited as not consumed.
- [ ] Negative proof still fails closed before graph mutation.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
