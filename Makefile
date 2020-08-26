# Configuration for the docker image
# Name of the docker image
NAME = backupbuilder
# Directory to mount in running docker image
LOCAL_FILES = $(CURDIR)

# Docker calling commands
DOCKER = docker
BUILD_CMD = $(DOCKER) build -t
# The --privileged is necessary as live-build mounts /sys, /proc, ... during the
# chroot phase.
RUN_CMD = $(DOCKER) run -v "$(LOCAL_FILES):/data" --rm --privileged

# Files used to generate Backup System
BUILD_DEPS = $(shell find config/includes.chroot/ -type f) \
	config/package-lists/backupsystem.list.chroot config/package-lists/keyboard-fix.list.chroot \
	auto/config

# Extra cleanup files to delete when running the target clean-all
CLEANUP_FILES = chroot.files chroot.packages.install chroot.packages.live \
	live-image-amd64.contents live-image-amd64.files live-image-amd64.packages \
	live-image-amd64.hybrid.iso.zsync
CLEANUP_DIRS = chroot binary local .build cache

# Local commands to build backupsystem
.PHONY: run clean clean-all iso

iso: live-image-amd64.hybrid.iso

live-image-amd64.hybrid.iso: $(BUILD_DEPS)
	lb config
	lb build

clean:
	lb clean
	lb clean --config

clean-all: clean
	rm -f builder
	rm -f chroot.files
	rm -f $(CLEANUP_FILES)
	rm -rf $(CLEANUP_DIRS)

# Targets to build backupsystem using the specified docker image.
# These targets run the corresponding local commands inside the docker image.
.PHONY: builder-iso builder-clean builder-clean-all
CALLING_USER = $(shell id -u)
CALLING_GROUP = $(shell id -g)
builder-iso: builder
	$(RUN_CMD) $(NAME) /bin/bash -c 'make iso && chown $(CALLING_USER):$(CALLING_GROUP) *.iso'

builder-clean: builder
	$(RUN_CMD) $(NAME) make clean

builder-clean-all: builder
	$(RUN_CMD) $(NAME) make clean-all

builder: Dockerfile
	$(BUILD_CMD) $(NAME) ./
	touch builder

# A target to run the builder interactively
run: builder
	$(RUN_CMD) -it $(NAME)
