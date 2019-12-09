# How to run atac-seq pipeline using caper
# Setup
### Prerequisites
1. Python3
2. pip3
3. caper 0.6.0
4. croo 0.2.1 , update to 0.3.1
5. [cromwell47] (https://github.com/broadinstitute/cromwell/releases/download/47/cromwell-47.jar)
6. [womtool47](https://github.com/broadinstitute/cromwell/releases/download/47/womtool-47.jar)
7. Docker
8. Java
9. qc2tsv (0.6.0)

Instructions on how to install some of these tools can be found [here](https://github.com/AshleyLab/motrpac-rna-seq-pipeline/blob/pipeline_test/vm_requirements.txt)

### Install latest caper (0.6.0)
```
pip3 install 'caper==0.6.0'
```

### Install qc2tsv
```
pip3 install qc2tsv
```

## run docker without sudo
You should be able to run docker without sudo , [source for fixing can be found in this link](https://techoverflow.net/2017/03/01/solving-docker-permissions)
## Add docker to group
```
sudo groupadd docker
sudo usermod -a -G docker $USER
```
shutdown and restart the instance after doing the above
```
docker run hello-world
```
Above command shold work successfully without any permission denied errors.

### Set up mysql db to store metadata on a persistent hard-disk
Run the below script everytime you kick off an instance. Running the below command to generate the mysql db in an NFS mount threw an error. It seemed to be fixed on rerunning it on the persistent hard-disk. [Solution](https://github.com/Illumina/hap.py/issues/48)

```
mkdir mysql_db_atac
run_mysql_server_docker.sh mysql_db_atac (worked)
```
If the above command complains that a container already exists , remove the container using the below commands and rerun `run_mysql_server_docker.sh`
The above command needs to run everytime you shutdown and restart a VM instance.

# list all the docker containers
```
docker container ls -a

```
# remove docker container
```
docker stop <CONTAINER ID>
docker rm <CONTAINER ID>
```
Make sure mysql db is running before instantiating caper server
```docker ps```

### Generate and configure ~/.caper/default.conf for gcp, add parameters for mysql backend
```
caper init gcp
```
### minimum configuration required to successfully run atac-seq pipeline using caper
```
cromwell=/home/araja7/tools/cromwell-47.jar
backend=gcp
gcp-prj=motrpac-portal
out-gcs-bucket=gs://rna-seq_araja/PASS/atac-seq/stanford/batch1/set1
tmp-gcs-bucket=gs://rna-seq_araja/PASS/atac-seq/stanford/batch1/caper_tmp
tmp-dir=/home/araja7/tmp_dir
db=mysql
mysql-db-ip=localhost
mysql-db-port=3306
mysql-db-user=cromwell
mysql-db-password=cromwell
java-heap-server=20G
## Cromwell server
ip=localhost
port=8000
```

#### Run caper server in a screen session and detach the screen (ctrl A + D)
```
screen -RD caper_server
caper server 2>caper.err 1>caper.out
```
To detach a screen
```
ctrl A + D
```
### Generate config files on a gcp vm , clone [Motrpac-atac-seq-repo](https://github.com/MoTrPAC/motrpac-atac-seq-pipeline.git)

```
sudo Rscript motrpac-atac-seq-pipeline/src/make_json_replicates.R -g ~/motrpac-atac-seq-pipeline -j ~/motrpac-atac-seq-pipeline/examples/base.json -m ~/motrpac-atac-seq-pipeline/metadata/ANI830_all.csv -r ~/motrpac-atac-seq-pipeline/metadata/Stanford_StandardReferenceMaterial.txt -f gs://motrpac-portal-transfer-stanford/atac-seq/rat/batch1_20191025/fastq_raw -o ~/motrpac-atac-seq-pipeline/config/stanford/batch1/ --gcp
```

### Submit workflows to caper server
```
caper submit atac.wdl -i input_json/stanford/batch1/set1/Rat-Gastrocnemius-Powder_phase1a_acute_male_0.5h.json

submitting in a loop
for i in input_json/stanford/batch1/set2/*.json;do caper submit atac.wdl -i $i ;done
```
### Consolidate outputs using croo, note croo takes only one metadata.json file at a time if you have multiples for loop through the list (right now croo overwrites outputs- to do fix this)
```
croo <metadata.json> --out-dir <gcp-bucket-output-path> --use-gsutil-over-aws-s3 --method copy
caper list|grep "Succeeded"|grep -v "subsampled_gcp"|cut -f1 >wfids.txt
for i in `cat wfids.txt`;do croo gs://rna-seq_araja/PASS/atac-seq/stanford/batch1/set1/atac/$i/metadata.json --out-dir gs://motrpac-portal-transfer-stanford/Output/atac-seq/batch1/ --use-gsutil-over-aws-s3 --method copy;done
```

###Copying output files without croo
```
gsutil -m cp -r gs://rna-seq_araja/PASS/atac-seq/stanford/batch1/set1/atac/* gs://motrpac-portal-transfer-stanford/Output/atac-seq/batch1/
```

### To Do

read qc2tsv


### Errors while instantiating caper server using mysql
1. If you encounter this error ```Caper] cmd:  ['java', '-Xmx20G', '-XX:ParallelGCThreads=1', '-DLOG_LEVEL=INFO', '-DLOG_MODE=standard', '-jar', '-Dconfig.file=/data/tmp/backend.conf', '/home/araja7/tools/cromwell-47.jar', 'server']
2019-11-08 20:40:28,428  INFO  - Running with database db.url = jdbc:mysql://localhost:3307/cromwell?allowPublicKeyRetrieval=true&useSSL=false&rewriteBatchedStatements=true&serverTimezone=UTC
2019-11-08 20:40:58,662  ERROR - Failed to instantiate Cromwell System. Shutting down Cromwell.```

do a `docker ps` and check for the port mysql is using.
```
araja7@ubuntu1904-nopreempt-rnaseq-8cpu-30gb-1:~/motrpac-rna-seq-pipeline$ docker ps
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                               NAMES
1b994e71d184        mysql:5.7           "docker-entrypoint.s…"   35 minutes ago      Up 34 minutes       0.0.0.0:3306->3306/tcp, 33060/tcp   mysql_cromwell
```
 
if it's different from the what is specified in ~/.caper/default.conf change ```mysql-db-port=3306``` to match the PORT listed by docker ps

## Restarting failed workflows
If an atac-workflow fails due to a resource issue (memory) , you can restart the failed job after increasing the resources for the appropriate task . For example `atac.macs2_signal_track_pooled`  task should not run for more than 7 hours for a 3.5 gb file if it does and the workflow failed at that step . Increase resources for `atac.macs2_signal_track_mem_mb` and submit the workflow like usual.
This would pick up from the cache and restart the workflow from the failed task.
By default all tasks in atac workflow except for `macs2_signal_track` and `align` tasks.  We run atac with premptible=0 by adding this inside the runtime block of every task just to make sure that premtible=0 is properly set.

## Debugging failed workflow
```
caper debug <workflow_id>
caper troubleshoot <workflow_id>
```

## Stop a workflow
```
caper abort <workflow_id>
```

## Workflow failure errors

1. Sometimes a workflow will fail with an error message `Status change from Running to Preempted` , this can be caused due to instance being preemptied for some unknown reasons. could be machine failure, out of memory, lack of disk space. This can be fixed by setting premptible=0 and increasing memory , hard-disk space and restarting the pipeline

## Making an optional default run-time attribute file
Make a json file called options.json and pass it to caper's -o parameter
```
{
  "default_runtime_attributes": {
    "preemptible": 0
  }
}
```




