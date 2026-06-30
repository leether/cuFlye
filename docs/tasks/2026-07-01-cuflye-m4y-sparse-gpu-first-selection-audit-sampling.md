# Task Card: cuFlye M4y Sparse GPU-First Selection and Audit Sampling

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Reduce GPU-first proof overhead and broaden selection from a single cached
query to a bounded set of supported overlap calls, without weakening the
fail-closed audit contract.

## Background

M4x proved that `gpu-first-supported-v0` can return a verified cached CUDA
worker `OverlapRange` vector before live CPU overlap for one allowlisted query.
The positive run preserved exact Flye artifacts but still took `84s` versus
`72s` for CPU. The selected ledger also recorded every non-selected decision,
creating thousands of JSONL lines for a proof that only needed selected seam
events.

## In Scope

- Add an explicit selected-only substitution ledger mode for sparse proof runs.
- Keep full ledger output as the default for existing session proofs.
- Add GPU-first audit query-id sampling so audit cost can be bounded.
- Fail closed if an audit query allowlist is provided without an audit mode.
- Expand DGX proof selection to a bounded high-cost supported query set.
- Preserve exact artifact diff against CPU for toy-raw proof runs.

## Out of Scope

- No default GPU mode.
- No broad unsupported-shape substitution.
- No graph algorithm rewrite.
- No removal of CPU oracle proof paths.
- No claim of whole-Flye speedup unless the DGX wall-time proof shows it.

## Acceptance Gates

- [x] Patch series applies and builds through the M4y patch.
- [x] `selected-only-v0` ledger mode suppresses non-selected skip rows while
      preserving selected, cached, and fail-closed rows.
- [x] GPU-first audit sampling fails closed on a forced mismatch for an audited
      query.
- [x] Positive toy-raw artifacts still match CPU.
- [x] DGX proof uses a bounded multi-query GPU-first selection set.
- [x] Local and DGX syntax/style/ownership gates pass.
- [x] Plain-language benefit assessment states whether wall time improved and
      why.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- No raw owning pointers in cuFlye seam code.
- Keep every new mode explicit, opt-in, and validated during startup.
- Keep GPU-first state auditable in ledger and seam summary.
- Keep unsupported or unaudited shapes fail-closed.

## Deliverables

- Flye seam implementation behind explicit sparse-ledger and audit-sampling
  environment variables.
- Runner-script flags and metadata fields for the new modes.
- ABI documentation updates for ledger and audit behavior.
- DGX proof manifest with positive and forced-mismatch audit runs.
- Roadmap, Task Card, golden index, and plain-language benefit assessment.

## Completion Notes

DGX proof:
`tests/golden/cuflye-m4y-sparse-gpu-first-selection-audit-sampling-dgx-aarch64.json`

Remote proof directory:
`/tmp/cuflye-m4y-proof-20260630T212731Z`

The first 8-query candidate set included `798`, but the worker validation gate
rejected it fail-closed:

```text
query_798 oracle_records=49 worker_records=48 canonical_diff_status=mismatch
```

The accepted positive proof used a bounded 7-query allowlist:

```text
161,554,89,112,896,110,752
```

The positive run used `gpu-first-supported-v0`,
`session-file-v0`, and `selected-only-v0`. It preserved exact toy-raw Flye
artifacts against CPU:

```text
Flye run diff: match
```

Selected-only ledger evidence:

```text
entries=35
non_selected_entries=0
deferred-session-batch-waiting=7
substituted-from-session-batch-run=1
gpu-first-from-session-batch-cache=6
skipped-already-substituted=21
```

The audit negative used `CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE=oracle-file-v0`,
`CUFLYE_OVERLAP_GPU_FIRST_AUDIT_QUERY_IDS=161`, and
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-gpu-first-overlap`.
Non-audited GPU-first cache hits were accepted first; the audited `161` reuse
then failed closed:

```text
status=gpu-first-substitution-failed-before-live-cpu-overlap
error=gpu-first audit object vector differs from captured CPU oracle
proof_fault_applied=true
graph_mutation_consumed_worker_output=false
```

Plain-language assessment: M4y moves from one GPU-first reuse to a bounded
multi-query proof. It produced 6 GPU-first cache hits with `cpu_overlap_ms=0`
and `worker_process_ms=0`, while keeping exact Flye artifacts. It also reduced
the positive ledger from M4x's 2886-row full ledger pattern to 35 selected
rows, which removes a lot of proof IO/noise. It is still not an end-to-end
speedup: CPU toy-raw took `72s`; M4y positive took `74s`, because most Flye
work remains CPU-bound and the proof still pays session setup, validation, and
instrumentation overhead.
