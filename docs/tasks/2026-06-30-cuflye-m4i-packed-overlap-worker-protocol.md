# Task Card: cuFlye M4i Packed Overlap Worker Protocol

Status: active

Created: 2026-06-30

Owner: cuFlye maintainers

Remote: https://github.com/leether/cuFlye

## Intent

Move the M4h packed overlap-chain speedup from a standalone replay executable
toward a governed worker boundary that can be called from Flye without changing
downstream graph semantics.

M4h reached the current stop condition by proving a bounded CUDA-over-CPU
overlap-chain replay speedup. M4i starts the next integration step by putting
that packed replay boundary behind a governed worker protocol.

## In Scope

- Define a packed overlap worker request/response contract.
- Preserve per-query fixture provenance, hashes, and fail-closed behavior.
- Keep CPU oracle diff gates before any downstream Flye graph mutation.
- Measure worker overhead separately from packed CUDA kernel time.
- Decide whether M4h should integrate through the existing long-lived external
  CUDA worker lane or through a new overlap-specific worker.
- Support file-backed `--worker-request-json` and `--worker-requests-jsonl`
  proof modes for packed overlap replay requests.
- Process at least two supported packed overlap requests in one worker process.

## Out of Scope

- No default GPU mode.
- No end-to-end Flye speed claim.
- No graph integration before parity gates.
- No base-level alignment or bad-mapping trim replay.
- No daemon, socket, or scheduler protocol.
- No candidate-generation worker behavior changes.

## C++/CUDA Style Constraints

- Keep CUDA code CUDA C++14.
- Reuse the M4h packed overlap replay implementation.
- Own CPU memory with standard containers or stack objects.
- Own CUDA allocations through existing move-only RAII wrappers.
- Do not add direct `cudaMalloc`, `cudaFree`, `cudaEventCreate`, or
  `cudaEventDestroy` outside approved RAII wrappers.
- Do not introduce raw owning pointers, direct `new`/`delete`, or direct
  `malloc`/`free`.
- Keep request parsing flat and fail closed on unsupported schema, adapter mode,
  ABI, backend, batch execution, or missing paths.
- Do not add silent CPU fallback.

## Deliverables

- Overlap worker protocol ABI doc.
- File-backed packed overlap worker mode in the overlap replay runner.
- DGX proof with at least two packed worker requests.
- Validation and canonical diff proof for every worker output.
- Worker overhead timing compared with M4h standalone packed timing.
- This Task Card completed after proof.

## Acceptance Gates

- Worker contract is documented before implementation.
- A replay request can round-trip through the worker and reproduce M4h packed
  output hashes.
- Unsupported shapes fail closed with explicit metadata.
- Worker overhead is measured and compared with M4h standalone packed timing.
- The second supported request reports warm worker context.
- Worker output validates as `overlap-range-v1`.
- Worker output canonical-diffs `match` against each fixture oracle.
- Local syntax/style gates pass.
- CUDA ownership scan shows no new direct resource APIs outside RAII wrappers.
- DGX proof is compact and does not include large TSV outputs.

## Execution Checklist

- [ ] Document packed overlap worker request/response contract.
- [ ] Add worker CLI proof modes.
- [ ] Implement supported packed overlap replay request path.
- [ ] Implement unsupported request failure response path.
- [ ] Run local static/style gates.
- [ ] Build and run on DGX.
- [ ] Validate and diff worker outputs.
- [ ] Record worker overhead and compact DGX proof.
- [ ] Close this card.
