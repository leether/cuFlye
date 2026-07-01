# Task Card: cuFlye M6z Full Query-Hit Selected CPU-Bypass Timing Attribution

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move from M6y's correctness-only selected CPU-bypass smoke to a bounded timing
and attribution gate.

M6y proves that selected full-query-hit CPU handoff rows can be skipped and
supplied by CUDA-derived rows without reaching graph mutation. M6z should
measure that seam: how much CPU handoff work is skipped, how much CUDA supplier
handoff costs, how much seam accounting costs, and how much residual work stays
CPU-owned.

## In Scope

- Add opt-in timing attribution around the M6y selected CPU-bypass smoke seam.
- Record selected skipped CPU row counts, CUDA-supplied row counts, residual
  CPU-owned row counts, and final merged ledger row counts.
- Record coarse wall-clock timings for CPU selected handoff accounting, CUDA
  supplier read/rehydration, final merge accounting, and total smoke seam time.
- Preserve M6y positive and negative fail-closed behavior.
- Compare default CPU canonical artifacts against the existing golden fixture.
- Store a compact DGX proof manifest under `tests/golden/`.

## Out of Scope

- No default GPU mode.
- No graph mutation consumption.
- No claim that full Flye is faster.
- No broad full-query-hit replacement beyond the selected proof set.
- No CUDA kernel rewrite in this card unless it is required to expose existing
  worker timing already produced by the worker.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Use RAII and existing helper patterns for timers and JSON emission.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep timing metadata separate from semantic pass/fail checks; timing noise
  must not hide correctness failures.
- Fail closed before graph mutation if any M6y correctness gate fails.

## Deliverables

- Flye patch extending the M6y smoke JSON with timing-attribution fields or
  writing a sibling timing JSON.
- Runner switches or manifest fields needed to enable the timing attribution.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [ ] M6y correctness gates still pass before timing attribution is trusted.
- [ ] Positive DGX proof records selected skipped CPU rows, CUDA-supplied rows,
      CPU-owned residual rows, and final merged rows.
- [ ] Positive DGX proof records nonzero, machine-readable timing fields for
      selected CPU skip accounting, CUDA supplier handoff, final merge
      accounting, and total selected CPU-bypass seam time.
- [ ] Positive DGX proof preserves `consumed=false` and
      `graph_mutation_consumed_worker_output=false`.
- [ ] Negative proof still fails closed before graph mutation on
      `leak-first-skipped-cpu-row`.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
