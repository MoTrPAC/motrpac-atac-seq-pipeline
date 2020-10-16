#!/bin/bash
# Nicole Gay
# 6 May 2020
#
# desription: copy necessary outputs from GCP 
# 
# usage: bash pass_extract_atac_from_gcp.sh ${NUM_CORES}
#
### Expected numbers of files:
##
## PASS1A:
# signal   : 98 * {N_tissues}
# peak     : 40 * {N_tissues}
# qc       : 1 
# tagalign : 80 * {N_tissues}
##
## PASS1B:
# signal   : 62 * {N_tissues}
# peak     : 24 * {N_tissues}
# qc       : 1 
# tagalign : 52 * {N_tissues}

set -e

cores=$1 # number of processes to run in parallel

download_dir=/projects/motrpac/PASS1A/ATAC/NOVASEQ_BATCH2/outputs
gsurl=gs://motrpac-portal-transfer-stanford/Output/atac-seq/batch_20200318

cd ${download_dir}
mkdir -p qc peak signal tagalign

# rep-to-sample map
gsutil cp -n ${gsurl}/rep_to_sample_map.csv .
# merged QC
gsutil cp -n ${gsurl}/*qc* qc

# individiual tagalign files 
gsutil -m cp -n ${gsurl}/*/*/align/rep?/*tagAlign.gz tagalign

# individual signal track (p-value)
gsutil -m cp -n ${gsurl}/*/*/signal/rep?/*pval.signal.bigwig signal

gscopy () {
	local dir=$1
	local subdir=$(gsutil ls ${dir})
	local condition=$(basename $(echo $subdir | sed "s|/$||"))

	# merged peak file 
	gsutil cp -n ${subdir}peak/overlap_reproducibility/overlap.optimal_peak.narrowPeak.gz peak/${condition}.overlap.optimal_peak.narrowPeak.gz
	gsutil cp -n ${subdir}peak/overlap_reproducibility/overlap.optimal_peak.narrowPeak.hammock.gz peak/${condition}.overlap.optimal_peak.narrowPeak.hammock.gz

	# pooled signal track
	if [[ $condition != *"GET-STDRef-Set"* ]]; then 
		gsutil cp -n ${subdir}signal/pooled-rep/basename_prefix.pooled.pval.signal.bigwig signal/${condition}.pooled.pval.signal.bigwig
	fi
	
	# qc.html
	gsutil cp -n ${subdir}qc/qc.html qc/${condition}.qc.html
}
export -f gscopy
parallel --verbose --jobs ${cores} gscopy ::: $(gsutil ls ${gsurl} | grep -E "/$")
