# Task Card: cuFlye M6c CUDA Raw-Overlap Filter/Sort Replay

Status: accepted

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

- [x] M6b pack manifest validates before CUDA consumption.
- [x] CUDA output canonical-diffs `match` against `oracle.chain-input.tsv`.
- [x] CPU replay and CUDA replay produce the same record count and SHA-256.
- [x] Timing report separates parse/pack, host-to-device, kernel, device-to-host,
      output write, and total wall time.
- [x] C++/CUDA ownership scan shows no direct raw allocation/resource calls
      outside approved wrappers.
- [x] Local and DGX syntax/style gates pass.

## Completion Notes

Implemented with:

- `cuda/cuflye_cuda_input_boundary_replay.cu`
- `scripts/build_cuda_input_boundary_replay.sh`
- `tools/diff_read_to_graph_chain_inputs.py`

DGX proof root:

```text
/tmp/cuflye-m6c-proof-20260701T060817Z
```

Proof summary:

- Built with `/usr/local/cuda/bin/nvcc`, arch `sm_121`.
- Input pack:
  `/tmp/cuflye-m6b-proof-20260701T055901Z/out/m6b-rerun/pack-a`.
- CUDA consumed 36 raw-overlap records and emitted 8 `chain_input` rows.
- `oracle.chain-input.tsv` vs CUDA output canonical diff: `match`.
- CPU replay vs CUDA output canonical diff: `match`.
- Shared output SHA-256:
  `5ab7b7fe51af9e90807e2d9be4824bd9216c732877cebc5eca58cb606b1c9f20`.
- CUDA timing:
  parse `0.156897 ms`, host pack `0.000224 ms`,
  host-to-device `0.069104 ms`, kernel `0.107616 ms`,
  device-to-host `0.019329 ms`, write output `0.091072 ms`,
  total `300.936895 ms`.

Plain-language benefit:

M6c is the first CUDA execution at this boundary, but it is not a speed win.
The useful result is correctness: CUDA can consume the new pack and emit exactly
the same `chain_input` rows as CPU replay. The pack is tiny, so process/CUDA
context startup dominates total time. Next ROI is not optimizing this toy
kernel; it is building a richer minimizer-source pack so CUDA can replace more
of `quickSeqOverlaps`.
