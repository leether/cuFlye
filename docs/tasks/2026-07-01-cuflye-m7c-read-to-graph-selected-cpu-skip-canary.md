# Task Card: cuFlye M7c Read-to-Graph Selected CPU-Skip Canary

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M7b's post-hoc selected graph-consumption mutation canary to the
first tiny selected CPU-skip canary in the read-to-graph path.

M7b proves CUDA full-query-hit output can be rebuilt into Flye `goodChains` and
substituted into the selected graph-facing slice without changing canonical
artifacts. M7c should prove the selected query CPU read-to-graph work can be
skipped before that slice exists, then supplied from the CUDA handoff under the
same parity and fail-closed gates.

## In Scope

- Add an opt-in selected CPU-skip canary after M7b.
- Restrict the canary to the bounded toy-hifi selected query set.
- Record selected query IDs, skipped CPU query count, skipped CPU row count, and
  CUDA-supplied replacement chain count.
- Rebuild selected graph-facing chains from CUDA worker output without relying
  on the selected CPU slice as the source of truth.
- Preserve CPU-owned residual query work and account it separately.
- Compare canonical Flye artifacts against the CPU golden.
- Record positive proof that selected CPU read-to-graph work is skipped and
  CUDA output supplies the selected chains.
- Record negative proof that missing/corrupted selected CUDA output fails closed
  before graph mutation commit.

## Out of Scope

- No default GPU mode.
- No full read-to-graph replacement.
- No broad benchmark claim beyond the selected query canary.
- No graph simplification or repeat-resolution algorithm changes.
- No hidden fallback that recomputes selected CPU work after a CUDA failure.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Keep raw `GraphEdge*` pointers non-owning and `RepeatGraph`-owned.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep the selected CPU-skip accounting explicit in JSON and fail closed on any
  mismatch.
- Preserve deterministic output ordering or add a canonical sort/diff gate.

## Deliverables

- Flye patch implementing the opt-in selected CPU-skip canary.
- ABI/design notes for the selected CPU-skip canary JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [ ] M7b mutation canary passes before selected CPU skip is allowed.
- [ ] Positive DGX proof records nonzero selected CPU read-to-graph work skipped.
- [ ] Positive DGX proof records CUDA-supplied selected chains consumed by the
      graph-facing slice.
- [ ] Positive DGX proof preserves canonical Flye artifacts against CPU golden.
- [ ] Positive DGX proof records timing for skipped CPU work, CUDA handoff, and
      graph-facing substitution.
- [ ] Negative proof fails closed before graph mutation commit when selected
      CUDA output is missing, corrupted, duplicated, or reordered.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
