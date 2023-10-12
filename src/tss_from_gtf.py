"""
Extract transcription start sites from an Ensembl GTF. Used to create the TSS reference file used in 
~/ATAC_PIPELINE/atac-seq-pipeline/scripts/build_genome_data.sh

Usage: 
    python tss_from_gtf.py <gtf.gz> <tss_outfile.gz>
"""
import gzip
import re
import sys

in_gtf = sys.argv[1]
out_tss = sys.argv[2]

# make TSS annotation file from GTF
# chr1	69089	69090	ENSG00000186092.4	0	+
# chr1    HAVANA  gene    11869   14409   .       +       .       gene_id "ENSG00000223972.5";

with gzip.open(in_gtf, 'rb') as gtf, gzip.open(out_tss, 'wb') as out:

	for line in gtf:

		if line.startswith('#'):
			continue

		l = line.strip().split('\t')

		if not l[2] == 'gene':
			continue

		strand = l[6]

		if strand == '+':
			tss = l[3]
		elif strand == '-':
			tss = l[4]
		else:
			print 'Strand not recognized'
			break

		chrom = l[0]

		gene_id = l[8].split(';')[0].split(' ')[1]
		gene_id = re.sub("\"", "", gene_id)

		gene_type = l[8].split(';')[2].split(' ')[1]
		if not gene_type == 'protein_coding':
			continue

		end = tss
		start = int(tss) - 1

		out.write('\t'.join([chrom, str(start), end, gene_id, '0', strand])+'\n')

