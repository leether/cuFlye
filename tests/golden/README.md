# Golden Manifests

This directory stores small, reviewable golden manifests for M0 oracle fixtures.

Do not commit full Flye run directories, generated assemblies, BAM/SAM files, or
profiler dumps here. Store compact manifests and canonical hashes only.

Accepted fixtures:

- `toy-hifi`: upstream Flye E. coli 500 kb HiFi toy fixture from
  `upstream-flye/flye/tests/data/ecoli_500kb_reads_hifi.fastq.gz`.
  - Manifest: `toy-hifi-dgx-aarch64.json`
