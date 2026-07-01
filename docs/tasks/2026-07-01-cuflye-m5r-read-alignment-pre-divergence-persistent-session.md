# Task Card: cuFlye M5r Read Alignment Pre-Divergence Persistent Session

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Turn the M5q hot-path result into a Flye-facing integration improvement by
removing repeated CUDA context/process setup from selected read-alignment
pre-divergence batches.

The core question this card must answer is:

```text
Can Flye submit selected pre-divergence read-alignment batches to a long-lived
CUDA worker/session and preserve exact artifacts while reducing selected-batch
worker wall time versus M5q's fresh-process batch worker?
```

## In Scope

- Reuse the M5p/M5q `batch-dry-run-v0` correctness contract.
- Define a minimal read-alignment pre-divergence session protocol, preferably
  file-backed JSONL or another repo-native external-worker boundary.
- Keep CUDA context and persistent arena alive across more than one selected
  batch request inside the proof.
- Compare session request timing against M5q fresh worker timing for the same
  selected query set or a deterministic larger set.
- Preserve exact canonical Flye artifacts against CPU baseline.
- Fail closed on worker mismatch, missing response, unsupported shape, timeout,
  or session lifecycle failure.

## Out of Scope

- No default GPU mode.
- No `_readAlignments` replacement from pre-divergence output.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib replacement.
- No production speedup claim unless the measured Flye-side session run proves
  it against a CPU baseline with unchanged artifacts.

## C++/CUDA Style Constraints

- Keep Flye patches C++11-compatible and narrow.
- Follow `docs/CODING_STYLE.md` ownership rules.
- Do not introduce direct owning `new` or `delete`, `malloc`/`free`, or direct
  CUDA resource ownership.
- Reuse existing CUDA RAII wrappers for any reusable CUDA resource.
- Session output ordering must remain deterministic and machine-diffable.
- Unsupported shapes must fail closed; silent CPU fallback is not allowed.

## Deliverables

- Session protocol documentation or ABI note.
- Worker/session implementation or proof shell that keeps CUDA setup warm across
  selected pre-divergence batch requests.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with measured session timing versus M5q fresh worker timing.
- Plain-language CUDA benefit assessment.

## Acceptance Gates

- [x] Patch series applies and patched Flye builds on DGX.
- [x] CUDA read-alignment session worker builds on DGX.
- [x] Positive Flye session run passes M5p per-query goodChain checks.
- [x] Positive Flye session run preserves exact canonical artifacts versus CPU.
- [x] Session request timing is measured separately from one-time session setup.
- [x] Selected-batch worker/request timing improves versus M5q fresh-process
      batch worker for a comparable selected query set.
- [x] Negative mismatch or lifecycle fault fails closed before graph mutation.
- [x] Local and DGX syntax/style gates pass.
- [x] C++/CUDA ownership scan shows no new direct owning heap/resource APIs.

## Completion Notes

DGX proof:

```text
proof_root=/tmp/cuflye-m5r-proof-20260701T032358Z
golden=tests/golden/cuflye-m5r-read-alignment-pre-divergence-persistent-session-dgx-aarch64.json
positive_selected_query_count=64
positive_status=passed
positive_matched_fixture_count=64
positive_canonical_diff=match
positive_worker_lifecycle_mode=session-file-v0
positive_worker_warmup_wall_ms=6.173764
positive_worker_actual_wall_ms=4.139341
positive_actual_response_request_ordinal=2
positive_actual_response_arena_cache_hit=true
positive_actual_response_request_total_ms=2.750920
m5q_fresh_worker_wall_ms=435.505899
selected_batch64_worker_wall_improvement_vs_m5q=105.211409x
selected_batch64_request_total_improvement_vs_m5q=158.312819x
negative_fault=drop-first-gpu-good-chain
negative_status=failed
negative_failed_closed=true
negative_matched_fixture_count=63
negative_mismatched_fixture_count=1
negative_graph_mutation_consumed_worker_output=false
full3546_cpu_backend_mean_total_before_json_ms=0.408065
full3546_cuda_session_backend_mean_total_before_json_ms=0.298561
full3546_cuda_backend_speedup_vs_cpu=1.366773x
full3546_cuda_session_request_total_ms=91.698238
```

Allowed M5r claim:

```text
cuFlye can submit selected Flye read-alignment pre-divergence batches to a
long-lived CUDA file session, keep CUDA context and device arena state warm
across warmup and actual requests, preserve exact Flye artifacts, and reduce
the selected batch64 worker segment from M5q's 435.505899 ms fresh-process
worker to 4.139341 ms actual session wall time.
```

Forbidden M5r claim:

```text
M5r must not claim default GPU mode or full Flye acceleration unless the
measured Flye-side session run demonstrates it against a CPU baseline with
unchanged artifacts.
```

Plain-language benefit:

```text
M5r removes the obvious integration tax: Flye no longer has to pay fresh CUDA
worker/context setup for the selected pre-divergence batch. On the 64-read Flye
proof, the actual session request hits the cached arena and preserves exact
artifacts. On the larger 3546-fixture backend hot path, CUDA is now faster than
CPU for the scoped read-alignment pre-divergence replay stage, but full request
time is still dominated by per-fixture file/JSON output.
```

Next highest-ROI task:

```text
M5s: reduce or bypass per-fixture TSV/JSON emission for the session path by
returning a compact verified object-vector or shared artifact payload, then
measure whether the graph-facing read-alignment path keeps the full3546 CUDA
backend advantage after host output overhead is removed.
```
