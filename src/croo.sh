#!/bin/sh
#Usage : src/croo.sh <list_of_atac-seq_workflow_ids> <gcp_path_to_atac_seq_pipeline_workflows_without_trailing_slash> <gcp-path-to-output-without-trailing-slash> >>croo_copy_jobs.txt
#Contributors : Archana Raja, Nicole Gay

workflow_id_list=$1
gcp_path=$2
outpath=$3
for i in `cat ${workflow_id_list}`; do
    sample_dir=${gcp_path}/$i
    #out_dir=gs://motrpac-portal-transfer-stanford/Output/atac-seq/batch_20200318/$i
    out_dir=${outpath}/$i
    #as long as the descrption is hyphenated and don't contain any spaces or special characters below would work
    descrip=$(gsutil cat ${sample_dir}/call-qc_report/glob-*/qc.json | grep "description" | sed -e 's/.*": "//' -e 's/".*//')
    empty="No description" 
    if [ "${descrip}" = "No description" ]
    then
        descrip=$(gsutil cat ${sample_dir}/call-qc_report/glob-*/qc.json | grep "title" | sed -e 's/.*": "//' -e 's/".*//')
    else
        descrip=${descrip}
    fi
    echo croo --method copy ${sample_dir}/metadata.json --out-dir ${out_dir}/${descrip}/
done


