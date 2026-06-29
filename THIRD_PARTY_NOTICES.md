# Third-Party Notices

This repository is initialized as a Flye-compatible CUDA backend project.

## Project License

Original code in this repository is licensed under BSD-3-Clause unless a file
declares a different SPDX license identifier.

## Upstream Flye

Flye is distributed under BSD-3-Clause.

- Source reviewed locally: `upstream-flye`
- Upstream repository: `https://github.com/mikolmogorov/Flye`
- License file: `LICENSES/BSD-3-Clause.txt`

If Flye source files are copied into this repository, preserve the original
copyright notices and file headers.

## NVIDIA GenomeWorks

NVIDIA GenomeWorks is distributed under Apache-2.0.

- Source reviewed locally: `GenomeWorks`
- Upstream repository: `https://github.com/NVIDIA-Genomics-Research/GenomeWorks`
- License file: `LICENSES/Apache-2.0.txt`

If GenomeWorks source files or substantial derived code are copied into this
repository, those files must retain Apache-2.0 headers and should use:

```text
SPDX-License-Identifier: Apache-2.0
```

Design ideas from GenomeWorks do not by themselves impose Apache-2.0 on new
code.

## Known Flye Third-Party Components

The upstream Flye source tree vendors or references permissively licensed
third-party components. If those components are copied into this repository,
retain their original notices and licenses.

- minimap2: MIT
- samtools / htslib: MIT/Expat-style license
- intervaltree: MIT
- LEMON: Boost Software License 1.0
- libcuckoo: Apache-2.0
- selected utility snippets may carry their own notices in source headers

## File-Level Licensing Rule

Use SPDX identifiers in new source files:

```text
SPDX-License-Identifier: BSD-3-Clause
```

Use `Apache-2.0` only for files copied from or substantially derived from
GenomeWorks or other Apache-2.0 sources.
