# Task Card: cuFlye M3c Device Prefix Compaction

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move sparse candidate output prefix/compaction from host memory into the CUDA
backend so the M3b warm worker path no longer pays the measured host prefix-sum
bottleneck.

The core question this card must answer is:

```text
Can cuFlye preserve exact candidate-record-v1 output while replacing host-side
prefix/offset materialization with device-side prefix compaction?
```

## Background

M3b proved a long-lived worker boundary:

- M3b warm backend total before JSON: `132.110 ms`
- M3b warm backend host prefix sum: `84.221 ms`
- M3b warm backend kernel: `6.224 ms`
- M3b candidate diff: `match`

The next bottleneck is no longer CUDA setup. It is host-side prefix/offset
materialization over the full `pair_count` flag array.

## In Scope

- Replace host prefix-sum and host-to-device offset copy with a device-side
  prefix path.
- Preserve `candidate-record-v1` TSV output.
- Preserve M3b worker JSONL proof mode.
- Add timing fields that distinguish host prefix, device prefix, and output-count
  readback.
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
- Use standard containers for CPU-owned memory.
- Use existing move-only RAII wrappers for CUDA allocations and events.
- Do not add direct CUDA resource creation or destruction outside the approved
  RAII wrapper.
- Use checked integer conversions and allocation-size arithmetic.
- Fail closed on unsupported input shape.
- Do not add silent CPU fallback.

## Deliverables

- Device-side prefix/offset generation in `cuda/cuflye_cuda_read_window_smoke.cu`.
- Updated read-window and worker ABI docs.
- DGX proof under `tests/golden/`.
- This Task Card completed after proof.

## Acceptance Gates

- Worker builds on DGX with `nvcc`.
- Existing `cuflye-cuda-read-window-smoke` build still succeeds.
- Worker `--requests-jsonl` proof mode still processes at least two requests in
  one process.
- The second request reports `worker_cuda_context_warm=true`.
- Runtime JSON reports `prefix_strategy=device-exclusive-scan-v1`.
- Runtime JSON reports `host_prefix_sum=0.000` for the device-prefix path.
- Runtime JSON reports no host materialization of the full prefix-offset array.
- Worker output validates as candidate-record-v1.
- Worker output canonical diff against the M2f CPU oracle is `match`.
- Warm backend total before JSON is lower than the M3b warm backend baseline of
  `132.110 ms`.
- No large TSV output is committed.

## Execution Checklist

- [ ] Add device-side prefix/offset path.
- [ ] Update ABI docs.
- [ ] Run local static/style gates.
- [ ] Build and run on DGX.
- [ ] Validate worker candidate outputs.
- [ ] Record compact proof and close this card.
