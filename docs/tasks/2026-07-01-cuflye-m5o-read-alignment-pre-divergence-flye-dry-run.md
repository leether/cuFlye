# Task Card: cuFlye M5o Read Alignment Pre-Divergence Flye Dry Run

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Wire the M5n pre-divergence CUDA chain output into Flye's read-alignment loop
as a selected-read dry run. Flye should invoke the CUDA worker for allowlisted
reads, rehydrate the pre-divergence chains into `GraphAlignment` objects, run
Flye's existing divergence filtering on those GPU-produced chains, and compare
the resulting `goodChains` with the CPU `goodChains`.

The core question this card must answer is:

```text
Can Flye compute divergence/filtering on CUDA-produced pre-divergence chains
and recover the same selected-read goodChains as CPU chainReadAlignments?
```

## In Scope

- Add opt-in
  `CUFLYE_READ_ALIGNMENT_PREDIVERGENCE_CHAIN_MODE=selected-read-dry-run-v0`.
- Require replay fixture dumping and selected query ids.
- Invoke the read-alignment worker with `--emit-pre-divergence-chains` for each
  selected read after Flye writes that read's edge-overlap fixture.
- Rehydrate worker `read-alignment.tsv` into `std::vector<GraphAlignment>`.
- Reuse Flye's existing `getChainBaseDivergence` for GPU-produced chains.
- Compare GPU-filtered good chains against CPU good chains.
- Write one per-query `read-alignment-predivergence-dry-run.json`.
- Fail closed on mismatch before repeat-graph mutation.

## Out of Scope

- No default GPU mode.
- No `_readAlignments` substitution in this card.
- No batch or persistent pre-divergence worker invocation from Flye.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib replacement.
- No end-to-end Flye acceleration claim.

## C++/CUDA Style Constraints

- Keep the Flye patch C++11-compatible.
- Reuse existing TSV readers, rehydration helpers, and JSON helpers.
- Do not introduce direct owning `new` or `delete`, `malloc`/`free`, or direct
  CUDA resource ownership in Flye code.
- Keep unsupported modes fail-closed.
- Do not silently fall back from CUDA to CPU.

## Deliverables

- `0032` Flye patch adding the pre-divergence dry-run seam.
- Runner env/CLI flags for the mode and proof fault.
- ABI note for Flye-side pre-divergence dry run.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with scoped benefit and next step.
- Plain-language CUDA benefit assessment.

## Acceptance Gates

- [x] Patch series applies through `0032` and patched Flye builds on DGX.
- [x] CUDA read-alignment replay binary builds on DGX.
- [x] Positive selected-read run invokes the worker with
      `--emit-pre-divergence-chains`.
- [x] Positive run records pre-divergence dry-run `status=passed`.
- [x] Positive run records CPU and GPU filtered good-chain outputs matching.
- [x] Positive run records no `_readAlignments` substitution and no graph
      mutation consumption from this dry-run seam.
- [x] Negative proof fault fails closed after worker output is produced.
- [x] Local syntax/style gates pass.
- [x] C++ ownership scan shows no new direct owning heap APIs.

## Completion Notes

Accepted with DGX proof:
`tests/golden/cuflye-m5o-read-alignment-pre-divergence-flye-dry-run-dgx-aarch64.json`

DGX proof:

```text
proof_root=/tmp/cuflye-m5o-proof-20260701T021134Z
query_id=3512
positive_status=passed
positive_cpu_predivergence_chains=1
positive_gpu_predivergence_chains=1
positive_cpu_good_records=3
positive_gpu_good_records=3
positive_canonical_diff=match
negative_fault=drop-first-gpu-good-chain
negative_exit_status=1
negative_failed_closed=true
negative_worker_exit_status=0
negative_worker_tsv_readable=true
graph_mutation_consumed_worker_output=false
```

The positive proof ran a CPU baseline and an M5o selected-read dry run, then
canonical-diffed Flye artifacts. All nine tracked artifacts matched. The
negative proof ran the same selected read with
`drop-first-gpu-good-chain`; the worker still wrote TSV output, then Flye
failed closed before consuming worker output for graph mutation.

Allowed M5o claim:

```text
cuFlye can invoke CUDA pre-divergence read-alignment chain output from inside
Flye, run Flye's existing divergence filter on the GPU-produced chains, and
prove the resulting goodChains match the CPU selected-read goodChains.
```

Forbidden M5o claim:

```text
M5o does not prove default GPU mode, _readAlignments substitution from
pre-divergence output, CUDA minimizer overlap discovery, CPU divergence
replacement, or end-to-end Flye acceleration.
```
