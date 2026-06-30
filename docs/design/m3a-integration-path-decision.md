# cuFlye M3a Integration Path Decision

Status: accepted

Date: 2026-06-30

## Decision

cuFlye will move from the current one-shot external CUDA adapter to a
long-lived external CUDA worker with a bounded request/response protocol.

The worker path is the next highest-ROI integration step because M2f already
proved that the sparse CUDA candidate backend can beat the CPU oracle at the
candidate-generation boundary. The remaining measured cost is now dominated by
setup and adapter overhead, not by the core candidate kernel.

## Evidence

The M2f DGX proof for query `-253` recorded:

| Metric | Value |
| --- | ---: |
| CPU oracle candidate generation | `943.032 ms` |
| GPU-only backend total before JSON | `425.540 ms` |
| GPU-only vs CPU oracle speedup | `2.22x` |
| CUDA kernel | `6.361 ms` |
| CUDA setup | `298.595 ms` |
| Host prefix sum | `83.331 ms` |
| Candidate records | `15571` |
| Pair comparisons | `51742433` |
| Device allocation | `260459496` bytes |
| Flye adapter controlled-stop wall time | `0:03.34` |

The correctness proof also recorded CPU/GPU/adapter candidate diffs as `match`
with canonical SHA-256
`5b50c458d82458516662e59daf3638e3534896a3ab1e77791f46dc54b663a1ae`.

## BDI Calibration

Beliefs:

- Flye's scientific contract is exact candidate equivalence first, speed claim
  second.
- M2f's speedup is real at the candidate boundary, but the project still has no
  downstream repeat-graph equivalence proof.
- The CUDA setup cost is large enough that a one-shot process model can erase
  much of the kernel advantage when repeated per query.
- Linking CUDA directly into Flye now would increase review, build, deployment,
  and failure-surface risk before the multi-query backend contract is mature.

Desire:

- Make a CUDA-enabled Flye path that can be shared publicly without silently
  changing Flye behavior.

Intention:

- Preserve the CPU oracle gates.
- Keep the Flye patch small.
- Amortize CUDA setup by keeping a worker process alive.
- Measure first-request and warm-request timings before considering in-process
  CUDA.

## Options

### In-Process CUDA

This is the lowest-overhead end state in theory. It could eventually avoid
process boundaries and file-backed transfer paths.

It is not the next step because it would link CUDA runtime behavior into Flye's
process before the backend contract has proven multi-query stability. It also
raises upstream compatibility concerns because Flye patches must remain
C++11-compatible and easy to review.

Decision: defer.

### Long-Lived External Worker

The worker keeps CUDA state warm across requests, so the M2f setup cost can be
amortized. It preserves the current fail-closed process boundary and lets Flye
send bounded candidate-backend requests without linking CUDA directly.

This path also gives clean checkpoints for measurement:

- cold worker startup;
- first request with CUDA context setup;
- warm request after context reuse;
- batch request across multiple query packs;
- exact candidate diff after every request.

Decision: choose for M3b.

### Batched External Adapter

A batched adapter is easy to add on top of the existing one-shot command shape,
but it is still fragile if every batch starts a new process. It is useful as a
compatibility bridge, not as the main architecture.

Decision: keep as a fallback interface shape inside the worker protocol.

### Device-Side Prefix/Compaction First

The M2f host prefix sum cost is measurable at `83.331 ms`. Moving prefix and
compaction fully to device-side code is likely useful later.

It is not the highest-ROI immediate step because CUDA setup alone is about
`298.595 ms`, larger than the host prefix sum. Worker reuse can reduce a larger
cost without changing candidate semantics.

Decision: defer until M3b/M3c worker timings show the remaining bottleneck.

## Architecture Shape

The M3 worker boundary should look like this:

```text
Flye candidate seam
  -> bounded request JSON
  -> long-lived cuflye-cuda-worker
  -> sparse CUDA candidate backend
  -> candidate-record-v1 TSV plus response JSON
  -> Flye parser and fail-closed validation
```

The worker must support one real `pack-dump-v0` request shape first. The M3b
proof must run at least two requests in one worker process so warm CUDA context
reuse is actually measured. Broader batching across many distinct Flye query
packs comes after that proof.

## Self-Consistency Check

This decision is self-consistent with the project goals because:

- It attacks the largest measured overhead before redesigning the Flye patch.
- It keeps correctness gates identical to M2f.
- It avoids overstating the claim: M3 remains a candidate-backend milestone, not
  full GPU Flye mode.
- It leaves a clean path to in-process CUDA later if the worker boundary becomes
  the limiting cost.
- It keeps C++ ownership and CUDA resource rules enforceable at a narrow worker
  code boundary.

## Next Milestone

M3b should build a minimal `cuflye-cuda-worker` that:

- starts once and initializes the selected CUDA device;
- accepts `cuflye-worker-request-v0`;
- processes at least two M2b/M2f real pack requests in one worker process for
  the proof run;
- emits `candidate-record-v1` plus `cuflye-worker-response-v0`;
- reports cold-start, first-request, and warm-request timing fields;
- fails closed on unsupported request shapes;
- passes the same candidate diff gate as M2f.
