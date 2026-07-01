# Task Card: cuFlye M5w Read Alignment Compact Binary Substitution Scale-Up

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Scale the M5v compact-binary vector-substitution proof from the selected
batch64 smoke to the broader full3546 selected read-alignment fixture set.

The core question for this card is:

```text
Can the guarded compact-binary CUDA read-alignment substitution path consume a
large selected set inside Flye, preserve exact artifacts, and keep the CUDA
integration path competitive when the fixed session overhead is amortized?
```

## In Scope

- Reuse the M5v compact-binary substitution seam without changing default
  behavior.
- Select the full3546 valid read-alignment fixture set harvested in M5h/M5t.
- Preserve exact canonical Flye artifacts versus CPU.
- Measure worker timing, Flye seam wall timing, compact binary size, and
  substitution count against M5u/M5v batch64 and M5t full3546 session payload
  evidence.
- Add mismatch or corruption negative proof with the scale-up configuration.

## Out of Scope

- No default GPU mode.
- No unbounded non-allowlisted `_readAlignments` replacement.
- No CUDA minimizer overlap discovery.
- No replacement of Flye's CPU divergence/base-alignment stages.
- No whole-Flye speed claim unless canonical artifacts match and timing evidence
  covers the broader selected path.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Keep Flye patches C++11-compatible and narrow.
- Prefer runner/proof tooling and env selection over broad code changes.
- Unsupported shapes and corrupted payloads must fail closed.

## Deliverables

- Full3546 selected-query proof runner or documented command.
- Positive DGX proof preserving exact artifacts and reporting substituted-chain
  counts.
- Negative DGX proof that blocks substitution before graph mutation.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with timing and benefit assessment.

## Acceptance Gates

- [x] Patch series applies and patched Flye builds on DGX.
- [x] CUDA worker builds on DGX.
- [x] Positive full3546 selected substitution validates compact binary and
      reports substitution consumption for all selected chains present in
      `_readAlignments`.
- [x] Canonical Flye artifacts match CPU.
- [x] Negative mismatch/corruption case fails closed before graph mutation.
- [x] Timing summary separates CUDA request time, Flye session wall time, and
      full Flye elapsed time.
- [x] Local and DGX syntax/style gates pass.

## Completion Notes

Accepted on DGX with proof root:

```text
/tmp/cuflye-m5w-proof-20260701T043703Z
```

Positive full3546 substitution proof:

```text
fixture_count=3546
matched_fixture_count=3546
mismatched_fixture_count=0
total_worker_records=3616
total_substituted_chains=3546
graph_mutation_consumed_worker_output=true
canonical_diff=match
compact_binary_bytes=332736
compact_binary_sha256=daaaf20276447d1e3656b36beb9f8ca21b9673cb99372b66521e7ccf2af8d4df
worker_actual_wall_ms=4.162895
worker_request_total_ms=2.263903
worker_kernel_ms=0.041136
full_flye_elapsed_seconds=20.765673444
```

Negative truncation proof:

```text
proof_fault=truncate-compact-binary-payload
status=failed
decision=failed-closed-before-graph-mutation
flye_exit_status=1
graph_mutation_consumed_worker_output=false
total_worker_records=0
total_substituted_chains=0
worker_actual_wall_ms=4.150512
worker_request_total_ms=1.519952
full_flye_elapsed_seconds=14.521368179
```

Golden manifest:

```text
tests/golden/cuflye-m5w-read-alignment-compact-binary-substitution-scaleup-dgx-aarch64.json
```

Plain-language benefit:

```text
M5w proves the compact-binary GPU path scales from a 64-read smoke to the
full3546 selected fixture set inside Flye. All selected chains are replaced by
verified CUDA-derived goodChains, the final assembly artifacts still match CPU
exactly, and corrupted payloads stop before graph mutation. The direct speed
benefit is still limited because this seam intentionally keeps CPU goodChains
as the live verifier; the value is that the GPU payload and substitution path
now work at the full selected scale, which makes CPU-bypass the next meaningful
performance step.
```
