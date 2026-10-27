#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.."

# Reverse Git's parent-first list: push nested submodules before their parents.
paths=$(git submodule foreach --quiet --recursive 'printf "%s\n" "$displaypath"')
repos=(.)
while IFS= read -r path; do
  [[ -z "$path" ]] || repos+=("$path")
done <<< "$paths"

for ((i=${#repos[@]}-1; i>=0; i--)); do
  (
    cd -- "${repos[i]}"
    git push origin HEAD:dev
  )
done
