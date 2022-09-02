#!/bin/bash
#Usage : src/croo.sh <list_of_atac-seq_workflow_ids> <gcp_path_to_atac_seq_pipeline_workflows_without_trailing_slash> <gcp-path-to-output-without-trailing-slash> >>croo_copy_jobs.txt
#Contributors : Archana Raja, Nicole Gay

if [ $# -lt 3 ]; then
  echo "Usage: ./croo.sh [workflow_id_list] [gcp_path] [out_path]"
  echd
  echo "Example: croo.sh ids.txt gs://my-bucket/my_workflow/outputs/croo gs://my-bucket/my_workflow/processed"
  echo
  echo "[workflow_id_list]: A list of workflow ids to process"
  echo "[gcp_path]: This directory with the outputs of the pipeline"
  echo "[out_path]: The location to output the croo files to"
  echo
  exit 1
fi

workflow_id_list=$1
gcp_path=$2
out_path=$3

while IFS= read -r line; do
  sample_dir=$gcp_path/$line
  out_dir=${out_path%/}/${line/gs:\/\///}

  # as long as the description is hyphenated and don't contain any spaces or special characters below would work
  descrip=$(gsutil cat "$sample_dir"/call-qc_report/glob-*/qc.json | grep "description" | sed -e 's/.*": "//' -e 's/".*//')

  if [ "$descrip" = "No description" ]; then
    descrip=$(gstil cat "$sample_dir"/call-qc_report/glob-*/qc.json | grep "title" | sed -e 's/.*": "//' -e 's/".*//')
  else
    descrip=$descrip
  fi

  croo --method copy "$sample_dir"/metadata.json --out-dir "$out_dir""${descrip/gs:\/\///}"/
done <"$workflow_id_list"
