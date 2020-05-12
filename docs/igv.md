# View rn6 tracks in IGV
Since we are not using the UCSC rn6 genome, we unfortunately cannot load tracks with the UCSC Genome Browser. However, Broad's Integrative Genome Viewer is compatible with custom genomes.  

## Download IGV 
Download the desktop app: http://software.broadinstitute.org/software/igv/ 

## Build a custom genome in IGV 

### Download reference files  
All of the necessary files are available [here]. Download the following files and save them somewhere you will remember (all in the same folder).  
1. [FASTA file](http://mitra.stanford.edu/montgomery/projects/motrpac/atac/SCG/motrpac_references/rn6_release96/Rattus_norvegicus.Rnor_6.0.dna.toplevel.standardized.fa.gz) **- unzip after downloading**
2. [Cytoband file](http://mitra.stanford.edu/montgomery/projects/motrpac/atac/SCG/motrpac_references/rn6_release96/cytoband.txt) 
3. [Gene file](http://mitra.stanford.edu/montgomery/projects/motrpac/atac/SCG/motrpac_references/rn6_release96/Rattus_norvegicus.Rnor_6.0.96.standardized.gtf)

### Create custom genome file in IGV 
In IGV: `Genomes` > `Create .genome file…` > select the files you downloaded. 

This will generate a `.genome` file that you can save anywhere and easily reload to view the custom rat genome in IGV. (Genomes > Load from file)

## Format ENCODE ATAC-seq pipeline output files for viewing in IGV  
You probably want to look at two types of files in IGV: 
- Peak calls: `{condition}.overlap.optimal_peak.narrowPeak.gz`  
- MACS2 peak calling signal tracks (p-value): `{condition}.pooled.pval.signal.bigwig` or `{viallabel}.pval.signal.bigwig`  

In order to view the `narrowPeak` files in IGV, gunzip them and add a `.bed` suffix. The `bigwig` files will load into IGV as-is. You must either download these files locally (which is a hassle for large files) or save them on a server with web access, in which case you will load files by their URL. 
