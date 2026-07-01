# Task Card: cuFlye M6e Minimizer Source Replay Gap Closure

Status: proposed

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

- [ ] M6d source pack validates before replay.
- [ ] Replay emits deterministic canonical output for the selected query set.
- [ ] Replay either matches selected raw-overlap oracle rows or records a
      narrowed missing-semantics ledger with concrete mismatch examples.
- [ ] Full Flye canonical artifacts remain unchanged when any new capture
      options are enabled.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
