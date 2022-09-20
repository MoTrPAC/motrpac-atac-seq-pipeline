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
GCS_BUCKET=mihir-test
FASTQ_RAW_DIR="gs://mihir-test/atac-seq/batch1_20220710/fastq_raw"
ATAC_OUTPUT_DIR="gs://mihir-test/atac-seq/batch1_20220710/processed"
BASE_JSON="batch1_20220710_base.json"
# set this to the region you want to run in (e.g. us-central1), the region should be compatible with life sciences API
CROMWELL_OUT_DIR="gs://mihir-test/pipelines/out"
# you need to have a service account with access to the life sciences API on the VM
REMOTE_KEY_FILE=~/.keys/service_account_key.json
###

# constants
JSON_DIR=json/
OUT_DIR=outputs/
MOUNT_DIR=~/mnt/

#### Script ####
if [ ! "$(docker ps -q -f name=${CONTAINER_NAME})" ]; then
  echo "MySQL container does not exist, creating Docker container"

  echo "Creating MySQL database..."
  DB_DIR=~/.caper/db
  INIT_DB_DIR=~/.caper/init_db
  sudo mkdir -p $DB_DIR $INIT_DB_DIR

  INIT_SQL="""
CREATE USER 'cromwell'@'%' IDENTIFIED BY 'cromwell';
GRANT ALL PRIVILEGES ON cromwell.* TO 'cromwell'@'%' WITH GRANT OPTION;
"""
  echo "${INIT_SQL}" >$INIT_DB_DIR/init_cromwell_user.sql

  docker run -d --rm \
    --name mysql \
    -v "$DB_DIR":/var/lib/mysql \
    -v "$INIT_DB_DIR":/docker-entrypoint-initdb.d \
    -e MYSQL_ROOT_PASSWORD=cromwell \
    -e MYSQL_DATABASE=cromwell \
    -p 3306:3306 mysql:5.7

  CONTAINER_DB_HOST='127.0.0.1'
  CONTAINER_DB_PORT=3306
  is_mysql_alive() {
    docker exec -it mysql \
      mysqladmin ping \
      --user=cromwell \
      --password=cromwell \
      --host=$CONTAINER_DB_HOST \
      --port=$CONTAINER_DB_PORT \
      >/dev/null
    returned_value=$?
    echo ${returned_value}
  }

  until [ "$(is_mysql_alive)" -eq 0 ]; do
    sleep 5
    echo "Waiting for MySQL container to be ready..."
  done
fi

gcloud auth activate-service-account --key-file="$REMOTE_KEY_FILE"
export GOOGLE_APPLICATION_CREDENTIALS="$REMOTE_KEY_FILE"

echo "Running caper in a tmux session..."
cd /opt/caper/ || exit 1
tmux new-session -d -s caper-server 'caper server > caper_server.log 2>&1'
cd - || exit 1

# create JSON files for each sample
echo "Creating JSON files..."
mkdir -p "$JSON_DIR"
bash src/make_json_singleton.sh "$BASE_JSON" "$FASTQ_RAW_DIR" "$JSON_DIR"

echo "Submitting workflows to ENCODE ATAC-seq pipeline..."
mkdir -p "$OUT_DIR"
bash src/submit.sh atac-seq-pipeline/atac.wdl "$JSON_DIR" $OUT_DIR/"$BATCH_PREFIX"_submissions.json
echo "Done!"

echo "Monitoring workflows..."
python3 src/get_execution_status.py $OUT_DIR/"$BATCH_PREFIX"_submissions.json

echo "Downloading outputs..."
bash src/croo.sh $OUT_DIR/"$BATCH_PREFIX"_submissions.json $CROMWELL_OUT_DIR/atac/ $ATAC_OUTPUT_DIR/croo true

#get qc tsv report
echo "Creating qc2tsv report"
bash src/qc2tsv.sh $ATAC_OUTPUT_DIR/croo "$BATCH_PREFIX"_qc.tsv

# reorganize croo outputs for quantification
echo "Copying files for quantification"
bash src/pass_extract_atac_from_gcp.sh $NUM_CORES $ATAC_OUTPUT_DIR/croo $ATAC_OUTPUT_DIR/

echo "Downloading and setting up gcsfuse..."
wget -q https://github.com/GoogleCloudPlatform/gcsfuse/releases/download/v0.41.6/gcsfuse_0.41.6_amd64.deb
sudo dpkg -i gcsfuse_0.41.6_amd64.deb

echo "Mounting GCS bucket..."
mkdir -p "$MOUNT_DIR"
gcsfuse --implicit-dirs "$GCS_BUCKET" "$MOUNT_DIR"/"$GCS_BUCKET"

# run samtools to generate genome alignment stats
echo "Generating alignment stats"
bash src/align_stats.sh $NUM_CORES ~/"$MOUNT_DIR"/${ATAC_OUTPUT_DIR#"gs://"} ~/"$MOUNT_DIR"/${ATAC_OUTPUT_DIR#"gs://"}/croo

# Create final qc report merging the metadata and workflow qc scores

Rscript src/merge_atac_qc_human.R -w ~/${in_mnt_dir}/${sample_metadata} -q ~/${in_mnt_dir}/qc/${qc2tsv_report_name} -m ${in_mnt_dir}/rep_to_sample_map.csv -a ${in_mnt_dir}/merged_chr_info.csv -o ${in_mnt_dir}/

echo "Success! Done generating merged qc reports"
