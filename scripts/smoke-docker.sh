#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

usage() {
    cat <<'USAGE'
Usage: ./scripts/smoke-docker.sh --context LOCAL_CONTEXT [--report PATH]

Builds and checks the real Docker adapter against one temporary, labelled Alpine
container with no mounts, published ports, or network access. Tests discovery,
inspection, metrics, start/stop/restart, log tail, and cancellable log following.
The exact test container is removed on exit. Existing workloads are not changed.
Requires an existing local engine, Docker CLI, and Apple Command Line Tools.
USAGE
}

context=""
report="$DOCKEY_PROJECT_DIR/.local/live-smoke.json"
while [ "$#" -gt 0 ]; do
    case "$1" in
        --context) [ "$#" -ge 2 ] || dockey_die "--context needs a value"; context="$2"; shift 2 ;;
        --report) [ "$#" -ge 2 ] || dockey_die "--report needs a value"; report="$2"; shift 2 ;;
        --help|-h) usage; exit 0 ;;
        *) dockey_die "unknown argument: $1" ;;
    esac
done
[ -n "$context" ] || dockey_die "an explicit --context is required"
dockey_require_macos
dockey_require_command docker
dockey_require_command swift
endpoint="$(docker context inspect --format '{{.Endpoints.docker.Host}}' -- "$context")"
case "$endpoint" in unix:///*) ;; *) dockey_die "smoke testing requires a local Unix-socket context" ;; esac

(cd "$DOCKEY_PROJECT_DIR" && swift build --product DockeySmoke) >&2
bin_dir="$(cd "$DOCKEY_PROJECT_DIR" && swift build --show-bin-path)"
# Apple Silicon requires an executable signature; some CLT linkers omit an ad-hoc one.
/usr/bin/codesign --force --sign - "$bin_dir/DockeySmoke" >&2
mkdir -p "$(dirname "$report")"
if ! docker --context "$context" image inspect alpine:3 >/dev/null 2>&1; then
    docker --context "$context" pull alpine:3 >&2
fi

fixture=""
name="dockey-smoke-$(date +%s)-$$"
cleanup() {
    local status=$?
    local target="${fixture:-$name}"
    local marker
    marker="$(docker --context "$context" inspect --format '{{index .Config.Labels "dev.dockey.smoke.run"}}' -- "$target" 2>/dev/null || true)"
    if [ -n "$marker" ]; then
        if [ "$marker" = "$name" ]; then
            if ! docker --context "$context" container rm --force -- "$target" >/dev/null; then
                dockey_note "test fixture cleanup failed; inspect $target in context $context"
                status=1
            fi
        else
            dockey_note "refused fixture cleanup because the expected ownership label was missing"
            status=1
        fi
    fi
    exit "$status"
}
trap cleanup EXIT
fixture="$(docker --context "$context" run --detach --name "$name" \
    --label dev.dockey.smoke=true \
    --label "dev.dockey.smoke.run=$name" \
    --label com.docker.compose.project=dockey-smoke \
    --label com.docker.compose.service=probe \
    --network none --memory 32m --cpus 0.1 --pids-limit 16 \
    --log-driver local --log-opt max-size=1m --log-opt max-file=2 \
    alpine:3 sh -c 'trap "exit 0" TERM; while :; do echo dockey-smoke-ready; sleep 1; done')"
"$bin_dir/DockeySmoke" --context "$context" --container "$fixture" --report "$report"
