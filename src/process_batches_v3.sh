#!/bin/bash

# Usage: ./process_batches_v3.sh <batches_tsv_file> [output_dir] [--per-batch]

if [ $# -lt 1 ]; then
  echo "Usage: $0 <batches_tsv_file> [output_dir] [--per-batch]"
  echo "Example: $0 batches.tsv config_output_v3"
  echo "Example: $0 batches.tsv config_output_v3 --per-batch"
  echo ""
  echo "Options:"
  echo "  --per-batch  Process batches separately instead of combining."
  echo "               Config files will include batch name in filename."
  exit 1
fi

BATCHES_FILE="$1"
OUTPUT_DIR="${2:-config_output_v3}"
PER_BATCH_FLAG=""

# Check for --per-batch flag in any position
for arg in "$@"; do
  if [ "$arg" == "--per-batch" ]; then
    PER_BATCH_FLAG="--per-batch"
  fi
done

if [ ! -f "$BATCHES_FILE" ]; then
  echo "Error: File $BATCHES_FILE not found"
  exit 1
fi

echo "Processing all batches from $BATCHES_FILE"
echo "Output directory: $OUTPUT_DIR"
if [ -n "$PER_BATCH_FLAG" ]; then
  echo "Mode: Per-batch (batches processed separately)"
else
  echo "Mode: Combined (batches merged together)"
fi
echo ""
echo "This script uses:"
echo "  - Sample metadata files from each batch"
echo "  - Phenotype data from gs://motrpac-data-hub/phenotype/rat/"
echo "  - BIC Label Data from gs://motrpac-portal-transfer-dmaqc/"
echo "  - Data dictionary from src/meta_pass_data_dict.txt"
echo "  - Reference standards from testing/Stanford_StandardReferenceMaterial.txt"
echo ""

python3 src/make_json_replicates_v3.py \
  -j ./examples/base.json \
  -r ./testing/Stanford_StandardReferenceMaterial.txt \
  -d ./src/meta_pass_data_dict.txt \
  -b "$BATCHES_FILE" \
  -o "$OUTPUT_DIR" \
  --bucket-base gs://motrpac-portal-transfer-stanford/atac-seq/rat \
  --bic-dict gs://motrpac-portal-transfer-dmaqc/Bic_Label_Data_Files/DMAQC_Transfer_CAS_BICLabelData_20251101/DMAQC_Transfer_MoTrPAC_Dictionary_CAS_BICLabelData.json \
  --bic-data gs://motrpac-portal-transfer-dmaqc/Bic_Label_Data_Files/DMAQC_Transfer_CAS_BICLabelData_20251101/DMAQC_Transfer_MoTrPAC_CAS_BICLabelData_20251101.json \
  $PER_BATCH_FLAG

echo ""
echo "Done! Check $OUTPUT_DIR for:"
echo "  - Config JSON files for each sample group"
echo "  - config_summary.tsv with counts of FASTQs, vial labels, and PIDs per config"
