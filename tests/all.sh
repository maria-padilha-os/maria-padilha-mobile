#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$root"
fail=0
if [ ! -s README.md ]; then echo "FAIL README.md missing"; fail=1; else echo "ok README.md"; fi
if git grep -nE 'sk-[A-Za-z0-9]{20,}|ghp_[A-Za-z0-9]{20,}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' -- . >/tmp/secret-scan.$$ 2>/dev/null; then
  echo "FAIL possible tracked secret"; cat /tmp/secret-scan.$$; fail=1
else
  echo "ok no obvious tracked secret"
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

[ "$fail" -eq 0 ]
