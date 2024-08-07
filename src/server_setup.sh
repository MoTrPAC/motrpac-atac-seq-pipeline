#!/bin/bash
# Wrapper script for running the ENCODE ATAC-seq pipeline
###
# working directory needs to be base directory (not src/)
# USAGE: src/atac-seq-human-wrapper.sh
###
set -eu

if [ $# -lt 2 ]; then
  echo "Usage: ./server_setup.sh [GCP_REGION] [GCP_PROJECT] [CROMWELL_OUT_DIR] [CROMWELL_LOC_DIR] [REMOTE_KEY_FILE]"
  echd
  echo "Example: bash server_setup.sh us-central1 my-project gs://my-bucket/out gs://my-bucket/loc ~/.keys/service_account_key.json"
  echo
  echo "[GCP_REGION]: The GCP region to run the pipeline in, must be compatible with the Google Life Sciences API"
  echo "[GCP_PROJECT]: The project you are running the pipeline in"
  echo "[CROMWELL_OUT_DIR]: The GCS bucket directory to store the cromwell output files in (with a prefix - gs://)"
  echo "[CROMWELL_LOC_DIR]: The GCS bucket directory to store the cromwell localization files in (with a prefix - gs://)"
  echo "[REMOTE_KEY_FILE]: The path to the service account key file on the remote machine"
  echo
  exit 1
fi

### VARIABLES TO SET ###
# set this to the region you want to run in (e.g. us-central1), the region should be compatible with life sciences API
GCP_REGION=$1
GCP_PROJECT=$2
CROMWELL_OUT_DIR=$3
CROMWELL_LOC_DIR=$4
# you need to have a service account with access to the life sciences API on the VM
REMOTE_KEY_FILE=$5
###

#### Script ####
echo "Installing dependencies..."
sudo apt-get update
sudo apt-get install -y curl wget jq parallel git acl tmux make build-essential \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev llvm libncursesw5-dev \
  xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev \
  autoconf automake gcc perl libcurl4-gnutls-dev libncurses5-dev software-properties-common dirmngr

sudo apt-add-repository -y ppa:fish-shell/release-3
sudo add-apt-repository -y ppa:neovim-ppa/stable
sudo apt update
sudo apt install -y fish neovim

if ! command -v pyenv &>/dev/null; then
  curl -L https://github.com/pyenv/pyenv-installer/raw/master/bin/pyenv-installer | bash

  echo """
export PYENV_ROOT=\"\$HOME/.pyenv\"
command -v pyenv >/dev/null || export PATH=\"\$PYENV_ROOT/bin:\$PATH\"
eval \"\$(pyenv init --path)\"
eval \"\$(pyenv init -)\"
eval \"\$(pyenv virtualenv-init -)\"
""" >>~/.bashrc

  echo """
export PYENV_ROOT=\"\$HOME/.pyenv\"
command -v pyenv >/dev/null || export PATH=\"\$PYENV_ROOT/bin:\$PATH\"
eval \"\$(pyenv init --path)\"
eval \"\$(pyenv init -)\"
eval \"\$(pyenv virtualenv-init -)\"
""" >>~/.profile

  export PYENV_ROOT="$HOME/.pyenv"
  command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init --path)"
  eval "$(pyenv init -)"
  eval "$(pyenv virtualenv-init -)"

  fish -c "set -Ux PYENV_ROOT \$HOME/.pyenv"
  fish -c "fish_add_path \$PYENV_ROOT/bin"
  echo "pyenv init - | source" >> ~/.config/fish/config.fish

  pyenv update
fi

ver=$(python3 -c "import sys;t='{v[0]}{v[1]}'.format(v=list(sys.version_info[:2]));sys.stdout.write(t)")

if [[ "$ver" != "311" ]]; then
  pyenv install 3.11.2
fi

pyenv global 3.11.2

if ! command -v java &>/dev/null; then
  sudo apt install gnupg ca-certificates curl
  curl -s https://repos.azul.com/azul-repo.key | sudo gpg --dearmor -o /usr/share/keyrings/azul.gpg
  echo "deb [signed-by=/usr/share/keyrings/azul.gpg] https://repos.azul.com/zulu/deb stable main" | sudo tee /etc/apt/sources.list.d/zulu.list
  sudo apt update
  sudo apt install zulu17-jdk
fi

if ! command -v Rscript &>/dev/null; then
  # update indices
  sudo apt update -qq
  # install two helper packages we need
  # add the signing key (by Michael Rutter) for these repos
  # To verify key, run gpg --show-keys /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc
  # Fingerprint: E298A3A825C0D65DFD57CBB651716619E084DAB9
  wget -qO- https://cloud.r-project.org/bin/linux/ubuntu/marutter_pubkey.asc | sudo tee -a /etc/apt/trusted.gpg.d/cran_ubuntu_key.asc
  # add the R 4.0 repo from CRAN -- adjust 'focal' to 'groovy' or 'bionic' as needed
  sudo add-apt-repository "deb https://cloud.r-project.org/bin/linux/ubuntu $(lsb_release -cs)-cran40/"
  sudo apt install -y r-base
  sudo chmod 777 /usr/local/lib/R/site-library
fi

echo "Installing Python requirements..."
python3 -m pip install --upgrade pip setuptools wheel
python3 -m pip install -r requirements.txt
python3 -m pip install qc2tsv croo

echo "Installing R requirements..."
Rscript -e "install.packages(c('data.table', 'optparse'), repos = 'http://cran.us.r-project.org')"

if ! command -v docker &>/dev/null; then
  echo "Installing Docker"
  curl -fsSL https://get.docker.com -o get-docker.sh
  sudo sh get-docker.sh
  sudo getent group docker || sudo groupadd docker
  sudo usermod -aG docker "$USER"
  newgrp docker
fi

if [ ! -d "atac-seq-pipeline" ]; then
  echo "Cloning ENCODE ATAC-seq pipeline..."
  git clone --single-branch --branch v1.7.0 https://github.com/ENCODE-DCC/atac-seq-pipeline.git
  git apply patches/fix__add_missing_runtime_attributes_to_atac-seq_v1_7_0.patch
fi

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
cat <<EOF >"/opt/caper/default.conf"
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
DB_DIR=$HOME/.caper/db
INIT_DB_DIR=$HOME/.caper/init_db
mkdir -p "$DB_DIR" "$INIT_DB_DIR"
sudo chown -R "$USER" "$DB_DIR" "$INIT_DB_DIR"
sudo chmod 777 -R "$DB_DIR" "$INIT_DB_DIR"

INIT_SQL="""
CREATE USER 'cromwell'@'%' IDENTIFIED BY 'cromwell';
GRANT ALL PRIVILEGES ON cromwell.* TO 'cromwell'@'%' WITH GRANT OPTION;
"""
echo "${INIT_SQL}" >"$INIT_DB_DIR"/init_cromwell_user.sql

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

gcloud auth activate-service-account --key-file="$REMOTE_KEY_FILE"
export GOOGLE_APPLICATION_CREDENTIALS="$REMOTE_KEY_FILE"

echo "Downloading and setting up gcsfuse..."
wget -q https://github.com/GoogleCloudPlatform/gcsfuse/releases/download/v0.41.7/gcsfuse_0.41.7_amd64.deb
sudo dpkg -i gcsfuse_0.41.6_amd64.deb

echo "Downloading and setting up bedtools and samtools..."
wget -q https://github.com/arq5x/bedtools2/releases/download/v2.30.0/bedtools.static.binary -O bedtools
sudo mv bedtools /usr/local/bin
sudo chmod a+x /usr/local/bin/bedtools

wget -q https://github.com/samtools/samtools/releases/download/1.16.1/samtools-1.16.1.tar.bz2 -O samtools.tar.bz2

tar -xjf samtools.tar.bz2
cd samtools-1.16.1
./configure
make
sudo make install
cd ..
rm -rf samtools-1.16.1 samtools.tar.bz2

echo "Downloading and setting up bigWigToBedGraph..."
wget -q https://hgdownload.soe.ucsc.edu/admin/exe/linux.x86_64/bigWigToBedGraph -O bigWigToBedGraph
sudo mv bigWigToBedGraph /usr/local/bin
sudo chmod a+x /usr/local/bin/bigWigToBedGraph

echo "Finished"

curl https://raw.githubusercontent.com/oh-my-fish/oh-my-fish/master/bin/install | fish
