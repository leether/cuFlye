# Task Card: cuFlye M4i Packed Overlap Worker Protocol

Status: completed

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

- [x] Document packed overlap worker request/response contract.
- [x] Add worker CLI proof modes.
- [x] Implement supported packed overlap replay request path.
- [x] Implement unsupported request failure response path.
- [x] Run local static/style gates.
- [x] Build and run on DGX.
- [x] Validate and diff worker outputs.
- [x] Record worker overhead and compact DGX proof.
- [x] Close this card.

## Merge Note

Protocol commit:
`90c15922c33ae26790d02d63f784dfdbaac5caa6`.

Implementation commit:
`f3c9549b7618ead850901ef2b2b86461ac8aaf5b`.

DGX proof:
`tests/golden/cuflye-m4i-packed-overlap-worker-protocol-dgx-aarch64.json`.

M4i added `cuflye-overlap-worker-request-v0` and
`cuflye-overlap-worker-response-v0` as an overlap-specific file-backed worker
contract. The implementation adds `--worker-request-json` and
`--worker-requests-jsonl` modes to the overlap replay runner, reusing the M4h
packed CUDA path and preserving fail-closed behavior.

The proof passed all worker gates:

- Two supported packed serial worker requests round-tripped in one process.
- The second request reported `worker_cuda_context_warm=true`.
- The second request reused the CUDA arena with `0` allocations and `161`
  reuses.
- Both requests produced `9` fixture outputs and every output canonical-diffed
  `match` against the fixture oracle.
- An unsupported `batch_execution=per-fixture` request wrote an error response
  and exited non-zero with code `1`.
- Syntax/style gates and CUDA ownership scan passed.

Measured DGX worker timing:

- M4h standalone packed serial mean total before write: `6.906646 ms`.
- Worker request 1 backend mean total before write: `6.854870 ms`.
- Worker request 2 backend mean total before write: `6.853111 ms`.
- Worker request 2 total wall time: `189.114338 ms` for `3` warmup and `20`
  timed runs.
- Worker request 2 measured overhead: `52.052121 ms`, or `2.602606 ms` per
  timed run when amortized across `20` timed runs.

Conclusion: M4i proves a governed overlap worker boundary can preserve M4h's
packed overlap output hashes and warm CUDA state. It still does not integrate
with Flye graph logic or claim end-to-end GPU mode speed.
