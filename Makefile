SHELL := /bin/bash

DOTFILES_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
WALLPAPER ?=
SYNC_TARGET ?=

.DEFAULT_GOAL := help

.PHONY: help install all dry-run monitors mouse theme wallpaper kernel doctor hooks restore sync-status sync-diff sync-pull sync-packages audit lint check

help:
	@printf '%s\n' \
	  'Dotfiles targets:' \
	  '  make install     interactive installer' \
	  '  make all         install every module and package group (no /etc)' \
	  '  make dry-run     show what a full install would do' \
	  '  make monitors    detect and configure monitor layout' \
	  '  make mouse       interactive mouse/touchpad tuner' \
	  '  make theme       regenerate colors with matugen' \
	  '  make wallpaper   store a wallpaper path and apply it' \
	  '  make kernel      detect the CPU level and install a kernel' \
	  '  make doctor      read-only system and config health check' \
	  '  make hooks       install the repository pre-commit hook' \
	  '  make restore     list and restore a backup (RESTORE_DATE=, MODULES=)' \
	  '  make sync-status show files that differ from the repository' \
	  '  make sync-diff   show diffs for those files (SYNC_TARGET=hypr)' \
	  '  make sync-pull   copy live changes back (DRY_RUN=1, YES=1)' \
	  '  make sync-packages compare installed packages with packages/*.txt' \
	  '  make audit       read-only configuration audit' \
	  '  make lint        bash -n + shellcheck' \
	  '  make check       lint + audit'

install:
	./install.sh

all:
	./install.sh --all

dry-run:
	./install.sh --dry-run --all --yes

monitors:
	./install.sh --monitors

mouse:
	./install.sh --mouse

wallpaper:
	@[[ -n "$(WALLPAPER)" ]] || { printf 'Use: make wallpaper WALLPAPER=/path/to/image\n' >&2; exit 1; }
	./install.sh --wallpaper "$(WALLPAPER)"

kernel:
	./install.sh --kernel

doctor:
	./scripts/doctor.sh

hooks:
	@./scripts/install-hooks.sh $(if $(filter 1,$(DRY_RUN)),--dry-run)

restore:
	@./install.sh --restore $(RESTORE_DATE) $(if $(MODULES),--modules $(MODULES),) $(if $(filter 1,$(DRY_RUN)),--dry-run,)

sync-status:
	@./scripts/sync.sh status $(SYNC_TARGET)

sync-diff:
	@./scripts/sync.sh diff $(SYNC_TARGET)

sync-pull:
	@./scripts/sync.sh pull $(SYNC_TARGET) $(if $(filter 1,$(DRY_RUN)),--dry-run,) $(if $(filter 1,$(YES)),--yes,)

sync-packages:
	@./scripts/sync.sh packages $(if $(filter 1,$(LIST)),--list,)

theme:
	@wall="$(WALLPAPER)"; \
	if [[ -z $$wall ]]; then \
	    if [[ -r $$HOME/.config/hypr/wallpaper.path ]]; then \
	        wall=$$(<"$$HOME/.config/hypr/wallpaper.path"); \
	    fi; \
	fi; \
	if [[ -z $$wall ]]; then \
	    wall=$$(awk -F'"' '/^[[:space:]]*image[[:space:]]*=/{print $$2; exit}' "$$HOME/.config/hypr/colors.lua" 2>/dev/null || true); \
	fi; \
	if [[ -z $$wall || ! -f $$wall ]]; then \
	    printf 'No wallpaper found. Use: make theme WALLPAPER=/path/to/image\n' >&2; \
	    exit 1; \
	fi; \
	printf 'Generating colors from %s\n' "$$wall"; \
	matugen image "$$wall" --config "$$HOME/.config/matugen/config.toml"; \
	pkill -SIGUSR2 waybar 2>/dev/null || true

lint:
	@find . -path ./.git -prune -o -type f -name '*.sh' -print0 \
	    | xargs -0 -r -n1 bash -n
	@bash -n hooks/pre-commit
	@files=$$(find . -path ./.git -prune -o -type f -name '*.sh' -print; printf '%s\n' hooks/pre-commit); \
	shellcheck -x $$files
	@printf 'lint: ok\n'

audit:
	./scripts/audit.sh

check: lint audit doctor
