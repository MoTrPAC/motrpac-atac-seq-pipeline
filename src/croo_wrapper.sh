#!/bin/sh

indir="gs://rna-seq_araja/PASS/atac-seq/stanford/PASS1B/atac"
outdir="gs://rna-seq_araja/PASS/atac-seq/stanford/batch10_20210113/Output"
wfids="hipp_wfids.txt"
croo_job_name="croo_copy_jobs_hippo.sh"

bash motrpac-atac-seq-pipeline-test/src/croo.sh ${wfids} ${indir} ${outdir} >>${croo_job_name}

echo "Success! Done creating croo copy jobs"
