#!/bin/bash
# Nicole Gay, updated for single-level croo output structure
# 13 May 2020 / 2026
# ATAC-seq alignment stats
#
# Reads croo filetables to locate genome BAMs (handles cache hits automatically),
# copies BAMs locally, runs samtools idxstats in parallel, then collapses to
# merged_chr_info.csv.
#
# Requirements: bc, samtools, gsutil, parallel
#   sudo apt install bc
#
# Usage: bash align_stats.sh [NUM_CORES] [CROO_OUTPUT_PATH] [OUT_DIR]
#   NUM_CORES:         number of parallel samtools jobs
#   CROO_OUTPUT_PATH:  GCS path to croo output dir (label dirs directly underneath)
#   OUT_DIR:           local output directory for idxstats/ and merged_chr_info.csv

set -e

if [ $# -lt 3 ]; then
  echo
  echo "Usage: bash align_stats.sh [NUM_CORES] [CROO_OUTPUT_PATH] [OUT_DIR]"
  echo
  echo "Example: bash align_stats.sh 4 gs://my-bucket/croo_output ./align_stats_output"
  echo
  exit 1
fi

cores=$1
CROO_OUTPUT_PATH=${2%/}
OUT_DIR=$3

TMP_BAM_DIR="${OUT_DIR}/tmp_bams"
mkdir -p "$OUT_DIR" "$TMP_BAM_DIR"

cwd=$(pwd)
cd "$OUT_DIR"
mkdir -p idxstats

# 1. Find all filetables across label dirs
echo "Finding filetables in ${CROO_OUTPUT_PATH} ..."
filetables=$(gsutil ls "${CROO_OUTPUT_PATH}/*/croo.filetable*.tsv" 2>/dev/null)

if [ -z "$filetables" ]; then
  echo "ERROR: No filetables found under ${CROO_OUTPUT_PATH}"
  exit 1
fi

echo "Found $(echo "$filetables" | wc -l) filetable(s)"

# 2. Extract genome BAM GCS paths from each filetable
#    Filter to /align/rep paths to exclude mito BAMs (/align_mito/rep)
echo "Extracting genome BAM paths..."
bam_gcs_paths=$(echo "$filetables" | while read -r ft; do
  gsutil cat "$ft" | grep "Raw BAM from aligner" | cut -f2 | grep "/align/rep"
done)

n_bams=$(echo "$bam_gcs_paths" | grep -c "." || true)
echo "Found ${n_bams} genome BAMs"

# 3. Copy BAMs to local tmp dir
echo "Copying BAMs to ${TMP_BAM_DIR} ..."
echo "$bam_gcs_paths" | while read -r bam; do
  dest="${TMP_BAM_DIR}/$(basename "$bam")"
  if [ -f "$dest" ]; then
    echo "  Already exists, skipping: $(basename "$bam")"
  else
    echo "  Copying $(basename "$bam")..."
    gsutil cp "$bam" "$dest"
  fi
done

# 4. Run align_stats in parallel on local BAMs
align_stats() {
  local bam=$1
  local viallabel
  local primary

  viallabel=$(basename "$bam" | sed "s/_R1.*//")
  echo "$viallabel"

  if [ -f "idxstats/${viallabel}_chrinfo.txt" ] && samtools quickcheck "$bam" 2>/dev/null; then
    echo "Skipping $viallabel"
    return
  fi

  primary="idxstats/${viallabel}_primary.bam"
  samtools view -b -F 0x900 "$bam" -o "$primary"
  samtools index "$primary"
  samtools idxstats "$primary" > "idxstats/${viallabel}_chrinfo.txt"
  rm -f "$primary" "${primary}.bai"

  local total y x mt auto contig
  local pct_y pct_x pct_mt pct_auto pct_contig

  total=$(awk '{sum+=$3;}END{print sum;}' "idxstats/${viallabel}_chrinfo.txt")
  y=$(grep -E "^chrY" "idxstats/${viallabel}_chrinfo.txt" | head -1 | cut -f 3)
  x=$(grep -E "^chrX" "idxstats/${viallabel}_chrinfo.txt" | head -1 | cut -f 3)
  mt=$(grep -E "^chrM" "idxstats/${viallabel}_chrinfo.txt" | head -1 | cut -f 3)
  auto=$(grep -E "^chr[0-9]" "idxstats/${viallabel}_chrinfo.txt" | cut -f 3 | awk '{sum+=$1;}END{print sum;}')
  contig=$(grep -E -v "^chr" "idxstats/${viallabel}_chrinfo.txt" | cut -f 3 | awk '{sum+=$1;}END{print sum;}')

  pct_y=$(echo "scale=5; ${y}/${total}*100" | bc -l | sed 's/^\./0./')
  pct_x=$(echo "scale=5; ${x}/${total}*100" | bc -l | sed 's/^\./0./')
  pct_mt=$(echo "scale=5; ${mt}/${total}*100" | bc -l | sed 's/^\./0./')
  pct_auto=$(echo "scale=5; ${auto}/${total}*100" | bc -l | sed 's/^\./0./')
  pct_contig=$(echo "scale=5; ${contig}/${total}*100" | bc -l | sed 's/^\./0./')

  echo 'viallabel,total_primary_alignments,pct_chrX,pct_chrY,pct_chrM,pct_auto,pct_contig' > "idxstats/${viallabel}_chrinfo.csv"
  echo "${viallabel},${total},${pct_x},${pct_y},${pct_mt},${pct_auto},${pct_contig}" >> "idxstats/${viallabel}_chrinfo.csv"
}
export -f align_stats

readarray -t local_bams < <(ls "${TMP_BAM_DIR}"/*_R1.trim.bam)
echo "Running align_stats on ${#local_bams[@]} BAMs with ${cores} cores..."

parallel \
  --joblog "align_stats_$(date "+%b%d%Y_%H%M%S")_joblog.log" \
  --progress --bar --verbose \
  --jobs "$cores" \
  align_stats ::: "${local_bams[@]}"

# 5. Collapse per-sample CSVs into merged output
cat idxstats/*_chrinfo.csv \
  | grep -v "^viallabel" \
  | sed '1iviallabel,total_primary_alignments,pct_chrX,pct_chrY,pct_chrM,pct_auto,pct_contig' \
  > merged_chr_info.csv

echo "Written: ${OUT_DIR}/merged_chr_info.csv"

# 6. Clean up local BAMs
echo "Cleaning up tmp BAMs..."
rm -rf "$TMP_BAM_DIR"

cd "$cwd" || exit 1
