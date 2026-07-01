# Task Card: cuFlye M5s Read Alignment Session Output Overhead Reduction

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Preserve the M5r persistent CUDA session correctness contract while reducing
the host-side per-fixture TSV/JSON output overhead that dominates full3546
request time.

The core question for this card is:

```text
Can cuFlye keep the full3546 CUDA backend advantage after replacing or bypassing
the per-fixture file-emission path with a compact verified payload suitable for
the next graph-facing read-alignment seam?
```

## In Scope

- Reuse the M5r file-session protocol and exactness gates.
- Add a compact output mode for session requests, such as a single canonical
  object-vector artifact or bounded binary/JSONL payload.
- Preserve deterministic ordering and CPU oracle diffability.
- Keep the existing TSV output mode available for audit/debug runs.
- Measure full3546 request time before and after output-overhead reduction.

## Out of Scope

- No default GPU mode.
- No broad `_readAlignments` replacement without a new fail-closed graph-facing
  gate.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib replacement.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Do not introduce direct owning `new`, `delete`, `malloc`, `free`, or direct
  CUDA resource ownership outside approved RAII wrappers.
- Keep Flye patches C++11-compatible and narrow.
- Unsupported shapes must fail closed.

## Deliverables

- Compact session output ABI note or update.
- Worker implementation for compact output mode.
- Flye seam or proof harness that validates compact output against CPU oracle.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with request-time comparison versus M5r.

## Acceptance Gates

- [x] Patch series applies and patched Flye builds on DGX.
- [x] CUDA worker builds on DGX.
- [x] Compact output preserves exact canonical CPU equivalence.
- [x] Full3546 request time improves versus M5r's `91.698238 ms`.
- [x] Negative mismatch fails closed before graph mutation.
- [x] Local and DGX syntax/style gates pass.
- [x] Ownership scan shows no new direct owning heap/resource APIs.

## Completion Notes

DGX proof:

```text
proof_root=/tmp/cuflye-m5s-proof-20260701T033744Z
golden=tests/golden/cuflye-m5s-read-alignment-session-output-overhead-reduction-dgx-aarch64.json
fixture_count=3546
output_artifact_mode=compact-jsonl-v0
compact_cmp=match
compact_jsonl_bytes=1126769
compact_sha256=2b0371e45c7b6c100c169ffed3829738db93b308f4d5aa55690ddc286f19f2bd
cpu_compact_backend_mean_total_before_json_ms=0.422561
cpu_compact_write_output_ms=3.221193
cpu_compact_per_fixture_files=0
cuda_actual_status=ok
cuda_actual_request_ordinal=2
cuda_actual_arena_cache_hit=true
cuda_actual_backend_mean_total_before_json_ms=0.442834
cuda_actual_write_output_ms=3.975386
cuda_actual_request_total_ms=4.450572
cuda_actual_per_fixture_files=0
m5r_full3546_cuda_session_request_total_ms=91.698238
cuda_compact_request_total_speedup_vs_m5r=20.603697x
negative_fault=compact_output_only_without_compact_output_jsonl
negative_status=error
negative_worker_exit_code=1
negative_error=read-alignment worker compact_output_only requires compact_output_jsonl
```

Allowed M5s claim:

```text
cuFlye can run the full3546 read-alignment pre-divergence CUDA session request
in compact-output mode, produce a single deterministic compact JSONL artifact
that byte-matches the CPU compact oracle, and reduce full3546 session request
time by removing per-fixture TSV emission.
```

Forbidden M5s claim:

```text
M5s does not prove default GPU mode, full Flye acceleration, broad
_readAlignments replacement, CUDA minimizer overlap discovery, or replacement
of Flye's CPU divergence/base-alignment stages. The compact JSONL write still
dominates request time, and this single-run M5s measurement does not show a
CUDA backend speedup over the CPU compact backend.
```

Plain-language benefit:

```text
M5s removes the wrong kind of output work. The CUDA session no longer writes
thousands of tiny per-fixture TSV files just to prove equivalence. On the same
3546-fixture proof, request time drops from M5r's 91.698238 ms to 4.450572 ms
while CPU and CUDA compact artifacts are byte-identical. The remaining blocker
is now much smaller and clearer: a 1.1 MB JSONL write still costs about 4 ms.
```

Next highest-ROI task:

```text
M5t: replace the compact JSONL proof payload with a smaller graph-facing binary
or object-vector payload, then validate and rehydrate it before graph mutation
while measuring whether payload write/read cost falls below M5s.
```
