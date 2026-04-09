"""
Extract transcription start sites from an Ensembl GTF. Used to create the TSS reference file used in
~/ATAC_PIPELINE/atac-seq-pipeline/scripts/build_genome_data.sh

Usage:
    python tss_from_gtf.py <gtf_file> <tss_outfile>

Supports both compressed (.gz) and uncompressed GTF files.
Output will be gzipped if the output filename ends with .gz
"""
import gzip
import re
import sys


def open_file(filename, mode='r'):
    """Open file, handling gzip compression if filename ends with .gz"""
    if filename.endswith('.gz'):
        if 'b' not in mode:
            mode += 't'
        return gzip.open(filename, mode)
    else:
        return open(filename, mode)


def main():
    if len(sys.argv) != 3:
        print("Usage: python tss_from_gtf.py <gtf_file> <tss_outfile>", file=sys.stderr)
        print("Supports both compressed (.gz) and uncompressed GTF files.", file=sys.stderr)
        sys.exit(1)

    in_gtf = sys.argv[1]
    out_tss = sys.argv[2]

    # make TSS annotation file from GTF
    # Output format: chr1	69089	69090	ENSG00000186092.4	0	+
    # GTF format: chr1    HAVANA  gene    11869   14409   .       +       .       gene_id "ENSG00000223972.5";

    tss_count = 0
    with open_file(in_gtf, 'r') as gtf, open_file(out_tss, 'w') as out:
        for line in gtf:
            if line.startswith('#'):
                continue

            fields = line.strip().split('\t')

            if len(fields) < 9:
                continue

            if fields[2] != 'gene':
                continue

            strand = fields[6]

            if strand == '+':
                tss = fields[3]
            elif strand == '-':
                tss = fields[4]
            else:
                print(f'Warning: Strand not recognized for line: {line[:100]}...', file=sys.stderr)
                continue

            chrom = fields[0]

            # Parse all attributes into a dict to avoid assumptions about order or spacing
            attrs = {}
            for attr in fields[8].split(';'):
                attr = attr.strip()
                if not attr:
                    continue
                m = re.match(r'(\w+)\s+"([^"]+)"', attr)
                if m:
                    attrs[m.group(1)] = m.group(2)

            gene_id = attrs.get('gene_id')
            gene_type = attrs.get('gene_biotype')

            if not gene_id or gene_type != 'protein_coding':
                continue

            end = tss
            start = int(tss) - 1
            out.write('\t'.join([chrom, str(start), end, gene_id, '0', strand]) + '\n')
            tss_count += 1

    print(f"Extracted {tss_count} TSS entries from protein_coding genes")


if __name__ == '__main__':
    main()



