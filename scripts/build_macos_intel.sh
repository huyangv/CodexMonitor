#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script only runs on macOS."
  exit 1
fi

if [[ "$(uname -m)" != "x86_64" ]]; then
  echo "This script only supports local Intel macOS builds (expected x86_64 host)."
  exit 1
fi

SMOKE_SECONDS="${SMOKE_SECONDS:-8}"
INSTALL_DEPS="${INSTALL_DEPS:-auto}"
LOG_DIR="${LOG_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/codex-monitor-build.XXXXXX")}"
SMOKE_BIN="src-tauri/target/release/codex-monitor"

mkdir -p "${LOG_DIR}"

if ! [[ "${SMOKE_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then
  echo "SMOKE_SECONDS must be a positive integer."
  exit 1
fi

run_and_log() {
  local log_path="$1"
  shift

  echo "==> $*"
  "$@" 2>&1 | tee "${log_path}"
}

cleanup_smoke_process() {
  local smoke_pid="$1"

  if ! kill -0 "${smoke_pid}" >/dev/null 2>&1; then
    return
  fi

  kill "${smoke_pid}" >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do
    if ! kill -0 "${smoke_pid}" >/dev/null 2>&1; then
      return
    fi
    sleep 0.1
  done
  kill -9 "${smoke_pid}" >/dev/null 2>&1 || true
}

echo "==> Repo: ${ROOT_DIR}"
echo "==> Logs: ${LOG_DIR}"

case "${INSTALL_DEPS}" in
  auto)
    if [[ ! -d node_modules ]]; then
      run_and_log "${LOG_DIR}/npm-ci.log" npm ci
    else
      echo "==> Reusing existing node_modules"
    fi
    ;;
  always)
    run_and_log "${LOG_DIR}/npm-ci.log" npm ci
    ;;
  never)
    if [[ ! -d node_modules ]]; then
      echo "node_modules is missing. Either run npm ci first or use INSTALL_DEPS=auto/always."
      exit 1
    fi
    echo "==> Skipping npm dependency install"
    ;;
  *)
    echo "INSTALL_DEPS must be one of: auto, always, never"
    exit 1
    ;;
esac

run_and_log "${LOG_DIR}/doctor.log" npm run doctor:strict
run_and_log "${LOG_DIR}/smoke-build.log" npm run tauri -- build --no-bundle

if [[ ! -x "${SMOKE_BIN}" ]]; then
  echo "Smoke binary not found: ${SMOKE_BIN}"
  exit 1
fi

echo "==> Smoke launch (${SMOKE_SECONDS}s): ${SMOKE_BIN}"
: > "${LOG_DIR}/smoke-run.log"
RUST_BACKTRACE=1 "${SMOKE_BIN}" >>"${LOG_DIR}/smoke-run.log" 2>&1 &
smoke_pid=$!

sleep "${SMOKE_SECONDS}"

if ! kill -0 "${smoke_pid}" >/dev/null 2>&1; then
  set +e
  wait "${smoke_pid}"
  smoke_status=$?
  set -e
  echo "Smoke launch failed with exit code ${smoke_status}."
  echo "See log: ${LOG_DIR}/smoke-run.log"
  tail -n 80 "${LOG_DIR}/smoke-run.log" || true
  exit 1
fi

cleanup_smoke_process "${smoke_pid}"
wait "${smoke_pid}" >/dev/null 2>&1 || true

echo "==> Smoke launch passed"
run_and_log "${LOG_DIR}/package.log" npm run tauri -- build --bundles app,dmg

echo "==> Artifacts"
find src-tauri/target/release/bundle -maxdepth 3 \( -name '*.app' -o -name '*.dmg' \) | sort

echo "==> Done"
echo "==> Logs: ${LOG_DIR}"
