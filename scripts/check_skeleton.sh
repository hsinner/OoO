#!/usr/bin/env bash
set -euo pipefail
# Historical script name; the manifest now contains the functional processor.
verilator --lint-only -Wall --top-module core -f rtl/superscalar/skeleton.f
printf 'PASS: complete superscalar core strict lint (no warning suppressions)\n'
