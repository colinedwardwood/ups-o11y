#!/usr/bin/env bash
# Install the NUT Prometheus exporter.
# Usage: sudo bash install-nut-exporter.sh
#
# NUT_EXPORTER_VERSION defaults to 3.2.5.
# NUT_EXPORTER_ARCH is auto-detected but can be overridden (linux-amd64, linux-arm64, linux-arm).

set -euo pipefail

VERSION="${NUT_EXPORTER_VERSION:-3.2.5}"
INSTALL_DIR="/opt/nut-exporter"
BINARY="${INSTALL_DIR}/nut_exporter"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ "$(id -u)" -eq 0 ]] || { echo "Run as root"; exit 1; }

# Detect arch
if [[ -z "${NUT_EXPORTER_ARCH:-}" ]]; then
  case "$(uname -m)" in
    x86_64)  NUT_EXPORTER_ARCH="linux-amd64" ;;
    aarch64) NUT_EXPORTER_ARCH="linux-arm64" ;;
    armv*l)  NUT_EXPORTER_ARCH="linux-arm"   ;;
    *)       echo "Unknown arch: $(uname -m). Set NUT_EXPORTER_ARCH manually."; exit 1 ;;
  esac
fi

BINARY_NAME="nut_exporter-v${VERSION}-${NUT_EXPORTER_ARCH}"
CHECKSUMS_NAME="nut_exporter_${VERSION}_checksums.txt"
BASE_URL="https://github.com/DRuggeri/nut_exporter/releases/download/v${VERSION}"

# Skip download if already on the right version
if [[ -x "$BINARY" ]]; then
  installed="$("$BINARY" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [[ "$installed" == "$VERSION" ]]; then
    echo "nut_exporter ${VERSION} already installed, skipping download"
    SKIP_DOWNLOAD=true
  fi
fi

apt-get install -y -q curl

if [[ "${SKIP_DOWNLOAD:-false}" != "true" ]]; then
  echo "Downloading nut_exporter v${VERSION} (${NUT_EXPORTER_ARCH})..."
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT

  curl -fsSL -o "${TMP}/${BINARY_NAME}" "${BASE_URL}/${BINARY_NAME}"
  curl -fsSL -o "${TMP}/${CHECKSUMS_NAME}" "${BASE_URL}/${CHECKSUMS_NAME}"

  (cd "$TMP" && grep "${BINARY_NAME}$" "${CHECKSUMS_NAME}" | sha256sum -c --status) || {
    echo "Checksum failed — aborting"
    exit 1
  }

  mkdir -p "$INSTALL_DIR"
  install -m 0755 "${TMP}/${BINARY_NAME}" "$BINARY"
  echo "Installed to ${BINARY}"
fi

install -m 0644 "${SCRIPT_DIR}/nut-exporter.service" /etc/systemd/system/nut-exporter.service

systemctl daemon-reload
systemctl enable nut-exporter
systemctl restart nut-exporter

sleep 2
if systemctl is-active --quiet nut-exporter; then
  echo "nut-exporter running on :9199"
else
  echo "Service didn't start — check: journalctl -u nut-exporter -n 50"
  exit 1
fi
