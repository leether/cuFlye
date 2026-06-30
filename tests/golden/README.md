# Golden Manifests

This directory stores small, reviewable golden manifests for oracle fixtures.

Do not commit full Flye run directories, generated assemblies, BAM/SAM files, or
profiler dumps here. Store compact manifests, canonical hashes, and summary
proof only.

Accepted fixtures:

- `toy-hifi`: upstream Flye E. coli 500 kb HiFi toy fixture from
  `upstream-flye/flye/tests/data/ecoli_500kb_reads_hifi.fastq.gz`.
  - Manifest: `toy-hifi-dgx-aarch64.json`
  - Candidate oracle manifest: `toy-hifi-candidate-dgx-aarch64.json`
  - Candidate backend seam manifest: `toy-hifi-backend-dgx-aarch64.json`
  - Candidate ABI manifest: `toy-hifi-candidate-abi-dgx-aarch64.json`
  - CUDA backend stub manifest: `toy-hifi-cuda-stub-dgx-aarch64.json`

ABI proof manifests use the same fixture and must reference compact validator
summaries, not full candidate TSV files.

CUDA runtime proof:

- Runtime probe manifest: `cuda-runtime-probe-dgx-aarch64.json`

CUDA candidate smoke proof:

- Candidate smoke manifest: `cuda-candidate-smoke-dgx-aarch64.json`

CUDA k-mer join smoke proof:

- K-mer join smoke manifest: `cuda-kmer-join-smoke-dgx-aarch64.json`

CUDA k-mer encode smoke proof:

- K-mer encode smoke manifest: `cuda-kmer-encode-smoke-dgx-aarch64.json`

CUDA read-window smoke proof:

- Read-window smoke manifest: `cuda-read-window-smoke-dgx-aarch64.json`

CUDA candidate-core benchmark proof:

- Candidate-core benchmark manifest: `cuda-candidate-core-bench-dgx-aarch64.json`

CUDA RAII resource-layer proof:

- CUDA RAII resource-layer manifest: `cuda-raii-resource-layer-dgx-aarch64.json`
