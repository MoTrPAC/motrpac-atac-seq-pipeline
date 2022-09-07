#!/bin/bash
# Nicole Gay
# 13 May 2020
# ATAC-seq alignment stats
# usage: bash align_stats.sh [NUM_CORES] [indir] [bamdir]
# make sure the vm has bc and samtools istalled
# sudo apt install bc
set -e

cores=$1
indir=$2
bamdir=$3

if [ -z "$4" ]; then
  type="glob"
else
  type=$4
fi

#indir=/projects/motrpac/PASS1A/ATAC/NOVASEQ_BATCH2/outputs
#indir=~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final
# path to ENCODE outputs, anywhere upstream of the bam files
# also where output folder will be made
#bamdir=~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output
#path to the location of unfiltered bam files (*_R1.trim.bam)

#module load samtools

cd "$indir"
mkdir -p idxstats # make outdir

align_stats() {
  local bam=$1 # 90141015805_R1.trim.bam - UNFILTERED BAM
  local viallabel

  viallabel=$(basename "$bam" | sed "s/_R1.*//")
  echo "Processing $viallabel"

  # get counts
  local total
  local y
  local x
  local mt
  local auto
  local contig
  total=$(awk '{sum+=$3;}END{print sum;}' "idxstats/${viallabel}_chrinfo.txt")
  y=$(grep -E "^chrY" "idxstats/${viallabel}_chrinfo.txt" | head -1 | cut -f 3)
  x=$(grep -E "^chrX" "idxstats/${viallabel}_chrinfo.txt" | head -1 | cut -f 3)
  mt=$(grep -E "^chrM" "idxstats/${viallabel}_chrinfo.txt" | head -1 | cut -f 3)
  auto=$(grep -E "^chr[0-9]" "idxstats/${viallabel}_chrinfo.txt" | cut -f 3 | awk '{sum+=$1;}END{print sum;}')
  contig=$(grep -E -v "^chr" "idxstats/${viallabel}_chrinfo.txt" | cut -f 3 | awk '{sum+=$1;}END{print sum;}')

  # get fractions
  local pct_y
  local pct_x
  local pct_mt
  local pct_auto
  local pct_contig
  pct_y=$(echo "scale=5; ${y}/${total}*100" | bc -l | sed 's/^\./0./')
  pct_x=$(echo "scale=5; ${x}/${total}*100" | bc -l | sed 's/^\./0./')
  pct_mt=$(echo "scale=5; ${mt}/${total}*100" | bc -l | sed 's/^\./0./')
  pct_auto=$(echo "scale=5; ${auto}/${total}*100" | bc -l | sed 's/^\./0./')
  pct_contig=$(echo "scale=5; ${contig}/${total}*100" | bc -l | sed 's/^\./0./')

  # output to file
  echo 'viallabel,total_primary_alignments,pct_chrX,pct_chrY,pct_chrM,pct_auto,pct_contig' >"idxstats/${viallabel}_chrinfo.csv"
  echo "${viallabel},${total},${pct_x},${pct_y},${pct_mt},${pct_auto},${pct_contig}" >>"idxstats/${viallabel}_chrinfo.csv"
}
export -f align_stats

if [ "$type" == "glob" ]; then
  parallel --verbose --jobs "$cores" align_stats ::: "$(ls "${bamdir%/}"/*/*/align/rep*/*.trim.bam)"
elif [ "$type" == "file" ]; then
  readarray -t raw_bam_list <<<"$bamdir"
  parallel --verbose --jobs "$cores" align_stats ::: "${raw_bam_list[@]}"
elif [ "$type" == "find" ]; then
  parallel --verbose --jobs "$cores" align_stats ::: "$(find -name "*_R1.trim.bam" "$bamdir")"
else
  echo "type must be glob, file, or find"
  exit 1
fi

# collapse
#head -1 $(find -name "*_chrinfo.csv" | head -1) > merged_chr_info.csv
#for file in $(find -name "*_chrinfo.csv"); do sed -e '1d' $file >> merged_chr_info.csv; done
cat idxstats/*_chrinfo.csv | grep -v "^viallabel" | sed '1iviallabel,total_primary_alignments,pct_chrX,pct_chrY,pct_chrM,pct_auto,pct_contig' >merged_chr_info.csv
