SHELL := /usr/bin/env bash
.DEFAULT_GOAL := check

.PHONY: check test keyboard-test shell-test settings-test power-test modem-test accessibility-test camera-test build build-dry-run boot qemu clean

check:
	@tests/build.sh

test:
	@tests/all.sh

keyboard-test:
	@tests/keyboard.sh

shell-test:
	@tests/shell.sh

settings-test:
	@tests/settings.sh

power-test:
	@tests/power.sh

modem-test:
	@tests/modem.sh

accessibility-test:
	@python3 tests/shell/palette_check.py
	@python3 tests/shell/contrast_check.py
	@python3 tests/shell/accessibility_check.py

camera-test:
	@tests/camera.sh

power-diagnostic:
	@scripts/power-diagnostic.sh

stage-power:
	@scripts/stage-power-config.sh

build:
	@scripts/build.sh

build-dry-run:
	@scripts/build.sh --dry-run

boot:
	@scripts/build.sh --boot

qemu:
	@scripts/run-qemu.sh

clean:
	@rm -rf -- out .scratch/build
