# Task Card: cuFlye M6h CUDA Full Query-Hit Replay Consumer

Status: completed

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

- [x] M6f/M6g source pack validates before CUDA replay.
- [x] M6g CPU replay row-key oracle remains `36/36`.
- [x] CUDA replay validates and canonical row-key diffs `match` against the
      M6g CPU oracle for the selected pack.
- [x] CUDA replay A/B is deterministic.
- [x] Unsupported shapes fail closed without silent CPU fallback.
- [x] DGX proof records timing and makes no speed claim because CUDA is slower
      than CPU on this tiny selected pack.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented the first standalone CUDA consumer for the selected full-query-hit
source pack:

- `cuda/cuflye_cuda_full_query_hit_replay.cu`
- `scripts/build_cuda_full_query_hit_replay.sh`
- `tools/diff_read_to_graph_raw_overlap_row_keys.py`
- `docs/abi/cuda-full-query-hit-replay-v0.md`

The CUDA consumer parses the M6f/M6g source pack, host-normalizes Flye
`std::sort`-sensitive input order, runs chain DP/backtracking/primary filtering
on device with one CUDA block per active ext group, and emits raw-overlap rows.
The proof compares CPU and CUDA by canonical M6g row key: read/edge coordinates
and score.

DGX proof:

```text
proof_root=/tmp/cuflye-m6h-proof-20260701T070728Z
golden=tests/golden/cuflye-m6h-cuda-full-query-hit-replay-consumer-dgx-aarch64.json
source_pack_canonical_sha256=16f4ced6054e7e4491071a1a7512760424a1e4fbc157e532ddb7c9e2aac53e5f
cpu_replay_raw_overlaps_sha256=2e1201a2e768ed682afc6b0feb90d50aeeea8ad66597861c6c61ba062a34e420
cpu_row_key_exact_match=true
cuda_status=ok
cuda_output_records=36
cuda_source_match_records=7747
cuda_source_ext_groups=33
cuda_active_ext_groups=22
cpu_vs_cuda_row_key_diff=match
cpu_vs_cuda_ordered_match=false
cuda_ab_row_key_diff=match
cuda_ab_ordered_match=true
unsupported_exit_status=2
unsupported_json_status=error
unsupported_error="required bytes exceed memory budget"
cpu_replay_wall_seconds=0.11
cuda_replay_wall_seconds=0.48
cuda_kernel_ms=53.170850
```

Plain-language benefit:

```text
M6h moves the full query-hit replay boundary onto the GPU for the first time:
CUDA now generates the same canonical row-key set as the M6g CPU replay for all
36 selected raw overlaps. It is still not faster. The current prototype uses
one CUDA block serially per active edge group, so on the tiny pack CPU replay is
about 0.11s while the cold CUDA process is about 0.48s. The benefit is
correctness migration and a real CUDA target for M6i parallelization, not speed.
```

Next highest-ROI task:

```text
M6i: parallelize the full-query-hit replay benchmark while preserving canonical
row-key parity, then decide whether the next blocker is kernel parallelism or
worker/session overhead.
```
