#!/bin/bash

if [ $# -lt 4 ]; then
  echo
  echo "Usage: ./submit.sh [PYTHON_LOCATION] [WDL_FILE] [JSON_DIR] [WF_ID_FILE]"
  echo
  echo "Example: ./submit.sh \$(which python) atac.wdl json/ wfids.json"
  echo "[PYTHON_LOCATION]: The python with caper installed"
  echo "[WDL_FILE]: the WDL file to use as the workflow"
  echo "[JSON_DIR]: the directory containing JSON files to use as the WDL inputs"
  echo "[WF_ID_MAP]: a JSON file to write an array of a map of label and workflow ID of the submitted jobs to"
  echo
  exit 1
fi

PYTHON=$1
WDL_FILE=$2
JSON_DIR=${3/%\//}
WF_ID_MAP=$4

if ! [ -f "$WDL_FILE" ]; then
  echo "$WDL_FILE does not exist"
fi

if ! $PYTHON -c 'import caper' &>/dev/null; then
  echo "caper not installed" >&2
  exit 1
fi

echo "[" >"$WF_ID_MAP"

function submit_file() {
  local input_json_file=$1
  local submission_output
  local workflow_id
  local json_str

  submission_output=$($PYTHON -m caper submit -i "$input_json_file" "$WDL_FILE" 2>&1)
  workflow_id=$(echo "$submission_output" | tail -n1 | sed -E 's/(.*)(\{[^}]*\})/\2/g' | sed -E 's/'\''/\"/g' | jq -r '.id')

  json_str="{\"label\": \"$(basename "$input_json_file" .json)\", \"workflow_id\": \"$workflow_id\"},"
  echo "$json_str" >>"$WF_ID_MAP"
  echo "Submitted $input_json_file"
}

for f in "$JSON_DIR"/*.json; do
  echo
  echo "Submitting $f"
  submit_file "$f"
done

echo "]" >>"$WF_ID_MAP"

echo "Submitted all jobs"
