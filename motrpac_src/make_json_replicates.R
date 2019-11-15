#!/bin/R

library(data.table)

args <- commandArgs(trailingOnly=TRUE)
gitdir <- args[1]
base_json <- args[2]
dmaqc_meta <- args[3]
refs <- args[4]
fastq_dir <- args[5]
outdir <- args[6]

########################################################################################
## Get list of FASTQ files 
########################################################################################

fastq_list <- list.files(fastq_dir, pattern="fastq.gz")
fastq_list <- fastq_list[!grepl("Undetermined",fastq_list)]

########################################################################################
## Read in metadata; replace values with human-readable definitions from Data Dictionary
########################################################################################

meta <- fread(dmaqc_meta, sep=',', header=TRUE)
dict <- fread(sprintf('%s/motrpac_docs/meta_pass_data_dict.txt',gitdir), sep='\t', header=TRUE)

for (col in c('sacrificeTime', 'sex', 'sampleTypeCode', 'Protocol', 'intervention', 'siteName')){
  meta[, c(col) := dict[column==col,val][ match(meta[,get(col)], dict[column==col, key]) ] ]
}

meta <- meta[, lapply(.SD, as.character)]

########################################################################################
## Subset metadata by sequenced samples
########################################################################################

sample_names <- unique(gsub("_.*","",fastq_list)) # these should be named by vialLabel
ref_standard <- sample_names[!(sample_names %in% meta[,vialLabel])]
meta <- meta[vialLabel %in% sample_names]

########################################################################################
## Define replicates 
########################################################################################

uniq_comb <- unique(meta, by=c('sacrificeTime','sex','sampleTypeCode','Protocol','intervention'))
write_fastq_to_json <- function(replicate_num, replicate_name, read, out=outfile, fdir=fastq_dir, last=FALSE){
  
  fastq_files <- list.files(path=fdir, pattern=replicate_name, full.names=TRUE)
  
  read_file <- fastq_files[grep(paste0("_R",read),basename(fastq_files))]
  
  system(sprintf('echo "    \\"atac.fastqs_rep%s_R%s\\" : [" >> %s',replicate_num,read,out))
  
  if(length(read_file) == 1){
    system(sprintf('echo "        \\"%s\\"" >> %s',read_file,out))
  } else { # more than one lane
    for (i in 1:length(read_file)){
      if (i == length(read_file)){
        system(sprintf('echo "        \\"%s\\"" >> %s',read_file,out)) # if it's the last file, don't add a comma
      } else {
        system(sprintf('echo "        \\"%s\\"," >> %s',read_file,out))
      }
    }
  }
  
  if(last){ # don't add a comma if it's the last replicate
    system(sprintf('echo "    ]" >> %s', out))
  } else {
    system(sprintf('echo "    ]," >> %s', out))
  }
  system(sprintf('echo >> %s', out))
}

for (id in as.character(uniq_comb[,barcode])){

  sub <- uniq_comb[barcode==id,.(sampleTypeCode,Protocol,intervention,sex,sacrificeTime)]
  replicates <- unique(merge(sub, meta, by=c('sacrificeTime','sex','sampleTypeCode','Protocol','intervention'))[,vialLabel])
  
  # make a character string to describe replicates
  description <- gsub(' ','-',paste(unname(unlist(sub[1])), collapse='_'))
  
  # generate JSON file for each set of replicates
  outfile <- paste0(outdir, '/', description, '.json')
  system(sprintf('echo "{" > %s',outfile))
  system(sprintf('cat %s >> %s', base_json, outfile))
  
  # add description to JSON
  system(sprintf('echo "    \\"atac.description\\" : \\"%s\\"," >> %s', description, outfile))
  system(sprintf('echo >> %s',outfile))
  
  # fastq files for each replicate
  for (i in 1:length(replicates)){
    write_fastq_to_json(i, replicates[i], read=1)
    if (i == length(replicates)){
      write_fastq_to_json(i, replicates[i], read=2, last=TRUE)
    } else {
      write_fastq_to_json(i, replicates[i], read=2)
    }
  }

  system(sprintf('echo "}" >> %s',outfile))
  
}

# read in reference standard file 
ref_meta <- fread(refs, sep='\t', header=TRUE)
ref_meta <- ref_meta[,.(MTP_RefType, MTP_RefDescription, MTP_Ref2DBarcode, MTP_RefLabel)]

# generate JSON file for each reference standard
for (sample_name in ref_standard){

  # make a character string to describe replicates
  description <- gsub(' ','-',paste(unname(unlist(ref_meta[as.character(MTP_RefLabel)==sample_name, .(MTP_RefType, MTP_RefDescription)])), collapse='_'))
  description <- gsub(',', '', description)

  # generate JSON file for each set of replicates
  outfile <- paste0(outdir, '/', description, '.json')
  system(sprintf('cat %s > %s', base_json, outfile))
  
  # add description to JSON
  system(sprintf('echo "    \\"atac.title\\" : \\"%s\\"," >> %s', description, outfile))
  system(sprintf('echo >> %s',outfile))
  
  # fastq files for each replicate
  write_fastq_to_json(1, sample_name, read=1)
  write_fastq_to_json(1, sample_name, read=2, last=TRUE)
  
  system(sprintf('echo "}" >> %s',outfile))
}


