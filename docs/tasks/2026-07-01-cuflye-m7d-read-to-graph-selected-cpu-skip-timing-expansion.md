# Task Card: cuFlye M7d Read-to-Graph Selected CPU-Skip Timing Expansion

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn M7c's correctness canary into an evidence-backed ROI decision by measuring
the selected CPU work that is actually skipped, the CUDA handoff cost, and the
graph-facing placeholder fill cost under larger selected sets.

M7c proves the selected CPU slice can be absent and supplied from CUDA output.
M7d should answer whether expanding that selected set is worth doing before
moving to a default GPU path.

## In Scope

- Add timing attribution around selected CPU-skip decisions in the Flye patch.
- Record per-query and aggregate skipped CPU chain/divergence timing when the
  M7c mode is disabled and equivalent selected queries run on CPU.
- Record M7c placeholder creation, CUDA rebuild, placeholder fill, and final
  parity timing.
- Expand the selected query set only when the shape remains supported by the
  existing CUDA full-query-hit worker and fail-closed gates.
- Produce a DGX manifest that compares skipped CPU time against CUDA worker and
  graph-facing substitution costs.
- Preserve canonical Flye artifacts and fail-closed negative proof.

## Out of Scope

- No default GPU mode.
- No broad read-to-graph replacement.
- No unsupported large-genome claim.
- No CUDA kernel rewrite beyond existing full-query-hit worker behavior unless
  timing proves it is the limiting factor.
- No silent CPU fallback after a selected CUDA failure.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patch code C++11-compatible and narrowly scoped.
- Keep raw `GraphEdge*` pointers non-owning and `RepeatGraph`-owned.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource lifecycle APIs in Flye patch code.
- Keep timing records deterministic enough for comparison, but exclude timing
  values from canonical correctness hashes.
- Fail closed on unsupported shapes or timing/proof accounting mismatches.

## Deliverables

- Flye patch or script updates for selected CPU-skip timing attribution.
- ABI/design notes for the timing expansion fields if new JSON fields are
  introduced.
- DGX positive and negative proof manifest under `tests/golden/`.
- Updated ROADMAP, golden index, and this Task Card.

## Acceptance Gates

- [ ] M7c selected CPU-skip canary still passes unchanged.
- [ ] Positive DGX proof records matched CPU-control timing for the same
      selected query set.
- [ ] Positive DGX proof records selected CPU skipped time, CUDA worker time,
      rebuild time, placeholder fill time, and total canary time.
- [ ] Positive DGX proof preserves canonical Flye artifacts against CPU golden.
- [ ] Negative proof fails closed before graph mutation commit.
- [ ] Summary states clearly whether the selected expanded path has a measured
      CUDA-side advantage or remains blocked by handoff/worker overhead.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
