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

if git ls-files | grep -qE '^(out|\.scratch)/'; then
  echo "FAIL build output is tracked"
  fail=1
else
  echo "ok no tracked build output"
fi


[ "$fail" -eq 0 ]
