#!/bin/bash
set -Eeuxo pipefail
trap "echo ERR trap fired!" ERR 
# Author: Nicole Gay, Anna Scherbina 
# Updated: 7 May 2020 
# Script : encode_to_count_matrix.sh ${indir} ${srcdir} ${batch_file} ${cores}
# Purpose: generate peak x sample read counts matrix from tagAlign and hammock files 
# Run pass_extract_from_gcp.sh before this 

#get a merged peak file       

#module load miniconda/3 # for python3
#module load bedtools 

############################################################
## USER-DEFINED VARIABLES 
#Examples for user defined input arguments
#indir=~/test_mnt/PASS/atac-seq/stanford #base path to the location of outputs from all batches 
#srcdir=~/motrpac-atac-seq-pipeline/src # directory with truncate_narrowpeak_200bp_summit.py
#batch_file=/home/araja7/motrpac-atac-seq-pipeline_code_dev/src/test_batch.txt #file containing the list of batches to merge the peak files
#example contents of batch file
#batch5_2020092
#final_results_dir=pass1b_atac_final
#3 worked on gcp , 8 crashes the system current gcp vm with 60gb ram
#cores=3 # number of cores allocated for parallelization 
# need ~25G per core. 10G was too low
indir=$1
srcdir=$2
batch_file=$3
cores=$4 
############################################################

outdir=${indir}/${final_results_dir}/merged_peaks  
mkdir -p ${outdir}
cd ${indir}

#concatenate peaks (narrowpeak.gz)
for i in `cat ${batch_file}`;do
	cat ${indir}/$i/Output/final/peak/*narrowPeak.gz >>${outdir}/overlap.optimal_peak.narrowPeak.bed.gz
done
echo "Success! done concatenating peak files from all tissues"

# concatenate peaks (narrowpeak.gz)
#cat $(find -path "./peak/*narrowPeak.gz") > ${outdir}/overlap.optimal_peak.narrowPeak.bed.gz

#truncate peaks to 200 bp around summit
python ${srcdir}/truncate_narrowpeak_200bp_summit.py --infile ${outdir}/overlap.optimal_peak.narrowPeak.bed.gz --outfile ${outdir}/overlap.optimal_peak.narrowPeak.200.bed.gz
echo "Success! finished truncating peaks"

# sort and merge peaks --> master peak file 
zcat ${outdir}/overlap.optimal_peak.narrowPeak.200.bed.gz | bedtools sort | bedtools merge > ${outdir}/overlap.optimal_peak.narrowPeak.200.sorted.merged.bed
echo "Success! Finished sorting and merging"

# intersect with tagalign files 
mkdir -p ${indir}/${final_results_dir}/counts_matrix
intersect_tag () {
	local tag=$1
	local results_dir=$(ls|grep "final") #assumes the results folder has the word final
	#echo "results dir is" ${results_dir}
	#echo "tag is" ${tag}		
	local viallabel=$(basename $tag | sed "s/_.*//")
	echo ${viallabel} > ${results_dir}/counts_matrix/counts.${viallabel}.txt
	bedtools coverage -nonamecheck -counts -a ${results_dir}/merged_peaks/overlap.optimal_peak.narrowPeak.200.sorted.merged.bed -b ${tag} | cut -f4 >> ${results_dir}/counts_matrix/counts.${viallabel}.txt
}
export -f intersect_tag

for i in `cat ${batch_file}`;do
	tag_align=$(ls $i/Output/final/tagalign/*tagAlign.gz)
	echo ${tag_align}
	echo ${final_results_dir}
	parallel --verbose --jobs ${cores} intersect_tag ::: $(echo ${tag_align})
done

#tag_align=$(find -path "./tagalign/*tagAlign.gz")
#parallel --verbose --jobs ${cores} intersect_tag ::: $(echo ${tag_align}) 

echo -e $'chrom\tstart\tend' > ${indir}/${final_results_dir}/index
cat ${outdir}/overlap.optimal_peak.narrowPeak.200.sorted.merged.bed >> ${indir}/${final_results_dir}/index

#split the results counts matrix by tissue
#to do : reimplement in python

cd ${indir}/${final_results_dir}/counts_matrix
ls *|awk -F "." '{print $2}'|awk '{print substr($1,8,2)}'|cut -f1|sort|uniq >>${indir}/${final_results_dir}/tmp_tids.txt
for i in `cat ${indir}/${final_results_dir}/tmp_tids.txt`;do
	paste ${indir}/${final_results_dir}/index counts.*$i??.txt >${indir}/${final_results_dir}/T$i.atac.counts.txt
	gzip ${indir}/${final_results_dir}/T$i.atac.counts.txt
done
rm ${indir}/${final_results_dir}/tmp_tids.txt
rm ${indir}/${final_results_dir}/index
echo "Success generating counts matrix"