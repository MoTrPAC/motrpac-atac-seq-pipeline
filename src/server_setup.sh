#!/usr/bin/env bash
# Wrapper script for running the ENCODE ATAC-seq pipeline

###
# working directory needs to be base directory (not src/)
# USAGE: src/atac-seq-human-wrapper.sh
###

set -eu

### VARIABLES TO SET ###
# set this to the region you want to run in (e.g. us-central1), the region should be compatible with life sciences API
GCP_REGION="us-central1"
GCP_PROJECT="motrpac-portal"
CROMWELL_OUT_DIR="gs://mihir-test/pipelines/out"
CROMWELL_LOC_DIR="gs://mihir-test/pipelines/loc"
# you need to have a service account with access to the life sciences API on the VM
REMOTE_KEY_FILE=~/.keys/service_account_key.json
###


#### Script ####
echo "Installing dependencies..."
sudo add-apt-repository ppa:deadsnakes/ppa
sudo apt-get update
sudo apt-get install -y curl wget jq parallel git python3.10 acl tmux
sudo apt-key adv \
  --keyserver hkp://keyserver.ubuntu.com:80 \
  --recv-keys 0xB1998361219BD9C9
curl -O https://cdn.azul.com/zulu/bin/zulu-repo_1.0.0-3_all.deb
sudo apt-get install ./zulu-repo_1.0.0-3_all.deb
sudo apt-get update
sudo apt-get install zulu11-jdk
rm zulu-repo_1.0.0-3_all.deb

echo "Installing Python requirements..."
pip install -r requirements.txt

echo "Installing Docker"
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo groupadd docker
sudo usermod -aG docker $USER
newgrp docker

echo "Cloning ENCODE ATAC-seq pipeline..."
git clone --single-branch --branch v1.7.0 https://github.com/ENCODE-DCC/atac-seq-pipeline.git
git apply patches/fix__add_missing_runtime_attributes_to_atac-seq_v1_7_0.patch

echo "Configuring caper..."
CAPER_CONF_DIR=/opt/caper
sudo mkdir -p $CAPER_CONF_DIR $CAPER_CONF_DIR/local_out_dir $CAPER_CONF_DIR/local_loc_dir

# set the permissions on the folder
sudo chown -R "$USER" $CAPER_CONF_DIR
sudo chmod 777 -R $CAPER_CONF_DIR
sudo setfacl -R -d -m u::rwX $CAPER_CONF_DIR
sudo setfacl -R -d -m g::rwX $CAPER_CONF_DIR
sudo setfacl -R -d -m o::rwX $CAPER_CONF_DIR

# create the config file
cat <<EOF > "/opt/caper/default.conf"
# caper
backend=gcp
no-server-heartbeat=True
# cromwell
max-concurrent-workflows=300
max-concurrent-tasks=1000
# local backend
local-out-dir=$CAPER_CONF_DIR/local_out_dir
local-loc-dir=$CAPER_CONF_DIR/local_loc_dir
# gcp backend
gcp-prj=$GCP_PROJECT
gcp-region=$GCP_REGION
gcp-out-dir=$CROMWELL_OUT_DIR
gcp-loc-dir=$CROMWELL_LOC_DIR
gcp-service-account-key-json=$REMOTE_KEY_FILE
use-google-cloud-life-sciences=True
# metadata DB
db=mysql
mysql-db-ip=localhost
mysql-db-port=3306
mysql-db-user=cromwell
mysql-db-password=cromwell
mysql-db-name=cromwell
EOF
sudo chmod +r "/opt/caper/default.conf"

echo "Creating MySQL database..."
DB_DIR=~/.caper/db
INIT_DB_DIR=~/.caper/init_db
sudo mkdir -p $DB_DIR $INIT_DB_DIR

INIT_SQL="""
CREATE USER 'cromwell'@'%' IDENTIFIED BY 'cromwell';
GRANT ALL PRIVILEGES ON cromwell.* TO 'cromwell'@'%' WITH GRANT OPTION;
"""
echo "${INIT_SQL}" > $INIT_DB_DIR/init_cromwell_user.sql

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
    > /dev/null
  returned_value=$?
  echo ${returned_value}
}

until [ "$(is_mysql_alive)" -eq 0 ]
do
  sleep 5
  echo "Waiting for MySQL container to be ready..."
done

gcloud auth activate-service-account --key-file="$REMOTE_KEY_FILE"
export GOOGLE_APPLICATION_CREDENTIALS="$REMOTE_KEY_FILE"
