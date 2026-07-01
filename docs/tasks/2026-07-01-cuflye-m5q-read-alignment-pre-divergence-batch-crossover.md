# Task Card: cuFlye M5q Read Alignment Pre-Divergence Batch Crossover

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Use the M5p batch dry-run seam to find the selected-read batch size and shape
mix where CUDA pre-divergence chain generation is meaningfully better than the
CPU replay baseline after accounting for worker setup, output copy, and Flye
integration overhead.

The core question this card must answer is:

```text
How large must the selected read-alignment batch be before the CUDA path's core
speed can overcome process/CUDA setup overhead, and what is the next engineering
target if it cannot?
```

## In Scope

- Reuse the M5p `batch-dry-run-v0` Flye seam.
- Build larger deterministic selected-read allowlists from existing toy-hifi or
  harvested M5h fixtures.
- Compare CUDA batch timing against CPU pre-divergence replay timing for the
  same fixture set.
- Preserve exact canonical Flye artifacts against CPU baseline for any Flye-side
  positive run.
- Record whether `setup`, `kernel`, `device_to_host`, `write_output`, or Flye
  integration wall time dominates.

## Out of Scope

- No default GPU mode.
- No `_readAlignments` replacement from pre-divergence output.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib replacement.
- No production speedup claim unless measured proof demonstrates it.

## C++/CUDA Style Constraints

- Prefer scripts/proof harness changes before new C++ code.
- If C++ changes are needed, keep Flye patches C++11-compatible.
- Follow `docs/CODING_STYLE.md` ownership rules.
- Do not introduce direct owning `new` or `delete`, `malloc`/`free`, or direct
  CUDA resource ownership.
- CUDA paths must fail closed on unsupported shapes.

## Deliverables

- Deterministic selected-read batch/crossover proof script or documented command
  sequence.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with measured crossover or blocker.
- Plain-language CUDA benefit assessment.

## Acceptance Gates

- [x] Patch series applies and patched Flye builds on DGX.
- [x] CUDA read-alignment replay binary builds on DGX.
- [x] At least one larger selected-read batch positive run passes M5p per-query
      goodChain checks.
- [x] Positive run preserves exact canonical Flye artifacts versus CPU.
- [x] CPU and CUDA pre-divergence replay timing are measured on the same fixture
      list.
- [x] Timing report separates setup, CUDA core, output copy, write output, and
      Flye integration wall time.
- [x] Local syntax/style gates pass.
- [x] C++/CUDA ownership scan shows no new direct owning heap APIs.

## Completion Notes

Accepted with DGX proof:

```text
tests/golden/cuflye-m5q-read-alignment-pre-divergence-batch-crossover-dgx-aarch64.json
proof_root=/tmp/cuflye-m5q-proof-20260701T025345Z
host=edgexpert-45d2
fixture_list=/tmp/cuflye-m5h-proof-20260630T234728Z/out/m5h/larger-batch/selected-fixtures.list
cold_batch_sizes=16,64,256,1024,3546
cold_outputs_match_cpu=true
full_batch_cold_cpu_ms=0.402465
full_batch_cold_cuda_persistent_bulk_single_invocation_ms=247.104709
full_batch_warm_cpu_ms=0.324878
full_batch_warm_cuda_persistent_bulk_ms=0.300236
full_batch_warm_cuda_hot_path_speedup_vs_cpu=1.082075
full_batch_warm_cuda_single_invocation_ms=249.070891
single_invocation_crossover_batch_size=null
flye_positive_selected_query_count=64
flye_positive_matched_fixture_count=64
flye_positive_canonical_diff=match
flye_positive_worker_wall_ms=435.505899
graph_mutation_consumed_worker_output=false
```

Allowed M5q claim:

```text
On the M5h 3546-fixture selected read-alignment replay set, a warmed
persistent-bulk CUDA pre-divergence hot path is slightly faster than CPU before
JSON/TSV emission, while all CUDA outputs match CPU and a Flye-side 64-read
batch dry-run preserves exact artifacts.
```

Forbidden M5q claim:

```text
M5q must not claim full Flye acceleration unless the measured Flye-side run
demonstrates it against a CPU baseline with unchanged artifacts.
```

Plain-language benefit:

```text
M5q found the boundary: CUDA can beat CPU only after the CUDA context and
persistent arena are already warm. At the full 3546-fixture replay batch, warm
persistent-bulk CUDA was 0.300236 ms versus CPU 0.324878 ms, a 1.082x hot-path
speedup. But Flye currently launches a fresh worker, and setup dominates: the
same full batch costs about 249.07 ms as a single persistent-bulk invocation.
So this is a real kernel/backend win trapped behind worker/context setup, not a
Flye integration speedup yet.
```

Next highest-ROI task:

```text
M5r: replace the Flye-side pre-divergence batch worker process with a
long-lived session/persistent worker proof so selected batches can reuse CUDA
context and arena across Flye calls, then re-measure batch64 and larger
selected-read integration timing.
```
