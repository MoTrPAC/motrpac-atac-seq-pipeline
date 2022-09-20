#!/bin/bash

set -eux
#Usage : src/croo.sh <list_of_atac-seq_workflow_ids> <GCP_PATH_to_atac_seq_pipeline_workflows_without_trailing_slash> <gcp-path-to-output-without-trailing-slash> >>croo_copy_jobs.txt
#Contributors : Archana Raja, Nicole Gay

if [ $# -lt 3 ]; then
  echo "Usage: ./croo.sh [WORKFLOW_SUBMISSION_MAP] [GCP_PATH] [OUT_PATH]"
  echd
  echo "Example: croo.sh out.json gs://my-bucket/my_workflow/outputs/croo gs://my-bucket/my_workflow/processed"
  echo
  echo "[WORKFLOW_SUBMISSION_MAP]: A JSON of workflow ids to process"
  echo "[GCP_PATH]: This directory with the outputs of the pipeline"
  echo "[OUT_PATH]: The location to output the croo files to"
  echo "[PARSE_FROM_ID_LIST] (Optional): Whether to use the workflow id list to parse the files to copy. If false/not set will use qc json to create a file name"
  echo
  exit 1
fi

WORKFLOW_SUBMISSION_MAP=$1
GCP_PATH=$2
OUT_PATH=${3%/}
PARSE_FROM_ID_LIST=$4

function run_croo() {
  local line=$1
  local sample_dir
  local out_dir
  local descrip

  sample_dir=$GCP_PATH/${line%/}
  out_dir=${OUT_PATH%/}/${sample_dir#gs://}

  if [[ "$PARSE_FROM_ID_LIST" ]]; then
    out_dir="$out_dir"/$(jq -r '.[] | select(.workflow_id == "'"$line"'") | .label' "$WORKFLOW_SUBMISSION_MAP")
    echo "out_dir: $out_dir"
  else
    # as long as the description is hyphenated and don't contain any spaces or special characters below would work
    descrip=$(gsutil cat "$sample_dir"/call-qc_report/glob-*/qc.json | grep "description" | sed -e 's/.*": "//' -e 's/".*//')

    if [ "$descrip" = "No description" ]; then
      descrip=$(gstil cat "$sample_dir"/call-qc_report/glob-*/qc.json | grep "title" | sed -e 's/.*": "//' -e 's/".*//')
    else
      descrip=$descrip
    fi

    out_dir="$out_dir"/"${descrip/gs:\/\///}"/
  fi

  croo --method copy "$sample_dir"/metadata.json --out-dir "$out_dir"
}

export GCP_PATH
export OUT_PATH
export WORKFLOW_SUBMISSION_MAP
export PARSE_FROM_ID_LIST
export -f run_croo
cores=10

# shellcheck disable=SC2046
parallel --joblog ~/mnt/tmp/"${WORKFLOW_SUBMISSION_MAP%%.*}"_croo.log --progress --verbose --jobs "$cores" run_croo ::: $(jq -r '.[].workflow_id' "$WORKFLOW_SUBMISSION_MAP")

#for line in $(jq -r '.[].workflow_id' "$WORKFLOW_SUBMISSION_MAP"); do
#  run_croo "$line"
#done
