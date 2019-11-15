## Prepare config files for single samples

MoTrPAC human samples must be run as singletons. 

A configuration (config) file is a file in JSON format that specifies input parameters required to run the ATAC-seq pipeline. Find comprehensive documentation of definable parameters [here](https://github.com/ENCODE-DCC/atac-seq-pipeline/blob/master/docs/input.md).  

This tutorial walks you through the steps to quickly generate config files for a large number of samples with the same runtime parameters (e.g. memory requirements, reference genome).  

You will need to define a few paths first: 
1. `base_json`: A trucated JSON file with paramaters that are constant for all samples in this batch. Find an example [here](examples/base.json). `/path/to/genome.tsv` refers to the path to either `"motrpac_rn6.tsv"` or `"motrpac_hg38.tsv"` file generated in **Step 3**. Note that you **must** include the following parameters for consistency within MoTrPAC:
```
    "atac.genome_tsv" : "/path/to/genome.tsv",
    "atac.paired_end" : true,
    "atac.multimapping" : 4,
    "atac.auto_detect_adapter" : true,
    "atac.enable_idr" : true,
    "atac.paired_end" : true,
```
2. `fastq_dir`: The path to the FASTQ files for all samples in this batch. Note that FASTQ files should be named by vial label, e.g. `90013015505_R1.fastq.gz`.  
3. `config_dir`: The path to the desired output directory for the generated config files. 

After you have defined the full paths in the variables described above, run the following command:
```bash
$ bash src/make_json_singleton.sh ${base_json} ${fastq_dir} ${config_dir} 
```

The result will be a single JSON-formatted config file in `${config_dir}` for each sample included in `${fastq_dir}`. Click [here](../examples/singleton_example.json) to see an example of what these config files should look like.  
