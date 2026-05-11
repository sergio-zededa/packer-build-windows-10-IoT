#!/usr/bin/env bash
# Build wrapper for the UEFI + vTPM Win10 IoT template.
#
# - Stages a per-build copy of OVMF_VARS_4M.fd in /tmp/swtpm-win10iot/
# - Starts swtpm as a daemon on a unix socket in the same dir
# - Runs `packer build win10_iot_uefi_build.json` against it
# - Cleans up swtpm + the staging dir on exit
#
# The matching qemuargs in win10_iot_uefi_build.json reference:
#   /tmp/swtpm-win10iot/OVMF_VARS.fd
#   /tmp/swtpm-win10iot/swtpm-sock

set -euo pipefail

STAGE_DIR="/tmp/swtpm-win10iot"
OVMF_CODE_SRC="/usr/share/OVMF/OVMF_CODE_4M.fd"
OVMF_VARS_SRC="/usr/share/OVMF/OVMF_VARS_4M.fd"
TEMPLATE="${1:-win10_iot_uefi_build.json}"

for f in "$OVMF_CODE_SRC" "$OVMF_VARS_SRC"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing $f - install the 'ovmf' package" >&2
    exit 1
  fi
done

if ! command -v swtpm >/dev/null 2>&1; then
  echo "ERROR: swtpm not found - install the 'swtpm' package" >&2
  exit 1
fi

if ! command -v packer >/dev/null 2>&1; then
  echo "ERROR: packer not found in PATH" >&2
  exit 1
fi

cleanup() {
  if [[ -n "${SWTPM_PID:-}" ]] && kill -0 "$SWTPM_PID" 2>/dev/null; then
    kill "$SWTPM_PID" 2>/dev/null || true
    wait "$SWTPM_PID" 2>/dev/null || true
  fi
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT INT TERM

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# Per-build, writable copy of UEFI variables.  Never reuse: secure-boot keys
# / boot order entries from a previous run can wedge the next install.
cp "$OVMF_VARS_SRC" "$STAGE_DIR/OVMF_VARS.fd"
chmod 0644 "$STAGE_DIR/OVMF_VARS.fd"

echo ">>> Starting swtpm on $STAGE_DIR/swtpm-sock"
swtpm socket \
  --tpmstate dir="$STAGE_DIR" \
  --ctrl type=unixio,path="$STAGE_DIR/swtpm-sock" \
  --tpm2 \
  --log level=0 \
  --daemon \
  --pid file="$STAGE_DIR/swtpm.pid"

# Give swtpm a moment to bind the socket before qemu connects.
sleep 1
SWTPM_PID="$(cat "$STAGE_DIR/swtpm.pid" 2>/dev/null || true)"
if [[ -z "$SWTPM_PID" ]]; then
  echo "ERROR: swtpm did not start" >&2
  exit 1
fi
echo ">>> swtpm pid=$SWTPM_PID"

echo ">>> packer build $TEMPLATE"
packer build "$TEMPLATE"
