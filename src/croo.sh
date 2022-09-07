#!/bin/bash
#Usage : src/croo.sh <list_of_atac-seq_workflow_ids> <GCP_PATH_to_atac_seq_pipeline_workflows_without_trailing_slash> <gcp-path-to-output-without-trailing-slash> >>croo_copy_jobs.txt
#Contributors : Archana Raja, Nicole Gay

if [ $# -lt 3 ]; then
  echo "Usage: ./croo.sh [WORKFLOW_ID_LIST] [GCP_PATH] [OUT_PATH]"
  echd
  echo "Example: croo.sh ids.txt gs://my-bucket/my_workflow/outputs/croo gs://my-bucket/my_workflow/processed"
  echo
  echo "[WORKFLOW_ID_LIST]: A list of workflow ids to process"
  echo "[GCP_PATH]: This directory with the outputs of the pipeline"
  echo "[OUT_PATH]: The location to output the croo files to"
  echo
  exit 1
fi

WORKFLOW_ID_LIST=$1
GCP_PATH=$2
OUT_PATH=${3%/}


function run_croo() {
  local line=$1
  local out_dir

  sample_dir=$GCP_PATH/${line%/}
  out_dir=${OUT_PATH%/}/${sample_dir#gs://}

  # as long as the description is hyphenated and don't contain any spaces or special characters below would work
  descrip=$(gsutil cat "$sample_dir"/call-qc_report/glob-*/qc.json | grep "description" | sed -e 's/.*": "//' -e 's/".*//')

  if [ "$descrip" = "No description" ]; then
    descrip=$(gstil cat "$sample_dir"/call-qc_report/glob-*/qc.json | grep "title" | sed -e 's/.*": "//' -e 's/".*//')
  else
    descrip=$descrip
  fi

  out_dir="$out_dir"/"${descrip/gs:\/\///}"/
  croo --method copy "$sample_dir"/metadata.json --out-dir "$out_dir"
}

export GCP_PATH
export OUT_PATH
export -f run_croo

while IFS= read -r line; do
  run_croo "$line" &
done <"$WORKFLOW_ID_LIST"
