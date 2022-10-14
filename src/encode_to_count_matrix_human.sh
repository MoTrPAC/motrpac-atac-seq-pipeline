#!/bin/bash
set -Eeuxo pipefail
# Author: Nicole Gay, Anna Scherbina
# Updated: 7 May 2020
# Script : encode_to_count_matrix.sh ${in_dir} ${src_dir} ${cores} ${final_results_dir}
# Purpose: generate peak x sample read counts matrix from tagAlign and hammock files
# Run pass_extract_from_gcp.sh before this

#get a merged peak file

############################################################
## USER-DEFINED VARIABLES
#Examples for user defined input arguments
#in_dir=~/test_mnt/PASS/atac-seq/stanford #base path to the location of outputs from all batches
#src_dir=~/motrpac-atac-seq-pipeline/src # directory with truncate_narrowpeak_200bp_summit.py
#batch_file=/home/araja7/motrpac-atac-seq-pipeline_code_dev/src/test_batch.txt #file containing the list of batches to merge the peak files
#example contents of batch file
#batch5_2020092
#final_results_dir=pass1b_atac_final
#3 worked on gcp , 8 crashes the system current gcp vm with 60gb ram
#cores=3 # number of cores allocated for parallelization
# need ~25G per core. 10G was too low
in_dir=$1
src_dir=$2
cores=$3
############################################################

#make the same code usable for generating counts from single or multiple batches

in_dir=${in_dir%/}
src_dir=${src_dir%/}

OUT_DIR=${in_dir}/merged_peaks
echo "$OUT_DIR"
mkdir -p "$OUT_DIR"

cd "$in_dir"

#concatenate peaks (narrowpeak.gz)
cat "${in_dir}"/peak/*narrowPeak.gz >>"${OUT_DIR}/overlap.optimal_peak.narrowPeak.bed.gz"
echo "Success! done concatenating peak files from all tissues"

# concatenate peaks (narrowpeak.gz)
#cat $(find -path "./peak/*narrowPeak.gz") > ${OUT_DIR}/overlap.optimal_peak.narrowPeak.bed.gz

#truncate peaks to 200 bp around summit
python "${src_dir}/truncate_narrowpeak_200bp_summit.py" --infile "${OUT_DIR}/overlap.optimal_peak.narrowPeak.bed.gz" --outfile "${OUT_DIR}/overlap.optimal_peak.narrowPeak.200.bed.gz"
echo "Success! finished truncating peaks"

# sort and merge peaks --> master peak file
zcat "${OUT_DIR}/overlap.optimal_peak.narrowPeak.200.bed.gz" | bedtools sort | bedtools merge >"${OUT_DIR}/overlap.optimal_peak.narrowPeak.200.sorted.merged.bed"
echo "Success! Finished sorting and merging"

# intersect with tagalign files
mkdir -p "${in_dir}/counts_matrix"

intersect_tag() {
  local TAG=$1
  local VIAL_LABEL

  VIAL_LABEL=$(basename "$TAG" | sed "s/_.*//")
  echo "$VIAL_LABEL" >"${in_dir}/counts_matrix/counts.${VIAL_LABEL}.txt"
  bedtools coverage -nonamecheck -counts -a "${in_dir}/merged_peaks/overlap.optimal_peak.narrowPeak.200.sorted.merged.bed" -b "$TAG" | cut -f4 >>"${in_dir}/counts_matrix/counts.${VIAL_LABEL}.txt"
}

export in_dir
export -f intersect_tag

# shellcheck disable=SC2046
parallel --verbose --jobs "$cores" intersect_tag ::: $(ls "${in_dir}"/tagalign/*tagAlign.gz)

echo -e $'chrom\tstart\tend' >"${in_dir}/index"
cat "${OUT_DIR}/overlap.optimal_peak.narrowPeak.200.sorted.merged.bed" >>"${in_dir}/index"

#split the results counts matrix by tissue
#to do : reimplement in python

cd "${in_dir}/counts_matrix"
ls ./* | awk -F "." '{print $2}' | awk '{print substr($1,8,2)}' | cut -f1 | sort | uniq >>"${in_dir}/tmp_tids.txt"

while IFS= read -r line; do
  paste "${in_dir}"/index counts.*"${line}"??.txt >"${in_dir}/T${line}.atac.counts.txt"
  gzip "${in_dir}/T${line}.atac.counts.txt"
done <"${in_dir}/tmp_tids.txt"

rm "${in_dir}/tmp_tids.txt"
rm "${in_dir}/index"

echo "Success generating counts matrix"
