# Task Card: cuFlye M5t Read Alignment Compact Binary Payload

Status: proposed

Created: 2026-07-01

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Build on M5s by replacing the session path's JSONL compact payload with a
smaller graph-facing payload that is cheaper to write, read, validate, and
rehydrate.

The core question for this card is:

```text
Can cuFlye keep M5s exactness while reducing the remaining compact-output
write/parse cost enough for the read-alignment session path to become a better
candidate for graph-facing substitution?
```

## In Scope

- Define a versioned compact binary or object-vector payload ABI for
  pre-divergence read-alignment chain output.
- Preserve deterministic record order and CPU oracle diffability.
- Keep M5s `compact-jsonl-v0` available as an audit/debug format.
- Add a Flye-side or proof-harness validator that checks record count, schema,
  checksum, fixture count, and selected shape metadata before any graph
  mutation.
- Measure request time, payload size, write time, and validation/rehydration
  time against M5s.

## Out of Scope

- No default GPU mode.
- No broad `_readAlignments` replacement without a new fail-closed graph-facing
  gate.
- No CUDA minimizer overlap discovery.
- No CPU divergence or edlib/base-alignment replacement.

## C++/CUDA Style Constraints

- Follow `docs/CODING_STYLE.md`.
- Do not introduce direct owning `new`, `delete`, `malloc`, `free`, or direct
  CUDA resource ownership outside approved RAII wrappers.
- Keep Flye patches C++11-compatible and narrow.
- Payload readers must bounds-check all sizes before allocation or indexing.
- Unsupported shapes, schema mismatches, checksum mismatches, and truncated
  payloads must fail closed.

## Deliverables

- Compact payload ABI documentation.
- Worker implementation for the new compact payload mode.
- CPU oracle writer or canonicalizer for byte-level comparison.
- Flye-side or proof-harness validation/rehydration gate.
- DGX proof manifest under `tests/golden/`.
- Roadmap update with timing and payload-size comparison versus M5s.

## Acceptance Gates

- [ ] Patch series applies and patched Flye builds on DGX.
- [ ] CUDA worker builds on DGX.
- [ ] New compact payload preserves exact CPU equivalence.
- [ ] New compact payload request time improves versus M5s `4.450572 ms`.
- [ ] Payload size and write time improve versus M5s compact JSONL.
- [ ] Negative schema/count/checksum/truncation cases fail closed before graph
      mutation.
- [ ] Local and DGX syntax/style gates pass.
- [ ] Ownership scan shows no new direct owning heap/resource APIs.

## Completion Notes

Pending implementation.
