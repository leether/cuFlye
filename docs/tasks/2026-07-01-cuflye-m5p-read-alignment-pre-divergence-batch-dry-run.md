# Task Card: cuFlye M5p Read Alignment Pre-Divergence Batch Dry Run

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Reduce the M5o per-selected-read worker process overhead by moving CUDA
pre-divergence read-alignment chain output to a batch or persistent dry-run
seam. The milestone should keep Flye artifacts unchanged while proving that a
supported selected-read batch can produce the same post-divergence `goodChains`
as CPU after Flye applies its existing divergence filter.

The core question this card must answer is:

```text
Can the M5o pre-divergence Flye dry-run boundary be batched or kept warm so the
integration path becomes cheaper than per-read process startup?
```

## In Scope

- Add an opt-in batch or persistent mode for pre-divergence chain output.
- Keep unsupported shapes fail-closed.
- Reuse the M5o selected-read audit JSON fields where possible.
- Compare GPU-produced, Flye-filtered goodChains against CPU goodChains for
  every selected read.
- Preserve exact canonical Flye artifacts against a CPU baseline.
- Record timing that separates worker process/session overhead from CUDA core
  and output materialization.

## Out of Scope

- No default GPU mode.
- No broad `_readAlignments` replacement unless a separate verified gate is
  defined in a later card.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib replacement.
- No end-to-end acceleration claim unless measured proof shows it.

## C++/CUDA Style Constraints

- Keep Flye patch C++11-compatible.
- Follow `docs/CODING_STYLE.md` ownership rules.
- Do not introduce direct owning `new` or `delete`, `malloc`/`free`, or direct
  CUDA resource ownership in Flye code.
- Keep worker resource ownership inside existing RAII wrappers.
- Do not silently fall back from CUDA to CPU.

## Deliverables

- Task-specific ABI note if the batch/persistent contract differs from M5o.
- CUDA worker support for the selected batch/persistent pre-divergence mode.
- Flye-side guarded dry-run seam or worker adapter changes.
- Runner flags and metadata for the new mode.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with scoped benefit and next step.
- Plain-language CUDA benefit assessment.

## Acceptance Gates

- [x] Patch series applies and patched Flye builds on DGX.
- [x] CUDA read-alignment replay binary builds on DGX.
- [x] Positive selected-read batch invokes CUDA pre-divergence chain output.
- [x] Positive run records per-query post-divergence goodChain matches.
- [x] Positive run preserves exact canonical Flye artifacts versus CPU.
- [x] Timing separates process/session overhead, CUDA core, and output copy.
- [x] Negative mismatch or unsupported-shape proof fails closed.
- [x] Local syntax/style gates pass.
- [x] C++/CUDA ownership scan shows no new direct owning heap APIs.

## Completion Notes

Accepted with DGX proof:

```text
tests/golden/cuflye-m5p-read-alignment-pre-divergence-batch-dry-run-dgx-aarch64.json
proof_root=/tmp/cuflye-m5p-proof-20260701T023808Z
host=edgexpert-45d2
arch=aarch64
cuda_arch=sm_121
positive_query_ids=5,47,200,204,3512
positive_status=passed
positive_fixture_count=5
positive_matched_fixture_count=5
positive_total_cpu_good_records=10
positive_total_gpu_good_records=10
positive_canonical_diff=match
positive_worker_wall_ms=446.799500
worker_setup_ms=313.588244
worker_kernel_ms=0.148640
worker_device_to_host_ms=0.074208
worker_write_output_ms=0.298688
negative_fault=drop-first-gpu-good-chain
negative_exit_status=1
negative_worker_exit_status=0
negative_matched_fixture_count=4
negative_mismatched_fixture_count=1
negative_failed_closed=true
graph_mutation_consumed_worker_output=false
```

Allowed M5p claim:

```text
cuFlye can batch selected Flye read-alignment pre-divergence CUDA chain output
into one worker invocation, let Flye apply its existing divergence filtering per
query, recover the same CPU goodChains for every selected query, preserve exact
canonical artifacts, and fail closed on mismatch.
```

Forbidden M5p claim:

```text
M5p does not prove default GPU mode, broad _readAlignments replacement, CUDA
minimizer overlap discovery, CPU divergence replacement, or end-to-end Flye
acceleration unless the measured proof explicitly demonstrates it.
```

Plain-language benefit:

```text
M5p is not a full-Flye speed win. It is an integration-overhead win over M5o:
five selected reads now use one CUDA worker process and one batch audit instead
of one worker process per read. On the tiny toy batch, CUDA setup still
dominates wall time, so the next ROI is a larger-batch crossover proof or a
setup/context overhead reduction.
```
