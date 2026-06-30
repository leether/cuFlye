# Task Card: cuFlye M4z Validation-Safe GPU-First Selection Planner

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn M4y's hand-picked GPU-first query allowlist into a reproducible planner
that ranks high-value repeated overlap calls while excluding candidates already
known to fail validation.

## Background

M4y broadened GPU-first substitution to a bounded 7-query set and reduced proof
ledger volume, but the first 8-query attempt included query `798`, which failed
worker validation (`oracle_records=49`, `worker_records=48`). That was the
right fail-closed behavior, but it also shows that manual query selection is now
the bottleneck.

## In Scope

- Add a small repo tool that reads substitution ledger JSONL and optional
  worker validation JSON, ranks repeated supported query ids, and emits a
  deterministic safe allowlist.
- Keep validation failures as hard rejections.
- Keep the planner independent from Flye runtime; no graph mutation changes.
- Compare existing overlap worker `serial` and `parallel-reduce` kernel modes
  on the accepted M4y fixture batch.
- Record whether this improves worker-kernel timing, while keeping exact output
  validation as the acceptance gate.

## Out of Scope

- No default GPU mode.
- No automatic runtime selection inside Flye.
- No broad unsupported-shape substitution.
- No whole-Flye speedup claim unless the measured proof shows one.

## Acceptance Gates

- [x] Planner emits the M4y-safe set and rejects query `798` from validation
      evidence.
- [x] Planner output is deterministic and JSON-parseable.
- [x] Local fixture test covers ranking and validation rejection.
- [x] DGX worker comparison validates both `serial` and `parallel-reduce`
      outputs before comparing timings.
- [x] Plain-language benefit assessment states whether the CUDA kernel mode
      improved and whether whole-Flye wall time improved.

## C++ Style Constraints

- No Flye C++ patch changes are planned for this task.
- If C++/CUDA is touched, keep ownership in existing RAII/value patterns and do
  not introduce direct resource ownership.

## Deliverables

- `tools/plan_gpu_first_selection.py`
- Local planner fixture/test data
- DGX proof manifest
- Roadmap, Task Card, golden index, and plain-language benefit assessment

## Completion Notes

M4z adds a deterministic GPU-first selection planner without changing Flye
runtime or CUDA/C++ code. On DGX, the planner combined M4y's failed 8-query
ledger evidence with the successful 7-query ledger and emitted:

```text
selected_query_ids: 161,89,554,752,112,896,110
rejected_query_ids: 798 validation_failed canonical_diff_status=mismatch
```

The accepted 7-query batch was replayed through both worker kernel modes with
`warmup_runs=1` and `benchmark_runs=10`. Both modes canonical-diffed `match`
against each fixture oracle. On this small M4y batch, `parallel-reduce` did not
improve timing:

```text
serial kernel_ms=6.735444 backend_mean_ms=6.788436 request_total_ms=89.063285
parallel-reduce kernel_ms=7.150598 backend_mean_ms=7.207953 request_total_ms=90.571207
parallel/serial kernel ratio=1.061637
```

Plain-language assessment: M4z improves selection governance and prevents
unsafe manual allowlists from slipping into GPU-first substitution. It does not
prove a whole-Flye speedup, and for this particular small fixture batch the
serial CUDA kernel remains the better worker mode.
