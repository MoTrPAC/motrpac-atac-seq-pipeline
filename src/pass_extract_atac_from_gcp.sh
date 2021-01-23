#!/bin/bash
# Nicole Gay, modified by Archana to work on copying outputs to GCP and locally
# 6 May 2020
#
# desription: copy necessary outputs from GCP to final destination on GCP or local cluster
#
# Usage: bash pass_extract_atac_from_gcp.sh ${NUM_CORES} ${download_dir_without_trailing_slash} ${gcp_path_to_atac_croo_outputs_without_trailing_slash} ${copy_dest}
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
# qc       : 12
# tagalign : 52 * {N_tissues}

set -e

cores=$1 # number of processes to run in parallel
download_dir=$2 # gcp or local output directory path
gsurl=$3 # gcp path to croo outputs
copy_dest=$4 # mode of copy use "gcp" if the copy destination is on gcp or "local" 

#download_dir=/projects/motrpac/PASS1A/ATAC/NOVASEQ_BATCH2/outputs
#gsurl=gs://motrpac-portal-transfer-stanford/Output/atac-seq/batch_20200318
#gcp
#download_dir=gs://rna-seq_araja/test/atac-seq/test2
#local
#download_dir=/projects/motrpac/PASS1A/ATAC/NOVASEQ_BATCH7/outputs
#gsurl=gs://rna-seq_araja/PASS/atac-seq/stanford/batch7_20201002/Output

if [[ "$copy_dest" == "gcp" ]]; then

	# individiual tagalign files
    gsutil -m cp -n ${gsurl}/*/*/align/rep?/*tagAlign.gz ${download_dir}/tagalign/

    # individual signal track (p-value)
    gsutil -m cp -n ${gsurl}/*/*/signal/rep?/*pval.signal.bigwig ${download_dir}/signal/

elif [[ $copy_dest == "local" ]]; then
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

#fail if the copy destination doesn't match "gcp" or "local"

else
	echo "Invalid value for \"copy_dest\", must be \"gcp\" or \"local\" only"
    exit 1
fi

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

gscopygcp () {
        local dir=$1
        local subdir=$(gsutil ls ${dir}|grep -v 'rep_to_sample_map.csv\|tagalign')
        local condition=$(basename $(echo $subdir | sed "s|/$||"))
        local outdir=`dirname ${dir}`"/final"


        # merged peak file
        gsutil -m cp -n ${subdir}peak/overlap_reproducibility/overlap.optimal_peak.narrowPeak.gz ${outdir}/peak/${condition}.overlap.optimal_peak.narrowPeak.gz
        gsutil -m cp -n ${subdir}peak/overlap_reproducibility/overlap.optimal_peak.narrowPeak.hammock.gz ${outdir}/peak/${condition}.overlap.optimal_peak.narrowPeak.hammock.gz

        # pooled signal track
        if [[ $condition != *"GET-STDRef-Set"* ]]; then
                gsutil -m cp -n ${subdir}signal/pooled-rep/basename_prefix.pooled.pval.signal.bigwig ${outdir}/signal/${condition}.pooled.pval.signal.bigwig
        fi

        # qc.html
        gsutil cp -n ${subdir}qc/qc.html ${outdir}/qc/${condition}.qc.html
}

if [[ "$copy_dest" == "gcp" ]]; then

	export -f gscopy
	parallel --verbose --jobs ${cores} gscopy ::: $(gsutil ls ${gsurl} | grep -E "/$")

elif [[ "$copy_dest" == "local" ]]; then

    export -f gscopy
    parallel --verbose --jobs ${cores} gscopy ::: $(gsutil ls ${gsurl} | grep -E "/$"|grep -v "final")

fi

