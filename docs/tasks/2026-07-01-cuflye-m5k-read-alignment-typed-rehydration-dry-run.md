# Task Card: cuFlye M5k Read Alignment Typed Rehydration Dry Run

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Convert validated CUDA read-alignment worker TSV rows back into a Flye-side
GraphAlignment-shaped typed representation, without replacing `_readAlignments`
or feeding CUDA output into graph mutation.

The core question this card must answer is:

```text
Can validated CUDA read-alignment rows survive Flye-side type conversion,
current-graph edge lookup, chain segment validation, and canonical comparison
against the CPU oracle while still staying not-consumed?
```

## Background

M5j moved the M5i CUDA read-alignment replay worker inside a real Flye run. It
validated worker TSV against CPU oracle TSV and wrote a graph guard, but the
boundary was still a file comparison.

M5k moves one step closer to a real consumption path. It proves that worker TSV
can be represented in Flye's read-alignment types: `FastaRecord::Id`,
`OverlapRange`, and `GraphEdge*` inside an `EdgeAlignment`-shaped segment.

## In Scope

- Add a Flye patch for
  `CUFLYE_READ_ALIGNMENT_REHYDRATION_MODE=typed-graph-alignment-v0`.
- Parse worker `read-alignment-v1` TSV into checked Flye-side typed records.
- Resolve each `edge_id` against the current `RepeatGraph`.
- Validate non-negative chain ids and contiguous segment ids per chain.
- Canonicalize typed records back to read-alignment fields and compare with
  the CPU oracle TSV.
- Write `read-alignment-worker-rehydration.json`.
- Extend `read-alignment-seam-summary.json` with rehydration status fields.
- Add runner flags for rehydration mode and proof fault.
- Prove positive and negative behavior on DGX.

## Out of Scope

- No replacement of Flye `_readAlignments`.
- No graph mutation consumption.
- No default GPU mode.
- No end-to-end Flye acceleration claim.
- No long-lived read-alignment worker protocol yet.
- No full base-alignment replay beyond the existing recorded fixture oracle.

## C++/CUDA Style Constraints

- Keep Flye patch code compatible with Flye 2.9.6's C++ standard.
- Do not introduce direct owning `new`, `delete`, `malloc`, or `free`.
- Use stack values, STL containers, checked conversions, and file RAII.
- Every explicit CUDA/read-alignment seam must fail closed.
- Every path written by the seam must be recorded in JSON metadata.
- Do not silently fall back from CUDA to CPU.

## Deliverables

- `patches/flye/2.9.6/0029-cuflye-read-alignment-typed-rehydration-dry-run.patch`
- `docs/abi/read-alignment-typed-rehydration-dry-run-v0.md`
- runner support for read-alignment rehydration env vars
- DGX proof manifest under `tests/golden/`
- Roadmap and golden index updates
- Plain-language CUDA benefit assessment

## Acceptance Gates

- [x] Patch series applies through `0029` and patched Flye builds on DGX.
- [x] CUDA read-alignment replay binary builds on DGX.
- [x] Positive dry-run invokes the CUDA worker from Flye.
- [x] Positive dry-run validates every worker output against CPU oracle TSV.
- [x] Positive dry-run writes graph guard JSON with
      `graph_consumption_state=not-consumed`.
- [x] Positive dry-run writes rehydration JSON with
      `status=passed`, `state=not-consumed`, and
      `typed_representation=typed-graph-alignment-v0`.
- [x] Positive dry-run records
      `graph_mutation_consumed_worker_output=false`.
- [x] Positive dry-run stops before graph mutation.
- [x] Negative proof fault fails closed after validation and graph guard pass.
- [x] Local syntax/style gates pass.
- [x] C++ ownership scan shows no new direct owning heap APIs.

## Completion Notes

Accepted with DGX proof:

- Proof root:
  `/tmp/cuflye-m5k-proof-20260701T005103Z`
- Golden manifest:
  `tests/golden/cuflye-m5k-read-alignment-typed-rehydration-dry-run-dgx-aarch64.json`
- Host: `edgexpert-45d2`, `aarch64`
- Patch series: applied through
  `0029-cuflye-read-alignment-typed-rehydration-dry-run.patch`
- Positive query ids: `5,47,200,204`
- Positive validation: `4/4` worker outputs matched CPU oracle.
- Positive typed rehydration: `status=passed`,
  `typed_representation=typed-graph-alignment-v0`,
  `total_rehydrated_records=7`, `total_rehydrated_chains=4`.
- Positive guard: `status=passed`,
  `graph_consumption_state=not-consumed`,
  `graph_mutation_consumed_worker_output=false`.
- Positive run intentionally exited non-zero with
  `status=stopped-before-graph-mutation`.
- Negative proof fault query ids: `5,47`
- Negative validation and graph guard both passed before proof fault handling.
- Negative proof fault:
  `CUFLYE_READ_ALIGNMENT_REHYDRATION_PROOF_FAULT=drop-first-worker-record`.
- Negative typed rehydration: `status=failed`,
  `state=failed-closed`,
  `decision=failed-closed-before-graph-mutation`.
- Negative run recorded
  `graph_mutation_consumed_worker_output=false`.

Allowed M5k claim:

```text
cuFlye can convert validated CUDA read-alignment output into Flye-side
GraphAlignment-shaped typed records, prove that the typed records still match
the CPU oracle, and still stop before graph mutation.
```

Forbidden M5k claim:

```text
M5k does not prove default GPU mode, replacement of Flye _readAlignments, graph
mutation consumption, or end-to-end Flye acceleration.
```

Plain-language benefit assessment:

```text
This step still does not add a new speed win. The benefit is representation
safety: CUDA read-alignment output now has to fit Flye's typed
GraphAlignment-shaped records and current repeat graph before any later
milestone can consider consuming it.
```
