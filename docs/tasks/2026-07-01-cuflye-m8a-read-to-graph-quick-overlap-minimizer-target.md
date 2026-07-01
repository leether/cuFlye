# Task Card: cuFlye M8a Read-to-Graph Quick-Overlap Minimizer Target

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the performance target upstream from selected chain/divergence work to
read-to-graph quick-overlap/minimizer candidate discovery.

M7d showed the selected CPU chain/divergence boundary is too small to beat CPU:
`0.926453 ms` of selected CPU-control work versus `54.250612 ms` for hot CUDA
kernel plus graph-fill. Earlier M6a/M7d input-boundary timing shows
quick-overlap/minimizer work is orders of magnitude larger, so M8a should
define and prove the next CUDA target there.

## In Scope

- Add or reuse CPU-control profiling for read-to-graph quick-overlap/minimizer
  discovery at query and aggregate levels.
- Select a bounded set of queries where quick-overlap work dominates selected
  chain/divergence work.
- Define the next CUDA ABI boundary for minimizer/query-hit candidate discovery
  before chain-input filtering.
- Produce a CPU oracle and replayable fixture pack for that boundary.
- Add a DGX proof manifest that compares the candidate boundary timing against
  M7d and states the expected CUDA ROI.

## Out of Scope

- No default GPU mode.
- No graph mutation consumption in M8a.
- No claim that M8a itself accelerates Flye.
- No broad genome-scale benchmark without a bounded oracle and canonical gate.
- No silent CPU fallback in later CUDA paths.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep GPU-target ABI records deterministic or compare through a canonical
  sort/diff gate.
- Preserve canonical Flye artifacts for all profiling/source-pack modes.

## Deliverables

- Task-local design notes or ABI notes for the quick-overlap/minimizer target.
- CPU-control timing summary and selected query pack.
- DGX golden proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [ ] CPU-control quick-overlap/minimizer timing is recorded for a bounded query
      set and full toy-hifi control run.
- [ ] Selected M8a query set has materially larger CPU-control target time than
      the M7d selected chain/divergence boundary.
- [ ] A replayable CPU oracle pack is emitted for the chosen boundary.
- [ ] Canonical Flye artifacts match CPU golden when profiling/source-pack mode
      is enabled.
- [ ] Summary states what CUDA kernel/prototype should be implemented next and
      what speedup threshold would justify graph-facing integration.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
