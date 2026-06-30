# Task Card: cuFlye M4k Flye Overlap Worker Batch Seam

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Extend the M4j Flye-side overlap worker seam from one selected replay fixture to
an explicit replay-match query allowlist, then invoke the packed overlap worker
as a batch and stop before graph mutation.

## Background

M4h proved the performance shape we care about: packed serial CUDA was faster
than the CPU replay batch for the top-9 replay-match overlap fixtures while
preserving every `overlap-range-v1` oracle hash. M4j proved Flye can generate a
worker request and stop before graph mutation, but only for a single selected
query.

M4k should connect those two facts without yet changing Flye graph semantics:
Flye should collect a governed allowlist of replay-match query ids, write one
packed worker request for that batch, validate worker output, and still stop
before graph mutation.

## In Scope

- Define an explicit replay query allowlist selector for the Flye seam.
- Capture only allowlisted replay-match query fixtures in deterministic
  `--threads 1` proof mode.
- Invoke the M4i packed overlap worker once with the collected fixture batch.
- Validate every worker output against its Flye CPU oracle.
- Record packed worker timing from the Flye-generated request.
- Preserve default CPU behavior when the selector is unset.
- Record compact DGX proof.

## Out of Scope

- No graph mutation from worker output.
- No default GPU mode.
- No base-level alignment replay.
- No bad-mapping trim replay.
- No arbitrary query sampling.
- No end-to-end Flye speed claim.

## Acceptance Gates

- Default CPU Flye run remains unchanged.
- Explicit batch proof mode captures the intended replay-match query ids and no
  non-allowlisted query ids.
- The generated worker request uses `batch_execution=packed`.
- Worker response records `status=ok` and one CUDA launch per timed run.
- Every per-query worker output validates as `overlap-range-v1`.
- Every per-query worker output canonical-diffs `match` against its Flye CPU
  oracle.
- Packed worker timing is recorded and compared with the M4h packed and CPU
  replay batch baselines.
- The proof stops before graph mutation and records
  `graph_mutation_consumed_worker_output=false`.
- Local and DGX syntax/style/ownership gates pass.

## C++ Style Constraints

- Keep Flye patch code C++11-compatible with upstream Flye.
- Use standard containers and stack objects for CPU-owned seam state.
- Do not add raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Keep external process invocation file-backed and explicit.
- Do not silently fall back to CPU when batch worker mode is requested.

## Deliverables

- ABI doc update for the batch allowlist selector.
- Flye `2.9.6` patch-series entry after `0010`.
- Fixture runner controls and metadata for the allowlist.
- DGX proof showing Flye-generated packed batch request correctness and timing.
- This Task Card completed after proof.

## Execution Checklist

- [ ] Define the batch allowlist environment selector.
- [ ] Add Flye patch for allowlist capture and batch worker request metadata.
- [ ] Extend fixture runner options and metadata.
- [ ] Build patched Flye on DGX.
- [ ] Prove default CPU fixture behavior remains unchanged.
- [ ] Prove explicit batch worker mode captures only allowlisted query ids.
- [ ] Validate and diff every worker output.
- [ ] Compare packed worker timing with M4h baselines.
- [ ] Record compact DGX proof and close this card.
