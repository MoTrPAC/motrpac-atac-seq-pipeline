# MoTrPAC ATAC-Seq QC and Analysis Pipeline 

This repository provides MoTrPAC-specific supplements to the [ENCODE ATAC-seq pipeline](https://github.com/ENCODE-DCC/atac-seq-pipeline). For additional details not directly related to running the ENCODE ATAC-seq pipeline or processing the results, see the most recent version of the MoTrPAC ATAC-seq QC and Analysis Pipeline MOP, available [here](https://docs.google.com/document/d/1vnB7ITAKnaZYc3v_FCdaDu3z-JXeDncRk5GnqzQVwRw/edit#heading=h.tjbixx8yyd33). 

This documentation is intended to help individuals who are preparing ATAC-seq data for submission to the BIC or processing pilot samples with the full pipeline. For simplicity, this documentation explains how to run the full pipeline on a computer compatible with Conda environments. Users working on the cloud or in other environments can follow ENCODE's documentation as necessary. Post-processing scripts are intended to be useful to all users, regardless of environment. 

### Important references:
- GitHub repository for the ENCODE ATAC-seq pipeline: https://github.com/ENCODE-DCC/atac-seq-pipeline
- ENCODE ATAC-seq pipeline documentation: https://www.encodeproject.org/atac-seq/
- ENCODE data quality standards: https://www.encodeproject.org/atac-seq/#standards 
- ENCODE terms and definitions: https://www.encodeproject.org/data-standards/terms/

### Table of Contents:

1. [Prepare ATAC-seq data for submission to the BIC](#1-prepare-atac-seq-data-for-submission-to-the-bic) 

    1.1 Clone this repository
    
    1.2 Generate and format FASTQs 
    
    1.3 Collect additional documents  
    
    1.4 Submit data  
    
2. [Install and test ENCODE ATAC-seq pipeline and dependencies](#2-install-and-test-encode-atac-seq-pipeline-and-dependencies)    
    
    2.1 Clone the ENCODE repository

    2.2 Install the `Conda` environment with all software dependencies

    2.3 Initialize `Caper`

    2.4 Run a test sample 
   
    2.5 [Install genome databases](#25-install-genome-databases)
    
      2.5.1 Install the hg38 genome database
    
      2.5.2 Install the custom rn6 genome database 

3. [Run the ENCODE ATAC-seq pipeline](#3-run-the-encode-atac-seq-pipeline)
    
    3.1 Generate configuration files  
    
    3.2 Run the pipeline
    
4. [Organize outputs](#4-organize-outputs)

    4.1 Collect important outputs with `Croo`
    
    4.2 Generate a spreadsheet of QC metrics for all samples with `qc2tsv`

5. [Flag problematic samples](#5-flag-problematic-samples)


## 1. Prepare ATAC-seq data for submission to the BIC 

### 1.1 Clone this repository 
This documentation will assume you clone it in a folder called `ATAC_PIPELINE` in your home directory. `~/ATAC_PIPELINE` is also the recommended destination folder for when you clone ENCODE's repository later. 
```bash
cd ~
mkdir ATAC_PIPELINE
cd ATAC_PIPELINE
git clone https://github.com/nicolerg/motrpac-atac-seq-pipeline.git
```

### 1.2 Generate and format FASTQs 
Each GET site (Stanford and MSSM) is responsible for sequencing the library and obtaining the demultiplexed FASTQ files for each sample. If sequencing is performed with NovaSeq, raw data is output as BCL files, which must be demultiplexed and converted to FASTQ files with `bcl2fastq` (version 2.20.0). `bcl2fastq v2.20.0` can be downloaded directly from Illumina [here](https://support.illumina.com/downloads/bcl2fastq-conversion-software-v2-20.html). 

Prepare a sample sheet for demultiplexing. Find an example [here](examples/SampleSheet.csv).  
- The sample sheet must not include the `Adapter` or `AdapterRead2` settings. This will prevent `bcl2fastq` from automatically performing adapter trimming, which provides us with FASTQ files that include the fullest form of the raw data. Adapter trimming is performed downstream
- `Sample_Name` and `Sample_ID` should correspond to vial labels; FASTQ files must follow the naming convention `${viallabel}_R?.fastq.gz` before submission to the BIC

[src/bcl2fastq.sh](src/bcl2fastq.sh) provides code both to run `bcl2fastq` and rename files. It can be run as follows:  
1. Define the following paths:
  - `bclfolder`: Path to sequencing output directory, e.g `181205_NB551514_0071_AHFHLGAFXY`
  - `samplesheet`: Path to the sample sheet, e.g. `${bclfolder}/SampleSheet.csv`
  - `outdir`: Path to root output folder, e.g. `/lab/data/NOVASEQ_BATCH1`
2. If applicable, load the correct version of `bcl2fastq`. For example, on Stanford SCG, run `module load bcl2fastq2/2.20.0.422`.  
3. Run [src/bcl2fastq.sh](src/bcl2fastq.sh):
```
bash ~/ATAC_PIPELINE/motrpac-atac-seq-pipeline/src/bcl2fastq.sh ${bclfolder} ${samplesheet} ${outdir}
```
This makes two new directories:  
1. `${outdir}/bcl2fastq`: Outputs of `bcl2fastq`  
2. `${outdir}/fastq_raw`: Merged and re-named FASTQ files, ready for submission to the BIC  

Alternatively, run the `bcl2fastq` command independently, and use your own scripts to merge and rename FASTQ files before submission to the BIC:
```bash
bcl2fastq \   
     --sample-sheet /path/to/SampleSheet.csv
     --runfolder-dir $seqDir \
     --output-dir $outDir 
```
This command will generate two FASTQ files (one for each read in the pair) per sample per lane, e.g. `${viallabel}_L${lane}_R{1,2}_001.fastq.gz`.  

### 1.3 Collect additional documents  
- Collect the laneBarcode HTML report in `${outdir}/bcl2fastq/Reports/html/*/all/all/all/laneBarcode.html`. This report must be included in the BIC data submission,
- Generate `sample_metadata_YYYYMMDD.csv`. See [this table](https://docs.google.com/document/d/1vnB7ITAKnaZYc3v_FCdaDu3z-JXeDncRk5GnqzQVwRw/edit#heading=h.sqhy9p63uf9b) for a list of metrics that must be included in this file. 
- Generate `file_manifest_YYYYMMDD.csv`. See the [GET CAS-to-BIC Data Transfer Guidelines](https://docs.google.com/document/d/1W1b5PVp2yjam4FU2IidGagqdA7lYpkTaD_LMeaN_n_k) for details about the format of this document. 
    
### 1.4 Submit data  
Refer to the [GET CAS-to-BIC Data Transfer Guidelines](https://docs.google.com/document/d/1W1b5PVp2yjam4FU2IidGagqdA7lYpkTaD_LMeaN_n_k) for details about the directory structure for ATAC-seq data submissions. The following files are required:
- `file_manifest_YYYYMMDD.csv`
- `sample_metadata_YYYYMMDD.csv`
- `readme_YYYYMMDD.txt`
- `laneBarcode.html`
- `fastq_raw/*.fastq.gz`

## 2. Install and test ENCODE ATAC-seq pipeline and dependencies
All steps in this section must only be performed once. After dependencies are installed and genome databases are built, skip to [here](#3-run-the-encode-atac-seq-pipeline).

The ENCODE pipeline supports many cloud platforms and cluster engines. It also supports `docker`, `singularity`, and `Conda` to resolve complicated software dependencies for the pipeline. There are special instructions for two major Stanford HPC servers (SCG4 and Sherlock).  

While the BIC runs this pipeline on Google Cloud Platform, this documentation is tailored for consortium users who use non-cloud computing environments, including clusters and personal computers. Therefore, this documentation describes the `Conda` implementation. Refer to ENCODE's documentation for alternatives. 

### 2.1 Clone the ENCODE repository
Clone the v1.5.3 ENCODE repository and this repository in a folder in your home directory:
```bash
cd ~/ATAC_PIPELINE
git clone --single-branch --branch v1.5.3 https://github.com/ENCODE-DCC/atac-seq-pipeline.git
```

### 2.2 Install the `Conda` environment with all software dependencies
1. If `Conda` is not already installed on your system, follow [these instructions](https://github.com/ENCODE-DCC/atac-seq-pipeline/blob/master/docs/install_conda.md). Skip this step if `Conda` is already available. For example, Stanford SCG users should replace this step with `module load miniconda/3`.  
2. Start a `screen` session. 
3. Uninstall and install the ENCODE ATAC-seq `Conda` environment:
```bash
bash ~/ATAC_PIPELINE/atac-seq-pipeline/scripts/uninstall_conda_env.sh
bash ~/ATAC_PIPELINE/atac-seq-pipeline/scripts/install_conda_env.sh
```

### 2.3 Initialize `Caper`
Installing the `Conda` environment also installs `Caper`. Make sure it works:
```bash
# load/activate conda or miniconda module, if necessary
conda activate encode-atac-seq-pipeline
caper
```
If you see an error like `caper: command not found`, then add the following line to the bottom of ~/.bashrc and re-login.
```
export PATH=$PATH:~/.local/bin
```

Choose a platform from the following table and initialize `Caper`. This will create a default `Caper` configuration file `~/.caper/default.conf`, which have only required parameters for each platform. There are special platforms for Stanford Sherlock/SCG users.
```bash
$ caper init [PLATFORM]
```

**Platform**|**Description**
:--------|:-----
sherlock | Stanford Sherlock cluster (SLURM)
scg | Stanford SCG cluster (SLURM)
gcp | Google Cloud Platform
aws | Amazon Web Service
local | General local computer
sge | HPC with Sun GridEngine cluster engine
pbs | HPC with PBS cluster engine
slurm | HPC with SLURM cluster engine

Edit `~/.caper/default.conf` according to your chosen platform. Find instruction for each item in the following table.
> **IMPORTANT**: ONCE YOU HAVE INITIALIZED THE CONFIGURATION FILE `~/.caper/default.conf` WITH YOUR CHOSEN PLATFORM, THEN IT WILL HAVE ONLY REQUIRED PARAMETERS FOR THE CHOSEN PLATFORM. DO NOT LEAVE ANY PARAMETERS UNDEFINED OR CAPER WILL NOT WORK CORRECTLY.

**Parameter**|**Description**
:--------|:-----
tmp-dir | **IMPORTANT**: A directory to store all cached files for inter-storage file transfer. DO NOT USE `/tmp`.
slurm-partition | SLURM partition. Define only if required by a cluster. You must define it for Stanford Sherlock.
slurm-account | SLURM partition. Define only if required by a cluster. You must define it for Stanford SCG.
sge-pe | Parallel environment of SGE. Find one with `$ qconf -spl` or ask you admin to add one if not exists.
aws-batch-arn | ARN for AWS Batch.
aws-region | AWS region (e.g. us-west-1)
out-s3-bucket | Output bucket path for AWS. This should start with `s3://`.
gcp-prj | Google Cloud Platform Project
out-gcs-bucket | Output bucket path for Google Cloud Platform. This should start with `gs://`.

### 2.4 Run a test sample 
Follow [these platform-specific instructions](https://github.com/ENCODE-DCC/caper/blob/master/README.md#activating-conda-environment) to run a test sample. Use the following variable assignments:
```bash
PIPELINE_CONDA_ENV=encode-atac-seq-pipeline
WDL=~/ATAC_PIPELINE/atac-seq-pipeline/atac.wdl
INPUT_JSON=https://storage.googleapis.com/encode-pipeline-test-samples/encode-atac-seq-pipeline/ENCSR356KRQ_subsampled_caper.json
```

### 2.5 Install genome databases
    
#### 2.5.1 Install the hg38 genome database
Specify a destination directory and install the ENCODE hg38 reference with the following command. We recommend not to run this installer on a login node of your cluster. It will take >8GB memory and >2h time.   
```bash  
outdir=/path/to/reference/genome/hg38
bash ~/ATAC_PIPELINE/atac-seq-pipeline/scripts/download_genome_data.s hg38 ${outdir}  
```
    
#### 2.5.2 Install the custom rn6 genome database 

Find this section in `~/ATAC_PIPELINE/atac-seq-pipeline/scripts/build_genome_data.sh`:
```
...

elif [[ "${GENOME}" == "YOUR_OWN_GENOME" ]]; then
  # Perl style regular expression to keep regular chromosomes only.
  # this reg-ex will be applied to peaks after blacklist filtering (b-filt) with "grep -P".
  # so that b-filt peak file (.bfilt.*Peak.gz) will only have chromosomes matching with this pattern
  # this reg-ex will work even without a blacklist.
  # you will still be able to find a .bfilt. peak file
  REGEX_BFILT_PEAK_CHR_NAME="chr[\dXY]+"
  # mitochondrial chromosome name (e.g. chrM, MT)
  MITO_CHR_NAME="chrM"
  # URL for your reference FASTA (fasta, fasta.gz, fa, fa.gz, 2bit)
  REF_FA="https://some.where.com/your.genome.fa.gz"
  # 3-col blacklist BED file to filter out overlapping peaks from b-filt peak file (.bfilt.*Peak.gz file).
  # leave it empty if you don't have one
  BLACKLIST=
fi
...
```
Above it, add this block:
```
elif [[ "${GENOME}" == "motrpac_rn6" ]]; then
  REGEX_BFILT_PEAK_CHR_NAME="chr[\dXY]+"
  MITO_CHR_NAME="chrM"
  REF_FA="http://mitra.stanford.edu/montgomery/projects/motrpac/atac/SCG/motrpac_references/rn6_release96/Rattus_norvegicus.Rnor_6.0.dna.toplevel.standardized.fa.gz"
  TSS="http://mitra.stanford.edu/montgomery/projects/motrpac/atac/SCG/motrpac_references/rn6_release96/Rattus_norvegicus.Rnor_6.0.96_protein_coding.tss.bed.gz"
```

Specify a destination directory and install the MoTrPAC rn6 reference with the following command. We recommend not to run this installer on a login node of your cluster. It will take >8GB memory and >2h time. 
```bash
outdir=/path/to/reference/genome/motrpac_rn6
bash ~/ATAC_PIPELINE/atac-seq-pipeline/scripts/build_genome_data.sh motrpac_rn6 ${outdir}
```
    
## 3. Run the ENCODE ATAC-seq pipeline  
MoTrPAC will run the ENCODE pipeline both with singletons for human samples and replicates for rat samples. In both cases, many iterations of the pipeline will need to be run for each batch of sequencing data. This repository provides scripts to automate this process, for both rat and human samples. 

Running the pipeline with replicates outputs all of the same per-sample information generated by running the pipeline with a single sample but improves power for peak calling and outputs a higher-confidence peak set called using all replicates. This generates a single peak set for every exercise protocol/timepoint/tissue/sex combination in the PASS study, which will be useful for downstream analyses.  

### 3.1 Generate configuration files
A configuration (config) file in JSON format that specifies input parameters is required to run the pipeline. Find comprehensive documentation of definable parameters [here](https://github.com/ENCODE-DCC/atac-seq-pipeline/blob/master/docs/input.md).  

Please click the appropriate link below for detailed instructions on how to automate the generation of config files for pipelines with singletons or replicates. This is particularly important for PASS data, as this repository provides a script to automatically group replicates in the same condition (protocol/timepoint/tissue/sex). 

* [Prepare config files for replicates (PASS/rat)](docs/replicate_config.md)
* [Prepare config files for singletons (CASS/human)](docs/single_config.md) 

### 3.2 Run the pipeline 
Actually running the pipeline is straightforward. However, the command is different depending on the environment in which you set up the pipeline. Refer back to environment-specific instructions [here](https://github.com/ENCODE-DCC/caper/blob/master/README.md#activating-conda-environment).

An `atac` directory containing all of the pipeline outputs is created in the output directory (note the default output directory is the current working directory). One arbitrarily-named subdirectory for each config file (assuming the command is run in a loop for several samples) is written in `atac`.  

Here is an example of code that submits a batch of pipelines to the Stanford SCG job queue:
```bash
module load miniconda/3
conda activate encode-atac-seq-pipeline

ATACSRC=~/ATAC_PIPELINE/atac-seq-pipeline
OUTDIR=/path/to/output/directory
cd ${OUTDIR}

# JSON_DIR is the path to all of the config files, generated in Step 4.1

for json in $(ls ${JSON_DIR}); do 
  
  INPUT_JSON=${JSON_DIR}/${json}
  JOB_NAME=$(basename ${INPUT_JSON} | sed "s/\.json.*//")

  sbatch -A ${ACCOUNT} -J ${JOB_NAME} --export=ALL --mem 2G -t 4-0 --wrap "caper run ${ATACSRC}/atac.wdl -i ${INPUT_JSON}"
  sleep 30
done
```
Note that for v1.5.3, the `sleep 30` command in between pipeline initializations is required to avoid an error. Run this in a screen session if you are initiating many pipelines in parallel.  

## 4. Organize outputs

### 4.1 Collect important outputs with `Croo`
`Croo` is a tool ENCODE developed to simplify the pipeline outputs. It was installed along with the `Conda` environment. Run it on each sample in the batch. See **Table 4.1** for a description of outputs generated by this process. 
```
module load miniconda/3
conda activate encode-atac-seq-pipeline

cd ${OUTDIR}/atac
for dir in *; do 
  cd $dir
  croo metadata.json 
  cd ..
done
```
    
**Table 4.1.** Important files in `Croo`-organized ENCODE ATAC-seq pipeline output.  

| Subdirectory or file                      | Description                             |
|-------------------------------------------|-----------------------------------------|
| `qc/qc.json` | JSON of important QC metrics. Useful for making spreadsheets of QC metrics for multiple samples |
| `qc/qc.html` | HTML report of important QC metrics. Includes QC metrics in `qc/qc.json` in addition to some plots |
| `signal/*/*fc.signal.bigwig` | MACS2 peak-calling signal (fold-change), useful for visualizing "read pileups" in a genome browser |
| `signal/*/*pval.signal.bigwig` | MACS2 peak-calling signal (P-value), useful for visualizing "read pileups" in a genome browser. P-value track is more dramatic than the fold-change track |
| `align/*/*.trim.merged.bam` | Unfiltered BAM files |
| `align/*/*.trim.merged.nodup.no_chrM_MT.bam` | Filtered BAM files, used as input for peak calling |
| `align/*/*.tagAlign.gz` | [tagAlign](https://genome.ucsc.edu/FAQ/FAQformat.html#format15) files from filtered BAMs |
| `peak/overlap_reproducibility/ overlap.optimal_peak.narrowPeak.hammock.gz` | Hammock file of `overlap` peaks, optimized for viewing peaks in a genome browser |
| `peak/overlap_reproducibility/ overlap.optimal_peak.narrowPeak.gz` | BED file of `overlap` peaks. **Generally, use this as your final peak set** |
| `peak/overlap_reproducibility/ overlap.optimal_peak.narrowPeak.bb` | [bigBed](https://genome.ucsc.edu/goldenPath/help/bigBed.html) file of `overlap` peaks  useful for visualizing peaks in a genome browser |
| `peak/idr.optimal_peak.narrowPeak.gz` | `IDR` peaks. More conservative than `overlap` peaks |

[ENCODE recommends](https://www.encodeproject.org/atac-seq/) using the `overlap` peak sets when one prefers a low false negative rate but potentially higher false positives; they recommend using the `IDR` peaks when one prefers low false positive rates.
    
### 4.2 Generate a spreadsheet of QC metrics for all samples with `qc2tsv`
This is most useful if you ran the pipeline for multiple samples. **Step 4.1** generates a `qc/qc.json` file for each pipeline run. After installing `qc2tsv` (`pip install qc2tsv`), run the following command to compile a spreadsheet with QC from all samples: 
```
cd ${outdir}/atac
qc2tsv $(find -path "*/qc/qc.json") --collapse-header > spreadsheet.tsv
```

**Table 4.2** provides definitions for a limited number of metrics included in the JSON QC reports. The full JSON report includes >100 metrics per sample; some lines are duplicates, and many metrics are irrelevant for running the pipeline with a single biological replicate. 

**Table 4.2. Description of relevant QC metrics.**

| Header:subheader | Metric | Definition/Notes |
|--------|--------|------------------|
| align:samstat | total_reads | Total number of alignments* (including multimappers)|
| align:samstat | pct_mapped_reads | Percent of reads that mapped|
| align:samstat| pct_properly_paired_reads |Percent of reads that are properly paired|
| align:dup | pct_duplicate_reads |Fraction (not percent) of read pairs that are duplicates **after** filtering alignments for quality|
| align:frac_mito | frac_mito_reads | Fraction of reads that align to chrM **after** filtering alignments for quality and removing duplicates | 
| align:nodup_samstat | total_reads | Number of alignments* after applying all filters |
| align:frag_len_stat | frac_reads_in_nfr | Fraction of reads in nucleosome-free-region. Should be a value between {} and {} |
| align:frag_len_stat | nfr_over_mono_nuc_reads | Reads in nucleosome-free-region versus reads in mononucleosomal peak. Should be a value greater than 2.5 |
| align:frag_len_stat | nfr_peak_exists | Does a nucleosome-free-peak exist? Should be `true` |
| align:frag_len_stat | mono_nuc_peak_exists | Does a mononucleosomal-peak exist? Should be `true` |
| align:frag_len_stat | di_nuc_peak_exists | Does a dinucleosomal-peak exist? Ideally `true`, but not condemnable if `false` |
| lib_complexity | NRF | Non-reduandant fraction. Measure of library complexity, i.e. degree of duplicates. Ideally >0.9 |
| lib_complexity | PBC1 | PCR bottlenecking coefficient 1. Measure of library complexity. Ideally >0.9 |
| lib_complexity | PBC2 | PCR bottlenecking coefficient 2. Measure of library complexity. Ideally >3 |
| replication:reproducibility:overlap | N_opt | Number of `overlap` peaks |
| replication:reproducibility:idr | N_opt | Number of `IDR` peaks |
| peak_enrich:frac_reads_in_peaks:overlap | * | Fraction of reads in `overlap` peaks | 
| peak_enrich:frac_reads_in_peaks:idr | * | Fraction of reads in `IDR` peaks |
| align_enrich:tss_enrich | tss_enrich | TSS enrichment |

*Note: Alignments are per read, so for PE reads, there are two alignments per fragment if each PE read aligns once. 

## 5. Flag problematic samples   
The following metrics are not strictly exclusion criteria for MoTrPAC samples, but samples should be flagged if any of these conditions are met. Some of these metrics reflect the [ENCODE ATAC-seq data standards](https://www.encodeproject.org/atac-seq/#standards). 

**Table 5.1 Criteria to flag problematic samples.**

| Description | In terms of Table 2 metrics | Comments |
|-------------|-------------------------------|----------|
|< 50 million filtered, non-duplicated, non-mitochondrial paired-end reads in the filtered BAM file (i.e. 25M pairs)| align:nodup_samstat:total_reads < 50M | This is the most stringent criterion and may be relaxed |
|Alignment rate < 80%| align:samstat:pct_mapped_reads < 80%||
|Fraction of reads in `overlap` peaks < 0.1|peak_enrich:frac_reads_in_peaks:overlap:{max} < 0.1|This is more relaxed than the ENCODE recommendation|
|Number of peaks in `overlap` peak set < 80,000|replication:reproducibility:overlap:N_opt < 80000|This is more relaxed than the ENCODE recommendation|
|A nucleosome-free region is not present| align:frag_len_stat:nfr_peak_exists == false|This should be enforced more strictly|
|A mononucleosome peak is not present|align:frag_len_stat:mono_nuc_peak_exists == false|This should be enforced more strictly|
|TSS enrichment < ?|align_enrich:tss_enrich|This cutoff needs to be evaluated retrospectively |
