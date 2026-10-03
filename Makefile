# Local checks, the same as CI's: make check
SH := steamify.sh $(wildcard lib/*.sh) ui/steamify-app.sh .github/tools/bundle.sh
# The unit tests live in ../steamify-cachyos-dev/tests (REPO points at this checkout).
DEV ?= ../steamify-cachyos-dev
TESTS := $(wildcard $(DEV)/tests/*-test.sh)

.PHONY: check syntax lint test bundle fmt-check
check: syntax lint test bundle

syntax:
	@for f in $(SH); do bash -n "$$f" || exit 1; done
	python3 -m py_compile ui/steamify-ui patches/*.py

lint:
	@command -v shellcheck >/dev/null && shellcheck -S warning $(SH) || echo "shellcheck not installed: skipped"

test:
	@for t in $(TESTS); do echo "== $$t"; REPO="$(CURDIR)" bash "$$t" || exit 1; done

bundle:
	.github/tools/bundle.sh dist/steamify.sh

fmt-check:
	@command -v shfmt >/dev/null && shfmt -d -i 4 -ci $(SH) || echo "shfmt not installed: skipped"
