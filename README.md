# rummage

Built on [uvr](https://github.com/nbafrank/uvr) — the fast Rust-based R
package manager (manifest, lockfile, P3M pre-built binaries) — with
[Apptainer](https://apptainer.org) definition files that package the
resulting environment into a portable SIF.

<details>
<summary>Credits</summary>

- **[uvr](https://github.com/nbafrank/uvr)** ([nbafrank/uvr](https://github.com/nbafrank/uvr))
  does the actual package management: `uvr.toml` manifests, `uvr.lock`
  lockfiles, P3M binary installs, and R version management. This repo is
  just the container packaging around it. Go star the original.
- **LLM-assisted development**: this codebase was written with the help of
  [GLM-5.3-Flash](https://github.com/zai-org/GLM) served from
  [Ollama Cloud](https://ollama.com/cloud) using the
  [oh-my-pi](https://github.com/can1357/oh-my-pi) agent harness. All build
  steps, container runs, and package installs were verified with real
  executions; every claim in this README was exercised, not assumed.

</details>

## What's here

| File | Purpose |
|------|---------|
| `rummage-base.def` | Ubuntu 24.04 + R + the uvr binary. No R packages. |
| `rummage-app.def`  | Starts from `rummage-base.sif`, bakes a package library. |
| `Makefile`         | Build driver: builds the base only when missing/stale. |
| `example/`         | Minimal analysis project (uvr.toml + script) showing the workflow. |

## Two ways to define the package set

1. **`make PACKAGES=...`** — package list on the command line. No `uvr.toml`
   needed in the build context; the image generates one internally.

       make PACKAGES="terra,tidyverse,ggplot2"

2. **A `uvr.toml` in the build context** — the app def picks it up via `%files`.
   Use this when you need version pins or git/Bioconductor sources.

       uvr add terra ggplot2   # or edit uvr.toml by hand
       make

The two modes are mutually exclusive per build: if the build context has a
`uvr.toml`, `make PACKAGES=...` ignores it; the `PACKAGES` build arg overrides.

## Building

Requires [apptainer](https://apptainer.org) with fakeroot enabled.

```sh
# Both stages in one command (base is rebuilt only if missing or stale):
make PACKAGES="terra,ggplot2"

# Or with pinned toolchain versions:
make PACKAGES="terra,ggplot2" R_VERSION=4.5.1 UVR_VERSION=v0.4.6

# Or drive apptainer directly:
apptainer build --fakeroot rummage-base.sif rummage-base.def
apptainer build --fakeroot --build-arg 'PACKAGES=terra ggplot2' \
    rummage-app.sif rummage-app.def
```

Notes:

- `PACKAGES` accepts comma- or space-separated names. **Commas are converted
  to spaces by the Makefile** — `apptainer build --build-arg` itself splits
  values on commas, so a direct invocation must use spaces.
- Default (no `--build-arg`s) is latest: R from the CRAN Ubuntu apt repo
  (`noble-cran40`, current 4.x line) and the latest uvr release. Two builds
  of the same def can therefore differ — the generated `uvr.lock` (below) is
  the actual reproducibility record.
- `--build-arg` flags must come **before** the positional `IMAGE PATH`
  `BUILD SPEC` arguments.

### Pinned R installs

When `R_VERSION` is set, R comes from a Posit prebuilt deb into
`/opt/R/<version>` (all recommended packages and headers bundled; no
`r-base-dev` needed). When unset, R comes from the CRAN apt repo.

## Running

The app image bind-mounts your working directory at `/work` and runs R
scripts against the baked library:

```sh
# Run an analysis script:
apptainer run --bind "$(pwd)":/work rummage-app.sif analysis.R

# Interactive R console with the baked library:
apptainer run --bind "$(pwd)":/work rummage-app.sif R

# Explicit tool invocations:
apptainer run --bind "$(pwd)":/work rummage-app.sif Rscript other-script.R
apptainer run --bind "$(pwd)":/work rummage-app.sif uvr doctor
```

On first run the runscript copies the baked `uvr.lock` out to `/work` if
absent (that lockfile is the detailed record of what was resolved). If a
`uvr.lock` is already there and differs from the baked one, it warns but
still runs.

## Example

```sh
make PACKAGES="terra,ggplot2"
apptainer run --bind "$(pwd)":/work rummage-app.sif example/analysis.R
```

For your own analysis, point the bind at your project directory. If it
contains a `uvr.toml`, you can build an app image from it with plain `make`
(from that directory, with the defs available).

## Housekeeping

```sh
make clean       # removes both SIFs and the package-list stamp
```

The SIFs, `.packages.stamp`, and `.uvr/` are gitignored build artifacts —
everything committed is sufficient to rebuild them.