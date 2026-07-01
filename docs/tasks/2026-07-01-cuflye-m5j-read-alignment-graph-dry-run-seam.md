# Task Card: cuFlye M5j Read Alignment Graph Dry-Run Seam

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Wire the validated M5i persistent CUDA bulk-output read-alignment backend behind
a Flye-side graph-facing dry-run seam.

The core question this card must answer is:

```text
Can Flye invoke the CUDA read-alignment replay backend during a real run,
validate the worker output against the CPU oracle, write graph-consumption guard
metadata, and still stop before graph mutation?
```

## Background

M5i proved that the bounded M5h read-alignment replay harvest can run faster on
CUDA than the CPU replay baseline before TSV/JSON emission while preserving
every per-read oracle diff. That proof was still outside Flye's graph-facing
runtime path.

M5j moves the proof boundary into Flye without consuming GPU output. It should
behave like the M4o overlap graph guard: explicit, auditable, fail-closed, and
no mutation.

## In Scope

- Add a Flye patch that enables an explicit read-alignment worker dry-run seam.
- Reuse existing read-alignment replay fixture dumps as the worker input.
- Invoke `cuflye-cuda-read-alignment-chain-replay` in batch mode with
  `--cuda-persistent-arena --cuda-persistent-bulk-output`.
- Validate every worker output against each fixture's
  `oracle.read-alignment.tsv` before marking the worker output eligible.
- Write read-alignment worker validation, graph guard, and seam summary JSON.
- Stop before graph mutation and record
  `graph_mutation_consumed_worker_output=false`.
- Add runner flags for the new environment variables.
- Prove positive and negative behavior on DGX.

## Out of Scope

- No replacement of Flye `_readAlignments`.
- No graph mutation consumption.
- No default GPU mode.
- No edlib/base realignment replay beyond recorded divergence acceptance flags.
- No end-to-end Flye acceleration claim.
- No long-lived read-alignment worker protocol yet.

## C++/CUDA Style Constraints

- Keep Flye patch code compatible with Flye 2.9.6's C++ standard.
- Do not introduce direct owning `new`, `delete`, `malloc`, or `free`.
- Use stack values, STL containers, and file RAII.
- Every external worker command must be explicit and fail closed.
- Every path written by the seam must be recorded in JSON metadata.
- Do not silently fall back from CUDA to CPU.

## Deliverables

- `patches/flye/2.9.6/0028-cuflye-read-alignment-graph-dry-run-seam.patch`
- `docs/abi/read-alignment-graph-dry-run-seam-v0.md`
- runner support for read-alignment worker dry-run env vars
- DGX proof manifest under `tests/golden/`
- Roadmap and golden index updates
- Plain-language CUDA benefit assessment

## Acceptance Gates

- [x] Patch series applies through `0028` and patched Flye builds on DGX.
- [x] CUDA read-alignment replay binary builds on DGX.
- [x] Positive dry-run invokes the CUDA worker from Flye.
- [x] Positive dry-run validates every worker output against the CPU oracle.
- [x] Positive dry-run writes graph guard JSON with
      `graph_consumption_state=not-consumed`.
- [x] Positive dry-run records
      `graph_mutation_consumed_worker_output=false`.
- [x] Positive dry-run stops before graph mutation.
- [x] Negative dry-run without worker binary fails closed before graph mutation.
- [x] Local syntax/style gates pass.
- [x] C++ ownership scan shows no new direct owning heap APIs.

## Completion Notes

Accepted with DGX proof:

- Proof root:
  `/tmp/cuflye-m5j-proof-20260701T002918Z`
- Golden manifest:
  `tests/golden/cuflye-m5j-read-alignment-graph-dry-run-seam-dgx-aarch64.json`
- Host: `edgexpert-45d2`, `aarch64`
- Patch series: applied through
  `0028-cuflye-read-alignment-graph-dry-run-seam.patch`
- Positive query ids: `5,47,200,204`
- Positive worker mode: `cuda-bulk-persistent-v0`
- Positive CUDA execution mode: `persistent-arena-bulk-output`
- Positive validation: `4/4` worker outputs matched CPU oracle.
- Positive guard: `status=passed`,
  `graph_consumption_state=not-consumed`,
  `graph_mutation_consumed_worker_output=false`.
- Positive run intentionally exited non-zero with
  `status=stopped-before-graph-mutation`.
- Negative query ids: `5,47`
- Negative missing-worker-bin validation: `status=worker-failed`.
- Negative guard: `status=failed`,
  `graph_consumption_state=failed-closed`,
  `graph_mutation_consumed_worker_output=false`.

Allowed M5j claim:

```text
cuFlye can invoke the M5i CUDA read-alignment replay backend from inside a real
Flye run, validate CUDA output against CPU oracle output, and write graph guard
metadata while still stopping before graph mutation.
```

Forbidden M5j claim:

```text
M5j does not prove default GPU mode, replacement of Flye _readAlignments, graph
mutation consumption, or end-to-end Flye acceleration.
```

Plain-language benefit assessment:

```text
This step does not add a new speed win. The benefit is integration safety:
CUDA read-alignment output is now produced and checked inside Flye, but the code
still refuses to let GPU output change the graph. That is the right prerequisite
before any real consumption path.
```
