#!/bin/bash
if [ $# -lt 1 ]; then
    echo
    echo "Usage: ./delete_json.sh [JSON_DIR]"
    echo
    echo "Deletes the JSON files in [JSON_DIR] that correspond to existing submissions that Cromwell has completed."
    echo "Requires Cromwell to be running and jq to be installed."
    echo
    echo "Example: ./delete_json.sh json/"
    echo "[JSON_DIR]: the directory containing JSON files to use as the WDL inputs"
    echo
    exit 1
fi

submitted_labels=$(curl -X GET 'http://localhost:8000/api/workflows/v1/query?additionalQueryResultFields=labels' | jq -r '.results| .[] | .labels["caper-str-label"]')

readarray -t lines <<<"$submitted_labels"

for line in "${lines[@]}"; do
    echo "Deleting $line.json"
    rm "$1"/"$line".json || true
done
