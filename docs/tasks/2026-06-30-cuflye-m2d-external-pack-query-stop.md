# Task Card: cuFlye M2d External Pack Query Stop

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Prove that Flye can invoke the external CUDA packed backend on one real
`pack-dump-v0` query, parse its candidate-record-v1 output, append matching
records at the Flye candidate boundary, and then fail closed before downstream
graph logic.

The core question this card must answer is:

```text
Can Flye's CUDA adapter consume real CUDA candidate records at the exact
candidate-generation seam?
```

## Background

M2b captured real Flye query/index data into a replayable packed bundle. M2c
proved the standalone CUDA read-window backend can consume that bundle and emit
the same candidate list as the packed CPU oracle.

M2d connects those two pieces: Flye should call the CUDA backend through
`external-packed-v0`, parse the CUDA TSV, append the query's records, and then
stop intentionally so no unproven downstream assembly path runs.

## In Scope

- Add a fail-closed stop mode for `external-packed-v0`.
- Surface the stop mode through `scripts/run_flye_fixture.sh`.
- Record the mode in run metadata.
- Build patched Flye on DGX.
- Build the CUDA read-window backend on DGX.
- Run Flye against the M2b real pack in stop-after-query mode.
- Verify the stop diagnostic reports the expected query id and emitted record
  count.
- Diff CUDA output against the pack's Flye CPU oracle.
- Record compact DGX proof under `tests/golden/`.

## Out of Scope

- No in-process CUDA runtime linkage inside Flye.
- No direct Flye `VertexIndex` upload to GPU.
- No multi-query adapter support.
- No downstream chaining, repeat graph, polishing, or full assembly run with GPU
  records.
- No end-to-end speedup claim.

## C++ Style Constraints

- Flye patch code remains C++11-compatible.
- The patch must match nearby upstream Flye style and stay small enough to audit.
- No direct owning heap allocation or CUDA resource ownership is introduced.
- Error messages must include adapter, query id, emitted record count, and output
  paths where available.
- Unsupported shapes must fail closed with no silent CPU fallback.

## Deliverables

- `patches/flye/2.9.6/0006-cuflye-external-pack-query-stop.patch`
- `scripts/run_flye_fixture.sh` support for
  `--cuda-stop-after-packed-query`
- `docs/abi/cuda-candidate-adapter-shell-v0.md` M2d extension note
- DGX proof that Flye reaches the external CUDA adapter, emits the expected
  record count, and stops intentionally
- Compact golden proof under `tests/golden/`

## Acceptance Gates

- Full Flye patch queue applies cleanly.
- Patched Flye builds on DGX.
- CUDA backend builds on DGX with `nvcc`.
- External backend output validates as candidate-record-v1.
- Flye packed CPU candidate output vs CUDA output diff is `match`.
- Flye stderr contains the controlled stop diagnostic:
  - `adapter=external-packed-v0`;
  - `stop_after_packed_query=1`;
  - `query_id=-253`;
  - `emitted_records=15571`.
- No direct CUDA resource APIs are added outside the RAII wrapper.
- No large pack output is committed.

## Execution Checklist

- [x] Add stop-after-packed-query Flye patch.
- [x] Add runner flag and metadata capture.
- [x] Update ABI docs.
- [x] Build patched Flye on DGX.
- [x] Build CUDA backend on DGX.
- [x] Run stop-after-query proof against the M2b real pack.
- [x] Validate and diff outputs.
- [x] Record compact golden proof and close this card.

## Merge Note

Implemented in repo commit `cf8cb8b081e23ba1bb4f6c182b2c5283c5be1e76` and
validated on DGX host `edgexpert-45d2` with Flye `2.9.6` patched through
`0006-cuflye-external-pack-query-stop.patch`.

DGX proof:

- Host: `edgexpert-45d2`, `aarch64`
- Flye build: `g++ 13.3.0`, `-std=c++11`, `THREADS=4`, `aarch64=1`,
  `arm_neon=1`
- CUDA build: `/usr/local/cuda/bin/nvcc` `13.0.88`, target `sm_121`
- Device: `NVIDIA GB10`, compute capability `12.1`
- Source pack:
  `/tmp/cuflye-m2b-1782793203/out/m2b/proof/pack/query_neg253`
- Query id: `-253`
- Query length: `3339`
- K-mer size: `17`
- Pair comparisons: `51742433`
- Device allocation bytes: `2536379140`
- Candidate records emitted by CUDA: `15571`
- Flye adapter stop diagnostic:
  `adapter=external-packed-v0; stop_after_packed_query=1; query_id=-253; emitted_records=15571`
- GPU candidate canonical SHA-256:
  `5b50c458d82458516662e59daf3638e3534896a3ab1e77791f46dc54b663a1ae`
- Flye packed CPU vs GPU diff: `match`

Tracked compact proof:

- `tests/golden/cuflye-m2d-external-pack-query-stop-dgx-aarch64.json`

This closes the adapter-boundary proof only. It does not claim full assembly
equivalence or end-to-end Flye speedup.
