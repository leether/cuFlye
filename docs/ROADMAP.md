# cuFlye CUDA-enabled Flye Roadmap

Status: active

Last updated: 2026-07-01

## North Star

cuFlye is a Flye-compatible CUDA acceleration project, not a replacement
assembler. The goal is:

```text
Keep Flye's CLI, stage contracts, intermediate artifacts, and CPU behavior as
the oracle while moving selected hotspot kernels to CUDA.
```

CPU Flye remains the default until the CUDA path passes deterministic parity
gates. `--gpu` must be opt-in, auditable, and able to fail closed or fall back
to CPU on unsupported shapes.

## Non-Negotiable Rules

- Do not claim "GPU Flye is faster" until an integrated Flye stage passes both
  parity and wall-time gates.
- Do not feed GPU output into downstream Flye graph logic until candidate-list
  equivalence against the CPU oracle is machine-checked.
- Do not silently fall back from CUDA to CPU; fallback must be explicit in
  metadata.
- Do not optimize by changing scientific semantics: k-mer encoding, standard
  form, repetitive filters, trivial-hit filters, ordering contracts, chaining
  penalties, and graph artifacts must remain compatible.
- Do not commit large generated outputs. Commit compact manifests, hashes, and
  proof summaries.

## Evidence Ladder

Each rung must be complete before the next one is allowed to make a stronger
claim.

| Rung | Claim allowed | Required proof |
| --- | --- | --- |
| Correctness fixture | Kernel emits ABI-valid records on a bounded fixture. | `validate_candidate_dump.py` and candidate diff pass. |
| Semantic fixture | Kernel implements one more Flye semantic unit. | CPU oracle, expected fixture, and GPU output match. |
| Core benchmark | CUDA is faster for a bounded subproblem. | CPU/GPU counts match and total CUDA time beats CPU. |
| Backend parity | CUDA backend can replace a CPU kernel boundary. | Candidate or overlap dumps match CPU oracle on fixtures. |
| Stage parity | A Flye stage is GPU-accelerated. | Canonical intermediate artifacts match CPU deterministic mode. |
| Product claim | `flye --gpu` is useful. | End-to-end wall time improves on target datasets with compatibility matrix. |

## Current State

Completed:

- M0: CPU oracle, canonical diff, and profiling harness.
- M1a-M1c: candidate dump oracle, backend seam, and candidate-record ABI.
- M1d-M1e: CUDA backend stub and CUDA runtime probe.
- M1f: CUDA can emit candidate-record-v1 output from a CPU sample.
- M1g: CUDA can generate candidates from query/index lookup-key fixtures.
- M1h: CUDA can compute Flye-style 2-bit k-mers, reverse complements, and
  standard-form lookup keys from DNA k-mer strings.
- M1i: CUDA can slide bounded read windows and generate query k-mers before
  candidate equality join.
- M1j: CUDA candidate equality-scan core is faster than CPU on DGX:
  268,435,456 pair comparisons, matched count 65,536, CUDA total best
  1.272772 ms vs CPU best 68.864532 ms, 54.105945x total speedup.
- M2a: Flye's CUDA candidate backend selector now reaches a real external
  packed adapter shell, invokes CUDA on a bounded fixture, validates
  candidate-record-v1 output, and fails closed for unsupported real Flye
  shapes.
- M2b: Flye can extract a real query and relevant `VertexIndex` buckets into a
  replayable packed candidate-backend bundle with per-query CPU candidate
  oracle output, then fail closed before downstream graph logic.
- M2c: CUDA read-window backend can consume the M2b real pack with dynamic
  read-base storage and reproduce the Flye CPU candidate list: 15,571 records,
  canonical SHA-256
  `5b50c458d82458516662e59daf3638e3534896a3ab1e77791f46dc54b663a1ae`.
- M2d-M2f: Flye can invoke the external packed CUDA backend at one real query
  boundary, stop before downstream graph mutation, and record sparse-output
  timing against the CPU oracle.
- M3a: the integration path is the long-lived external CUDA worker, not
  in-process CUDA inside Flye.
- M3b: the long-lived worker keeps CUDA context warm across repeated requests:
  warm backend total before JSON `132.110 ms`.
- M3c: device-side prefix compaction removes full host prefix/offset
  materialization: warm backend total before JSON `28.330 ms`, candidate diff
  `match`.
- M3d: worker-side reusable device buffers remove stable-shape allocation
  churn: warm backend total before JSON `18.643 ms`, warm device allocation
  `0.001 ms`, arena allocations `0`, arena reuses `7`, candidate diff `match`.
- M3e: sampled real-pack batch planning derives four heterogeneous request
  shapes from the M2b `query_neg253` pack, orders them by estimated pair count,
  runs them in one CUDA worker process, and preserves candidate-list
  equivalence for every sample. Warm sampled requests reuse the worker arena
  with zero new allocations, and the best warm worker request is `41.08x`
  faster than its sampled CPU oracle.
- M4a: `overlap-range-v1` defines Flye CPU overlap-range records after
  `OverlapDetector::getSeqOverlaps`, and DGX toy runs produce deterministic
  oracle dumps: `53,728` records per run, canonical SHA-256
  `71477479f412c90463aa60d8565b52da10f9dfec98d96387525ed50ae937c22b`,
  canonical diff `match`.
- M4b: `overlap-replay-fixture-v0` captures a bounded raw-read candidate chain
  fixture and the CPU replay tool reproduces Flye's overlap oracle for query
  `-71`: `7,859` candidate records, `51` overlap records, canonical
  overlap SHA-256
  `1a3347f96c74e0297a80871b32fa6cce2bccbf2731a7facb95e9333185c23e73`,
  canonical diff `match`.
- M4c: a standalone CUDA overlap-chain DP prototype consumes the M4b
  supported fixture and reproduces the CPU replay oracle at `overlap-range-v1`:
  `7,859` candidate records, `120` target groups, `51` overlap records,
  canonical overlap SHA-256
  `1a3347f96c74e0297a80871b32fa6cce2bccbf2731a7facb95e9333185c23e73`,
  canonical diff `match`. The single-fixture CUDA kernel time was
  `4.80657 ms` on DGX `NVIDIA GB10`.
- M4d: a fair C++ CPU baseline and warm CUDA benchmark reproduce the same
  M4b oracle, but the current CUDA hotpath is slower for this small single-query
  fixture: CPU mean hotpath `2.330413 ms`, CUDA mean hotpath `4.721515 ms`,
  CUDA speedup vs CPU `0.493573x`, CUDA slowdown vs CPU `2.026042x`.
- M4e: an explicit `parallel-reduce` CUDA kernel mode preserves exact
  `overlap-range-v1` output but is still slower on the single supported
  fixture: CPU mean hotpath `1.317636 ms`, serial CUDA `4.742383 ms`,
  parallel-reduce CUDA `5.794421 ms`; parallel-reduce speedup vs CPU
  `0.227397x`.
- M4f: multi-fixture replay capture is available through
  `CUFLYE_OVERLAP_REPLAY_MAX_FIXTURES`; a toy-raw run captured `100` fixture
  directories, including `50` supported-shape fixtures. Python replay matched
  `46` and mismatched `4`. A clean top-9 real replay-match batch diff-matched
  for CPU, serial CUDA, and parallel CUDA, but per-fixture CUDA invocation was
  still slower: CPU `12.300116 ms`, serial CUDA `38.801200 ms`, parallel CUDA
  `47.293990 ms`.
- M4g: a single-process batched overlap worker validates the same top-9
  replay-match fixtures while reusing CUDA context and device buffers. All CPU,
  serial CUDA, and parallel CUDA fixture outputs validate as `overlap-range-v1`
  and canonical-diff `match`. Arena reuse was recorded with `9` allocations,
  `369` reuses, and `492552` bytes of final capacity. The worker slightly
  improves CUDA overhead compared with M4f external invocation, but it is still
  slower than CPU: CPU `9.217960 ms`, serial CUDA `36.781822 ms`, parallel CUDA
  `45.264240 ms`.
- M4h: packed multi-query overlap-chain replay validates the same top-9
  replay-match fixtures while reducing CUDA launches from `9` per timed run to
  `1`. Packed serial CUDA preserves every `overlap-range-v1` oracle hash and is
  faster than the CPU replay batch on DGX: CPU `14.977639 ms`, packed serial
  CUDA `6.906646 ms`, speedup vs current CPU `2.168584x`, and speedup vs the
  M4g CPU baseline `1.334651x`.
- M4i: packed overlap-chain replay now has an overlap-specific file-backed
  worker protocol. Two supported packed serial worker requests round-tripped in
  one process, the second request reported warm context, reused the CUDA arena
  with `0` allocations and `161` reuses, and every output preserved the M4h
  oracle hashes. An unsupported request wrote `status=error` and exited with
  code `1`.
- M4j: Flye can explicitly generate a packed overlap worker request at a
  bounded replay fixture boundary, invoke the CUDA overlap worker, record the
  response, and stop before graph mutation. The DGX proof captured raw-read
  query `-71`, produced `51` worker overlap records, validated
  `overlap-range-v1`, canonical-diffed `match` against the Flye CPU oracle, and
  preserved default `toy-hifi` CPU artifact hashes against the M0 golden set.
- M4k: Flye can collect an explicit replay-match query-id allowlist, generate
  one packed CUDA overlap worker request for the captured batch, and still stop
  before graph mutation. The DGX proof captured 9 allowlisted raw-read queries,
  produced `382` total worker overlap records, validated every worker output as
  `overlap-range-v1`, canonical-diffed every output `match` against the Flye CPU
  oracle, and preserved default `toy-hifi` CPU artifact hashes against the M0
  golden set. The Flye-generated packed worker request reported
  `6.84245 ms` backend mean total before write versus the M4h CPU replay batch
  baseline `14.977639 ms`, a bounded replay speedup of `2.188929x`.
- M4l: Flye can validate packed CUDA overlap worker output before marking it
  consumption-eligible. The DGX positive proof validated all 9 worker TSVs as
  `overlap-range-v1`, canonical-diffed every output `match` against its CPU
  oracle, wrote `worker_output_consumption_eligible=true`, and still recorded
  `graph_mutation_consumed_worker_output=false`. The DGX negative proof ran the
  real worker through a wrapper that removed one overlap record from `query_381`;
  Flye validation caught the mismatch, wrote
  `status=validation-failed-before-graph-mutation`, marked
  `worker_output_consumption_eligible=false`, and exited non-zero before graph
  mutation.
- M4m: Flye can parse validated packed CUDA overlap worker output back into a
  Flye-side canonical shadow overlap representation and compare it against CPU
  overlap ranges captured in memory. The DGX positive proof shadow-compared all
  9 top-batch worker outputs `match`, wrote `shadow_consumption_eligible=true`,
  and still recorded `graph_mutation_consumed_worker_output=false`. The DGX
  negative proof corrupted both the first worker output TSV and its disk oracle,
  so file validation still passed; shadow comparison caught `query_neg71` as
  `51` CPU records versus `50` worker records, wrote
  `status=shadow-failed-before-graph-mutation`, and exited non-zero before graph
  mutation.
- M4n: the validation and shadow-consumption proof now covers a deterministic
  heterogeneous supported-shape matrix instead of only the fixed top-9 batch.
  A DGX toy-raw scan captured `227` replay fixtures; the selector found `96`
  supported replay-match fixtures, explicitly excluded `120` unsupported shapes
  and `11` replay mismatches, then selected `12` fixtures spanning candidate
  records `327` to `8372`, target groups `18` to `231`, overlap records `4` to
  `60`, and overlap density `0.0026367831245880024` to
  `0.027848101265822784`. The positive proof validated and shadow-compared all
  `12` selected worker outputs `match`, wrote
  `shadow_consumption_eligible=true`, and kept
  `graph_mutation_consumed_worker_output=false`. The negative proof corrupted
  both worker TSV and disk oracle for `query_353`; validation still passed, but
  shadow comparison caught `8` CPU records versus `7` worker records and failed
  closed before graph mutation.
- M4o: Flye now has an explicit graph-consumption guard dry-run for packed CUDA
  overlap worker output. The guard is disabled by default and enabled only with
  `CUFLYE_OVERLAP_GRAPH_CONSUMPTION_MODE=dry-run-v0`. The positive DGX proof
  used the M4n 12-fixture heterogeneous matrix with validation and shadow
  enabled; it wrote `graph_guard_status=passed`,
  `graph_guard_eligibility=eligible`, `graph_consumption_state=not-consumed`,
  and `graph_mutation_consumed_worker_output=false`. The negative proof enabled
  the guard without shadow mode; validation still passed, but guard checks
  `shadow_mode_selected` and `shadow_passed` failed, producing
  `status=guard-failed-before-graph-mutation` before graph mutation.
- M4p: Flye can rehydrate validated packed CUDA overlap worker output into a
  Flye-side typed overlap vector after validation, shadow comparison, and the
  M4o guard pass. The positive DGX proof used the M4n 12-fixture heterogeneous
  matrix and wrote `overlap_rehydration_status=passed`,
  `overlap_rehydration_state=not-consumed`, and
  `graph_mutation_consumed_worker_output=false`. The negative proof used the
  same matrix with `CUFLYE_OVERLAP_REHYDRATION_PROOF_FAULT=drop-first-worker-record`;
  validation, shadow comparison, and guard still passed, but typed-vector
  comparison produced `12` mismatching fixtures and failed closed with
  `status=rehydration-failed-before-graph-mutation` before graph mutation.
- M4v: Flye can invoke the packed overlap worker through a two-request
  persistent JSONL lifecycle in opt-in session-batch mode. The positive DGX
  proof wrote a cold warmup response with `request_ordinal=1` and
  `worker_cuda_context_warm=false`, then an actual warm response with
  `request_ordinal=2`, `worker_cuda_context_warm=true`, and
  `timing_ms.request_total=8.223469 ms`. Exact toy-raw Flye artifacts matched
  the CPU baseline. This reduced measured per-request lifecycle cost by
  `98.134393%` versus the M4u cold batch-run worker process, but the full
  toy-raw run was still slower than CPU (`88s` vs `82s`) because the proof still
  pays for one synthetic warmup request inside the same Flye run.
- M5a-M5l: cuFlye now has a deterministic read-to-graph alignment oracle,
  bounded replay fixtures, a CUDA chain replay prototype, real multi-read
  batching, heterogeneous shape grouping, and a persistent per-shape CUDA arena.
  The M5h proof expands the toy-hifi replay harvest to `3546` valid fixtures
  and `3781` total input records while preserving every per-read
  `read-alignment-v1` oracle diff. M5i then replaces thousands of tiny
  per-fixture output copies with one bulk output copy per shape group. On the
  same M5h harvest, explicit persistent bulk-output CUDA averages
  `0.302834 ms` versus CPU `0.333798 ms` before TSV/JSON emission, a bounded
  replay hot-path speedup of `1.102247x`, while preserving every oracle diff.
  M5j-M5l move that worker into a Flye-side dry-run seam: Flye can invoke the
  CUDA read-alignment backend, validate output against CPU oracle rows, rehydrate
  typed rows into a shadow `std::vector<GraphAlignment>` object-vector, prove it
  matches the CPU `_readAlignments` slice, and still stop before graph mutation.

Current allowed performance claim:

```text
cuFlye's CUDA candidate-generation worker is faster than the CPU oracle for the
measured real-pack and sampled real-read candidate fixtures while preserving
candidate-list equivalence.

cuFlye also has a deterministic CPU overlap-range oracle for the upstream toy
fixture; this is a correctness boundary for future CUDA overlap chaining, not a
GPU speed claim.

cuFlye has isolated one non-base-alignment CPU overlap-chain replay shape from
candidate records to `overlap-range-v1`; this is a semantic replay claim, not a
CUDA or end-to-end performance claim.

cuFlye has also reproduced that same bounded overlap-chain replay shape with a
standalone CUDA prototype; this is a CUDA correctness claim for one supported
fixture, not a Flye graph-integration or workload-level speed claim.

The current CUDA overlap-chain hotpath is not faster than the C++ CPU baseline
for the only supported M4b fixture; this is a measured optimization blocker,
not a speedup claim.

The current parallel-reduce CUDA overlap-chain kernel preserves correctness but
does not improve the single-query benchmark. Further overlap-chain performance
work must increase real batched work before claiming speed.

cuFlye now has a bounded overlap-chain CUDA speedup on the M4f/M4g top-9 real
replay-match fixture batch: packed serial CUDA is faster than the CPU replay
batch while preserving exact `overlap-range-v1` oracle hashes. This is an
overlap-chain replay claim only, not a Flye stage or end-to-end GPU mode claim.

cuFlye also has a governed file-backed overlap worker boundary for that packed
replay path. This is a worker round-trip and fail-closed protocol claim, not a
claim that Flye graph logic consumes GPU overlap output.

cuFlye now has a Flye-side proof seam that can request CUDA overlap worker
output and stop before graph mutation. This is an integration-boundary claim,
not an end-to-end GPU Flye or graph-consumption claim.

cuFlye can now request a packed multi-query CUDA overlap worker batch from the
Flye seam using an explicit query-id allowlist. This preserves the M4h bounded
overlap-chain replay speedup at the Flye request boundary, while still refusing
to feed GPU overlap output into Flye graph logic.

cuFlye now has a Flye-side validation gate for packed CUDA overlap worker
output. Passing output can be marked consumption-eligible, and mismatching
output fails closed before graph mutation. This is still not a graph-consumption
claim.

cuFlye now has a Flye-side shadow consumption proof for packed CUDA overlap
worker output. Validated worker output can be parsed into canonical overlap
records and compared against CPU overlap ranges captured in memory. This is one
more integration boundary, but it still does not feed GPU output into graph
mutation.

cuFlye now has a broader heterogeneous shadow matrix proof for that boundary.
The proof documents selected supported shapes and unsupported exclusions, and it
shows validation and shadow success across `12` replay-match fixtures before
graph mutation. This still does not feed GPU output into graph mutation.

cuFlye now has a guarded graph-consumption dry-run contract for that same
boundary. This is a safety and auditability claim: the code can prove the
preconditions for future graph consumption and still records that worker output
was not consumed by graph mutation.

cuFlye can now rehydrate validated CUDA overlap worker records into a
Flye-side typed overlap vector and prove that vector matches CPU overlap
records captured in memory. This is a representation-boundary claim; it still
does not feed GPU output into graph mutation.

cuFlye can now keep the actual overlap-worker request warm inside a two-request
persistent JSONL lifecycle and preserve exact toy-raw Flye artifacts. This is a
worker-lifecycle seam claim: the warm request is much cheaper than the M4u cold
batch worker process, but the proof is not yet a whole-Flye speedup.

cuFlye can also reuse per-shape CUDA read-alignment arenas across benchmark
iterations while preserving every per-read oracle diff. This is a CUDA overhead
reduction claim for a bounded replay benchmark, not a CPU-beating or end-to-end
Flye speed claim.

cuFlye can now expand that proof to a much larger toy-hifi read-alignment
fixture harvest. This improves diagnosis: kernel work is no longer the main
problem, while thousands of tiny output copies dominate total CUDA time.

cuFlye can now run that bounded M5h read-alignment chain replay harvest through
an explicit persistent CUDA bulk-output mode faster than the CPU replay
baseline before TSV/JSON emission while preserving every per-read oracle diff.
This is a bounded read-alignment replay hot-path claim, not a full Flye GPU-mode
claim.

cuFlye can now invoke that M5i read-alignment CUDA backend from inside a real
Flye run behind a graph-facing dry-run seam. The seam validates worker TSVs
against CPU oracle TSVs, writes graph guard metadata, records
`graph_mutation_consumed_worker_output=false`, and stops before graph mutation.
This is an integration-safety claim, not a graph-consumption or speed claim.
```

Current forbidden claim:

```text
Flye as a whole is faster in GPU mode.
```

## Roadmap

### M2: Real Candidate Backend Integration

Purpose: replace the current CUDA stub at the candidate-generation boundary
without changing downstream chaining or graph logic.

Work items:

- Add a C++ candidate backend interface with CPU and CUDA implementations.
- Move standalone M1i/M1j logic behind the backend seam.
- Upload read windows and flattened index buckets from real Flye data
  structures, not hand-written fixtures.
- Return candidate-record-v1 compatible records to the existing CPU path.
- Canonically sort GPU records before comparison.

Gate:

- CPU backend and CUDA backend candidate dumps match after canonical sorting on
  toy fixture.
- Default CPU Flye output remains unchanged.
- `CUFLYE_CANDIDATE_BACKEND=cuda` no longer fails as a stub for supported toy
  data, and it never silently falls back.

Stop if:

- GPU candidate dump differs from CPU and the mismatch cannot be explained by
  ordering alone.
- GPU path needs downstream graph changes to pass.

### M3: Candidate Backend Scale-Up

Purpose: prove candidate parity and speed on larger sampled data.

Work items:

- Add sampled real-read fixtures from DGX runs.
- Add bounded memory budget and batch planner.
- Measure candidate generation wall time, CPU fallback rate, peak CPU RSS, peak
  GPU allocation, and output record counts.

Gate:

- Candidate dumps match CPU oracle on toy plus sampled real reads.
- CUDA candidate generation is faster than CPU for at least one realistic
  sampled fixture.

Allowed claim after gate:

```text
cuFlye's candidate-generation backend is faster on CUDA for specific sampled
fixtures while preserving candidate-list equivalence.
```

### M4: Overlap Chaining Parity

Purpose: move from raw candidate hits to overlap ranges while preserving Flye
chaining semantics.

Work items:

- Define an overlap-range ABI. Completed in M4a.
- Isolate a bounded CPU overlap-chain replay fixture. Completed in M4b.
- Port or batch the chain DP used by `OverlapDetector::getSeqOverlaps`.
- Preserve gap penalties, jump thresholds, minimum overlap, overhang filters,
  and divergence thresholds.

Gate:

- GPU and CPU overlap dumps match in deterministic mode on regression fixtures.
- Candidate backend speedup is not erased by chaining overhead.

### M5: Read-to-Graph Alignment

Purpose: accelerate read-to-graph alignment using the same sequence/index
primitives.

Work items:

- Identify `ReadAligner::alignReads` data contracts.
- Build read-to-graph candidate and chain oracles.
- Add parity gates for `read_alignment_dump`.

Gate:

- `read_alignment_dump` matches CPU on toy and sampled fixtures.

### M6: Polishing Kernels

Purpose: evaluate GPU acceleration for polishing only after overlap/read-graph
contracts are stable.

Work items:

- Define bubble-level CPU oracle.
- Evaluate custom CUDA kernels or a Flye-compatible `cudapoa` wrapper.
- Preserve Flye scoring and output ordering.

Gate:

- Polishing consensus output matches CPU on fixtures.

### M7: Experimental `flye --gpu`

Purpose: expose opt-in GPU mode.

Work items:

- Add CLI flags: `--gpu`, `--gpu-devices`, `--gpu-batch-mb`,
  `--verify-cpu-kernels`.
- Emit metadata for backend selection, CUDA device, memory budgets, fallback
  events, and verification mode.
- Build an end-to-end benchmark matrix.

Gate:

- End-to-end Flye outputs pass deterministic or scientific-equivalence gates.
- Wall time improves on target workloads.
- CPU fallback paths are auditable.

## Regression Matrix

Minimum fixtures:

- upstream toy HiFi;
- small PacBio CLR;
- small ONT raw;
- uneven-coverage or metagenome fixture;
- DGX sampled subset from the target exact rerun workload.

Each fixture should run:

- CPU default;
- CPU deterministic;
- CUDA deterministic with CPU verification;
- CUDA throughput mode.

Required reports:

- candidate counts and hashes;
- overlap counts and hashes once M4 exists;
- canonical artifact diff;
- wall time by stage;
- peak RAM;
- peak GPU memory allocation;
- CPU fallback count and reasons.

## Naming And Claim Discipline

Use precise milestone labels:

- `CUDA candidate smoke`: ABI output only.
- `CUDA k-mer join smoke`: bounded equality join fixture.
- `CUDA k-mer encode smoke`: device-side k-mer encoding fixture.
- `CUDA read-window smoke`: bounded read-window fixture.
- `CUDA candidate-core benchmark`: bounded performance subproblem.
- `CUDA candidate backend`: integrated Flye candidate-generation boundary.
- `GPU Flye mode`: only after end-to-end `flye --gpu` exists and passes gates.

## Immediate Next Step

Next highest-ROI task:

```text
M4o: define a guarded overlap graph-consumption contract and dry-run proof
before allowing CUDA overlap output to affect Flye graph mutation. Completed.
```

Next highest-ROI task:

```text
M4p: rehydrate validated CUDA overlap worker output into a Flye-side typed
overlap vector in a no-mutation dry-run, then prove it matches the CPU vector
before any graph-consumption path is enabled. Completed.
```

Next highest-ROI task:

```text
M4q: convert the validated typed overlap vector into actual Flye `OverlapRange`
objects in a no-mutation dry-run, then prove the object vector canonicalizes
back to the CPU overlap vector before graph consumption is enabled.
Completed.
```

M4q proof on DGX used the M4n 12-fixture heterogeneous matrix. The positive
run passed validation, shadow comparison, graph guard, M4p typed rehydration,
and M4q `OverlapRange` object rehydration with
`graph_mutation_consumed_worker_output=false`. The negative proof injected
`drop-first-overlap-range`; validation, shadow comparison, graph guard, and
typed rehydration still passed, while object-vector comparison found 12
mismatching fixtures and failed closed before graph mutation.

Allowed M4q claim:

```text
cuFlye can construct actual Flye `OverlapRange` object vectors from validated
CUDA overlap worker output and prove they canonicalize to CPU overlap records
before graph mutation.
```

Next highest-ROI task:

```text
M4r: use the verified `OverlapRange` object vector as an opt-in graph-facing
substitution smoke for selected fixtures, still guarded by exact CPU comparison
and fail-closed behavior, then prove graph artifacts stay unchanged or the run
stops before mutation.
Completed.
```

M4r proof on DGX selected toy-raw query `353` as the first graph-facing
substitution smoke. The positive run passed validation, shadow comparison,
graph guard, typed rehydration, object rehydration, and exact CPU comparison,
then returned the worker-derived `OverlapRange` vector to Flye. Canonical graph
and assembly artifacts matched the CPU toy-raw run. A durable
`worker-vector-substitution.consumed` sentinel kept later Flye subprocesses
from re-invoking the worker and overwriting the accepted proof.

The negative proof injected `drop-first-substitution-overlap`; all upstream
checks still passed, but substitution detected the object-vector mismatch and
failed closed before returning worker output.

Allowed M4r claim:

```text
cuFlye can return a verified CUDA-worker-derived Flye `OverlapRange` vector for
one selected supported overlap query, preserve canonical Flye graph artifacts,
and fail closed on a forced substitution mismatch.
```

Forbidden M4r claim:

```text
M4r does not prove default GPU mode, unsupported-shape substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4s: expand verified graph-facing substitution from one selected query to a
deterministic supported-shape session ledger. Every query/shape decision should
be recorded as substituted, skipped, or failed-closed, and positive artifacts
must still match CPU.
Completed.
```

M4s proof on DGX selected toy-raw query ids `353,381`. The positive session
substituted both selected supported queries, wrote per-query sentinels, and
preserved canonical Flye graph/output artifacts against the CPU toy-raw
baseline. The session ledger recorded:

```text
substituted: 2
skipped-already-substituted: 5
skipped-not-selected: 1892
skipped-unsupported-non-selected-shape: 987
```

The mismatch negative proof injected `drop-first-substitution-overlap` and
failed closed before returning worker output. The unsupported-shape negative
proof injected `force-unsupported-selected-shape` and failed closed before
worker invocation.

Allowed M4s claim:

```text
cuFlye can substitute multiple selected supported Flye overlap queries with
verified CUDA-worker-derived `OverlapRange` vectors, preserve canonical Flye
artifacts, and record substituted, skipped, and failed-closed query/shape
decisions in a session ledger.
```

Forbidden M4s claim:

```text
M4s does not prove default GPU mode, unsupported-shape CUDA substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4t: add timing attribution to substitution sessions so cuFlye can separate CPU
overlap time, CUDA worker time, process/IO overhead, validation overhead, and
ledger overhead before choosing the next performance optimization.
Completed.
```

M4t proof on DGX preserved the M4s safety gates and added per-decision timing
attribution to the substitution ledger. The positive toy-raw session selected
query ids `353,381`, substituted both, and preserved canonical Flye artifacts
against the CPU baseline. Ledger decision counts were unchanged from M4s:

```text
substituted: 2
skipped-already-substituted: 5
skipped-not-selected: 1892
skipped-unsupported-non-selected-shape: 987
```

The timing result was not a speedup. CPU toy-raw baseline elapsed `87s`; the
substitution/timing run elapsed `99s` (`1.137931x` CPU wall time). Selected
query timing showed the current seam is dominated by external worker/process
overhead:

```text
query 353: cpu_overlap_ms=1.307334, worker_process_ms=452.297705, seam_total_ms=469.227281
query 381: cpu_overlap_ms=18.568655, worker_process_ms=376.389273, seam_total_ms=395.499113
```

The mismatch negative proof injected `drop-first-substitution-overlap` and
failed closed with timing attribution. The unsupported-shape negative proof
injected `force-unsupported-selected-shape`, failed closed before worker
invocation, and recorded `worker_process_ms=0`.

Allowed M4t claim:

```text
cuFlye can attach non-negative timing attribution to graph-facing substitution
decisions, preserve exact Flye artifacts for two selected supported toy-raw
queries, and keep mismatch and unsupported-shape negative paths fail-closed.
```

Forbidden M4t claim:

```text
M4t does not prove default GPU mode, unsupported-shape CUDA substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4u: reduce selected-query substitution seam overhead, especially external
worker process startup and request/response file IO, before expanding
graph-facing substitution scope.
Completed.
```

M4u added an opt-in session batch/cache substitution mode:

```text
CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=verified-overlap-range-session-batch-v0
```

The positive DGX proof preserved exact canonical Flye artifacts. It recorded one
selected query deferred while waiting for the allowlist-sized batch, one selected
query substituted from the batch worker run, and one later selected query
substituted from the verified batch cache:

```text
deferred-session-batch-waiting: 1
substituted-from-session-batch-run: 1
substituted-from-session-batch-cache: 1
skipped-already-substituted: 4
skipped-not-selected: 1892
skipped-unsupported-non-selected-shape: 987
```

The timing result showed integration progress but not end-to-end Flye speedup.
CPU toy-raw baseline elapsed `84s`; batch/cache substitution elapsed `91s`
(`1.083333x` CPU wall time). Selected substitution timing improved versus M4t:

```text
M4t selected worker_process_ms avg: 414.343489
M4u selected worker_process_ms avg: 220.396566
worker_process avg reduction: 46.808247%
M4t selected seam_total_ms avg: 432.363197
M4u selected seam_total_ms avg: 228.892051
seam_total avg reduction: 47.060237%
```

The mismatch negative proof injected `drop-first-substitution-overlap`; query
`353` deferred and query `381` failed closed at exact substitution comparison.
The unsupported-shape negative proof injected `force-unsupported-selected-shape`
and failed closed before worker invocation with `worker_process_ms=0`.

Allowed M4u claim:

```text
cuFlye can amortize one verified session batch worker run across a later cached
selected substitution, preserve exact Flye artifacts, and reduce selected
substitution seam overhead versus M4t.
```

Forbidden M4u claim:

```text
M4u does not prove default GPU mode, unsupported-shape CUDA substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4v: introduce an explicit persistent overlap-worker lifecycle so warm
sequential batch requests avoid paying external worker process startup cost each
time.
Completed.
```

M4v proof on DGX used toy-raw query ids `353,381` in
`verified-overlap-range-session-batch-v0` with
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=jsonl-persistent-v0`. The positive run
preserved exact canonical Flye artifacts against the CPU toy-raw baseline. The
worker processed two requests from `worker-requests.jsonl`: a cold warmup
request, then an actual warm request. The actual response reported:

```text
request_ordinal: 2
worker_cuda_context_warm: true
timing_ms.request_total: 8.223469 ms
timing_ms.backend_mean_total_before_write: 5.530894 ms
timing_ms.worker_overhead: 2.692575 ms
```

Compared with M4u's cold batch-run worker process time of `440.793131 ms`, the
M4v actual warm request total is `53.601847x` faster, a `98.134393%` reduction
in measured request-lifecycle cost.

M4v is still not an end-to-end Flye speedup. CPU toy-raw elapsed `82s`; the
persistent lifecycle run elapsed `88s` (`1.073171x` CPU wall time), because this
proof still pays for one synthetic warmup batch inside the same Flye run. The
mismatch negative proof failed closed at exact substitution comparison, and the
unsupported-shape negative proof failed closed before worker invocation with
`worker_process_ms=0`.

Allowed M4v claim:

```text
cuFlye can invoke the overlap worker through a two-request persistent JSONL
lifecycle, keep the actual request warm, preserve exact toy-raw Flye artifacts,
and fail closed on mismatch or unsupported selected shapes.
```

Forbidden M4v claim:

```text
M4v does not prove default GPU mode, broad unsupported-shape substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4w: turn the M4v warm-request lifecycle proof into a Flye-visible persistent
worker session that avoids a duplicate warmup batch in the same proof path.
Completed.
```

M4w proof on DGX used toy-raw query ids `353,381` in
`verified-overlap-range-session-batch-v0` with
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`. An external
file-backed worker session initialized CUDA context before writing
`session-ready.json`; Flye then submitted only the actual `worker-request.json`
through the session inbox. The positive run generated no
`worker-request-warmup.json`, no `worker-response-warmup.json`, and no
`worker-requests.jsonl`.

The actual response reported:

```text
request_ordinal: 1
worker_cuda_context_warm: true
worker_context_setup_ms: 304.411037 ms
timing_ms.request_total: 9.025404 ms
timing_ms.backend_mean_total_before_write: 6.148255 ms
timing_ms.worker_overhead: 2.877149 ms
```

Flye-visible selected `worker_process_ms` fell to `14.157398 ms`, versus M4u's
cold batch-run `440.793131 ms` and M4v's warmup-plus-actual process segment
`463.398560 ms`. That is a `96.788199%` reduction versus M4u and a
`96.944877%` reduction versus M4v for the selected worker/process segment.

M4w is still not an end-to-end Flye speedup. CPU toy-raw elapsed `73s`; the
M4w positive run elapsed `83s` (`1.136986x` CPU wall time), because the proof
still computes CPU overlaps first as the live oracle and only then substitutes
the verified GPU-derived overlap vector. The mismatch negative proof failed
closed at exact substitution comparison, and the unsupported-shape negative
proof failed closed before any worker/session submission with
`worker_process_ms=0`.

Allowed M4w claim:

```text
cuFlye can submit a verified Flye overlap worker request to a true file-backed
persistent CUDA session without a duplicate warmup request, preserve exact
toy-raw Flye artifacts, and fail closed on mismatch or unsupported selected
shapes.
```

Forbidden M4w claim:

```text
M4w does not prove default GPU mode, broad unsupported-shape substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4x: split the proof-only live CPU oracle from a bounded GPU-first supported
overlap substitution path, so performance runs can avoid computing the selected
CPU overlap before invoking CUDA while still retaining an audit gate.
```

Completed.

M4x proof on DGX used toy-raw query ids `353,381` in
`gpu-first-supported-v0` with `CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`.
Flye first built the same verified session batch cache as M4w. A later
allowlisted supported call for query `353` then returned the cached
CUDA-worker `OverlapRange` vector before live CPU overlap.

The positive selected ledger evidence was:

```text
353 deferred-session-batch-waiting cpu_overlap_ms=0.939491 worker_process_ms=0.0
381 substituted-from-session-batch-run cpu_overlap_ms=9.166123 worker_process_ms=12.997414
353 gpu-first-from-session-batch-cache cpu_overlap_ms=0.0 worker_process_ms=0.0
```

The positive DGX proof preserved exact toy-raw artifacts against CPU:

```text
Flye run diff: match
```

The audit negative enabled `CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE=oracle-file-v0`
and `CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-gpu-first-overlap`.
It failed closed before graph mutation:

```text
status: gpu-first-substitution-failed-before-live-cpu-overlap
error: gpu-first audit object vector differs from captured CPU oracle
graph_mutation_consumed_worker_output: false
```

M4x is a real seam-level benefit, but it is still not an end-to-end Flye
speedup. CPU toy-raw elapsed `72s`; the M4x positive run elapsed `84s`
(`1.166667x` CPU wall time), because the proof bypasses one selected cached
overlap while the rest of Flye remains CPU-bound and instrumentation still
records ledger decisions.

Allowed M4x claim:

```text
cuFlye can reuse a verified file-backed CUDA session batch cache for a later
allowlisted supported overlap query before live CPU overlap, preserve exact
toy-raw artifacts, and fail closed on GPU-first audit mismatch.
```

Forbidden M4x claim:

```text
M4x does not prove default GPU mode, broad unsupported-shape substitution, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4y: reduce proof overhead and broaden GPU-first selection to a bounded set of
high-cost supported overlap calls, while keeping the sparse ledger and audit
sampling explicit.
```

Completed.

M4y proof on DGX used toy-raw with
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_MODE=gpu-first-supported-v0`,
`CUFLYE_OVERLAP_WORKER_LIFECYCLE_MODE=session-file-v0`, and
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_LEDGER_MODE=selected-only-v0`.

An initial 8-query set included `798`, but the worker validation gate rejected
it fail-closed because the canonical worker output did not match the CPU oracle:

```text
query_798 oracle_records=49 worker_records=48 canonical_diff_status=mismatch
```

The accepted positive proof used the bounded 7-query allowlist
`161,554,89,112,896,110,752`. It preserved exact toy-raw artifacts:

```text
Flye run diff: match
```

The sparse positive ledger evidence was:

```text
entries=35
non_selected_entries=0
deferred-session-batch-waiting=7
substituted-from-session-batch-run=1
gpu-first-from-session-batch-cache=6
skipped-already-substituted=21
```

The sampled audit negative used
`CUFLYE_OVERLAP_GPU_FIRST_AUDIT_MODE=oracle-file-v0`,
`CUFLYE_OVERLAP_GPU_FIRST_AUDIT_QUERY_IDS=161`, and
`CUFLYE_OVERLAP_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-gpu-first-overlap`.
Non-audited GPU-first cache hits were accepted first; the audited `161` reuse
then failed closed before graph mutation:

```text
status: gpu-first-substitution-failed-before-live-cpu-overlap
error: gpu-first audit object vector differs from captured CPU oracle
proof_fault_applied: true
graph_mutation_consumed_worker_output: false
```

M4y reduces proof overhead and broadens the GPU-first surface, but still does
not prove end-to-end Flye speedup. CPU toy-raw elapsed `72s`; the M4y positive
run elapsed `74s` (`1.027778x` CPU wall time). The benefit is seam-level:
6 later selected calls returned cached worker `OverlapRange` vectors with
`cpu_overlap_ms=0` and `worker_process_ms=0`, and positive ledger volume fell
from M4x's 2886-row full-ledger pattern to 35 selected rows.

Allowed M4y claim:

```text
cuFlye can run a bounded multi-query GPU-first supported overlap substitution
proof with sparse selected-only ledger output, preserve exact toy-raw artifacts,
and fail closed on sampled GPU-first audit mismatch.
```

Forbidden M4y claim:

```text
M4y does not prove default GPU mode, broad unsupported-shape substitution,
unsupported candidate acceptance, or end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M4z: turn the bounded manual selection proof into an automated validation-safe
GPU-first selection planner and compare serial versus parallel-reduce worker
kernels, so the next proof can increase accepted cache hits without hand-picking
unsafe query ids like 798.
```

Completed.

M4z adds a deterministic planner for GPU-first overlap query selection. It reads
substitution ledger JSONL plus worker-validation JSON, ranks repeated supported
query ids by later CPU-overlap cost, and treats validation failures as hard
rejections.

The DGX planner proof combined M4y's failed 8-query evidence with the successful
7-query positive proof. It rejected query `798` because validation had already
shown a canonical mismatch:

```text
query_798 oracle_records=49 worker_records=48 canonical_diff_status=mismatch
```

It emitted this validation-safe allowlist:

```text
161,89,554,752,112,896,110
```

The accepted 7-query batch was then replayed directly through the overlap
worker with `warmup_runs=1` and `benchmark_runs=10`. Both CUDA worker kernel
modes produced `237` total overlap records and canonical-diffed `match` against
all 7 fixture CPU oracles.

The worker timing comparison was:

```text
serial kernel_ms=6.735444 backend_mean_ms=6.788436 request_total_ms=89.063285
parallel-reduce kernel_ms=7.150598 backend_mean_ms=7.207953 request_total_ms=90.571207
parallel/serial kernel ratio=1.061637
```

M4z improves selection governance, not whole-Flye speed. It prevents unsafe
manual allowlists from admitting known mismatches, and it shows that
`parallel-reduce` is not the better kernel for the current small M4y fixture
batch. The serial packed worker remains the preferred mode for the next
GPU-first proof.

Allowed M4z claim:

```text
cuFlye can derive a validation-safe GPU-first overlap query allowlist from
ledger and validation evidence, reject known mismatches such as query 798, and
verify both serial and parallel-reduce worker modes before choosing the faster
safe mode for the next proof.
```

Forbidden M4z claim:

```text
M4z does not prove default GPU mode, broad unsupported-shape substitution,
parallel-reduce superiority, or end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M5a: start the read-to-graph alignment oracle by locating Flye's
ReadAligner::alignReads contract, defining a compact alignment-record ABI, and
dumping CPU oracle records before any CUDA read-to-graph acceleration.
```

Completed.

M5a defines `read-alignment-v1`, a flat TSV CPU oracle for Flye
`GraphAlignment` records after `ReadAligner::alignReads` accepts and
divergence-filters read-to-repeat-graph chains. The opt-in dump is controlled by
`CUFLYE_READ_ALIGNMENT_DUMP` and fails closed unless Flye runs with
`--threads 1`, because raw chain append order is not deterministic in the
parallel aligner.

The DGX toy-hifi proof applied and built the patch series through
`0025-cuflye-read-alignment-dump.patch`. Two deterministic runs produced the
same `read-alignment-v1` oracle:

```text
records=7232
chains=7092
reads=7092
edges=14
canonical_sha256=f4815278bffdb993fd815a8a0ead2db44263aefe2fc38d65836bc48186dc904e
canonical diff=match
```

The negative DGX run enabled the dump with `--threads 2`; Flye exited with
status `1`, recorded expected failure metadata, found the fail-closed message
`cuFlye read alignment dump requires --threads 1`, and produced no dump file.

Allowed M5a claim:

```text
cuFlye can produce and validate a deterministic CPU read-to-graph alignment
oracle after ReadAligner::alignReads, and it fails closed when the proof is not
single-thread deterministic.
```

Forbidden M5a claim:

```text
M5a does not prove CUDA read-to-graph acceleration, default GPU mode, graph
mutation consumption, or end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M5b: isolate a bounded read-to-graph replay fixture that captures the graph-edge
sequences, read sequence, and per-read edge-overlap inputs needed to reproduce
one read alignment chain outside a full Flye run.
```

Completed.

M5b adds `read-alignment-replay-fixture-v0`, an opt-in fixture dump for one
selected `ReadAligner::chainReadAlignments` input/output contract. The patch is
controlled by `CUFLYE_READ_ALIGNMENT_REPLAY_DUMP_DIR` and
`CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_ID`, requires `--threads 1`, and dumps the
selected read, graph edge sequences, graph edge adjacency, edge-overlap inputs,
chain divergence decisions, and accepted oracle `read-alignment-v1` records.

The DGX toy-hifi proof applied and built the patch series through
`0026-cuflye-read-alignment-replay-fixture-dump.patch`. The selected read was
query `200`:

```text
alignment_input_records=4
candidate_chains=1
oracle_chains=1
replayed_records=3
canonical_sha256=c8aa478626cad18a598140a00a39effba464c187109a2b71a2509806ff7aa802
canonical diff=match
```

The negative DGX run enabled replay fixture dumping with `--threads 2`; Flye
exited with status `1`, recorded expected failure metadata, found the
fail-closed message
`cuFlye read alignment replay fixture dump requires --threads 1`, and produced
no replay fixture manifest.

Allowed M5b claim:

```text
cuFlye can capture one deterministic read-to-graph replay fixture and reproduce
its accepted read-alignment-v1 oracle outside a full Flye run.
```

Forbidden M5b claim:

```text
M5b does not prove CUDA read-alignment acceleration, multi-read batching, graph
mutation consumption, default GPU mode, or end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M5c: implement the first CUDA/CPU benchmark prototype for the bounded
read-alignment chain replay fixture, preserving the replay oracle output while
measuring whether the chain DP hot path has a real GPU advantage.
```

Completed.

M5c adds a standalone CUDA/C++ binary,
`cuflye-cuda-read-alignment-chain-replay`, for
`read-alignment-replay-fixture-v0`. It supports explicit `cpu` and `cuda`
backends, emits `read-alignment-v1`, consumes M5b's recorded
`chain-divergence.tsv` acceptance decisions, and records warm benchmark timing.

The DGX proof built the prototype with `/usr/local/cuda/bin/nvcc` for
`sm_121` and ran the M5b toy-hifi read `200` fixture:

```text
input_records=4
output_records=3
canonical_sha256=c8aa478626cad18a598140a00a39effba464c187109a2b71a2509806ff7aa802
cpu vs oracle diff=match
cuda vs oracle diff=match
cpu vs cuda diff=match
```

Warm benchmark timing with `5` warmups and `200` timed runs:

```text
cpu_mean_total_before_json_ms=0.000482
cpu_mean_core_ms=0.000482
cuda_mean_total_before_json_ms=0.137072
cuda_mean_kernel_ms=0.012329
cuda_total_speedup_vs_cpu=0.003516x
cuda_core_speedup_vs_cpu=0.039095x
```

The bad-schema negative gate and CUDA memory-budget negative gate both failed
closed before writing success JSON/TSV.

Allowed M5c claim:

```text
cuFlye can replay one M5b read-to-graph chain DP fixture through a standalone
CUDA backend and reproduce the read-alignment-v1 oracle exactly.
```

Forbidden M5c claim:

```text
M5c does not prove CUDA is faster for this shape, multi-read batching, graph
mutation consumption, default GPU mode, edlib/base realignment replay, or
end-to-end Flye speedup.
```

Next highest-ROI task:

```text
M5d: collect and benchmark a deterministic multi-read read-alignment replay
fixture batch, then add packed CUDA execution so the chain DP proof has enough
parallel work to test whether GPU occupancy can beat the CPU baseline.
```

Completed as a controlled replicated-batch proof.

M5d adds `--replicate-fixture N` to
`cuflye-cuda-read-alignment-chain-replay`. The CPU backend repeats the same
fixture work `N` times. The CUDA backend packs `N` independent copies and
launches one block per logical fixture. The TSV output remains the first
representative `read-alignment-v1` result so the existing oracle diff gate stays
small and exact.

The DGX scan showed the crossover point for the M5b read `200` fixture:

```text
batch_size=1     total_speedup=0.003843x  core_speedup=0.044659x
batch_size=64    total_speedup=0.114514x  core_speedup=1.314436x
batch_size=1024  total_speedup=1.090091x  core_speedup=14.275613x
batch_size=4096  total_speedup=4.791615x  core_speedup=47.841914x
batch_size=16384 total_speedup=2.978410x  core_speedup=44.619671x
```

The selected stable proof used `batch_size=4096`, `5` warmups, and `200` timed
runs:

```text
total_input_records=16384
representative_output_records=3
canonical_sha256=c8aa478626cad18a598140a00a39effba464c187109a2b71a2509806ff7aa802
cpu_mean_total_before_json_ms=1.031995
cuda_mean_total_before_json_ms=0.323783
cuda_total_speedup_vs_cpu=3.187304x
cpu_mean_core_ms=1.031995
cuda_mean_kernel_ms=0.030339
cuda_core_speedup_vs_cpu=34.015459x
```

Representative CPU, CUDA, and oracle `read-alignment-v1` outputs canonical-diff
`match`. The replicated memory-budget negative gate used `budget=1` and failed
closed before writing success JSON/TSV.

Allowed M5d claim:

```text
cuFlye CUDA read-alignment chain replay is faster than the C++ CPU baseline for
the controlled replicated-batch M5b fixture at batch_size=4096 while preserving
the representative read-alignment-v1 oracle.
```

Forbidden M5d claim:

```text
M5d does not prove real multi-read Flye speedup, default GPU mode, graph
mutation consumption, or end-to-end Flye acceleration.
```

Next highest-ROI task:

```text
M5e: replace replicated-batch evidence with real multi-read replay fixture
harvest and packed CUDA execution, preserving per-read oracle diffs before any
Flye graph-consumption integration.
```

Completed.

M5e adds multi-query read-alignment replay fixture harvest with
`CUFLYE_READ_ALIGNMENT_REPLAY_QUERY_IDS`. In multi-query mode, Flye writes one
`read-alignment-replay-fixture-v0` directory per selected read under
`query_<id>/`, while the older single-query flat layout remains compatible with
M5b-M5d.

M5e also adds real multi-fixture batch mode to
`cuflye-cuda-read-alignment-chain-replay`:

```text
--batch-fixtures-file FILE
--batch-output-dir DIR
--batch-json-output PATH
```

The first packed CUDA contract requires same-shape fixtures: identical
`alignment_input_records`, identical chain-divergence row counts, and identical
replay parameters. Unsupported mixed-shape batches fail closed instead of
falling back.

The DGX proof applied and built Flye 2.9.6 plus patches through
`0027-cuflye-read-alignment-multi-replay-fixture-dump.patch`. A toy-hifi
multi-query harvest dumped `68` real read fixtures from one Flye run. The
largest useful same-shape group selected for packed replay contained `19` real
reads:

```text
query_ids=1069,1100,1229,1252,1279,1480,1500,1584,1716,1820,1909,1930,1989,2080,2214,2332,2345,2390,667
alignment_input_records_per_fixture=3
total_input_records=57
output_records=38
```

Every selected CPU batch output and CUDA batch output validated as
`read-alignment-v1`. CPU vs oracle, CUDA vs oracle, and CPU vs CUDA
canonical diffs were `match` for all `19` reads.

Warm benchmark timing with `5` warmups and `200` timed runs:

```text
cpu_mean_total_before_json_ms=0.003566
cpu_mean_core_ms=0.003566
cuda_mean_total_before_json_ms=0.233540
cuda_mean_kernel_ms=0.011199
cuda_total_speedup_vs_cpu=0.015269x
cuda_total_slowdown_vs_cpu=65.490746x
cuda_core_speedup_vs_cpu=0.318421x
cuda_required_bytes=9595
```

The negative gates passed:

```text
mixed_shape: unsupported read-alignment batch: alignment_input_records differ
memory_budget: CUDA memory budget exceeded for read-alignment batch
```

Allowed M5e claim:

```text
cuFlye can harvest multiple real Flye read-alignment replay fixtures, execute a
same-shape 19-read packed CPU/CUDA batch, and preserve every per-read
read-alignment-v1 oracle diff.
```

Forbidden M5e claim:

```text
M5e does not prove real-batch CUDA speedup, default GPU mode, graph mutation
consumption, heterogeneous-shape batching, edlib/base realignment replay, or
end-to-end Flye acceleration.
```

Next highest-ROI task:

```text
M5f: increase useful real read-alignment work per CUDA launch, either by
harvesting larger same-shape batches from non-toy data, adding heterogeneous
packing, or moving read-alignment replay into a persistent worker before any
graph-consumption integration.
```

Completed as explicit heterogeneous shape-group execution.

M5f adds `--allow-heterogeneous-batch` to
`cuflye-cuda-read-alignment-chain-replay`. Default mixed-shape batch input
still fails closed. With the explicit flag, the runner groups fixtures by the
CUDA-supported shape key:

```text
alignment_input_records
chain_divergence_rows
maximum_jump
max_read_overlap
minimum_overlap
max_separation
```

Each group runs through the existing packed CPU/CUDA batch path, and output is
written back as one `read-alignment-v1` TSV per original fixture. Batch JSON now
records `heterogeneous_batch`, `shape_group_count`, min/max input records, and
one `shape_groups` entry per grouped launch.

The DGX proof reused the M5e toy-hifi multi-query harvest and ran all `68` real
fixtures:

```text
shape_group_count=4
input_records=1: fixture_count=30, total_input_records=30
input_records=2: fixture_count=11, total_input_records=22
input_records=3: fixture_count=19, total_input_records=57
input_records=4: fixture_count=8,  total_input_records=32
total_input_records=141
output_records=114
```

Every CPU heterogeneous output and CUDA heterogeneous output validated as
`read-alignment-v1`. CPU vs oracle, CUDA vs oracle, and CPU vs CUDA canonical
diffs were `match` for all `68` reads.

Warm benchmark timing with `5` warmups and `200` timed runs:

```text
cpu_mean_total_before_json_ms=0.021866
cpu_mean_core_ms=0.021866
cuda_mean_total_before_json_ms=0.899946
cuda_mean_kernel_ms=0.044258
cuda_total_speedup_vs_cpu=0.024297x
cuda_total_slowdown_vs_cpu=41.157322x
cuda_core_speedup_vs_cpu=0.494058x
cuda_required_bytes=9595
```

The default mixed-shape negative gate failed closed without
`--allow-heterogeneous-batch`, and the CUDA memory-budget negative gate failed
closed before writing success JSON/TSV.

Allowed M5f claim:

```text
cuFlye can explicitly group a heterogeneous 68-read real replay fixture list
into 4 supported CUDA shape groups, run packed CPU/CUDA batches per group, and
preserve every per-read read-alignment-v1 oracle diff.
```

Forbidden M5f claim:

```text
M5f does not prove heterogeneous-batch CUDA speedup, default GPU mode, graph
mutation consumption, edlib/base realignment replay, or end-to-end Flye
acceleration.
```

Next highest-ROI task:

```text
M5g: remove grouped-launch overhead or increase batch scale. Prefer a
persistent grouped read-alignment worker with reusable device buffers, then
test on larger non-toy fixture harvests before graph-consumption integration.
```

Completed as a persistent per-shape CUDA arena.

M5g adds `--cuda-persistent-arena` to
`cuflye-cuda-read-alignment-chain-replay`. The mode is explicit, batch-only,
and CUDA-only. It keeps the existing default behavior: mixed-shape batches still
fail closed unless `--allow-heterogeneous-batch` is set.

Persistent arena mode groups the fixture list by the same M5f shape key, then
allocates one reusable device-buffer set per shape group. Static
overlap/divergence fixture inputs are copied once before warmup/timed runs.
The benchmark timing records steady-state kernel/device-to-host/finalize cost,
while `timing_ms.one_time_*` records arena setup/allocation/H2D separately.

The DGX proof reused the same M5e toy-hifi multi-query harvest and ran all
`68` real fixtures:

```text
shape_group_count=4
input_records=1: fixture_count=30, total_input_records=30, output_records=30
input_records=2: fixture_count=11, total_input_records=22, output_records=22
input_records=3: fixture_count=19, total_input_records=57, output_records=38
input_records=4: fixture_count=8,  total_input_records=32, output_records=24
total_input_records=141
output_records=114
```

Every CPU, cold CUDA, persistent CUDA, and oracle per-fixture
`read-alignment-v1` output validated and canonical-diffed as `match`.

Warm benchmark timing with `5` warmups and `200` timed runs:

```text
cpu_mean_total_before_json_ms=0.010628
cpu_mean_core_ms=0.010628
cold_cuda_mean_total_before_json_ms=0.871576
cold_cuda_mean_kernel_ms=0.043325
persistent_cuda_mean_total_before_json_ms=0.377181
persistent_cuda_mean_kernel_ms=0.020074
persistent_cuda_speedup_vs_cold_cuda=2.310763x
persistent_cuda_core_speedup_vs_cold_cuda=2.158264x
persistent_cuda_speedup_vs_cpu=0.028177x
persistent_cuda_slowdown_vs_cpu=35.489368x
persistent_cuda_core_speedup_vs_cpu=0.529441x
one_time_arena_setup_allocation_h2d_ms=243.870057
```

The negative gates passed:

```text
cpu_backend: --cuda-persistent-arena requires --backend cuda
memory_budget: CUDA memory budget exceeded for persistent read-alignment arena
mixed_shape_default: unsupported read-alignment batch: alignment_input_records differ
```

Allowed M5g claim:

```text
cuFlye can explicitly reuse per-shape CUDA read-alignment arenas across
benchmark iterations for the 68-read heterogeneous M5e replay fixture set while
preserving every per-read oracle diff.
```

Forbidden M5g claim:

```text
M5g does not prove end-to-end Flye acceleration, default GPU mode, graph
mutation consumption, edlib/base realignment replay, or CUDA read-alignment
speedup over CPU for this small fixture set.
```

Next highest-ROI task:

```text
M5h: increase real read-alignment work per persistent CUDA invocation. Prefer
larger non-toy fixture harvests or a long-lived persistent read-alignment
worker before any graph-consumption integration.
```

Completed as a larger read-alignment fixture harvest and persistent-arena
diagnostic proof.

M5h adds `tools/select_read_alignment_fixture_batch.py`, a deterministic scanner
for `cuflye-read-alignment-replay-fixture-v0` directories. It validates fixture
shape, validates `oracle.read-alignment.tsv`, writes a selected fixture list,
and records shape distribution plus invalid fixture exclusions.

The DGX proof requested toy-hifi query ids `1..6000` through the existing M5e
multi-query replay dump protocol. The harvest produced:

```text
discovered_fixture_count=3577
valid_selected_fixture_count=3546
invalid_fixture_count=31
invalid_reason=read alignment dump is empty
shape_group_count=4
selected_total_input_records=3781
selected_total_oracle_records=3616
```

Selected shape distribution:

```text
input_records=1: fixture_count=3418, total_input_records=3418, total_oracle_records=3418
input_records=2: fixture_count=29,   total_input_records=58,   total_oracle_records=45
input_records=3: fixture_count=91,   total_input_records=273,  total_oracle_records=129
input_records=4: fixture_count=8,    total_input_records=32,   total_oracle_records=24
```

Every CPU, cold CUDA, persistent CUDA, and oracle per-fixture
`read-alignment-v1` output validated and canonical-diffed as `match` across all
`3546` selected fixtures.

Warm benchmark timing with `5` warmups and `50` timed runs:

```text
cpu_mean_total_before_json_ms=0.332580
cpu_mean_core_ms=0.332580
cold_cuda_mean_total_before_json_ms=18.270376
cold_cuda_mean_kernel_ms=0.048954
persistent_cuda_mean_total_before_json_ms=18.301868
persistent_cuda_mean_kernel_ms=0.026174
persistent_cuda_speedup_vs_cold_cuda=0.998279x
persistent_cuda_speedup_vs_cpu=0.018172x
persistent_cuda_slowdown_vs_cpu=55.029972x
persistent_cuda_core_speedup_vs_cpu=12.706503x
persistent_cuda_core_speedup_vs_cold_cuda=1.870329x
persistent_cuda_device_to_host_ms=18.156663
```

Allowed M5h claim:

```text
cuFlye can expand read-alignment replay proof from 68 toy-hifi fixtures to a
wider 3546-fixture harvest and run the persistent CUDA arena while preserving
every per-read oracle diff.
```

Forbidden M5h claim:

```text
M5h does not prove default GPU mode, graph mutation consumption, edlib/base
realignment replay, end-to-end Flye acceleration, or CPU-beating
read-alignment speed.
```

M5i adds `--cuda-persistent-bulk-output`, an explicit CUDA batch mode layered on
top of `--cuda-persistent-arena`. It keeps the same kernel and per-fixture
`DeviceSummary` contract, but copies one output buffer per shape group and
slices that host buffer into the existing per-fixture `read-alignment-v1`
outputs.

The DGX proof reused the M5h larger selected fixture list:

```text
selected_fixture_count=3546
selected_total_input_records=3781
selected_total_output_records=3616
shape_group_count=4
```

Every oracle, CPU, current persistent CUDA, and bulk persistent CUDA
per-fixture `read-alignment-v1` output validated and canonical-diffed as
`match` across all `3546` selected fixtures.

Warm benchmark timing with `5` warmups and `50` timed runs:

```text
cpu_mean_total_before_json_ms=0.333798
cpu_mean_core_ms=0.333798
current_persistent_cuda_mean_total_before_json_ms=17.862780
current_persistent_cuda_mean_kernel_ms=0.025782
current_persistent_cuda_device_to_host_ms=17.680561
bulk_persistent_cuda_mean_total_before_json_ms=0.302834
bulk_persistent_cuda_mean_kernel_ms=0.025953
bulk_persistent_cuda_device_to_host_ms=0.223648
bulk_total_speedup_vs_cpu=1.102247x
bulk_total_speedup_vs_current_persistent=58.985385x
bulk_d2h_speedup_vs_current_persistent_d2h=79.055306x
bulk_core_speedup_vs_cpu_core=12.861634x
```

Allowed M5i claim:

```text
cuFlye can run the bounded M5h read-alignment chain replay harvest through an
explicit persistent CUDA bulk-output mode faster than the CPU replay baseline
before TSV/JSON emission while preserving every per-read oracle diff.
```

Forbidden M5i claim:

```text
M5i does not prove default GPU mode, Flye graph mutation consumption,
edlib/base realignment replay, or end-to-end Flye acceleration.
```

M5j adds `0028-cuflye-read-alignment-graph-dry-run-seam.patch`, an explicit
Flye-side read-alignment worker dry-run seam selected by:

```text
CUFLYE_READ_ALIGNMENT_WORKER_MODE=cuda-bulk-persistent-v0
CUFLYE_READ_ALIGNMENT_GRAPH_CONSUMPTION_MODE=dry-run-v0
```

The seam reuses the M5b/M5e replay fixture dump boundary, invokes
`cuflye-cuda-read-alignment-chain-replay` with
`--cuda-persistent-arena --cuda-persistent-bulk-output`, validates every worker
output against the fixture oracle, writes graph guard metadata, and then stops
before graph mutation.

The DGX positive proof used toy-hifi query ids `5,47,200,204`:

```text
worker_mode=cuda-bulk-persistent-v0
cuda_execution_mode=persistent-arena-bulk-output
worker_validation_status=passed
fixture_count=4
validated_fixture_count=4
independent_python_oracle_diffs=4/4 match
graph_guard_status=passed
graph_consumption_state=not-consumed
graph_mutation_consumed_worker_output=false
run_status=stopped-before-graph-mutation
```

The DGX negative proof enabled the same seam for query ids `5,47` without
`CUFLYE_READ_ALIGNMENT_WORKER_BIN`. It failed closed with:

```text
worker_validation_status=worker-failed
graph_guard_status=failed
graph_consumption_state=failed-closed
graph_mutation_consumed_worker_output=false
```

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

M5k accepted result:

```text
cuFlye can convert validated CUDA read-alignment worker TSV rows into
Flye-side GraphAlignment-shaped typed records, confirm current repeat-graph
edge identity, validate chain segment continuity, canonicalize the typed
records back to read-alignment fields, and match the CPU oracle while still
stopping before graph mutation.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5k-proof-20260701T005103Z
positive_query_ids=5,47,200,204
worker_validation_status=passed
graph_guard_status=passed
read_alignment_rehydration_status=passed
read_alignment_rehydration_state=not-consumed
read_alignment_rehydration_total_records=7
read_alignment_rehydration_total_chains=4
graph_mutation_consumed_worker_output=false
```

The DGX negative proof enabled
`CUFLYE_READ_ALIGNMENT_REHYDRATION_PROOF_FAULT=drop-first-worker-record` for
query ids `5,47`. Worker validation and graph guard both passed first, then
typed rehydration failed closed with:

```text
read_alignment_rehydration_status=failed
read_alignment_rehydration_state=failed-closed
read_alignment_rehydration_decision=failed-closed-before-graph-mutation
graph_mutation_consumed_worker_output=false
```

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

M5l accepted result:

```text
cuFlye can group validated CUDA read-alignment typed segments into a shadow
std::vector<GraphAlignment> object-vector, compare the object vector against
the CPU _readAlignments slice for selected reads, and still stop before graph
mutation.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5l-proof-20260701T010956Z
positive_query_ids=5,47,200,204
worker_validation_status=passed
graph_guard_status=passed
read_alignment_rehydration_status=passed
read_alignment_object_rehydration_status=passed
read_alignment_object_rehydration_state=not-consumed
object_representation=graph-alignment-object-vector-v0
total_object_records=7
total_object_chains=4
graph_mutation_consumed_worker_output=false
```

The DGX negative proof enabled
`CUFLYE_READ_ALIGNMENT_OBJECT_REHYDRATION_PROOF_FAULT=drop-first-graph-alignment-chain`
for query ids `5,47`. Worker validation, graph guard, and M5k typed
rehydration passed first. Object-vector comparison then failed closed with:

```text
read_alignment_object_rehydration_status=failed
read_alignment_object_rehydration_state=failed-closed
read_alignment_object_rehydration_decision=failed-closed-before-graph-mutation
graph_mutation_consumed_worker_output=false
```

Allowed M5l claim:

```text
cuFlye can convert validated CUDA read-alignment output into a shadow
std::vector<GraphAlignment>, prove that it matches the CPU _readAlignments
slice, and still stop before graph mutation.
```

Forbidden M5l claim:

```text
M5l does not prove default GPU mode, replacement of Flye _readAlignments, graph
mutation consumption, or end-to-end Flye acceleration.
```

M5m accepted result:

```text
cuFlye can substitute a verified CUDA-derived GraphAlignment object vector for a
small selected _readAlignments slice, preserve exact Flye artifacts, and fail
closed on mismatch before graph mutation.
```

DGX proof:

```text
proof_root=/tmp/cuflye-m5m-proof-20260701T013646Z
positive_query_ids=5,47,200,204
worker_validation_status=passed
graph_guard_status=passed
read_alignment_rehydration_status=passed
read_alignment_object_rehydration_status=passed
read_alignment_vector_substitution_status=passed
read_alignment_vector_substitution_state=consumed
total_cpu_records=7
total_object_records=7
total_substituted_chains=4
graph_facing_returned_worker_output=true
graph_mutation_consumed_worker_output=true
positive_vs_cpu_canonical_diff=match
```

The DGX negative proof enabled
`CUFLYE_READ_ALIGNMENT_VECTOR_SUBSTITUTION_PROOF_FAULT=drop-first-substitution-chain`
for query ids `5,47`. Worker validation, graph guard, typed rehydration, and
object-vector rehydration passed first. Vector substitution then failed closed
with:

```text
read_alignment_vector_substitution_status=failed
read_alignment_vector_substitution_state=failed-closed
read_alignment_vector_substitution_decision=failed-closed-before-graph-mutation
graph_facing_returned_worker_output=false
graph_mutation_consumed_worker_output=false
```

Allowed M5m claim:

```text
cuFlye can let verified CUDA-derived read-alignment output cross the first real
Flye _readAlignments consumption boundary for a selected tiny slice, while
preserving exact canonical Flye artifacts and fail-closing before graph mutation
on mismatch.
```

Forbidden M5m claim:

```text
M5m does not prove default GPU mode, broad _readAlignments replacement, removal
of CPU read alignment, or end-to-end Flye acceleration.
```

Next highest-ROI task:

```text
M5n: reduce duplicate CPU work around the read-alignment substitution path by
introducing a guarded GPU-first read-alignment planner for selected safe slices,
with artifact parity and fail-closed gates preserved.
```
