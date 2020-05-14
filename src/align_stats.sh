#!/bin/bash
# Nicole Gay
# 13 May 2020
# ATAC-seq alignment stats
# usage: bash align_stats.sh [NUM_CORES]

set -e 

cores=$1

indir=/projects/motrpac/PASS1A/ATAC/NOVASEQ_BATCH2/outputs
# path to ENCODE outputs, anywhere upstream of the bam files
# also where output folder will be made

module load samtools

cd ${indir}
mkdir -p idxstats # make outdir

align_stats () {
	local bam=$1 # 90141015805_R1.trim.bam - UNFILTERED BAM
	local viallabel=$(basename $bam | sed "s/_R1.*//")
	local primary=idxstats/${viallabel}_primary.bam
	# already sorted
	# keep only primary alignments 
	samtools view -b -F 0x900 ${bam} -o ${primary}
	# index
	samtools index ${primary}
	samtools idxstats ${primary} > idxstats/${viallabel}_chrinfo.txt
	rm ${primary} ${primary}.bai

	# get counts
	local total=$(awk '{sum+=$3;}END{print sum;}' idxstats/${viallabel}_chrinfo.txt)
	local y=$(grep -E "^chrY" idxstats/${viallabel}_chrinfo.txt | cut -f 3)
	local x=$(grep -E "^chrX" idxstats/${viallabel}_chrinfo.txt | cut -f 3)
	local mt=$(grep -E "^chrM" idxstats/${viallabel}_chrinfo.txt | cut -f 3)
	local auto=$(grep -E "^chr[0-9]" idxstats/${viallabel}_chrinfo.txt | cut -f 3 | awk '{sum+=$1;}END{print sum;}')
	local contig=$(grep -E -v "^chr" idxstats/${viallabel}_chrinfo.txt | cut -f 3 | awk '{sum+=$1;}END{print sum;}')

	# get fractions
	local pct_y=$(echo "scale=5; ${y}/${total}*100" | bc -l | sed 's/^\./0./')
	local pct_x=$(echo "scale=5; ${x}/${total}*100" | bc -l | sed 's/^\./0./')
	local pct_mt=$(echo "scale=5; ${mt}/${total}*100" | bc -l | sed 's/^\./0./')
	local pct_auto=$(echo "scale=5; ${auto}/${total}*100" | bc -l | sed 's/^\./0./')
	local pct_contig=$(echo "scale=5; ${contig}/${total}*100" | bc -l | sed 's/^\./0./')

	# output to file 
	echo 'viallabel,total_primary_alignments,pct_chrX,pct_chrY,pct_chrM,pct_auto,pct_contig' > idxstats/${viallabel}_chrinfo.csv
	echo ${viallabel},${total},${pct_x},${pct_y},${pct_mt},${pct_auto},${pct_contig} >> idxstats/${viallabel}_chrinfo.csv
}
export -f align_stats
parallel --verbose --jobs ${cores} align_stats ::: $(find -name "*_R1.trim.bam")

# collapse
head -1 $(find -name "*_chrinfo.csv" | head -1) > merged_chr_info.csv
for file in $(find -name "*_chrinfo.csv"); do sed -e '1d' $file >> merged_chr_info.csv
