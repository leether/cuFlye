# Task Card: cuFlye M3d Worker Device Buffer Arena

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Add a worker-side reusable device-buffer arena so repeated warm requests do not
pay the M3c per-request CUDA allocation overhead for stable input shapes.

The core question this card must answer is:

```text
Can cuFlye preserve exact candidate-record-v1 output while reusing CUDA device
buffers across repeated worker requests?
```

## Background

M3c moved prefix/offset generation to the device:

- M3c warm backend total before JSON: `28.330 ms`
- M3c warm device allocation: `10.339 ms`
- M3c warm kernel: `6.223 ms`
- M3c warm device prefix sum: `3.496 ms`
- M3c candidate diff: `match`

The next bottleneck is allocation churn. The worker already keeps CUDA context
warm; it should also keep stable-capacity device buffers warm across requests.

## In Scope

- Add reusable worker device buffers for the read-window backend.
- Preserve the existing one-shot read-window smoke CLI behavior.
- Track arena capacity, allocation/reuse counts, and timing metadata.
- Keep memory-budget checks conservative.
- Validate toy and real-pack outputs on DGX.
- Record compact proof under `tests/golden/`.

## Out of Scope

- No Flye patch behavior change.
- No in-process CUDA inside Flye.
- No daemon or socket protocol.
- No overlap, graph, or polishing work.
- No full assembly speedup claim.

## C++/CUDA Style Constraints

- Keep CUDA code CUDA C++14.
- Keep Flye patches untouched.
- Own device memory through move-only RAII wrappers only.
- Do not add direct CUDA resource creation or destruction outside the approved
  RAII wrapper.
- Use checked integer conversions and allocation-size arithmetic.
- Fail closed on memory-budget or unsupported-shape failures.
- Do not add silent CPU fallback.

## Deliverables

- Reusable worker device-buffer arena in `cuda/cuflye_cuda_read_window_smoke.cu`.
- RAII capacity helper in `cuda/cuflye_cuda_raii.hpp`.
- Updated read-window and worker ABI docs.
- DGX proof under `tests/golden/`.
- This Task Card completed after proof.

## Acceptance Gates

- Worker builds on DGX with `nvcc`.
- Existing `cuflye-cuda-read-window-smoke` build still succeeds.
- Worker `--requests-jsonl` proof mode still processes at least two requests in
  one process.
- The second request reports `worker_cuda_context_warm=true`.
- Runtime JSON reports worker arena enabled for worker requests.
- Warm request reports buffer reuse for stable real-pack shape.
- Warm backend `timing_ms.device_allocation` is lower than the M3c warm baseline
  of `10.339 ms`.
- Warm backend total before JSON is lower than the M3c warm baseline of
  `28.330 ms`.
- Worker output validates as candidate-record-v1.
- Worker output canonical diff against the M2f CPU oracle is `match`.
- No large TSV output is committed.

## Execution Checklist

- [x] Add RAII capacity helper.
- [x] Add worker arena and backend reuse path.
- [x] Update ABI docs.
- [x] Run local static/style gates.
- [x] Build and run on DGX.
- [x] Validate worker candidate outputs.
- [x] Record compact proof and close this card.

## Merge Note

Implemented in repo commit `8ac82c29577a5625a188e089bf48292deabf335b` and
validated on DGX host `edgexpert-45d2` with `/usr/local/cuda/bin/nvcc`
`13.0.88` targeting `sm_121`.

Real pack proof:

- Source pack:
  `/tmp/cuflye-m2b-1782793203/out/m2b/proof/pack/query_neg253`
- Query id: `-253`
- K-mer size: `17`
- Requests processed in one worker process: `2`
- Candidate records per request: `15571`
- Second request warm context: `true`
- Worker arena enabled: `true`
- Warm arena allocations: `0`
- Warm arena reuses: `7`
- Warm arena capacity: `260459496 bytes`
- Warm backend device allocation: `0.001 ms`
- M3c warm backend device allocation: `10.339 ms`
- Warm backend total before JSON: `18.643 ms`
- M3c warm backend total before JSON: `28.330 ms`
- Warm backend vs M3c speedup: `1.52x`
- Warm backend vs CPU oracle speedup: `50.58x`
- Worker RSS for two real requests: `103844 kB`
- CPU/worker candidate diffs: `match`
- Canonical SHA-256:
  `5b50c458d82458516662e59daf3638e3534896a3ab1e77791f46dc54b663a1ae`

Tracked compact proof:

- `tests/golden/cuflye-m3d-worker-device-buffer-arena-dgx-aarch64.json`

M3d proves reusable worker device buffers at the candidate backend boundary. It
still does not claim full Flye assembly speedup.
