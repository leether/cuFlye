# Task Card: cuFlye M5t Read Alignment Compact Binary Payload

Status: accepted

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

- [x] Patch series applies and patched Flye builds on DGX.
- [x] CUDA worker builds on DGX.
- [x] New compact payload preserves exact CPU equivalence.
- [x] New compact payload request time improves versus M5s `4.450572 ms`.
- [x] Payload size and write time improve versus M5s compact JSONL.
- [x] Negative schema/count/checksum/truncation cases fail closed before graph
      mutation.
- [x] Local and DGX syntax/style gates pass.
- [x] Ownership scan shows no new direct owning heap/resource APIs.

## Completion Notes

DGX proof:

```text
proof_root=/tmp/cuflye-m5t-proof-20260701T035137Z
golden=tests/golden/cuflye-m5t-read-alignment-compact-binary-payload-dgx-aarch64.json
fixture_count=3546
output_artifact_mode=compact-binary-v0
binary_cmp=match
binary_payload_bytes=332736
m5s_jsonl_payload_bytes=1126769
payload_size_reduction_ratio_vs_m5s_jsonl=3.386375x
cpu_binary_sha256=daaaf20276447d1e3656b36beb9f8ca21b9673cb99372b66521e7ccf2af8d4df
cuda_actual_binary_sha256=daaaf20276447d1e3656b36beb9f8ca21b9673cb99372b66521e7ccf2af8d4df
cpu_binary_backend_mean_total_before_json_ms=0.400641
cpu_binary_write_output_ms=1.030275
cuda_actual_status=ok
cuda_actual_request_ordinal=2
cuda_actual_arena_cache_hit=true
cuda_actual_backend_mean_total_before_json_ms=0.417153
cuda_actual_write_output_ms=1.811909
cuda_actual_request_total_ms=2.273654
m5s_cuda_actual_request_total_ms=4.450572
cuda_actual_request_speedup_vs_m5s=1.957454x
cuda_actual_write_speedup_vs_m5s=2.194032x
negative_bad_magic_status=error
negative_bad_count_status=error
negative_bad_checksum_status=error
negative_truncated_status=error
```

Allowed M5t claim:

```text
cuFlye can write the full3546 read-alignment pre-divergence session output as
compact-binary-v0, validate the payload with schema/count/checksum/length
gates, byte-match the CPU compact binary oracle, and reduce M5s compact-output
request time.
```

Forbidden M5t claim:

```text
M5t does not prove default GPU mode, full Flye acceleration, broad
_readAlignments replacement, CUDA minimizer overlap discovery, or replacement
of Flye's CPU divergence/base-alignment stages. It also does not yet prove that
Flye itself can consume the compact binary payload; that is M5u.
```

Plain-language benefit:

```text
M5t replaces the human-readable proof file with a machine-facing binary file.
The same 3546-fixture output shrinks from 1,126,769 bytes to 332,736 bytes.
CUDA write time drops from M5s 3.975386 ms to 1.811909 ms, and full request
time drops from 4.450572 ms to 2.273654 ms while CPU and CUDA files are
byte-identical.
```

Next highest-ROI task:

```text
M5u: move compact-binary-v0 into the Flye-side pre-divergence dry-run seam,
validate and rehydrate it inside Flye, apply Flye's existing divergence filter,
and fail closed on corrupted payloads before graph mutation.
```
