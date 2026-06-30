# cuFlye CUDA-enabled Flye Roadmap

Status: active

Last updated: 2026-06-30

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
M4l: add a validated consumption gate before any future graph-consumption path
can treat CUDA overlap worker output as consumption-eligible.
```

Acceptance should preserve exact per-fixture `overlap-range-v1` hashes, require
ABI validation and oracle diff checks before marking worker output
consumption-eligible, include a negative fail-closed validation case, and still
stop before graph mutation.
