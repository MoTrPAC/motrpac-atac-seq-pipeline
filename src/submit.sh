#!/bin/bash

if [ $# -lt 3 ]; then
  echo
  echo "Usage: ./submit.sh [PYTHON_LOCATION] [WDL_FILE] [JSON_DIR]"
  echo
  echo "Example: ./submit.sh \$(which python) atac.wdl json/"
  echo "[PYTHON_LOCATION]: The python with caper installed"
  echo "[WDL_FILE]: the WDL file to use as the workflow"
  echo "[JSON_DIR]: the directory containing JSON files to use as the WDL inputs"
  echo
  exit 1
fi

PYTHON=$1
WDL_FILE=$2
JSON_DIR=${3/%\//}

if ! [ -f "$WDL_FILE" ]; then
  echo "$WDL_FILE does not exist"
fi

if ! $PYTHON -c 'import caper' &>/dev/null; then
  echo "Caper not installed" >&2
  exit 1
fi

for f in "$JSON_DIR"/*.json; do
  printf "\nSubmitting %s\n" "$f"
  $PYTHON -m caper submit -i "$f" "$WDL_FILE"
  sleep 10
done
