#!/bin/bash

# Write JSON files for ENCODE ATAC pipeline input
# Assumes that reads are paired-end

set -eu

if [ $# -lt 3 ]; then
  echo "Usage: ./make_json.sh [JSON_BASE] [FASTQ_DIR] [JSON_DIR]"
  echo
  echo "Example: make_json.sh base.json /home/user/fastq jsons"
  echo
  echo "[JSON_BASE]: The base JSON file to use"
  echo "[FASTQ_DIR]: This directory with raw FASTQ files"
  echo "[JSON_DIR]: The directory to output the JSON files to"
  echo
  exit 1
fi

JSON_BASE=$1
FASTQ_DIR=$2
JSON_DIR=$3

mkdir -p "$JSON_DIR"

# assign the ls command based on the FastQ directory's prefix
if [[ $FASTQ_DIR == gs://* ]]; then
  ls_command="gsutil ls"
else
  ls_command="ls"
fi

samples=$($ls_command "$FASTQ_DIR" | grep "fastq.gz" | grep -v "Undetermined" | grep -E "R1|R2" | sed "s/_R.*//" | sort | uniq)
echo "$samples"

create_sample_json() {
  sample=$1

  # name JSON file from FASTQ sample name
  json_file=$JSON_DIR/$(basename "$sample").json

  printf "{\n    \"atac.description\": \"%s\",\n" "$(basename "$sample")" >"$json_file"

  # standard parameters for this project
  cat "$JSON_BASE" >>"$json_file"

  # add paths to FASTQ files
  echo "    \"atac.fastqs_rep1_R1\": [" >>"$json_file"

  lanes=$($ls_command "$FASTQ_DIR" | grep "$sample" | grep -c "R1")
  counter=1
  for r1 in $($ls_command "$FASTQ_DIR" | grep "$sample" | grep "R1"); do
    if [ "$counter" = "$lanes" ]; then
      echo "        \"$r1\"" >>"$json_file"
    else
      echo "        \"$r1\"," >>"$json_file"
    fi
    counter=$((counter + 1))
  done
  printf "    ],\n" >>"$json_file"

  echo "    \"atac.fastqs_rep1_R2\": [" >>"$json_file"

  counter=1
  for r2 in $($ls_command "$FASTQ_DIR" | grep "$sample" | grep "R2"); do
    if [ "$counter" = "$lanes" ]; then
      echo "        \"$r2\"" >>"$json_file"
    else
      echo "        \"$r2\"," >>"$json_file"
    fi
    counter=$((counter + 1))
  done
  printf "    ]\n}" >>"$json_file"
}

N_JOBS=6

for i in $samples; do
  create_sample_json "$i" &

  # allow to execute up to $N jobs in parallel
  if [[ $(jobs -r -p | wc -l) -ge $N_JOBS ]]; then
    # now there are $N jobs already running, so wait here for any job
    # to be finished so there is a place to start next one.
    wait -n
  fi

done

# no more jobs to be started but wait for pending jobs
# (all need to be finished)
wait

echo "all done"
