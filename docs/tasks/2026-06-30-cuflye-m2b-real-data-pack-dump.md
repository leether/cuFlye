# Task Card: cuFlye M2b Real Data Pack Dump

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Define and implement the first real Flye data packer boundary for CUDA
candidate backend integration.

The core question this card must answer is:

```text
Can cuFlye extract a real Flye query and its relevant VertexIndex buckets into a replayable candidate-backend input bundle?
```

## Background

M2a proved Flye can select the CUDA candidate backend and invoke an external
CUDA backend on hand-written packed toy data. The next blocker is that the CUDA
backend still does not receive data derived from Flye's real `FastaRecord` and
`VertexIndex` objects. M2b adds a pack-dump mode that uses Flye's real CPU
candidate walk to emit a bounded pack and a per-query CPU candidate oracle.

## In Scope

- Add `CUFLYE_CUDA_ADAPTER_MODE=pack-dump-v0`.
- Require `CUFLYE_CUDA_PACK_DUMP_DIR`.
- Extract the current `FastaRecord` into `reads.tsv`.
- Flatten relevant `VertexIndex` buckets into `index.tsv`.
- Extract repetitive query lookup k-mers into `repetitive-kmers.tsv`.
- Emit per-query `cpu-candidates.tsv` using candidate-record-v1.
- Emit `pack-manifest.json` with counts and parameters.
- Fail closed after writing one query pack.
- Extend the fixture runner with pack-dump environment variables.
- Prove on DGX that the pack is written and the CPU candidate TSV validates.

## Out of Scope

- Running CUDA on the real pack.
- Supporting multi-query or multi-thread pack capture.
- Direct Flye-to-CUDA in-process buffers.
- Full candidate backend parity.
- Assembly completion under `CUFLYE_CANDIDATE_BACKEND=cuda`.
- Speed claims beyond M1j's bounded core benchmark.

## Deliverables

- `patches/flye/2.9.6/0005-cuflye-real-data-pack-dump.patch`
- `docs/abi/cuda-real-data-pack-dump-v0.md`
- runner support for `--cuda-pack-dump-dir` and `--cuda-pack-query-id`
- DGX proof that pack-dump mode captures a real toy query and fails closed
- compact golden proof under `tests/golden/`

## Acceptance Gates

- Patch series applies through 0005 and builds on DGX.
- Default backend run still completes on the toy fixture.
- `pack-dump-v0` writes `reads.tsv`, `index.tsv`, `repetitive-kmers.tsv`,
  `cpu-candidates.tsv`, and `pack-manifest.json`.
- `cpu-candidates.tsv` validates as candidate-record-v1.
- The run fails closed with `adapter=pack-dump-v0`.
- No large pack output is committed.

## Execution Checklist

- [x] Inspect M2a adapter shell and VertexIndex public access.
- [x] Add real-data pack-dump ABI document.
- [x] Add 0005 Flye patch.
- [x] Extend fixture runner environment passthrough.
- [x] Build patched Flye on DGX.
- [x] Run default CPU regression on DGX.
- [x] Run pack-dump proof on DGX.
- [x] Validate packed CPU candidate dump.
- [x] Record compact proof and close this card.

## Merge Note

Completed on DGX host `edgexpert-45d2` using a temporary proof checkout at
`/tmp/cuflye-m2b-1782793203`.

Build proof:

- Flye commit: `886b8c17412c`
- Flye version: `2.9.6-b1802`
- Applied patch series:
  - `0001-cuflye-candidate-dump.patch`
  - `0002-cuflye-candidate-backend-seam.patch`
  - `0003-cuflye-cuda-backend-stub.patch`
  - `0004-cuflye-cuda-adapter-shell.patch`
  - `0005-cuflye-real-data-pack-dump.patch`

Default regression proof:

- Run: `out/m2b/proof/runs/toy-default`
- Fixture: `toy-hifi`
- Status: completed with exit status `0`

Pack-dump proof:

- Run: `out/m2b/proof/runs/toy-pack-dump`
- Pack directory: `out/m2b/proof/pack/query_neg253`
- Final status: failed closed after pack capture
- Error excerpt:
  `cuFlye CUDA pack-dump adapter captured real Flye query/index data; adapter=pack-dump-v0; query_id=-253; pack_dir=out/m2b/proof/pack/query_neg253; failing closed before downstream graph logic`

Captured pack:

- Query id: `-253`
- Query length: `3339`
- K-mer size: `17`
- Query windows: `3322`
- Flattened index entries: `15571`
- Repetitive k-mers: `0`
- Absent windows: `2100`
- Trivial hits filtered: `1092`
- CPU candidate records: `15571`
- CPU candidate raw SHA-256:
  `6c4e5e7bf162d7f4223c9e34ab2c92e0cc253f8a76e0802e45bbcaf423baa68b`
- CPU candidate canonical SHA-256:
  `5b50c458d82458516662e59daf3638e3534896a3ab1e77791f46dc54b663a1ae`

Tracked compact proof:

- `tests/golden/cuda-real-data-pack-dump-dgx-aarch64.json`
