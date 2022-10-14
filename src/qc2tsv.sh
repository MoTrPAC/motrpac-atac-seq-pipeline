#!/bin/bash
set -Eeuxo pipefail
trap "echo ERR trap fired!" ERR
#This script generates atac qc tsv report and write the output to a gcp bucket.
#Usage : bash src/qc2tsv.sh <gcp_path_path_to_croo_outputs> <output_qc_report_name>

gcp_path=$1
outfile_name=$2

random_string=$(openssl rand -hex 8)
mkdir "$random_string"
cd "$random_string" || exit

gsutil ls "$gcp_path"/*/*/qc/qc.json >file_list.txt
echo "Done creating file list"
qc2tsv --file file_list.txt --collapse-header >"$outfile_name"
gsutil mv "$outfile_name" "$gcp_path"/final/
echo "Done creating atac-seq qc report"

cd ..
rm -rf "$random_string"
