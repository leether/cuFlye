# CUDA-enabled Flye design

## Positioning

The realistic target is not a clean-room "GPU Flye". The realistic target is a
Flye 2.9.6-compatible fork with CUDA backends for selected hot kernels, while
keeping the upstream command-line behavior, stage boundaries, intermediate file
formats, and CPU implementation as the reference oracle.

See `GENOMEWORKS_NOTES.md` for a source-level read of NVIDIA GenomeWorks
`cudamapper`, `cudapoa`, and `cudaaligner`, and how those designs influence the
backend split below.

Current upstream shape, checked against `upstream-flye`:

- Python pipeline driver: `flye/main.py`
- Native module dispatcher: `src/main.cpp`
- Native subcommands: `assemble`, `repeat`, `contigger`, `polisher`
- Read overlap and read-to-graph alignment core: `src/sequence/*`,
  `src/repeat_graph/read_aligner.cpp`
- Polishing map/sort stage: `flye/polishing/alignment.py` via vendored minimap2
  and samtools
- Bubble correction: `src/polishing/*`

The public GPU mode should be opt-in:

```text
flye ... --threads N --gpu
flye ... --threads N --gpu --gpu-devices 0,1 --gpu-batch-mb 8192
flye ... --gpu --verify-cpu-kernels
```

CPU remains the default. Every CUDA backend must have a CPU fallback and a parity
test against the upstream CPU path.

## What "precise replication" means

Bit-identical output for every dataset is too brittle as a product requirement:
Flye already has thread-order-sensitive paths, and GPU parallelism changes
candidate ordering unless we deliberately stabilize it. The right contract is:

1. CLI compatibility: all existing Flye options and outputs remain valid.
2. Stage compatibility: `00-assembly`, `20-repeat`, `30-contigger`, polishing,
   and final output files retain the same names and schemas.
3. Algorithm compatibility: CUDA kernels implement the same scoring,
   thresholds, tie-breaking, canonical k-mer/minimizer rules, overlap filters,
   and graph-read alignment semantics.
4. Deterministic mode: with deterministic execution enabled, GPU mode must
   produce identical canonicalized intermediate artifacts on the regression set,
   or fail closed to CPU.
5. Scientific equivalence: on non-deterministic high-throughput mode, final
   assembly graph/contig outputs must match CPU within a defined equivalence
   harness: canonical GFA graph, contig sequence identity, contig lengths,
   coverage tags, and read-alignment support.

For exact reruns, use deterministic or CPU-verified GPU mode. Do not silently
substitute a different assembler pipeline such as `cudamapper + miniasm`.

## CUDA acceleration boundaries

### Keep on CPU

These components are branch-heavy graph algorithms and should stay CPU in the
first production design:

- Repeat graph construction and simplification:
  `src/repeat_graph/repeat_graph.cpp`,
  `src/repeat_graph/multiplicity_inferer.cpp`,
  `src/repeat_graph/repeat_resolver.cpp`,
  `src/repeat_graph/haplotype_resolver.cpp`
- Contig/scaffold path generation:
  `src/contigger/contig_extender.cpp`
- Python orchestration, resume state, and final file movement:
  `flye/main.py`

GPU should feed these stages the same overlap/read-alignment artifacts, not
replace the graph logic.

### Accelerate first

1. Read/read and read/graph candidate generation
   - Current hotspots are minimizer or solid k-mer indexing and candidate
     lookup in `VertexIndex` plus `OverlapDetector::getSeqOverlaps`.
   - CUDA backend should build sorted `(kmer, read_id, pos, strand)` arrays,
     generate candidate pairs by k-mer bucket, then return candidates in stable
     CPU-compatible order.

2. Chaining and overlap scoring
   - Current chain DP is in `OverlapDetector::getSeqOverlaps`.
   - GPU version should batch many candidate read pairs. Preserve exact gap
     penalties, `maximum_jump`, `max_jump_gap`, `minimumOverlap`,
     overhang filters, and divergence thresholds.

3. Base-level alignment checks
   - Current code uses edlib and ksw2-style alignment in
     `src/sequence/alignment.cpp`.
   - CUDA can accelerate batched pairwise alignment, but the scoring and cigar
     decoding must remain compatible. This is a good place to evaluate
     GenomeWorks `cudaaligner` only after a wrapper proves parity.

4. Polishing bubble correction
   - Bubble-level work in `src/polishing/bubble_processor.cpp` is naturally
     batchable. GPU can process batches of bubbles below `MAX_BUBBLE` while
     preserving output ordering.
   - `cudapoa` may help here, but only behind a Flye-compatible scoring wrapper.

### Defer

- Replacing polishing minimap2 with a GPU mapper. This changes too much at once:
  Flye currently expects minimap2/SAM/BAM behavior, including secondary
  sequence handling and sorted/indexed BAM. GPU mapping can be a later backend
  only if it reproduces those downstream-visible semantics.
- Full GPU repeat graph simplification. It is unlikely to pay back before the
  overlap/alignment kernels are solved.

## Proposed code architecture

Add a backend interface layer without changing existing stage contracts:

```text
src/cuda/
  cuda_runtime.{h,cu}
  cuda_sequences.{h,cu}
  cuda_kmer_index.{h,cu}
  cuda_overlap_candidates.{h,cu}
  cuda_overlap_chain.{h,cu}
  cuda_alignment.{h,cu}
  cuda_polishing.{h,cu}

src/sequence/
  overlap_backend.h
  overlap_backend_cpu.cpp
  overlap_backend_cuda.cpp

src/polishing/
  polish_backend.h
  polish_backend_cpu.cpp
  polish_backend_cuda.cpp
```

Public selection:

- Python `flye/main.py` accepts `--gpu`, `--gpu-devices`, `--gpu-batch-mb`,
  `--verify-cpu-kernels`.
- Python passes those options to `flye-modules assemble/repeat/contigger/polisher`.
- C++ stores runtime settings in `Parameters` or a new `RuntimeOptions`.
- Backend selection is per module and per kernel, with CPU fallback on unsupported
  data shape or CUDA failure.

Internal data contracts:

- Pack sequences once per stage into contiguous base arrays plus read offset and
  read id tables.
- Use canonical k-mers/minimizers exactly as Flye does, including reverse
  complement position transforms.
- Sort all GPU-generated records by deterministic keys before returning to CPU:
  `(query_id, target_id, query_pos, target_pos, strand, score)`.
- Never use atomic append order as semantic order.

## Milestones

### M0: Baseline and proof harness

- Build unmodified Flye 2.9.6 locally.
- Run upstream tests and at least one small PacBio/ONT fixture.
- Add canonical diff tools for:
  - `draft_assembly.fasta`
  - `repeat_graph_dump`
  - `read_alignment_dump`
  - `repeat_graph_edges.fasta`
  - `graph_final.gfa`
  - final `assembly.fasta`
- Add profiler capture on target DGX data to rank hotspots before writing CUDA.

Gate: CPU baseline is reproducible and profiled.

### M1: GPU candidate generation only

- Implement CUDA sequence packing and k-mer/minimizer bucket construction.
- Return candidate match lists to existing CPU chaining.
- Compare candidate lists against CPU on toy and sampled real reads.

Gate: same candidates after canonical sorting, no graph/output changes.

### M2: GPU overlap chaining

- Port the per-target-chain DP used by `OverlapDetector::getSeqOverlaps`.
- Keep CPU divergence/base-alignment checks initially.
- Compare full `OverlapRange` output against CPU for sampled reads.

Gate: overlap dumps match in deterministic mode.

### M3: GPU read-to-graph alignment

- Reuse M1/M2 kernels for `ReadAligner::alignReads`.
- Preserve read chain construction and graph edge mapping semantics.

Gate: `read_alignment_dump` matches CPU on regression fixtures.

### M4: GPU bubble polishing

- Batch `BubbleProcessor` work while preserving output order.
- Optionally evaluate `cudapoa` or custom kernels behind exact Flye scoring.

Gate: polishing consensus output matches CPU for all fixtures.

### M5: Integrated experimental release

- Expose `--gpu` as experimental.
- Include CPU fallback and `--verify-cpu-kernels`.
- Publish performance matrix: bacterial, fungal, metagenome, mammalian-scale
  sampled runs.

Gate: faster than CPU on target workloads without losing compatibility.

## Regression matrix

Minimum fixtures:

- Upstream toy tests.
- Small E. coli PacBio CLR.
- Small ONT raw.
- HiFi dataset.
- Metagenome or uneven-coverage fixture.
- A target DGX sampled subset from the exact rerun workload.

For each fixture:

- CPU default.
- CPU deterministic.
- GPU deterministic with CPU verification.
- GPU throughput mode.

Acceptance:

- Deterministic mode: canonical intermediate artifacts match, or the kernel
  falls back to CPU.
- Throughput mode: final assembly and graph equivalence pass; all deviations are
  logged and auditable.
- Performance claims include wall time, peak RAM, peak GPU memory, GPU occupancy,
  and time spent in CPU fallback.

## Immediate DGX implication

For the current PacBio CLR exact rerun, GPU-enabled Flye is not an immediate
stopbleed. The exact rerun should continue using upstream CPU Flye unless and
until the CUDA fork passes deterministic intermediate-artifact parity. The first
useful DGX work item is profiling and fixture extraction, not changing production
assembly parameters.
