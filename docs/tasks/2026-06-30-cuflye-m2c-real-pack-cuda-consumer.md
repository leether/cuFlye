# Task Card: cuFlye M2c Real Pack CUDA Consumer

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Make the standalone CUDA candidate backend consume a real `pack-dump-v0` bundle
captured from Flye, then prove its candidate-record output matches the packed
CPU oracle.

The core question this card must answer is:

```text
Can CUDA consume real Flye query/index pack data and reproduce the CPU candidate list?
```

## Background

M2b captured one real Flye query and its relevant `VertexIndex` buckets into a
pack bundle. The blocker was that the M1i CUDA read-window backend stored each
query read in a fixed 256-byte struct, while the M2b toy query is 3,339 bases.

M2c removes that artificial read-size limit by uploading read metadata and a
flat read-base buffer.

## In Scope

- Replace fixed-size query read storage in `cuflye-cuda-read-window-smoke` with
  dynamic read metadata plus flat base storage.
- Preserve the existing `reads.tsv`, `index.tsv`, and `repetitive-kmers.tsv`
  input format.
- Keep GPU kernel semantics equivalent for M1i fixtures.
- Run the backend on the M2b real pack.
- Compare GPU output to:
  - the backend's optional host oracle;
  - the pack's Flye CPU `cpu-candidates.tsv`.
- Record compact DGX proof under `tests/golden/`.

## Out of Scope

- No Flye patch changes.
- No direct in-process Flye-to-CUDA buffers.
- No multi-query batching.
- No CUDA stream pipeline.
- No full assembly completion claim.
- No end-to-end Flye speed claim.

## Deliverables

- `cuda/cuflye_cuda_read_window_smoke.cu` dynamic read-base support.
- `docs/abi/cuda-read-window-smoke-v0.md` M2c extension note.
- `docs/tasks/2026-06-30-cuflye-m2c-real-pack-cuda-consumer.md`
- DGX proof that M1i fixture parity still passes.
- DGX proof that M2b real pack CPU/GPU diff passes.
- Compact golden proof under `tests/golden/`.

## Acceptance Gates

- `cuflye-cuda-read-window-smoke` builds on DGX with `nvcc`.
- M1i read-window fixture still validates and diffs cleanly.
- Real pack `reads.tsv` with query length 3,339 is accepted.
- Real pack GPU output validates as candidate-record-v1.
- Real pack Flye CPU `cpu-candidates.tsv` vs GPU output diff is `match`.
- No direct CUDA resource API calls are added outside the RAII wrapper.
- No large pack output is committed.

## Execution Checklist

- [ ] Replace fixed read structs with dynamic read-base storage.
- [ ] Update ABI docs.
- [ ] Build backend on DGX.
- [ ] Re-run M1i fixture parity on DGX.
- [ ] Run backend against M2b real pack on DGX.
- [ ] Validate and diff outputs.
- [ ] Record compact golden proof and close this card.
