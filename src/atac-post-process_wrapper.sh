#!/bin/sh
set -Eeuxo pipefail
#Usage: bash atac-post-process_wrapper.sh
# On gcp , make sure that the bucket containing the inputs is mounted before running the script
##############################################
#Change the paths to USER DEFINED VARIABLES IN THIS SECTION ONLY BEFORE RUNNING THE SCRIPT
pipeline_output_path=gs://rna-seq_araja/PASS/atac-seq/stanford/PASS1B/atac
download_dir=gs://rna-seq_araja/PASS/atac-seq/stanford/batch8_20210113/Output/final
croo_output_path=gs://rna-seq_araja/PASS/atac-seq/stanford/batch8_20210113/Output
qc2tsv_report_name="atac_qc.tsv"
final_qc_report_name="merged_atac_qc.tsv"
copy_cores=12
copy_dest="gcp"
align_cores=12
indir=~/test_mnt/PASS/atac-seq/stanford
in_mnt_dir=~/test_mnt/PASS/atac-seq/stanford/batch8_20210113/Output/final
in_bam_dir=~/test_mnt/PASS/atac-seq/stanford/batch8_20210113/Output #path to raw unfiltered bam files
script_dir=/home/araja7/atac-pp/motrpac-atac-seq-pipeline/src
batch_wfids="/home/araja7/atac-pp/stanford/batch8/batch8_wfids.txt"
gcp_project="motrpac-portal"
sample_metadata="sample_metadata_20200928.csv"
merge_counts_cores=3
batch_filelist="/home/araja7/atac-pp/stanford/batch_list.txt"
batch_count=1
final_results_dir="batch8_20210113/Output/final"
mode=0
#final_results_dir="test_merge"
##############################################

#get replicates to sample mapping file

python3 ${script_dir}/encode_rep_names_from_croo.py ${croo_output_path} ${download_dir}/ ${batch_wfids} ${gcp_project}

#bash src/extract_rep_names_from_encode.sh ${pipeline_output_path}/ ${download_dir}/
echo "Success! Done creation of sample mapping file"

#get qc tsv report

bash ${script_dir}/qc2tsv.sh ${croo_output_path} ${qc2tsv_report_name}

echo "Success! Done creation of qc2tsv report"

# reorganize croo outputs for quantification

bash ${script_dir}/pass_extract_atac_from_gcp.sh ${copy_cores} ${download_dir} ${croo_output_path} ${copy_dest}

echo "Success! Done copying files for quantification"

# run samtools to generate genome alignment stats
bash ${script_dir}/align_stats.sh ${align_cores} ${in_mnt_dir} ${in_bam_dir}

echo "Success! Done generating alignment stats"

# Create final qc report merging the metadata and workflow qc scores

Rscript ${script_dir}/merge_atac_qc.R -w ~/${in_mnt_dir}/${sample_metadata} -q ~/${in_mnt_dir}/qc/${qc2tsv_report_name} -m ${in_mnt_dir}/rep_to_sample_map.csv -a ${in_mnt_dir}/merged_chr_info.csv -o ${in_mnt_dir}/

echo "Success! Done generating merged qc reports"

#generate counts matrix per batch
if [[ "$batch_count" == "1" ]]; then
    bash ${script_dir}/encode_to_count_matrix.sh ${indir} ${script_dir} ${batch_filelist} ${merge_counts_cores} ${final_results_dir} ${mode}
else
    echo "Skipping this step as the batch count is greater than 1, this step has to be run outside of wrapper"
    exit
fi

echo "Success! Finished"


