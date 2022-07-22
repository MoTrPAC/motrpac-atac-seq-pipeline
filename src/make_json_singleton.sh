#!/bin/bash

# Write JSON files for ENCODE ATAC pipeline input
# Assumes that reads are paired-end

set -e

json_base=$1
fastq_dir=$2
json_dir=$3

mkdir -p ${json_dir}

samples=$(ls $fastq_dir | grep "fastq.gz" | grep -v "Undetermined" | grep -E "R1|R2" | sed "s/_R.*//" | sort | uniq)
echo $samples

for i in $samples; do

    # name JSON file from FASTQ sample name 
    json_file=${json_dir}/${i}.json

    echo "{" > ${json_file}
    echo "    \"atac.description\" : \"${i}\"," >> ${json_file}

    # standard parameters for this project
    cat ${json_base} >> ${json_file}

    # add paths to FASTQ files 
    echo "    \"atac.fastqs_rep1_R1\" : [" >> ${json_file}
    
    lanes=$(ls ${fastq_dir} | grep "$i" | grep "R1" | wc -l)
    counter=1
    for r1 in $(ls ${fastq_dir} | grep "$i" | grep "R1"); do
        if [ "$counter" = "$lanes" ]; then
            echo "        \"${fastq_dir}/${r1}\"" >> ${json_file}
        else
            echo "        \"${fastq_dir}/${r1}\"," >> ${json_file}
        fi
        counter=$((counter +1))
    done
    echo "    ]," >> ${json_file}
    echo >> ${json_file}
    
    echo "    \"atac.fastqs_rep1_R2\" : [" >> ${json_file}

    counter=1
    for r2 in $(ls ${fastq_dir} | grep "$i" | grep "R2"); do
        if [ "$counter" = "$lanes" ]; then
            echo "        \"${fastq_dir}/${r2}\"" >> ${json_file}
        else
            echo "        \"${fastq_dir}/${r2}\"," >> ${json_file}
        fi
        counter=$((counter +1))
    done
    echo "    ]" >> ${json_file}
    echo >> ${json_file}

    echo "}" >> ${json_file}

done

