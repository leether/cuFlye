# Golden Manifests

This directory stores small, reviewable golden manifests for M0 oracle fixtures.

Do not commit full Flye run directories, generated assemblies, BAM/SAM files, or
profiler dumps here. Store compact manifests and canonical hashes only.

Expected first fixture:

- `toy-hifi`: upstream Flye E. coli 500 kb HiFi toy fixture from
  `upstream-flye/flye/tests/data/ecoli_500kb_reads_hifi.fastq.gz`.

After the DGX M0 run is accepted, add a fixture manifest that records:

- cuFlye commit
- Flye upstream commit/tag
- host architecture
- fixture parameters
- canonical artifact hashes
- profile summary path or attached proof location
