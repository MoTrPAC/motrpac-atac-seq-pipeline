#!/bin/bash
# Nicole Gay, modified by Archana Raja
# 31 March 2020
# pull replicate names from ATAC pipeline stucture
#Usage : bash src/extract_rep_names_from_encode.sh <gcp-path-to-atac-run-with-trailing-slash> <gcp-path-to-output-results-bucket-with-trailing-slash>

run_dir=$1
out_gcp_path=$2

for dir in $(gsutil ls ${run_dir}); do
	# get condition name
	gsutil cp $(gsutil ls ${dir}call-qc_report/glob*/qc.json) .
	condition=$(grep "description" qc.json  | sed 's/.*: "//' | sed 's/".*//')
	if [[ $condition == *" "* ]]; then
		# try getting it from "title"
		condition=$(grep "title" qc.json  | sed 's/.*: "//' | sed 's/".*//')
		if [[ $condition == *" "* ]]; then
			echo "Using workflow ID as condition label."
			condition=$(basename $dir)
		else
			condition=$condition
		fi
	fi

	# get replicate names
	rep=1
	for shard in $(gsutil ls ${dir}call-filter); do
		viallabel=$(basename $(gsutil ls ${shard}glob*/*bam) | sed "s/_R1.*//")
		echo "${condition},rep${rep},${viallabel}" >> rep_to_sample_map.csv
		rep=$((rep + 1))
	done
done

#copy outputs to gcp and delete the local copies
gsutil -m cp -r rep_to_sample_map.csv ${out_gcp_path}/
rm -rf rep_to_sample_map.csv
rm -rf qc.json
