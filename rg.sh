#!/bin/bash
args=()
for arg in "$@"; do
  if [[ "$arg" == "--cursor-ignore" ]]; then
    args+=("--ignore-file")
  else
    args+=("$arg")
  fi
done

exec /usr/bin/rg "${args[@]}"
