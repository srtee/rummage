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
# Example: make PACKAGES="terra,tidyverse,ggplot2"
ifndef PACKAGES
$(error Set PACKAGES, e.g.: make PACKAGES="terra,tidyverse")
endif

# Stamp recording the last-built package list so `make` rebuilds the app
# only when the list (or base image / def) actually changes.
PACKAGES_STAMP := .packages.stamp

all: $(APP_SIF)

$(BASE_SIF): $(BASE_DEF)
	apptainer build --fakeroot --force $(BUILD_ARGS) $@ $<

$(PACKAGES_STAMP): Makefile
	@printf '%s\n' '$(PACKAGES)' | cmp -s - $@ || printf '%s\n' '$(PACKAGES)' > $@

$(APP_SIF): $(APP_DEF) $(BASE_SIF) $(PACKAGES_STAMP)
	apptainer build --fakeroot --force --build-arg 'PACKAGES=$(subst $(comma), ,$(PACKAGES))' $@ $<

.PHONY: all clean
clean:
	rm -f $(BASE_SIF) $(APP_SIF) $(PACKAGES_STAMP)