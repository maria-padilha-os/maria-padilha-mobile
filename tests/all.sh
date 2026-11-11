#!/usr/bin/env bash
# Repository hygiene and build-scaffold checks.

set -euo pipefail

root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
fail=0

if [ ! -s README.md ]; then
  echo "FAIL README.md missing"
  fail=1
else
  echo "ok README.md"
fi
rm -f /tmp/secret-scan.$$

adr=docs/adr/0001-mobile-base-and-reference-device.md
if [ -s "$adr" ]; then echo "ok $adr"; else echo "FAIL $adr missing"; fail=1; fi

check_text() {
  local file=$1 needle=$2 label=$3
  if grep -qF -- "$needle" "$file"; then
    echo "ok $label"
  else
    echo "FAIL $label"
    fail=1
  fi
}

if [ -s "$adr" ]; then
  check_text "$adr" "## Decision" "ADR decision section"
  check_text "$adr" "## Options considered" "ADR options section"
  check_text "$adr" "### Package availability" "ADR package availability"
  check_text "$adr" "### Kernel and firmware support" "ADR kernel and firmware"
  check_text "$adr" "### Maintenance effort" "ADR maintenance effort"
  check_text "$adr" "### Touch stack maturity" "ADR touch stack maturity"
  check_text "$adr" "### Reuse of Maria Padilha palette and shell work" "ADR reuse"
  check_text "$adr" "## Unsupported cases" "ADR unsupported cases"
  check_text "$adr" "## Risks for the next tasks" "ADR risks"
  check_text "$adr" "Arch Linux ARM + Phosh" "ADR compares Arch Linux ARM + Phosh"
  check_text "$adr" "Arch Linux ARM + Plasma Mobile" "ADR compares Arch Linux ARM + Plasma Mobile"
  check_text "$adr" "postmarketOS/Nura + Phosh" "ADR compares postmarketOS/Nura + Phosh"
  check_text "$adr" "postmarketOS/Nura + Plasma Mobile" "ADR compares postmarketOS/Nura + Plasma Mobile"
  check_text "$adr" "qemu-aarch64" "ADR names the QEMU reference"
  check_text "$adr" "PinePhone-class" "ADR names the physical device class"
fi
check_text README.md "$adr" "README links the ADR"

shell_readme=shell/README.md
if [ -s "$shell_readme" ]; then echo "ok $shell_readme"; else echo "FAIL $shell_readme missing"; fail=1; fi
check_text README.md "## Touch-first shell prototype" "README documents the shell prototype"
check_text README.md "### Screenshot checklist" "README has the screenshot checklist"
check_text README.md "quickshell -p" "README documents the shell launch"
check_text README.md "$shell_readme" "README links the shell notes"
check_text "$shell_readme" "## Palette wiring" "shell notes document palette wiring"
check_text "$shell_readme" "## Verification" "shell notes document verification"


if grep -q 'scripts/build.sh' README.md; then
  echo "ok README documents the build entry point"
else
  echo "FAIL README does not document scripts/build.sh"
  fail=1
fi

if git diff --check HEAD; then
  echo "ok no whitespace errors in the working diff"
else
  echo "FAIL whitespace errors in the working diff"
  fail=1
fi

if bash tests/build.sh; then
  echo "ok tests/build.sh"
else
  echo "FAIL tests/build.sh"
  fail=1
fi

if bash tests/keyboard.sh; then
  echo "ok tests/keyboard.sh"
else
  echo "FAIL tests/keyboard.sh"
  fail=1
fi

if bash tests/power.sh; then
  echo "ok tests/power.sh"
else
  echo "FAIL tests/power.sh"
  fail=1
fi

if bash tests/modem.sh; then
  echo "ok tests/modem.sh"
else
  echo "FAIL tests/modem.sh"
  fail=1
fi

if bash tests/camera.sh; then
  echo "ok tests/camera.sh"
else
  echo "FAIL tests/camera.sh"
  fail=1
fi

if bash tests/shell.sh; then
  echo "ok tests/shell.sh"
else
  echo "FAIL tests/shell.sh"
  fail=1
fi

if git ls-files | grep -qE '^(out|\.scratch)/'; then
  echo "FAIL build output is tracked"
  fail=1
else
  echo "ok no tracked build output"
fi


[ "$fail" -eq 0 ]
