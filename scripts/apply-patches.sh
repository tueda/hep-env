#!/bin/bash
set -euo pipefail
shopt -s nullglob

# Usage: apply-patches.sh PATCH_DIR=. DIR=. PATCH_LEVEL=1

patch_dir=${1:-.}
dir=${2:-.}
patch_level=${3:-1}

for f in "$patch_dir"/*.patch; do
  patch -p"$patch_level" -d "$dir" <"$f"
done
