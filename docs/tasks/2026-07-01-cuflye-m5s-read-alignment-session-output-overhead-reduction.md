# Task Card: cuFlye M5s Read Alignment Session Output Overhead Reduction

Status: proposed

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

- [ ] Patch series applies and patched Flye builds on DGX.
- [ ] CUDA worker builds on DGX.
- [ ] Compact output preserves exact canonical CPU equivalence.
- [ ] Full3546 request time improves versus M5r's `91.698238 ms`.
- [ ] Negative mismatch fails closed before graph mutation.
- [ ] Local and DGX syntax/style gates pass.
- [ ] Ownership scan shows no new direct owning heap/resource APIs.

## Completion Notes

Pending implementation.
