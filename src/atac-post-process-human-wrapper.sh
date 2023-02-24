#!/usr/bin/env bash
# Wrapper script for running the ENCODE ATAC-seq pipeline

###
# working directory needs to be base directory (not src/)
# USAGE: src/atac-seq-human-wrapper.sh
###

set -eu

### VARIABLES TO SET ###
NUM_CORES=12
BATCH_PREFIX=batch1_20220710
GCS_BUCKET=my_bucket
ATAC_OUTPUT_DIR="gs://my_bucket/atac-seq/batch1_20220710/processed"
SAMPLE_METADATA_FILENAME="batch1_20220710_sample_metadata.csv"
# set this to the region you want to run in (e.g. us-central1), the region should be compatible with life sciences API
CROMWELL_OUT_DIR="gs://my_bucket/pipelines/out"
###

# constants
OUT_DIR=outputs/
MOUNT_DIR=~/mnt/
LOCAL_ATAC_OUT_DIR=${ATAC_OUTPUT_DIR#"gs://"}

echo "Downloading outputs..."
bash src/croo.sh $OUT_DIR/"$BATCH_PREFIX"_submissions.json $CROMWELL_OUT_DIR/atac/ $ATAC_OUTPUT_DIR/croo true

echo "Mounting GCS bucket..."
mkdir -p "$MOUNT_DIR"/"$GCS_BUCKET"
mkdir -p "$MOUNT_DIR"/tmp
gcsfuse --implicit-dirs "$GCS_BUCKET" "$MOUNT_DIR"/"$GCS_BUCKET"

#get qc tsv report
echo "Creating qc2tsv report..."
mkdir -p "$MOUNT_DIR"/"$GCS_BUCKET"/qc/
bash src/qc2tsv.sh $ATAC_OUTPUT_DIR/croo "$MOUNT_DIR"/"$GCS_BUCKET"/qc/"$BATCH_PREFIX"_qc.tsv

# reorganize croo outputs for quantification
echo "Copying files for quantification..."
bash src/human_extract_atac_from_gcp.sh $NUM_CORES $ATAC_OUTPUT_DIR/ $ATAC_OUTPUT_DIR/croo

# run samtools to generate genome alignment stats
echo "Generating alignment stats..."
bash src/align_stats.sh $NUM_CORES ~/"$MOUNT_DIR"/$LOCAL_ATAC_OUT_DIR ~/"$MOUNT_DIR"/$LOCAL_ATAC_OUT_DIR/croo

# Create final qc report merging the metadata and workflow qc scores
echo "Generating merged qc reports..."
Rscript src/merge_atac_qc_human.R -w ~/"$MOUNT_DIR"/$LOCAL_ATAC_OUT_DIR/$SAMPLE_METADATA_FILENAME -q ~/"$MOUNT_DIR"/$LOCAL_ATAC_OUT_DIR/qc/"$BATCH_PREFIX"_qc.tsv -a ~/"$MOUNT_DIR"/$LOCAL_ATAC_OUT_DIR/merged_chr_info.csv -o ~/"$MOUNT_DIR"/${ATAC_OUTPUT_DIR#"gs://"}/

echo "Generating sample counts matrix..."
bash src/encode_to_count_matrix_human.sh $ATAC_OUTPUT_DIR "$(pwd)"/src/ $NUM_CORES

echo "Done!"
