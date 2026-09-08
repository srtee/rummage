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
| `rummage-studio-base.def` | `rummage-base` + RStudio Server (web IDE, port 18787). |
| `rummage-studio-app.def`  | Starts from `rummage-studio-base.sif`, bakes a package library. |
| `Makefile`         | Build driver: builds the base only when missing/stale. |
| `example/`         | Minimal analysis project (uvr.toml + script) showing the workflow. |

## Three ways to define the package set

1. **`make PACKAGES=...`** — package list on the command line. No `uvr.toml`
   needed in the build context; the image generates one internally.

       make PACKAGES="terra,tidyverse,ggplot2"

2. **A `uvr.toml` in the build context** — the app def picks it up via `%files`.
   Use this when you need version pins or git/Bioconductor sources.

       uvr add terra ggplot2   # or edit uvr.toml by hand
       make

   There is also a third mode: **`make all-deps`** bakes everything in the
   build context's `uvr.toml` — `[dependencies]` *and* `[dev-dependencies]`
   (testthat, devtools, etc.). `PACKAGES` must be unset for this; a
   generated-from-PACKAGES manifest has no dev section by construction.

The two base modes are mutually exclusive per build: if the build context
has a `uvr.toml`, `make PACKAGES=...` ignores it; the `PACKAGES` build arg
overrides.

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

## RStudio Server variant (studio)

`rummage-studio-base.def` adds [RStudio Server](https://posit.co/download/rstudio-server/)
(Open Source, AGPL) on top of `rummage-base`; `rummage-studio-app.def` bakes
the package library onto that, exactly as `rummage-app.def` does — same
`PACKAGES`/`uvr.toml`/`all-deps` modes, same P3M binary installs.

```sh
# Build (base only if missing/stale):
make studio PACKAGES="terra,ggplot2"
make studio-all-deps                      # everything in uvr.toml

# Run as a persistent background instance:
make studio-run
#   → http://localhost:18787   login: studio / studio
make studio-stop                          # shut it down
```

Notes:

- **Port**: default 18787, set at build time via `RSTUDIO_PORT`
  (`make studio RSTUDIO_PORT=8787`). Apptainer shares the host network
  namespace, so a port already used by a host service is unavailable —
  8787 (the RStudio default) is a frequent collision.
- **Login**: user `studio`, password `studio` (set at build). rserver runs
  as root inside the container so PAM can authenticate against
  `/etc/shadow`; each browser session still runs unprivileged as
  `studio`, which has passwordless sudo inside the container.
- **Writable state binds**: the SIF's `/var` is read-only, so `studio-run`
  binds `/tmp/rstudio-state` over `/var/{lib,log,run}/rstudio-server` and
  adds `--writable-tmpfs`. That directory is disposable session state;
  if the server misbehaves after crashes, `rm -rf /tmp/rstudio-state &&
  make studio-stop && make studio-run` resets it.
- `make studio-run` uses `apptainer instance start`, which survives the
  calling shell — check `apptainer instance list`, stop with
  `make studio-stop`.
- Same pinning as the non-studio images: `R_VERSION`, `UVR_VERSION` at
  build; plus `RSTUDIO_VERSION` (`latest` or e.g. `2026.08.2-200`).

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
make clean       # removes all SIFs and the package-list stamp
make studio-stop # if a studio instance is running
```
The SIFs, `.packages.stamp`, and `.uvr/` are gitignored build artifacts —
everything committed is sufficient to rebuild them.