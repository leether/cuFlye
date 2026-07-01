# Task Card: cuFlye M6l Flye Full Query-Hit Worker Dry-Run Seam

Status: proposed

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

- [ ] Flye dry-run emits a worker request using the M6k protocol.
- [ ] Worker output row-key diff matches CPU raw-overlap oracle.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Dry-run metadata records that worker output was not consumed by graph
      mutation.
- [ ] Negative proof fails closed before graph mutation.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
