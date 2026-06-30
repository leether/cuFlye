# Task Card: cuFlye M5a Read Alignment Oracle

Status: accepted

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Start the M5 read-to-graph line by turning Flye's `ReadAligner::alignReads`
output into a deterministic, machine-checkable CPU oracle before any CUDA
read-to-graph acceleration is attempted.

## Background

M4 proved increasingly deep overlap-worker safety and found real seam-level
benefits, but whole-Flye time is still dominated by CPU stages outside the
bounded overlap worker proof. The next high-ROI surface is read-to-repeat-graph
alignment in `src/repeat_graph/read_aligner.cpp`, which feeds multiplicity
inference and repeat resolution.

## In Scope

- Define `read-alignment-v1`.
- Add an opt-in `CUFLYE_READ_ALIGNMENT_DUMP` CPU oracle dump after
  `ReadAligner::alignReads`.
- Fail closed unless the dump runs with `--threads 1`.
- Add validator and canonical diff tools.
- Add runner support for the dump path.
- Prove on DGX toy data that the dump is non-empty, validates, and canonical
  diffs match across two deterministic runs.

## Out of Scope

- No CUDA read-to-graph kernel.
- No replacement of Flye `ReadAligner`.
- No graph mutation changes.
- No whole-Flye speedup claim.

## Acceptance Gates

- [x] ABI doc describes all fields and deterministic constraints.
- [x] Patch series applies and builds through `0025`.
- [x] `CUFLYE_READ_ALIGNMENT_DUMP` produces valid `read-alignment-v1`.
- [x] Enabling the dump with more than one thread fails closed.
- [x] Two DGX toy deterministic runs canonical-diff `match`.
- [x] No C++ direct resource ownership is introduced.

## C++ Style Constraints

- Use RAII file handles and `std::lock_guard`.
- Keep dump code side-effect-free with respect to `_readAlignments`.
- Do not introduce `new`, `delete`, `malloc`, `free`, or direct CUDA resource
  calls.

## Deliverables

- `docs/abi/read-alignment-v1.md`
- `patches/flye/2.9.6/0025-cuflye-read-alignment-dump.patch`
- `tools/validate_read_alignment_dump.py`
- `tools/diff_read_alignment_dumps.py`
- runner support for `--read-alignment-dump`
- DGX proof manifest and golden index update

## Completion Notes

M5a defines `read-alignment-v1` and adds an opt-in
`CUFLYE_READ_ALIGNMENT_DUMP` after `ReadAligner::alignReads`. The dump requires
`--threads 1` because Flye appends accepted read chains from a parallel loop.

DGX toy-hifi proof with patch series through `0025` produced two deterministic
oracle runs:

```text
records=7232
chains=7092
reads=7092
edges=14
canonical_sha256=f4815278bffdb993fd815a8a0ead2db44263aefe2fc38d65836bc48186dc904e
diff_status=match
```

The negative run enabled the dump with `--threads 2`; Flye exited with status
`1`, recorded expected failure metadata, emitted the fail-closed message, and
did not create a dump file.

Plain-language assessment: M5a does not accelerate Flye. It gives the project a
stable read-to-graph CPU oracle so a later CUDA implementation can be judged by
exact alignment-chain parity before graph logic sees it.
