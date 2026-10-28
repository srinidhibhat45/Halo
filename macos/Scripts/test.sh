#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed, the swift-testing macro plugin
# sometimes fails to load ("plugin for module 'TestingMacros' not found"); that is a toolchain
# hiccup, not a test failure, so retry a few times before giving up.
set -uo pipefail
cd "$(dirname "$0")/.."
for attempt in 1 2 3 4 5; do
    output="$(swift test 2>&1)"
    status=$?
    if ! grep -q "plugin for module 'TestingMacros' not found" <<<"$output"; then
        grep -vE "ld: warning: search path|^\[[0-9]+ ?/ ?[0-9]+\]" <<<"$output"
        exit $status
    fi
    echo "▸ Test macros didn't load (toolchain hiccup); retrying ($attempt/5)…"
    sleep 3
done
echo "✗ The test macro plugin wouldn't load. Try again, or install Xcode." >&2
exit 1
