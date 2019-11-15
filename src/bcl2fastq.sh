set -e

#This script is best to run interactively to find where the problem is.

#Please note that SampleSheet.csv needs to have the adpater setting removed
#as we are going to use cutadapt to remove the adapter anyway.

bclfolder=$1
samplesheet=$2
outdir=$3

cd $outdir

mkdir -p bcl2fastq
cd bcl2fastq

# the following command DOES split sequencing by lane to get all demultiplexing stats

bcl2fastq --sample-sheet $samplesheet \
      --runfolder-dir $bclfolder \
      --output-dir .

# now merge lanes of the same sample together; rename to ${viallabel}_R?.fastq.gz

samples=$(sed -n '/^\[Data\]/,$p' $samplesheet |tail -n +3|cut -f 2 -d , | sed "s/ /\n/g" | sort | uniq)
cd ..
mkdir -p fastq_raw
cd fastq_raw
for SID in $samples; do
    fastq_folder=$(dirname $(find ../bcl2fastq -name "${SID}_S*_L00?_R1_001.fastq.gz" |head -1))
    cat  $fastq_folder/${SID}_S*_L00?_R1_001.fastq.gz > ${SID}_R1.fastq.gz
    cat  $fastq_folder/${SID}_S*_L00?_R2_001.fastq.gz > ${SID}_R2.fastq.gz
done

# add undetermined FASTQ files

for L in $(find ../bcl2fastq -name "Undetermined*L00${L}*R?*" | sed "s/.*L00//" | sed "s/_R.*//" | sort | uniq); do

  cp $(find ../bcl2fastq -name "Undetermined*L00${L}*R1*") Undetermined_L00${L}_R1.fastq.gz
  cp $(find ../bcl2fastq -name "Undetermined*L00${L}*R2*") Undetermined_L00${L}_R2.fastq.gz

done
