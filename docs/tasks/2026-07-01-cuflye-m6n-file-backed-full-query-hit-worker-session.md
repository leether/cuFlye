# Task Card: cuFlye M6n File-Backed Full Query-Hit Worker Session

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move beyond M6m's intra-process JSONL warm lifecycle by adding a true
file-backed full-query-hit worker session so separate Flye seam calls can reuse
one already-running CUDA worker process.

## In Scope

- Define a bounded `full-query-hit-session-v0` request/response contract.
- Start or attach to a long-lived CUDA full-query-hit worker session in proof
  mode.
- Submit at least two separate actual requests to the same live worker process.
- Prove the second request is warm without relaunching the worker binary.
- Preserve the M6m row-key oracle gate and
  `graph_mutation_consumed_worker_output=false`.
- Keep worker startup, attach, request, and teardown timing separated.
- Keep unsupported session state, worker failures, stale response files, and
  mismatched output fail-closed before graph mutation.

## Out of Scope

- No graph mutation from worker output.
- No default GPU mode.
- No whole-Flye speed claim until end-to-end worker wall time improves.
- No full non-key raw-overlap parity claim.

## C++/CUDA/Python Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and minimal.
- Do not add direct owning `new`, `delete`, `malloc`, `free`, or direct CUDA
  resource APIs in Flye integration code.
- Keep direct CUDA resource management inside CUDA worker code and existing RAII
  wrappers.
- Worker output must pass the row-key oracle gate before any eligibility flag is
  set.

## Deliverables

- Session protocol documentation under `docs/abi/`.
- Flye-side proof seam for file-backed full-query-hit worker sessions.
- CUDA worker session proof mode or helper compatible with the protocol.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with a bounded session-lifecycle conclusion.

## Acceptance Gates

- [ ] Two separate Flye seam submissions attach to one live worker session.
- [ ] The second actual request reports `worker_cuda_context_warm=true`.
- [ ] The second actual request avoids source parsing, device allocation, and
      host-to-device copy in worker timing.
- [ ] Row-key diff matches the CPU raw-overlap oracle for every validated
      actual request.
- [ ] Negative stale-session or memory-budget proof fails closed before graph
      mutation.
- [ ] Default CPU Flye canonical artifacts remain unchanged.
- [ ] Local and DGX syntax/style/ownership gates pass.

## Completion Notes

Pending implementation.
