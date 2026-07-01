# Task Card: cuFlye M7b Full Query-Hit Selected Graph-Consumption Mutation Canary

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M7a's not-consumed graph-facing parity gate to the first tiny,
guarded selected graph-consumption mutation canary.

M7a proves the final merged handoff can be represented as live graph-facing
rows. M7b should allow that selected handoff to reach the actual graph mutation
path only on a bounded opt-in toy fixture, then prove canonical Flye artifacts
match the CPU golden.

## In Scope

- Add an opt-in selected graph-consumption mutation canary after M7a passes.
- Restrict the canary to the bounded selected query set and explicit proof
  fixture.
- Preserve CPU-owned residual rows and selected CUDA-supplied rows as separate
  audit ledgers.
- Compare canonical Flye artifacts against the CPU golden.
- Record positive proof that graph mutation can consume the selected handoff
  without changing canonical artifacts.
- Record negative proof that fails closed before committing graph mutation when
  the selected handoff is corrupted.

## Out of Scope

- No default GPU mode.
- No broad full-query-hit replacement.
- No whole-Flye speedup claim unless artifact parity and timing both pass.
- No graph simplification or repeat-resolution algorithm changes.
- No hidden fallback.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Keep raw `GraphEdge*` pointers non-owning and `RepeatGraph`-owned.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep mutation canary state explicit in JSON and fail closed on any mismatch.

## Deliverables

- Flye patch implementing the opt-in mutation canary.
- ABI/design notes for the mutation canary JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [ ] M7a graph-facing parity passes before mutation canary is allowed.
- [ ] Positive DGX proof reaches the selected graph mutation path with the
      merged CUDA-supplied plus CPU-owned handoff.
- [ ] Positive DGX proof preserves canonical Flye artifacts against CPU golden.
- [ ] Positive DGX proof records timing for canary handoff and graph mutation.
- [ ] Negative proof fails closed before graph mutation commit when selected
      handoff rows are corrupted, missing, duplicated, or reordered.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
