## Prepare config files for samples with biological replicates

PASS data must be processed with replicates together.

A configuration (config) file is a file in JSON format that specifies input parameters required to run the ATAC-seq pipeline. Find comprehensive documentation of definable parameters [here](https://github.com/ENCODE-DCC/atac-seq-pipeline/blob/master/docs/input.md).  

This tutorial walks you through the steps to quickly generate config files for a large number of samples with the same runtime parameters (e.g. memory requirements, reference genome).  

**Prerequisites:**
* R 
* R `data.table` package  

You will need a few things for this tutorial:  
1. `gitdir`: The absolute path to this repository, e.g. `~/ATAC_PIPELINE/motrpac-atac-seq-pipeline` 
2. `base_json`: A trucated JSON file with paramaters that are constant for all samples in this batch. Find an example [here](../examples/base.json). `/path/to/genome.tsv` refers to the path to either `"motrpac_rn6.tsv"` or `"hg38.tsv"` file generated in **Step 3**. Note that you must include the following parameters for consistency within MoTrPAC:
```
    "atac.genome_tsv" : "/path/to/genome.tsv",
    "atac.multimapping" : 4,
    "atac.auto_detect_adapter" : true,
    "atac.enable_idr" : true,
    "atac.enable_tss_enrich" : true,
    "atac.paired_end" : true,
```
3. `dmaqc_meta`: A copy of the DMAQC metadata corresponding to the samples in this batch (e.g. `ANI830-10009.csv`). Each CAS site has a batching officer who is able to retrieve this metadata from the web API. Note that you may have to concatenate multiple DMAQC metadata files into a single file if you are generating config files for a NovaSeq run where the sequenced samples were received in multiple tranches.  
4. `ref_standards`: A copy of the Reference Standards metadata from Russ, converted from an Excel file to a TXT file (e.g. `Stanford_StandardReferenceMaterial_0129191.txt`). Note that you may have to concatenate multiple Reference Standard metadata files into a single file if you are generating config files for a NovaSeq run where the sequenced samples were received in multiple tranches.  
5. `fastq_dir`: The path to the FASTQ files for all samples in this batch. Note that FASTQ files should be named by vial label, e.g. `90013015505_R1.fastq.gz`.  
6. `config_dir`: The path to the desired output directory for the generated config files.  

When you have the absolute file paths to all of the files mentioned above, run the following command:
```bash
$ Rscript src/make_json_replicates.R  ${gitdir} ${base_json} ${dmaqc_meta} ${ref_standards} \
                                                                        ${fastq_dir} ${config_dir} 
```

The result will be a single JSON-formatted config file in `${config_dir}` for every tissue, sex, timepoint, intervention/exercise protocol combination of the samples included in `${fastq_dir}`. Each file will be named `${sampleTypeCode}_${Protocol}_${intervention}_${sex}_${sacrificeTime}` according to the corresponding DMAQC metadata. Click [here](../examples/rat_with_replicates_example.json) to see an example of what these config files should look like.  
