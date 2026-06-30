# Task Card: cuFlye M2e Real Pack Timing Proof

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Measure the real `pack-dump-v0` candidate-generation boundary honestly enough
to decide where CUDA is already better and where external adapter overhead is
still dominant.

The core question this card must answer is:

```text
On the same real packed query, how do CPU candidate generation, CUDA kernel
time, CUDA end-to-end backend time, and Flye external adapter time compare?
```

## Background

M2d proved Flye can invoke the external CUDA packed backend, parse the emitted
candidate records, and fail closed after one real query. It did not measure
where time is spent.

M2e adds timing fields to the standalone CUDA read-window backend JSON, then
runs the same M2b real pack with CPU oracle output enabled and compares the
timing breakdown without changing candidate semantics.

## In Scope

- Add timing metadata to `cuflye-cuda-read-window-smoke`.
- Keep candidate-record-v1 TSV output unchanged.
- Time CPU oracle generation when `--cpu-output-tsv` is supplied.
- Time device allocation, host-to-device transfer, kernel execution,
  device-to-host transfer, compaction, and candidate TSV write.
- Run the real M2b pack on DGX with CPU oracle enabled.
- Validate CPU/GPU candidate equivalence.
- Record a compact golden proof with timing fields.

## Out of Scope

- No Flye patch changes.
- No change to kernel candidate semantics.
- No multi-query batching.
- No full assembly run.
- No end-to-end Flye speedup claim.

## C++/CUDA Style Constraints

- Keep the standalone backend in CUDA C++14.
- Use RAII CUDA event wrappers for timing resources.
- Do not add direct CUDA resource creation/destruction outside
  `cuda/cuflye_cuda_raii.hpp`.
- Keep timing fields in JSON metadata only; do not change TSV ABI.
- Keep timing claims scoped to the measured pack shape.

## Deliverables

- `cuda/cuflye_cuda_read_window_smoke.cu` timing metadata.
- `docs/abi/cuda-read-window-smoke-v0.md` M2e extension note.
- DGX timing proof for the real M2b pack.
- Compact golden proof under `tests/golden/`.

## Acceptance Gates

- CUDA backend builds on DGX with `nvcc`.
- Real pack CPU oracle output validates as candidate-record-v1.
- Real pack GPU output validates as candidate-record-v1.
- CPU vs GPU canonical diff is `match`.
- Runtime JSON includes a `timing_ms` object.
- Timing proof reports CPU oracle time, CUDA kernel time, CUDA backend total, and
  output write time.
- No direct CUDA resource APIs are added outside the RAII wrapper.
- No large TSV output is committed.

## Execution Checklist

- [x] Add backend timing fields.
- [x] Update ABI docs.
- [x] Build CUDA backend on DGX.
- [x] Run real-pack timing proof with CPU oracle enabled.
- [x] Validate and diff CPU/GPU outputs.
- [x] Record compact golden proof and close this card.

## Merge Note

Implemented in repo commit `5992c0b39d336d45535240cface5a0255b632681` and
validated on DGX host `edgexpert-45d2` with `/usr/local/cuda/bin/nvcc`
`13.0.88` targeting `sm_121`.

Real pack proof:

- Source pack:
  `/tmp/cuflye-m2b-1782793203/out/m2b/proof/pack/query_neg253`
- Query id: `-253`
- Query length: `3339`
- K-mer size: `17`
- Pair comparisons: `51742433`
- Candidate records: `15571`
- CPU oracle time: `947.291 ms`
- GPU kernel time: `5.815 ms`
- Kernel vs CPU oracle speedup: `162.9x`
- GPU-only backend total before JSON: `1245.546 ms`
- Host output allocation time: `819.391 ms`
- Host output allocation share of GPU-only total: `65.8%`
- Flye external adapter wall time to controlled stop: `0:05.73`
- CPU/GPU/adapter candidate diffs: `match`
- Canonical SHA-256:
  `5b50c458d82458516662e59daf3638e3534896a3ab1e77791f46dc54b663a1ae`

Interpretation:

- CUDA is already better at the measured candidate kernel: about `163x` faster
  than the CPU oracle for this real pack shape.
- The current standalone backend is not yet end-to-end faster than the CPU
  oracle because it materializes a dense `pairCount` output buffer. That buffer
  costs far more than the kernel itself.

Tracked compact proof:

- `tests/golden/cuflye-m2e-real-pack-timing-proof-dgx-aarch64.json`
