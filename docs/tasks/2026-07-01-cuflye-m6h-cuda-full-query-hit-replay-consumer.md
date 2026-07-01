# Task Card: cuFlye M6h CUDA Full Query-Hit Replay Consumer

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M6g row-key-compatible full-query-hit replay boundary onto CUDA for a
bounded selected source pack, without changing Flye graph behavior or claiming
whole-Flye acceleration.

## In Scope

- Consume validated M6f/M6g `full-query-hits.tsv` source packs for selected
  read-to-graph queries.
- Build a standalone CUDA replay consumer that emits raw-overlap row keys:
  read coordinates, edge sequence coordinates, lengths, and score.
- Keep libstdc++ `std::sort` equal-key behavior modeled or pre-normalized before
  GPU DP so the CUDA output target is deterministic.
- Compare CUDA output against the M6g CPU replay row-key oracle.
- Record bounded DGX timing as diagnostic data only.

## Out of Scope

- No default GPU mode.
- No Flye graph mutation.
- No source-pack recapture unless M6h proves the current pack is insufficient.
- No claim that `seq_divergence`, `edge_id`, or chain-input filter fields are
  fully recomputed on GPU.
- No whole-Flye speed claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Use existing CUDA RAII wrappers for reusable device buffers, streams, and
  events.
- Do not introduce direct owning `new`, `delete`, `malloc`, `free`, or direct
  CUDA resource APIs outside approved low-level RAII wrappers.
- Use explicit-width integer fields at file, ABI, and CUDA kernel boundaries.
- Unsupported source-pack shapes must fail closed with metadata naming the
  reason and input shape.

## Deliverables

- CUDA full-query-hit replay prototype or worker under the existing `cuda/`
  layout.
- CPU-vs-CUDA row-key diff tool or extension to an existing replay diff.
- DGX golden manifest under `tests/golden/`.
- Roadmap update that states whether M6h is correctness-only or shows a bounded
  subproblem speedup.

## Acceptance Gates

- [ ] M6f/M6g source pack validates before CUDA replay.
- [ ] M6g CPU replay row-key oracle remains `36/36`.
- [ ] CUDA replay validates and row-key diffs `match` against the M6g CPU
      oracle for the selected pack.
- [ ] CUDA replay A/B is deterministic.
- [ ] Unsupported shapes fail closed without silent CPU fallback.
- [ ] DGX proof records timing but makes no speed claim unless CUDA beats a
      matched CPU baseline for the same bounded work.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
