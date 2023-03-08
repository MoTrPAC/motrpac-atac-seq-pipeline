#!/usr/bin/env bash

CONTAINER_NAME=mysql_cromwell
FASTQ_RAW_DIR="gs://my_bucket/atac-seq/batch1_20220710/fastq_raw"
BASE_JSON="batch1_20220710_base.json"
# you need to have a service account with access to the life sciences API on the VM
REMOTE_KEY_FILE=~/.keys/service_account_key.json

# constants
JSON_DIR=json/
OUT_DIR=outputs/

#### Script ####
if [ ! "$(docker ps -q -f name="${CONTAINER_NAME}")" ]; then
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
