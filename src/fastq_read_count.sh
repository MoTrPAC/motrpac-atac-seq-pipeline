#!/bin/bash

# get read counts for FASTQ files

indir=$1
prefix=$2

total=0
for file in `ls ${indir} | grep "$prefix" | grep -E "_R1_|_R2_"`; do 
	count=`zcat ${indir}/${file} | wc -l`
	tmp=$((total + count))
	total=${tmp}
done
y=4
count=$((total / y))
echo $prefix $count
