# Task Card: cuFlye M3b Long-Lived CUDA Worker

Status: completed

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Build the first minimal `cuflye-cuda-worker` boundary so cuFlye can process more
than one candidate-generation request in a single CUDA process.

The core question this card must answer is:

```text
Can cuFlye keep the sparse real-pack CUDA backend correct while measuring
first-request versus warm-request behavior in one worker process?
```

## Background

M2f proved one real pack candidate-boundary speedup:

- CPU oracle: `943.032 ms`
- GPU-only backend total before JSON: `425.540 ms`
- CUDA kernel: `6.361 ms`
- CUDA setup: `298.595 ms`
- Host prefix sum: `83.331 ms`
- Candidate diffs: `match`

M3a chose a long-lived external worker because CUDA setup and adapter overhead
are now larger targets than the candidate kernel itself.

## In Scope

- Add a `cuflye-cuda-worker` build target.
- Support `--requests-jsonl PATH` proof mode.
- Support `--request-json PATH` debug mode.
- Parse `cuflye-worker-request-v0` with no new third-party dependency.
- Process at least two requests in one worker process for the proof run.
- Emit `cuflye-worker-response-v0` JSON per request.
- Reuse the existing sparse read-window backend implementation instead of
  duplicating the candidate algorithm.
- Preserve candidate-record-v1 output ordering and diff gates.

## Out of Scope

- No Flye patch behavior change.
- No daemon or socket protocol.
- No in-process CUDA inside Flye.
- No multi-query scheduling inside Flye.
- No downstream overlap or graph logic.
- No full assembly speedup claim.

## C++/CUDA Style Constraints

- Keep the worker CUDA C++14.
- Keep Flye patches untouched in this slice.
- Use standard containers for CPU-owned memory.
- Use existing move-only RAII wrappers for CUDA allocations and events.
- Do not add direct CUDA resource creation or destruction outside the approved
  RAII wrapper.
- Use checked integer conversions and allocation-size arithmetic.
- Fail closed on unsupported request schema, adapter mode, ABI, or input shape.
- Do not add silent CPU fallback.

## Deliverables

- `cuda/cuflye_cuda_read_window_smoke.cu` refactored to expose a reusable backend
  runner while preserving the existing smoke CLI.
- `scripts/build_cuda_worker.sh`.
- Worker protocol docs updated if implementation sharpens the M3a draft.
- DGX proof under `tests/golden/`.
- This Task Card completed after proof.

## Acceptance Gates

- Worker builds on DGX with `nvcc`.
- Existing `cuflye-cuda-read-window-smoke` build still succeeds.
- `--requests-jsonl` proof mode processes at least two requests in one worker
  process.
- The second request reports `worker_cuda_context_warm=true`.
- Worker output validates as candidate-record-v1.
- Worker output canonical diff against the M2f CPU oracle is `match`.
- Response JSON reports `output_strategy=sparse-offsets-v1` and
  `dense_pair_output_materialized=false`.
- Timing output includes first-request and warm-request fields.
- No large TSV output is committed.

## Execution Checklist

- [x] Refactor backend runner without changing candidate semantics.
- [x] Add worker CLI and JSONL protocol handling.
- [x] Add worker build script.
- [x] Run local static/style gates.
- [x] Build and run on DGX.
- [x] Validate worker candidate outputs.
- [x] Record compact proof and close this card.

## Merge Note

Implemented in repo commit `699228bb9c409b2ab1be59cb2508bb9dd4b7be1c` and
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
- Worker context setup: `264.730 ms`
- First request total: `187.557 ms`
- First backend total before JSON: `162.663 ms`
- Warm request total: `157.098 ms`
- Warm backend total before JSON: `132.110 ms`
- Warm backend CUDA setup: `0.000 ms`
- Warm backend kernel: `6.224 ms`
- Warm backend host prefix sum: `84.221 ms`
- M2f GPU-only backend total before JSON: `425.540 ms`
- M2f CPU oracle: `943.032 ms`
- Warm backend vs M2f GPU-only speedup: `3.22x`
- Warm backend vs CPU oracle speedup: `7.14x`
- Worker RSS for two real requests: `356240 kB`
- CPU/worker candidate diffs: `match`
- Canonical SHA-256:
  `5b50c458d82458516662e59daf3638e3534896a3ab1e77791f46dc54b663a1ae`

Tracked compact proof:

- `tests/golden/cuflye-m3b-long-lived-cuda-worker-dgx-aarch64.json`

M3b proves a reusable CUDA worker boundary and removes CUDA setup from
per-request backend timing. It still does not claim full Flye assembly speedup.
