#!/bin/bash

if [ $# -lt 3 ]; then
  echo
  echo "Usage: ./run_croo.sh [WF_ID_MAP] [METADATA_DIR] [CROO_OUT_DIR]"
  echo
  echo "Example: ./run_croo.sh wfids.json /mnt/test_output/atac gs://my-bucket/croo_output"
  echo "[WF_ID_MAP]: JSON file with array of {label, workflow_id} objects (output of submit.sh)"
  echo "[METADATA_DIR]: base directory containing workflow output subdirectories with metadata.json"
  echo "[CROO_OUT_DIR]: GCS or local base output directory for croo organized outputs"
  echo
  exit 1
fi

WF_ID_MAP=$1
METADATA_DIR=${2/%\//}
CROO_OUT_DIR=${3/%\//}

if ! [ -f "$WF_ID_MAP" ]; then
  echo "ERROR: $WF_ID_MAP does not exist"
  exit 1
fi

if ! command -v croo &>/dev/null; then
  echo "croo not installed" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "jq not installed" >&2
  exit 1
fi

python3 -c "
import re, json, sys
text = open(sys.argv[1]).read()
text = re.sub(r',(\s*[}\]])', r'\1', text)
[print(json.dumps(e)) for e in json.loads(text)]
" "$WF_ID_MAP" | while read -r entry; do
  label=$(echo "$entry" | jq -r '.label')
  wf_id=$(echo "$entry" | jq -r '.workflow_id')
  metadata="${METADATA_DIR}/${wf_id}/metadata.json"

  if ! [ -f "$metadata" ]; then
    echo "WARNING: metadata.json not found for $label ($wf_id), skipping"
    continue
  fi

  echo "Running croo for: $label ($wf_id)"
  croo "$metadata" \
    --out-dir "${CROO_OUT_DIR}/${label}" \
    --method copy
  echo "Done: $label"
done

echo "All croo runs complete"
