# Task Card: cuFlye M6e Minimizer Source Replay Gap Closure

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Consume the M6d read-to-graph minimizer source pack with an external CPU replay
harness and close the semantics gap toward Flye `quickSeqOverlaps` before
writing a CUDA minimizer-source consumer.

## In Scope

- Parse the M6d source pack without depending on a live Flye process.
- Reconstruct query minimizer bucket hits into candidate match groups.
- Implement or explicitly model the `KmerMatch` grouping and chain DP semantics
  needed to reproduce selected raw-overlap oracle rows.
- Preserve deterministic row ordering and canonical diff output.
- Shrink the `missing-semantics` ledger to only the Flye operations not yet
  reproduced.
- Record exact mismatch examples when replay diverges from the oracle.

## Out of Scope

- No CUDA kernel in M6e.
- No Flye graph mutation.
- No default GPU mode.
- No whole-Flye speed claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Prefer a Python replay/proof harness first unless profiling proves C++ is
  required for this semantics-closure step.
- Keep any new C++ code C++11-compatible if it touches Flye patches.
- Use explicit-width integer fields at replay boundaries.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or CUDA resource
  APIs.

## Deliverables

- Source-pack replay tool under `tools/`.
- Diff/summary output that compares replayed raw-overlap rows with M6d oracle
  rows.
- Updated ABI notes describing which `quickSeqOverlaps` semantics are now
  reproduced.
- DGX golden manifest under `tests/golden/`.
- Roadmap update naming the first CUDA minimizer-source replay consumer if the
  CPU replay gate becomes tight enough.

## Acceptance Gates

- [x] M6d source pack validates before replay.
- [x] Replay emits deterministic canonical output for the selected query set.
- [x] Replay either matches selected raw-overlap oracle rows or records a
      narrowed missing-semantics ledger with concrete mismatch examples.
- [x] Full Flye canonical artifacts remain unchanged when any new capture
      options are enabled.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Accepted with DGX proof:

- Golden manifest:
  `tests/golden/cuflye-m6e-minimizer-source-replay-gap-closure-dgx-aarch64.json`
- Proof root: `/tmp/cuflye-m6e-proof-20260701T063514Z`
- Host: `edgexpert-45d2`, `aarch64`
- Fixture: `toy-hifi`
- Source-pack canonical SHA-256:
  `4b38ac5dfc40e6e4ac7308b24c1286494241954a872eac8de33a25f5ccff5e87`
- Replay status: `gap-ledger`
- Replay SHA-256:
  `d6bcac19ab5fdd3ba2cd37f2c677a744104c093ae6e508c0225ebf9eec5d626b`
- Replay determinism: source-pack A/B replay diff `match`
- Replay totals: `7640` source match records, `33` ext groups, `36` oracle
  raw-overlap rows, `34` replay raw-overlap rows, `14` exact matched rows, and
  `26` geometry matched rows.
- Flye artifact diffs from baseline to both source-pack capture runs: `match`

Plain-language benefit:

M6e still does not make Flye faster, and it does not yet prove a CUDA
replacement. It does something more useful at this point: it turns the vague
`quickSeqOverlaps` gap into a concrete failure ledger. The replay can rebuild
the match grouping, DP, `overlapTest`, and primary-overlap filtering from M6d
data, but it only exactly matches `14/36` raw-overlap rows and geometrically
matches `26/36`. The main gap is now clear: M6d captured query minimizer hits,
while Flye's CPU path iterates all query k-mers through `IterKmers`. M6f should
capture or regenerate that full query-hit stream before another CUDA kernel is
worth writing.
