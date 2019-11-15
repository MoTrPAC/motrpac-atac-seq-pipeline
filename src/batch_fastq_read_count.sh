#!/bin/bash

# get read counts in raw FASTQ files 

fastq_read_count=/path/to/fastq_read_count.sh
indir=/path/to/FASTQ

for prefix in `ls $indir | grep "_R1_001.fastq.gz"  | grep -v "Undetermined" | sed "s/_L00.*//" | uniq`; do

	bash ${fastq_read_count} ${indir} ${prefix} &

done
