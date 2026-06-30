# Task Card: cuFlye M3b Long-Lived CUDA Worker

Status: active

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

- [ ] Refactor backend runner without changing candidate semantics.
- [ ] Add worker CLI and JSONL protocol handling.
- [ ] Add worker build script.
- [ ] Run local static/style gates.
- [ ] Build and run on DGX.
- [ ] Validate worker candidate outputs.
- [ ] Record compact proof and close this card.
