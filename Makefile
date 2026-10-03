# Local checks, the same as CI's: make check
SH := steamify.sh $(wildcard lib/*.sh) ui/steamify-app.sh .github/tools/bundle.sh
# The unit tests live in ../steamify-cachyos-dev/tests (REPO points at this checkout).
DEV ?= ../steamify-cachyos-dev
# Not the hardware test: it is for a real NVIDIA PC and writes a report in $$HOME.
TESTS := $(filter-out %-hardware-test.sh,$(wildcard $(DEV)/tests/*-test.sh))

.PHONY: check syntax lint lint-sh lint-py lint-qml test bundle fmt-check
check: syntax lint test bundle

syntax:
	@for f in $(SH); do bash -n "$$f" || exit 1; done
	python3 -c 'import ast, sys; [ast.parse(open(f).read(), f) for f in sys.argv[1:]]' ui/steamify-ui patches/*.py

lint: lint-sh lint-py lint-qml

lint-sh:
	@command -v shellcheck >/dev/null && shellcheck -S warning $(SH) || echo "shellcheck not installed: skipped"

lint-py:
	@command -v ruff >/dev/null && ruff check ui/steamify-ui patches || echo "ruff not installed: skipped"

lint-qml:
	@Q="$$(command -v qmllint6 || command -v qmllint || ls /usr/lib/qt6/bin/qmllint 2>/dev/null)"; \
	[ -n "$$Q" ] && "$$Q" --unqualified disable --max-warnings 0 ui/qml/*.qml || echo "qmllint not installed: skipped"

test:
	@for t in $(TESTS); do echo "== $$t"; REPO="$(CURDIR)" bash "$$t" || exit 1; done

bundle:
	.github/tools/bundle.sh dist/steamify.sh

fmt-check:
	@command -v shfmt >/dev/null && shfmt -d -i 4 -ci $(SH) || echo "shfmt not installed: skipped"
