# Task Card: cuFlye M6a Read-To-Graph Overlap Input Boundary

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Define the next high-ROI CUDA boundary after M5y: the read-to-graph
overlap/minimizer input boundary that feeds read-alignment chain work. M5y shows
selected chain-DP bypass is scientifically safe but too small on toy-hifi to
move whole-Flye wall time, so M6a should first machine-check the earlier input
contract before adding a new kernel.

## In Scope

- Locate the Flye read-to-repeat-graph candidate/minimizer generation boundary
  that precedes `ReadAligner::chainReadAlignments`.
- Add an opt-in CPU oracle dump for the smallest stable input/output contract
  at that boundary.
- Canonicalize and diff the oracle across deterministic toy-hifi runs.
- Record per-stage timing around candidate/minimizer generation, chain DP,
  divergence filtering, worker request, and full Flye elapsed time.
- Create a golden manifest with paths, hashes, row counts, and allowed claims.

## Out of Scope

- No new CUDA kernel in M6a.
- No default GPU mode.
- No graph mutation from new boundary output.
- No real-dataset speed claim unless a bounded DGX sample is explicitly run and
  canonical artifacts match.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patching minimal and C++11-compatible.
- Keep oracle output deterministic and machine-checkable.
- Do not reformat upstream Flye code.
- Unsupported shapes must fail closed when the later CUDA backend is added.

## Deliverables

- Flye patch for an opt-in read-to-graph input-boundary oracle dump.
- Validator/canonicalizer or extension of existing tooling for the new oracle.
- DGX proof manifest under `tests/golden/`.
- Roadmap update naming the next CUDA implementation boundary.

## Acceptance Gates

- [ ] Two deterministic CPU oracle runs canonical-diff `match`.
- [ ] Oracle records include stable query ids, graph/read coordinates, ordering
      keys, and enough metadata to replay the boundary outside Flye.
- [ ] Timing separates candidate/minimizer generation from chain DP and
      divergence filtering.
- [ ] Full Flye canonical artifacts remain unchanged with the oracle enabled.
- [ ] Local and DGX syntax/style gates pass.

## Completion Notes

Pending implementation.
