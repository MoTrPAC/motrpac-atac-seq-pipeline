#!/bin/bash
# Gets a list of all the workflows that have been run, and deletes the corresponding input json files

if [ $# -lt 2 ]; then
  echo "Usage: ./delete_json.sh [SUBMITTED_LABELS] [JSON_DIR]"
  echd
  echo "Example: delete_json.sh labels.txt jsons"
  echo
  echo "[SUBMITTED_LABELS]: a file containing a list of labels of the submitted jobs"
  echo "[JSON_DIR]: The directory where the JSON files are stored"
  echo
  exit 1
fi

SUBMITTED_LABELS=$1
JSON_DIR=$2

readarray -t lines <<<"$SUBMITTED_LABELS"

for line in "${lines[@]}"; do
  echo "Deleting $line.json"
  rm "${JSON_DIR%/}"/"$line".json || true
done
