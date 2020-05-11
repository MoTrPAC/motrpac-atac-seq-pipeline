#!/bin/python3
# Author: Nicole Gay, Anna Scherbina
# Updated: 7 May 2020 
# Script: truncate_narrowpeak_200bp_summit.py 
# Purpose: For an input peak file (concatenated .narrowpeak.gz file), truncate each peak to 100bp on either side of the summit 

import gzip 
import argparse

def parse_args():
    parser=argparse.ArgumentParser("truncate a narrowPeak file to specified interval around summit")
    parser.add_argument("--infile")
    parser.add_argument("--summit_flank",type=int,default=100)
    parser.add_argument("--outfile")
    return parser.parse_args()

def main():
    args=parse_args()
    with gzip.open(args.infile, 'rt') as inpeak, gzip.open(args.outfile, 'wt') as outpeak:
        for line in inpeak:
            l = line.strip().split()
            chrom = l[0]
            startpos = int(l[1])
            summit_pos = startpos + int(l[9])
            adjusted_start = int(max(0, summit_pos-args.summit_flank))
            adjusted_end = int(summit_pos+args.summit_flank)
            outpeak.write('\t'.join([chrom, str(adjusted_start), str(adjusted_end)]) + '\n')


if __name__=="__main__":
    main()
