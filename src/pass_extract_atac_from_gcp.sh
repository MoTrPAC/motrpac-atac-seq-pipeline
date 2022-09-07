#!/bin/bash

# Nicole Gay, modified by Archana to work on copying outputs to GCP and locally
# 6 May 2020
#
# description: copy necessary outputs from GCP to final destination on GCP or local cluster
#
# Usage: bash pass_extract_atac_from_gcp.sh ${NUM_CORES} ${DOWNLOAD_DIR_without_trailing_slash} ${gcp_path_to_atac_croo_outputs_without_trailing_slash} ${copy_dest}
#
### Expected numbers of files:
##
## PASS1A:
# signal   : 98 * {N_tissues}
# peak     : 40 * {N_tissues}
# qc       : 1
# tagAlign : 80 * {N_tissues}
##
## PASS1B:
# signal   : 62 * {N_tissues}
# peak     : 24 * {N_tissues}
# qc       : 12
# tagAlign : 52 * {N_tissues}

if [ $# -lt 3 ]; then
  echo "Usage: ./pass_extract_atac_from_gcp.sh [NUM_CORES] [CROO_OUTPUT_PATH] [DOWNLOAD_DIR]"
  echd
  echo "Example: pass_extract_atac_from_gcp.sh 4 gs://my-bucket/my_workflow/outputs/croo gs://my-bucket/my_workflow/processed"
  echo
  echo "[NUM_CORES]: The number of cores to use"
  echo "[CROO_OUTPUT_PATH]: The location of the croo outputs"
  echo "[DOWNLOAD_DIR]: The directory to output the files to"
  echo
  exit 1
fi

NUM_CORES=$1        # number of processes to run in parallel
CROO_OUTPUT_PATH=$2 # gcp path to croo outputs without trailing slash
DOWNLOAD_DIR=$3     # gcp or local output directory path without trailing slash

if [[ $CROO_OUTPUT_PATH == gs://* ]]; then
  copy_dest="gcp"
else
  copy_dest="local"
fi

CROO_OUTPUT_PATH=${CROO_OUTPUT_PATH%/}
DOWNLOAD_DIR=${DOWNLOAD_DIR%/}

if [[ "$copy_dest" == "gcp" ]]; then

  # individual tagAlign files
  gsutil -m cp -n "${CROO_OUTPUT_PATH}/*/*/align/rep?/*tagAlign.gz" "${DOWNLOAD_DIR}/tagalign/"

  # individual signal track (p-value)
  gsutil -m cp -n "${CROO_OUTPUT_PATH}/*/*/signal/rep?/*pval.signal.bigwig" "${DOWNLOAD_DIR}/signal/"
else
  cd "$DOWNLOAD_DIR" || (echo "ERROR: could not cd to $DOWNLOAD_DIR" && exit 1)
  mkdir -p qc peak signal tagalign

  # rep-to-sample map
  gsutil cp -n "${CROO_OUTPUT_PATH}/rep_to_sample_map.csv" .
  # merged QC
  gsutil cp -n "${CROO_OUTPUT_PATH}/*qc*" qc

  # individual tagAlign files
  gsutil -m cp -n "${CROO_OUTPUT_PATH}/*/*/align/rep?/*tagAlign.gz" tagalign

  # individual signal track (p-value)
  gsutil -m cp -n "${CROO_OUTPUT_PATH}/*/*/signal/rep?/*pval.signal.bigwig signal"
fi

gs_copy() {
  local dir=$1
  local subdir
  local condition

  subdir=$(gsutil ls "$dir")
  condition=$(basename "${subdir%/}")

  # merged peak file
  gsutil cp -n "${subdir}peak/overlap_reproducibility/overlap.optimal_peak.narrowPeak.gz peak/${condition}.overlap.optimal_peak.narrowPeak.gz"
  gsutil cp -n "${subdir}peak/overlap_reproducibility/overlap.optimal_peak.narrowPeak.hammock.gz peak/${condition}.overlap.optimal_peak.narrowPeak.hammock.gz"

  # pooled signal track
  if [[ $condition != *"GET-STDRef-Set"* ]]; then
    gsutil cp -n "${subdir}signal/pooled-rep/basename_prefix.pooled.pval.signal.bigwig signal/${condition}.pooled.pval.signal.bigwig"
  fi

  # qc.html
  gsutil cp -n "${subdir}qc/qc.html" "qc/${condition}.qc.html"
}

gs_copy_gcp() {
  local dir=$1
  local subdir
  local condition
  local out_dir

  subdir=$(gsutil ls "$dir" | grep -v 'rep_to_sample_map.csv\|tagalign')
  condition=$(basename "${subdir%/}")
  out_dir="$(dirname "$dir")/final"

  # merged peak file
  gsutil -m cp -n "${subdir}peak/overlap_reproducibility/overlap.optimal_peak.narrowPeak.gz" "${out_dir}/peak/${condition}.overlap.optimal_peak.narrowPeak.gz"
  gsutil -m cp -n "${subdir}peak/overlap_reproducibility/overlap.optimal_peak.narrowPeak.hammock.gz" "${out_dir}/peak/${condition}.overlap.optimal_peak.narrowPeak.hammock.gz"

  # pooled signal track
  if [[ $condition != *"GET-STDRef-Set"* ]]; then
    gsutil -m cp -n "${subdir}signal/pooled-rep/basename_prefix.pooled.pval.signal.bigwig" "${out_dir}/signal/${condition}.pooled.pval.signal.bigwig"
  fi

  # qc.html
  gsutil cp -n "${subdir}qc/qc.html" "${out_dir}/qc/${condition}.qc.html"
}

if [[ "$copy_dest" == "gcp" ]]; then
  export -f gs_copy_gcp
  parallel --verbose --jobs "$NUM_CORES" gs_copy_gcp ::: "$(gsutil ls "$CROO_OUTPUT_PATH" | grep -E "/$" | grep -v "final")"
else
  export -f gs_copy
  parallel --verbose --jobs "$NUM_CORES" gs_copy ::: "$(gsutil ls "$CROO_OUTPUT_PATH" | grep -E "/$" | grep -v "final")"
fi
