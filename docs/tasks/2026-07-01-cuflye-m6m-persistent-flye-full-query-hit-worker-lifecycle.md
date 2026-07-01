# Task Card: cuFlye M6m Persistent Flye Full Query-Hit Worker Lifecycle

Status: proposed

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

- [ ] Flye emits a two-request JSONL worker lifecycle.
- [ ] Actual request reports `worker_cuda_context_warm=true`.
- [ ] Actual request row-key diff matches CPU raw-overlap oracle.
- [ ] Actual warm request timing is reported separately from cold setup.
- [ ] Negative lifecycle proof fails closed before graph mutation.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
