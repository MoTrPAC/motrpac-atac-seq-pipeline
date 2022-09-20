#!/bin/bash

if [ $# -lt 4 ]; then
  echo
  echo "Usage: ./submit.sh [WDL_FILE] [JSON_DIR] [WF_ID_MAP]"
  echo
  echo "Example: ./submit.sh atac.wdl json/ wfids.json"
  echo "[WDL_FILE]: the WDL file to use as the workflow"
  echo "[JSON_DIR]: the directory containing JSON files to use as the WDL inputs"
  echo "[WF_ID_MAP]: a JSON file to write an array of a map of label and workflow ID of the submitted jobs to"
  echo
  exit 1
fi

WDL_FILE=$2
JSON_DIR=${3/%\//}
WF_ID_MAP=$4
NUM_CORES=4

if ! [ -f "$WDL_FILE" ]; then
  echo "$WDL_FILE does not exist"
fi

if ! python -c 'import caper' &>/dev/null; then
  echo "caper not installed" >&2
  exit 1
fi

echo "[" >"$WF_ID_MAP"

function submit_file() {
  local input_json_file=$1
  echo
  echo "Submitting $input_json_file"
  local submission_output
  local workflow_id
  local json_str

  submission_output=$($PYTHON -m caper submit -i "$input_json_file" "$WDL_FILE" 2>&1)
  parsed_output=$(echo "$submission_output" | tail -n1 | sed -E 's/(.*)(\{[^}]*\})/\2/g' | sed -E 's/'\''/\"/g')
  echo "$parsed_output"
  workflow_id=$(echo "$parsed_output" | jq -r '.id')
  json_str="{\"label\": \"$(basename "$input_json_file" .json)\", \"workflow_id\": \"$workflow_id\"},"
  echo "$json_str" >>"$WF_ID_MAP"

  echo "Submitted $input_json_file"
}

export -f submit_file
export WDL_FILE
export WF_ID_MAP
echo "Submitting files in $JSON_DIR"
parallel --verbose --jobs "$NUM_CORES" submit_file ::: "$JSON_DIR"/*.json

echo "]" >>"$WF_ID_MAP"

echo "Submitted all jobs"
