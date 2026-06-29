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
