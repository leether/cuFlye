# Task Card: cuFlye M6l Flye Full Query-Hit Worker Dry-Run Seam

Status: completed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M6k full-query-hit worker boundary into a Flye-side dry-run seam so a
real Flye run can generate or select the bounded source pack, submit a worker
request, validate the worker raw-overlap row keys against the CPU oracle, and
stop before graph mutation.

## In Scope

- Add an opt-in Flye-side dry-run mode for selected M6 source-pack requests.
- Invoke the M6k worker through file-backed request/response metadata.
- Validate worker output against CPU raw-overlap row keys before any downstream
  graph logic can consume it.
- Preserve exact Flye canonical artifacts and record
  `graph_mutation_consumed_worker_output=false`.
- Keep unsupported shapes fail-closed with explicit metadata.

## Out of Scope

- No graph mutation from worker output.
- No default GPU mode.
- No broader source-pack expansion.
- No full non-key raw-overlap parity claim.
- No whole-Flye speed claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches small and C++11-compatible.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs in Flye integration code.
- Worker output must be validated before it can be marked dry-run eligible.
- Fail closed on missing worker binary, worker failure, mismatched output, or
  unsupported source-pack shape.

## Deliverables

- Flye-side full-query-hit worker dry-run seam.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a bounded Flye-seam conclusion.

## Acceptance Gates

- [x] Flye dry-run emits a worker request using the M6k protocol.
- [x] Worker output row-key diff matches CPU raw-overlap oracle.
- [x] Default CPU Flye canonical artifacts remain unchanged.
- [x] Dry-run metadata records that worker output was not consumed by graph
      mutation.
- [x] Negative proof fails closed before graph mutation.
- [x] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Implemented in
`0042-cuflye-read-to-graph-full-query-hit-worker-dry-run-seam.patch` and
documented in `docs/abi/flye-full-query-hit-worker-dry-run-seam-v0.md`.

DGX proof root:

```text
/tmp/cuflye-m6l-proof-20260701T080708Z
```

Positive dry-run:

```text
status=passed
decision=stopped-before-graph-mutation
query_ids=5,6,7,8,9,10,11,12
expected_output_records=36
row_key_diff=match
matched_rows=36
missing_rows=0
extra_rows=0
graph_mutation_consumed_worker_output=false
```

Negative proof:

```text
status=failed-before-graph-mutation
error="required bytes exceed memory budget"
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
M6l does not speed up whole Flye yet. It proves the real Flye process can
generate the selected read-to-graph source pack, call the CUDA full-query-hit
worker through the M6k file protocol, validate 36/36 raw-overlap row keys
against the CPU oracle, and stop before graph mutation. This turns the previous
standalone worker win into a Flye integration seam with a fail-closed safety
gate.
```
