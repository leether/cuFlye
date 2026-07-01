# Task Card: cuFlye M6m Persistent Flye Full Query-Hit Worker Lifecycle

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Extend the M6l Flye-side full-query-hit worker dry-run seam so it can submit a
warm/persistent request lifecycle instead of paying cold CUDA context and device
buffer setup for every proof request.

## In Scope

- Add a Flye-side lifecycle mode for the M6k `--worker-requests-jsonl` protocol.
- Emit at least two compatible requests from one Flye dry-run proof: warmup and
  actual.
- Validate only the actual worker output against the CPU raw-overlap row-key
  oracle.
- Preserve `graph_mutation_consumed_worker_output=false`.
- Keep unsupported lifecycle modes and worker failures fail-closed before graph
  mutation.

## Out of Scope

- No graph mutation from worker output.
- No default GPU mode.
- No daemon/session manager yet unless the JSONL lifecycle is insufficient.
- No whole-Flye speed claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and minimal.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs in Flye integration code.
- Metadata must separate cold setup time from actual warm request timing.
- Worker output must pass the row-key oracle gate before any eligibility flag is
  set.

## Deliverables

- Flye-side `jsonl-persistent-v0` lifecycle for full-query-hit dry-run requests.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a bounded warm-lifecycle conclusion.

## Acceptance Gates

- [x] Flye emits a two-request JSONL worker lifecycle.
- [x] Actual request reports `worker_cuda_context_warm=true`.
- [x] Actual request row-key diff matches CPU raw-overlap oracle.
- [x] Actual warm request timing is reported separately from cold setup.
- [x] Negative lifecycle proof fails closed before graph mutation.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in
`0043-cuflye-read-to-graph-full-query-hit-worker-jsonl-lifecycle.patch` and
recorded in
`tests/golden/cuflye-m6m-persistent-flye-full-query-hit-worker-lifecycle-dgx-aarch64.json`.

DGX proof root:

```text
/tmp/cuflye-m6m-proof-20260701T083036Z
```

Positive lifecycle dry-run:

```text
status=passed
worker_lifecycle_mode=jsonl-persistent-v0
requests_jsonl_line_count=2
request_ids=read-to-graph-full-query-hit-warmup,read-to-graph-full-query-hit-actual
actual_worker_cuda_context_warm=true
worker_context_setup_ms=312.078
actual_request_total_ms=52.2432
actual_request_parse_ms=0
actual_request_device_allocation_ms=0
actual_request_host_to_device_ms=0
row_key_diff=match
matched_rows=36
missing_rows=0
extra_rows=0
graph_mutation_consumed_worker_output=false
```

Negative lifecycle proof:

```text
status=failed-before-graph-mutation
error="CUDA full-query-hit worker failed with status 256: required bytes exceed memory budget"
expected_output_records=36
missing_rows=36
graph_mutation_consumed_worker_output=false
```

Default CPU proof:

```text
toy-hifi artifact_hashes_match_m0_golden=true
```

Plain-language benefit:

```text
M6m still does not make whole Flye faster. It proves the real Flye seam can send
two requests to one CUDA worker process, pay cold CUDA setup on the warmup
request, then run the actual request warm with parse, allocation, and H2D copy
reported as 0 ms. The actual bounded request is now about kernel-time sized
inside the worker, while Flye still refuses to mutate graph state until the CPU
oracle row-key gate passes.
```
