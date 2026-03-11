#!/bin/bash
# Author: Nicole Gay, Anna Scherbina
# Updated: 2026
# Purpose: Generate peak x sample read counts matrix from tagAlign and peak files
#          across all phases/tissues. Run extract_atac_from_gcp_pass.sh for each
#          phase before running this script.
#
# Requirements: bedtools, python3, gsutil, parallel
#   sudo apt install bedtools
#
# Usage: bash encode_to_count_matrix_all_tissues_pass.sh \
#            [NUM_CORES] [OUT_DIR] [SRCDIR] [GCS_FINAL_DIR ...]
#
#   NUM_CORES:      parallel bedtools jobs (~25G RAM per core recommended)
#   OUT_DIR:        local output directory
#   SRCDIR:         path to motrpac-atac-seq-pipeline/src
#   GCS_FINAL_DIR:  one or more GCS paths to phase final dirs
#
# Example:
#   bash encode_to_count_matrix_all_tissues_pass.sh \
#       3 ./counts_output ./src \
#       gs://my-bucket/phase1b_final \
#       gs://my-bucket/phase1a_final

set -Eeuo pipefail

if [ $# -lt 4 ]; then
  echo
  echo "Usage: bash encode_to_count_matrix_all_tissues_pass.sh [NUM_CORES] [OUT_DIR] [SRCDIR] [GCS_FINAL_DIR ...]"
  echo
  exit 1
fi

NUM_CORES=$1
OUT_DIR=$(realpath "$2")
SRCDIR=$(realpath "$3")
shift 3
GCS_FINAL_DIRS=("$@")

MERGED_PEAKS_DIR="${OUT_DIR}/merged_peaks"
COUNTS_DIR="${OUT_DIR}/counts_matrix"
TMP_TAG_DIR="${OUT_DIR}/tmp_tagalign"

mkdir -p "$MERGED_PEAKS_DIR" "$COUNTS_DIR" "$TMP_TAG_DIR"

##############################################################
## Step 1: Download and concatenate all peak files
##############################################################
echo "=== Step 1: Concatenating peak files ==="
CONCAT_PEAKS="${MERGED_PEAKS_DIR}/overlap.optimal_peak.narrowPeak.bed.gz"
rm -f "$CONCAT_PEAKS"

for gcs_dir in "${GCS_FINAL_DIRS[@]}"; do
  echo "  Getting peaks from ${gcs_dir}/peak/ ..."
  gsutil ls "${gcs_dir}/peak/*.narrowPeak.gz" | while read -r peak_file; do
    echo "    Appending $(basename "$peak_file")..."
    gsutil cat "$peak_file" >> "$CONCAT_PEAKS"
  done
done
echo "Done concatenating peaks"

##############################################################
## Step 2: Truncate peaks to 200bp around summit
##############################################################
echo "=== Step 2: Truncating peaks to 200bp around summit ==="
TRUNCATED_PEAKS="${MERGED_PEAKS_DIR}/overlap.optimal_peak.narrowPeak.200.bed.gz"
python3 "${SRCDIR}/truncate_narrowpeak_200bp_summit.py" \
  --infile "$CONCAT_PEAKS" \
  --outfile "$TRUNCATED_PEAKS"
echo "Done truncating peaks"

##############################################################
## Step 3: Sort and merge → master peak file
##############################################################
echo "=== Step 3: Sorting and merging peaks ==="
MASTER_PEAKS="${MERGED_PEAKS_DIR}/overlap.optimal_peak.narrowPeak.200.sorted.merged.bed"
zcat "$TRUNCATED_PEAKS" | bedtools sort | bedtools merge > "$MASTER_PEAKS"
echo "Done: $(wc -l < "$MASTER_PEAKS") peaks in master file"

##############################################################
## Step 4: Intersect tagAlign files with master peak file
##          Each job downloads its tagAlign, runs bedtools, then deletes
##############################################################
echo "=== Step 4: Counting reads per peak per sample ==="

intersect_tag() {
  local tag_gcs=$1
  local viallabel
  viallabel=$(basename "$tag_gcs" | sed "s/_.*//")
  local out="${COUNTS_DIR}/counts.${viallabel}.txt"

  if [ -f "$out" ]; then
    echo "Skipping $viallabel (already done)"
    return
  fi

  local local_tag="${TMP_TAG_DIR}/${viallabel}.tagAlign.gz"
  echo "Copying ${viallabel}..."
  gsutil cp "$tag_gcs" "$local_tag"

  echo "$viallabel" > "$out"
  bedtools coverage -nonamecheck -counts \
    -a "$MASTER_PEAKS" \
    -b "$local_tag" | cut -f4 >> "$out"

  rm -f "$local_tag"
  echo "Done: $viallabel"
}
export -f intersect_tag
export COUNTS_DIR TMP_TAG_DIR MASTER_PEAKS

# Collect all tagAlign GCS paths across all phase dirs
all_tags=()
for gcs_dir in "${GCS_FINAL_DIRS[@]}"; do
  while IFS= read -r tag; do
    all_tags+=("$tag")
  done < <(gsutil ls "${gcs_dir}/tagalign/*.tagAlign.gz")
done
echo "Found ${#all_tags[@]} tagAlign files"

parallel \
  --joblog "${OUT_DIR}/counts_matrix_$(date "+%b%d%Y_%H%M%S")_joblog.log" \
  --progress --bar --verbose \
  --jobs "$NUM_CORES" \
  intersect_tag ::: "${all_tags[@]}"

##############################################################
## Step 5: Build genomic index and split counts by tissue
##############################################################
echo "=== Step 5: Splitting count matrix by tissue ==="

INDEX="${OUT_DIR}/index"
echo -e "chrom\tstart\tend" > "$INDEX"
cat "$MASTER_PEAKS" >> "$INDEX"

cd "$COUNTS_DIR"
# Extract unique 2-digit tissue IDs from vial labels (characters 8-9)
ls counts.*.txt \
  | awk -F "." '{print $2}' \
  | awk '{print substr($1,8,2)}' \
  | sort | uniq > "${OUT_DIR}/tmp_tids.txt"

while read -r tid; do
  echo "  Generating t${tid}.atac.counts.txt.gz ..."
  paste "$INDEX" counts.*${tid}??.txt > "${OUT_DIR}/t${tid}.atac.counts.txt"
  gzip "${OUT_DIR}/t${tid}.atac.counts.txt"
done < "${OUT_DIR}/tmp_tids.txt"

rm "${OUT_DIR}/tmp_tids.txt" "$INDEX"
rmdir "$TMP_TAG_DIR" 2>/dev/null || true

echo "=== Done! ==="
ls "${OUT_DIR}"/t*.atac.counts.txt.gz
