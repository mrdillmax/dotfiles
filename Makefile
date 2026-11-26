SHELL := /bin/bash

# No built-in rules: `make install` must not copy install.sh into ./install.
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables

DOTFILES_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

.DEFAULT_GOAL := help

.PHONY: help lint test check audit doctor hooks

help:
	@printf '%s\n' \
	  'Developer targets:' \
	  '  make lint     bash -n + shellcheck' \
	  '  make test     shell test suite (temporary HOME, live files untouched)' \
	  '  make check    lint + test + audit + doctor' \
	  '  make audit    read-only repository audit' \
	  '  make doctor   read-only system and config health check' \
	  '  make hooks    install the repository pre-commit hook (DRY_RUN=1)' \
	  '' \
	  'User-facing work:' \
	  '  ./install.sh            main menu' \
	  '  ./install.sh --help     every flag for automation'

lint:
	@git ls-files '*.sh' | xargs -r -n1 bash -n
	@bash -n hooks/pre-commit
	@files=$$(git ls-files '*.sh'; printf '%s\n' hooks/pre-commit); \
	shellcheck -x $$files
	@printf 'lint: ok\n'

test:
	./tests/run.sh

audit:
	./scripts/audit.sh

doctor:
	./scripts/doctor.sh

check: lint test audit doctor

hooks:
	@./scripts/install-hooks.sh $(if $(filter 1,$(DRY_RUN)),--dry-run,)
