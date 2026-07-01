# Task Card: cuFlye M6a Read-To-Graph Overlap Input Boundary

Status: accepted

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

- [x] Two deterministic CPU oracle runs canonical-diff `match`.
- [x] Oracle records include stable query ids, graph/read coordinates, ordering
      keys, and enough metadata to replay the boundary outside Flye.
- [x] Timing separates candidate/minimizer generation from chain DP and
      divergence filtering.
- [x] Full Flye canonical artifacts remain unchanged with the oracle enabled.
- [x] Local and DGX syntax/style gates pass.

## Completion Notes

Implemented in `0039-cuflye-read-to-graph-input-boundary-oracle.patch`.

DGX proof root:

```text
/tmp/cuflye-m6a-proof-20260701T054514Z
```

Proof summary:

- Flye 2.9.6 patched through `0039` built on DGX Linux/aarch64.
- Two toy-hifi oracle runs produced the same canonical input-boundary hash:
  `674a6bc7ffb42a058859254ac78aa83b374c578a18d17a339bd2e6a669d6d628`.
- Oracle records: 3,577 query summaries, 5,092 raw overlap records, 3,814
  chain-input records.
- Canonical timing is intentionally excluded from the hash, but validation
  records separate quick overlap discovery, input filter/sort, chain DP, and
  divergence filtering.
- Baseline vs oracle A and baseline vs oracle B full Flye canonical artifact
  diffs both returned `match`.

Plain-language benefit:

M6a shows the earlier read-to-graph overlap discovery boundary is measurable,
deterministic, and graph-safe as an oracle. On this toy proof, quick overlap
discovery is about 1.55-1.59 seconds, divergence filtering is about 0.17
seconds, and chain DP is under 1 ms. That means the next CUDA ROI should move
toward candidate/minimizer discovery rather than further optimizing the already
tiny chain-DP slice.
