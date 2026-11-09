#!/usr/bin/env bash
# systemd-sleep hook: re-apply charge thresholds after resume.
#
# systemd-sleep runs this once for "pre" and once for "post"; there is no loop.
# A missing helper or unsupported hardware must not fail the resume path.

set -euo pipefail

HELPER="${POWER_THRESHOLD_HELPER:-/usr/libexec/maria-padilha/power-charge-thresholds}"

case "${1:-}" in
  post)
    if [ "$(id -u)" -ne 0 ]; then
      printf 'skip charge threshold reapply: not root\n' >&2
      exit 0
    fi
    if [ -x "$HELPER" ]; then
      "$HELPER" --apply --quiet || printf 'charge threshold reapply failed\n' >&2
    else
      printf 'skip charge threshold reapply: %s is not installed\n' "$HELPER" >&2
    fi
    ;;
  pre)
    # Nothing needs to run before suspend. Keeping the branch explicit makes
    # the hook's scope obvious.
    ;;
  *)
    printf 'usage: %s pre|post\n' "${0##*/}" >&2
    exit 1
    ;;
esac
