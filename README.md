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

- `PACKAGES` accepts comma- or space-separated names — both spellings
  work identically, through the Makefile or a direct
  `apptainer build --build-arg` invocation.
- Default (no `--build-arg`s) is latest: R from the CRAN Ubuntu apt repo
  (`noble-cran40`, current 4.x line, with the matching `r-base-dev`
  toolchain) and the latest uvr release. Two builds of the same def can
  therefore differ — the generated `uvr.lock` (below) is the actual
  reproducibility record.
- `--build-arg` flags must come **before** the positional `IMAGE PATH`
  `BUILD SPEC` arguments.

### Pinned R installs

R always comes from the CRAN Ubuntu apt repo. When `R_VERSION` is set, the
build resolves the newest matching deb in the repo index and pins
`r-base-core`, `r-base`, `r-recommended`, and `r-base-dev` to that exact
version — so the compiler toolchain always matches the pinned R. When
unset, latest R installs (`r-base` + `r-base-dev`).

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
#   → http://localhost:18787   (logged in as your own user)
make studio-stop                          # shut it down
```

Or run directly (the `--scratch` flag below is REQUIRED — the SIF's
`/var` is read-only):

```sh
apptainer run --bind "$(pwd)":/work \
    --scratch /var/lib/rstudio-server,/var/log/rstudio-server,/var/run/rstudio-server \
    rummage-studio-app.sif
```

rserver logs to syslog, so this stays silent on success — confirm the
server is up with `ss -ltn | grep 18787`, then open the URL. Starting it
without `--scratch` fails with *"system error 30 (Read-only file system)
[path: /var/run/rstudio-server ...]"*. Scratch state is tmpfs-backed and
discarded when the instance stops.

Notes:

- **Port**: default 18787, set at build time via `RSTUDIO_PORT`
  (`make studio RSTUDIO_PORT=8787`). Apptainer shares the host network
  namespace, so a port already used by a host service is unavailable —
  8787 (the RStudio default) is a frequent collision.
- **Login**: none. rserver runs as the invoking user (`--server-user
  $(whoami)` in the runscripts), so the IDE session is your own host
  account ($HOME included); no container-side account exists. Single-user
  by design.
- **Scratch state**: the SIF's `/var` is read-only, so `studio-run` and
  the direct-run command mount tmpfs scratch dirs over
  `/var/{lib,log,run}/rstudio-server` via `--scratch`. That state is
  ephemeral — `make studio-stop && make studio-run` resets it.
- `make studio-run` uses `apptainer instance start`, which survives the
  calling shell — check `apptainer instance list`, stop with
  `make studio-stop`.
- Same pinning as the non-studio images: `R_VERSION`, `UVR_VERSION` at
  build; plus `RSTUDIO_VERSION` (`latest` or e.g. `2026.08.2-200`).

### Sessions and files in /work (studio)

RStudio sessions don't inherit the server's environment, so the image
sets the library path for every session via `r-libs-user` in
`/etc/rstudio/rsession.conf` and `R_LIBS_USER` in `/etc/R/Renviron.site`.
The baked library is active in the IDE out of the box — no activation
step.

At startup the runscript also prepares `/work`:

- `uvr.toml` / `uvr.lock`: copied out if absent; existing copies are
  chmod'ed 644 if unreadable. Warns if the copy differs from what's
  baked into the image (the image remains the environment spec).
- `.Rhistory` / `.RData`: created empty if absent; existing copies are
  chmod'ed 666. RStudio writes session records here, and a file the
  container can't write would silently kill history and session
  restore. 666 means any writer can save — your host user, root in a
  `--fakeroot` maintenance run, or a uid left by an earlier run — which
  also covers repeat runs picking up where the last one left off.

**Caveat**: the 666 chmod applies to files on your host through the
`/work` bind. Fine for a single-user project directory; if you bind a
directory shared with other people, every local user on the host can
write your `.Rhistory`/`.RData`. Bind a private directory, or set the
modes yourself afterwards.

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