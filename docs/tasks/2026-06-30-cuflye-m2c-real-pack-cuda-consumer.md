# Task Card: cuFlye M2c Real Pack CUDA Consumer

Status: completed

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

- [x] Replace fixed read structs with dynamic read-base storage.
- [x] Update ABI docs.
- [x] Build backend on DGX.
- [x] Re-run M1i fixture parity on DGX.
- [x] Run backend against M2b real pack on DGX.
- [x] Validate and diff outputs.
- [x] Record compact golden proof and close this card.

## Merge Note

Implemented in repo commit `98cc45fa196bd333392b043346a518e46bcb738a` and
validated on DGX host `edgexpert-45d2` with `/usr/local/cuda/bin/nvcc`
`13.0.88` targeting `sm_121`.

M1i regression proof:

- Fixture: `read-window-smoke-v0`
- K-mer size: `4`
- Reads: `2`
- Query windows: `23`
- Max read length: `19`
- Candidate records: `6`
- Expected vs backend CPU diff: `match`
- Backend CPU vs GPU diff: `match`
- GPU raw SHA-256:
  `f0ef59dafc1a8efa5f007443d4c11191e3f03b2500c87874b40fa89f2803010d`

Real pack proof:

- Source pack: `/tmp/cuflye-m2b-1782793203/out/m2b/proof/pack/query_neg253`
- Query id: `-253`
- Query length: `3339`
- K-mer size: `17`
- Runtime query windows evaluated: `3323`
- Pack manifest query windows: `3322`
- Index entries: `15571`
- Pair comparisons: `51742433`
- Device allocation bytes: `2536379140`
- Candidate records: `15571`
- Backend CPU vs GPU diff: `match`
- Flye packed CPU vs GPU diff: `match`
- GPU canonical SHA-256:
  `5b50c458d82458516662e59daf3638e3534896a3ab1e77791f46dc54b663a1ae`

The one-window count difference is a counting-definition difference between
the M2b pack manifest and the backend runtime window formula
`read_length - kmer_size + 1`. It did not affect candidate parity: the GPU
candidate set matches the Flye CPU oracle exactly after canonical sorting.

Tracked compact proof:

- `tests/golden/cuflye-m2c-real-pack-cuda-consumer-dgx-aarch64.json`
