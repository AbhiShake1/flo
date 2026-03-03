#!/usr/bin/env bash
set -euo pipefail

swift test --enable-xctest --enable-swift-testing "$@"
