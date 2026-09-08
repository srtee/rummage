BASE_SIF := rummage-base.sif
APP_SIF  := rummage-app.sif
BASE_DEF := rummage-base.def
APP_DEF  := rummage-app.def

comma := ,

# Pin toolchain versions here, or leave empty for latest.
# R_VERSION = 4.5.1
# UVR_VERSION = v0.4.6
BUILD_ARGS := $(if $(R_VERSION),--build-arg R_VERSION=$(R_VERSION)) $(if $(UVR_VERSION),--build-arg UVR_VERSION=$(UVR_VERSION))

# Packages to bake into the app image (comma- or space-separated).
# - make PACKAGES="terra,tidyverse"  : bake exactly these packages
# - make all-deps                    : bake everything in uvr.toml
#   (incl. [dev-dependencies]); PACKAGES must be unset
ifeq ($(strip $(PACKAGES)),)
  ifeq ($(origin MAKECMDGOALS),undefined)
    $(error Set PACKAGES, e.g.: make PACKAGES="terra,tidyverse")
  endif
endif

# Stamp recording the last-built package list so `make` rebuilds the app
# only when the list (or base image / def) actually changes.
PACKAGES_STAMP := .packages.stamp

all: $(APP_SIF)

# Build the app image with BOTH [dependencies] and [dev-dependencies]
# baked in. Requires a uvr.toml in the build context (PACKAGES mode
# ignores dev-dependencies — it generates its own manifest).
all-deps: $(APP_SIF)
	apptainer build --fakeroot --force --build-arg 'PACKAGES=' \
	    --build-arg ALL_DEPS=1 $(APP_SIF) $(APP_DEF)

$(BASE_SIF): $(BASE_DEF)
	apptainer build --fakeroot --force $(BUILD_ARGS) $@ $<

$(PACKAGES_STAMP): Makefile
	@printf '%s\n' '$(PACKAGES)' | cmp -s - $@ || printf '%s\n' '$(PACKAGES)' > $@

$(APP_SIF): $(APP_DEF) $(BASE_SIF) $(PACKAGES_STAMP)
	apptainer build --fakeroot --force --build-arg 'PACKAGES=$(subst $(comma), ,$(PACKAGES))' $@ $<

STUDIO_BASE_SIF := rummage-studio-base.sif
STUDIO_APP_SIF  := rummage-studio-app.sif
STUDIO_BASE_DEF := rummage-studio-base.def
STUDIO_APP_DEF  := rummage-studio-app.def

# RStudio Server port and version (defaults in the def files).
STUDIO_PORT     ?= 18787
RSTUDIO_VERSION ?= latest

.PHONY: all clean studio-base studio studio-all-deps studio-run

# Build the RStudio Server base (rummage-base + RStudio Server).
studio-base: $(STUDIO_BASE_SIF)

$(STUDIO_BASE_SIF): $(STUDIO_BASE_DEF) $(BASE_SIF)
	apptainer build --fakeroot --force --build-arg RSTUDIO_PORT=$(STUDIO_PORT) \
	    --build-arg RSTUDIO_VERSION=$(RSTUDIO_VERSION) $@ $<

# Build the studio app image (studio base + baked packages).
# Usage: make studio PACKAGES="terra,ggplot2"
studio: $(STUDIO_APP_SIF)

$(STUDIO_APP_SIF): $(STUDIO_APP_DEF) $(STUDIO_BASE_SIF) $(PACKAGES_STAMP)
	apptainer build --fakeroot --force --build-arg 'PACKAGES=$(subst $(comma), ,$(PACKAGES))' $@ $<

# Studio app with everything in uvr.toml (incl. [dev-dependencies]).
studio-all-deps: $(STUDIO_APP_SIF)
	apptainer build --fakeroot --force --build-arg 'PACKAGES=' \
	    --build-arg ALL_DEPS=1 $(STUDIO_APP_SIF) $(STUDIO_APP_DEF)

# Start RStudio Server from the studio app image (needs --fakeroot:
# rserver drops privileges to the rstudio-server user). State dirs must
# be writable binds — the SIF's /var is read-only.
studio-run:
	apptainer run --fakeroot \
	    --bind "$(CURDIR)":/work \
	    --bind /tmp/rstudio-state:/var/lib/rstudio-server \
	    --bind /tmp/rstudio-state:/var/log/rstudio-server \
	    --bind /tmp/rstudio-state:/var/run/rstudio-server \
	    --writable-tmpfs \
	    $(STUDIO_APP_SIF)

.PHONY: all clean
clean:
	rm -f $(BASE_SIF) $(APP_SIF) $(PACKAGES_STAMP) $(STUDIO_BASE_SIF) $(STUDIO_APP_SIF)