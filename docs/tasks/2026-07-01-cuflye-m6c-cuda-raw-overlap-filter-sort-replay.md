# Task Card: cuFlye M6c CUDA Raw-Overlap Filter/Sort Replay

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Consume the M6b read-to-graph input-boundary replay pack with a bounded CUDA
prototype that reproduces Flye's `chain_input` rows from packed raw overlaps.
This is the first GPU step at the M6 boundary, but it is deliberately scoped to
filter/sort replay, not full `quickSeqOverlaps` or minimizer discovery.

## In Scope

- Implement a CUDA prototype that reads `raw-overlaps.tsv` from an M6b pack.
- Filter rows where `passes_chain_input_filter == 1`.
- Sort or deterministically emit selected rows by per-query `read_begin`.
- Write `chain_input` rows in the M6b `oracle.chain-input.tsv` format.
- Diff CUDA output against `oracle.chain-input.tsv` for all selected queries.
- Record CUDA timing, CPU replay timing, counts, hashes, device metadata, and
  unsupported-shape behavior in a DGX golden manifest.

## Out of Scope

- No full `quickSeqOverlaps` implementation.
- No minimizer bucket generation.
- No Flye graph mutation.
- No default GPU mode.
- No whole-Flye speed claim.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Use existing cuFlye CUDA RAII wrappers for device memory, streams, and events.
- Keep host/device record structs explicit-width and trivially copyable.
- Fail closed on duplicate `read_begin`, empty selected inputs, or pack schema
  mismatch.
- Do not introduce raw CUDA resource calls outside approved RAII wrappers.

## Deliverables

- CUDA prototype source under `cuda/`.
- Host CLI or tool wrapper for M6b pack consumption.
- Validator/diff integration against `oracle.chain-input.tsv`.
- DGX golden manifest under `tests/golden/`.
- Roadmap update naming the next true minimizer-source pack step.

## Acceptance Gates

- [ ] M6b pack manifest validates before CUDA consumption.
- [ ] CUDA output canonical-diffs `match` against `oracle.chain-input.tsv`.
- [ ] CPU replay and CUDA replay produce the same record count and SHA-256.
- [ ] Timing report separates parse/pack, host-to-device, kernel, device-to-host,
      output write, and total wall time.
- [ ] C++/CUDA ownership scan shows no direct raw allocation/resource calls
      outside approved wrappers.
- [ ] Local and DGX syntax/style gates pass.

## Completion Notes

Pending implementation.
