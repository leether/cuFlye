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

Current allowed performance claim:

```text
The bounded candidate equality-scan core is faster on CUDA than the CPU oracle
for the measured synthetic lookup-key pair space.
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

- Define an overlap-range ABI.
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
M2e: add a real-pack adapter-boundary timing proof that compares Flye's packed
CPU candidate generation, standalone CUDA candidate generation, and external
adapter overhead on the same `pack-dump-v0` query.
```

Acceptance should remain candidate-list equivalence plus honest timing
breakdown. Do not claim full assembly speed until downstream graph equivalence
is proven.
