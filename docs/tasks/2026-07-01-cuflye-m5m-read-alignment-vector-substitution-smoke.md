# Task Card: cuFlye M5m Read Alignment Vector Substitution Smoke

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Use the M5l shadow `std::vector<GraphAlignment>` as a verified substitute for a
small allowlisted slice of Flye's `_readAlignments`, then prove the full Flye
run preserves canonical CPU artifacts or fails closed before graph mutation.

The core question this card must answer is:

```text
Can validated CUDA read-alignment output cross the first real _readAlignments
consumption boundary for selected reads without changing Flye artifacts?
```

## In Scope

- Add opt-in
  `CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_MODE=verified-graph-alignment-v0`.
- Require M5l object-vector rehydration success before substitution.
- Replace only the forward `_readAlignments` chains for selected query ids.
- Preserve complement chains and global chain order.
- Write `read-alignment-vector-substitution.json`.
- Extend seam summary with substitution status and consumed flags.
- Run a positive full Flye fixture and compare canonical artifacts to CPU.
- Run a negative proof fault that fails closed before graph mutation.

## Out of Scope

- No default GPU mode.
- No broad read-alignment replacement.
- No unsupported-shape substitution.
- No end-to-end speed claim.
- No removal of CPU read-alignment work yet.

## Acceptance Gates

- [x] Patch series applies through `0031` and patched Flye builds on DGX.
- [x] CUDA read-alignment replay binary builds on DGX.
- [x] Positive substitution run completes full Flye.
- [x] Positive run records vector substitution `status=passed` and
      `state=consumed`.
- [x] Positive run records
      `graph_mutation_consumed_worker_output=true`.
- [x] Positive canonical Flye artifacts match a CPU baseline.
- [x] Negative proof fault fails closed after validation, graph guard, typed
      rehydration, and object-vector rehydration pass.
- [x] Negative run records
      `graph_mutation_consumed_worker_output=false`.
- [x] Local syntax/style gates pass.
- [x] C++ ownership scan shows no new direct owning heap APIs.

## Completion Notes

Accepted with DGX proof:

- Proof root:
  `/tmp/cuflye-m5m-proof-20260701T013646Z`
- Golden manifest:
  `tests/golden/cuflye-m5m-read-alignment-vector-substitution-smoke-dgx-aarch64.json`
- Host: `edgexpert-45d2`, `aarch64`, GPU `NVIDIA GB10`, CUDA arch `sm_121`.
- Positive query ids: `5,47,200,204`.
- Positive run completed full Flye with `exit_status=0`.
- Positive vector substitution recorded `status=passed`, `state=consumed`,
  `total_substituted_chains=4`, and
  `graph_mutation_consumed_worker_output=true`.
- CPU baseline versus positive substitution canonical artifact diff:
  `status=match`.
- Negative proof fault:
  `CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-chain`.
  Worker validation, graph guard, typed rehydration, and object-vector
  rehydration passed first; vector substitution failed closed before graph
  mutation with `graph_mutation_consumed_worker_output=false`.

Plain-language result:

```text
M5m is the first read-alignment milestone where verified CUDA-derived output is
actually consumed by Flye's graph-facing _readAlignments vector. It still is not
a speed win because CPU read alignment is still computed first as the oracle.
```

Allowed M5m claim:

```text
cuFlye can substitute a verified CUDA-derived GraphAlignment object vector for a
small selected _readAlignments slice, preserve exact Flye artifacts, and fail
closed on mismatch before graph mutation.
```

Forbidden M5m claim:

```text
M5m does not prove default GPU mode, broad _readAlignments replacement, removal
of CPU read alignment, or end-to-end Flye acceleration.
```
