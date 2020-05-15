#!/bin/bash
# Nicole Gay
# 31 March 2020
# pull replicate names from ATAC pipeline stucture

for dir in $(gsutil ls gs://motrpac-portal-transfer-stanford/Output/atac-seq/batch1/); do

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
