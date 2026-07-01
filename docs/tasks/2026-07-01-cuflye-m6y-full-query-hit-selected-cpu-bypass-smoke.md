# Task Card: cuFlye M6y Full Query-Hit Selected CPU-Bypass Smoke

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6x's selected bypass dry-run ledger to the first guarded selected
CPU-bypass smoke.

M6x marks selected rows as bypassed in dry-run state, but it still primarily
proves accounting. M6y should prove the next boundary: selected full-query-hit
rows can be treated as CPU-selected-handoff-skipped, supplied by the
CUDA-derived bypass rows, while CPU-owned residual rows remain explicit and the
whole merged handoff is still blocked before graph mutation.

## In Scope

- Add an opt-in selected CPU-bypass smoke mode after M6x passes.
- Record selected CPU handoff rows as skipped in the smoke ledger.
- Record CUDA-derived selected bypass rows as the selected handoff supplier.
- Preserve CPU-owned residual rows and reasons from M6x.
- Record a final merged smoke ledger accounting for all CPU raw-overlap rows.
- Compare the merged smoke ledger against the CPU oracle row keys.
- Add a negative proof fault that makes a skipped selected CPU row leak back
  into the CPU-owned path or removes a bypassed selected row, and fail closed
  before graph mutation.
- Preserve default CPU Flye canonical artifacts.

## Out of Scope

- No default GPU mode.
- No unguarded graph mutation or graph simplification change.
- No broad full-query-hit replacement outside the selected proof set.
- No whole-Flye speedup claim.
- No GPU-computed chain-input filtering or edge identity claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Keep raw `GraphEdge*` pointers non-owning and scoped to the live
  `RepeatGraph`.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs.
- Keep skipped CPU-selected rows, CUDA-supplied selected rows, and CPU-owned
  residual rows as separate explicit ledgers.
- Fail closed if any row-key, rehydration, ledger, binding, object-vector
  smoke, substitution-guard, verified-substitution, bypass-plan, selected
  bypass dry-run, or selected CPU-bypass smoke gate fails.

## Deliverables

- Flye patch implementing the opt-in selected CPU-bypass smoke audit.
- ABI/design notes for the selected CPU-bypass smoke JSON.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [ ] M6p through M6x gates must pass before selected CPU-bypass smoke runs.
- [ ] Positive DGX proof records nonzero selected CPU handoff rows as skipped.
- [ ] Positive DGX proof records the same count as CUDA-derived selected
      bypass supplied rows.
- [ ] Positive DGX proof preserves explicit CPU-owned residual rows.
- [ ] Positive DGX proof accounts for all CPU raw-overlap rows in the final
      merged smoke ledger.
- [ ] Positive DGX proof proves selected CPU-bypass smoke output is not
      consumed by graph mutation.
- [ ] Negative proof fails closed before graph mutation when a skipped selected
      CPU row leaks back into the CPU-owned path or a selected bypass row is
      removed.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
