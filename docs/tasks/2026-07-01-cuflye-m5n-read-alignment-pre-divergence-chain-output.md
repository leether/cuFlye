# Task Card: cuFlye M5n Read Alignment Pre-Divergence Chain Output

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Decouple the CUDA read-alignment chain replay worker from CPU-generated
divergence acceptance rows. M5m proved that CUDA-derived `GraphAlignment`
objects can be consumed by Flye after CPU oracle generation. M5n must prove the
CUDA worker can emit the pre-divergence chain DP result from only the
`edge-overlaps.tsv` input pack and fixture manifest.

The core question this card must answer is:

```text
Can CUDA produce the same pre-divergence read-alignment chains as the CPU replay
without reading CPU chain-divergence acceptance rows?
```

## In Scope

- Add an explicit `--emit-pre-divergence-chains` worker mode.
- Keep default worker behavior unchanged.
- Support the mode for single-fixture CPU and CUDA backends.
- Reject the mode in batch/persistent paths until separately verified.
- Allow the mode to run when `chain-divergence.tsv` is absent.
- Compare CPU and CUDA pre-divergence outputs on a real DGX fixture.
- Record compact DGX proof under `tests/golden/`.

## Out of Scope

- No Flye graph mutation consumption change.
- No default GPU mode.
- No batch/persistent pre-divergence mode yet.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib replacement.
- No whole-Flye speed claim.

## C++/CUDA Style Constraints

- Keep standalone CUDA code CUDA C++14.
- Reuse existing move-only RAII helpers for CUDA allocations.
- Do not introduce direct `cudaMalloc`, `cudaFree`, direct owning `new` or
  `delete`, or direct `malloc`/`free`.
- Keep unsupported modes fail-closed.
- Do not silently fall back from CUDA to CPU.

## Deliverables

- Worker CLI flag and JSON output mode for pre-divergence chains.
- ABI note describing the no-divergence input contract.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with scoped benefit and next step.
- Plain-language CUDA benefit assessment.

## Acceptance Gates

- [x] CUDA read-alignment replay binary builds on DGX.
- [x] CPU backend runs with `--emit-pre-divergence-chains` on a fixture without
      `chain-divergence.tsv`.
- [x] CUDA backend runs with `--emit-pre-divergence-chains` on the same fixture
      without `chain-divergence.tsv`.
- [x] CPU and CUDA pre-divergence outputs canonical-diff as `match`.
- [x] JSON records `output_mode=pre-divergence-chains` and
      `uses_fixture_divergence_acceptance=false`.
- [x] Batch mode rejects `--emit-pre-divergence-chains` fail-closed.
- [x] Local syntax/style gates pass.
- [x] CUDA ownership scan shows no new direct resource APIs outside RAII
      wrappers.

## Completion Notes

Accepted with DGX proof:

- Proof root:
  `/tmp/cuflye-m5n-proof-20260701T015602Z`
- Golden manifest:
  `tests/golden/cuflye-m5n-read-alignment-pre-divergence-chain-output-dgx-aarch64.json`
- Host: `edgexpert-45d2`, `aarch64`, GPU `NVIDIA GB10`, CUDA arch `sm_121`.
- Fixture source:
  `/tmp/cuflye-m5h-proof-20260630T234728Z/out/m5h/runs/toy-hifi-wide-read-alignment/read-alignment-replay-fixtures/query_3512`
- Proof fixture:
  `query_3512_no_divergence`, with `chain-divergence.tsv` and
  `oracle.read-alignment.tsv` removed.
- CPU pre-divergence output: `3` records,
  `uses_fixture_divergence_acceptance=false`.
- CUDA pre-divergence output: `3` records,
  `uses_fixture_divergence_acceptance=false`.
- CPU/CUDA pre-divergence canonical diff: `match`,
  SHA-256 `c817d867dfa173d28f76ebe9b19274e2d54db650ed87fa5bc3811a17a1e3e67f`.
- Negative batch gate:
  `--emit-pre-divergence-chains is only supported in single-fixture mode`.

Plain-language result:

```text
M5n is not a full-Flye speed win. It proves the CUDA chain DP worker no longer
needs CPU divergence-acceptance rows to produce pre-divergence chain output.
On this tiny single fixture, CUDA total time is slower than CPU, but the
protocol dependency that blocked future selected-read GPU-first chaining is
removed.
```

Allowed M5n claim:

```text
cuFlye can run the read-alignment chain DP replay on CUDA without depending on
CPU-generated divergence acceptance rows, producing the same pre-divergence
chain output as the CPU replay for a real fixture.
```

Forbidden M5n claim:

```text
M5n does not prove Flye graph-facing consumption of pre-divergence CUDA output,
default GPU mode, CUDA minimizer overlap discovery, CPU divergence replacement,
or end-to-end Flye acceleration.
```
