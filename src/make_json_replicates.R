#!/bin/R

library(data.table)
library(optparse)

option_list <- list(
  make_option(c("-g", "--gitdir"), help="Absolute path to motrpac-atac-seq-pipeline repository, e.g. '~/ATAC_PIPELINE/motrpac-atac-seq-pipeline'"),
  make_option(c("-j", "--json"), help="Global JSON parameters"),
  make_option(c("-m", "--dmaqc"), help="Absolute path to DMAQC metadata file, e.g. ANI830.csv"),
  make_option(c("-r", "--refstd"), help="Absolute path to Reference Standards in TXT format"),
  make_option(c("-f", "--fastq", help="Absolute path to directory with FASTQ files, named ${viallabel}_R?.fastq.gz")),
  make_option(c("-o", "--outdir", help="Absolute path to output directory for config files")),
  make_option("--gcp", default = FALSE, action = "store_true", help="--fastq points to a GCP bucket")
)

opt <- parse_args(OptionParser(option_list=option_list))

########################################################################################
## Get list of FASTQ files 
########################################################################################

if(opt$gcp){
  # read from bucket
  fastq_list <- system(sprintf('gsutil ls %s | grep "fastq.gz"',opt$fastq),intern=T)
}else{
  # read from directory 
  fastq_list <- list.files(path=opt$fastq, pattern="fastq.gz", full.names=T)
}
fastq_list <- fastq_list[!grepl("Undetermined",fastq_list)]

########################################################################################
## Read in metadata; replace values with human-readable definitions from Data Dictionary
########################################################################################

meta <- fread(opt$dmaqc, sep=',', header=TRUE)
dict <- fread(sprintf('%s/src/meta_pass_data_dict.txt',opt$gitdir), sep='\t', header=TRUE)

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
write_fastq_to_json <- function(replicate_num, replicate_name, read, out=outfile, flist=fastq_list, last=FALSE){
  
  fastq_files <- fastq_list[grepl(replicate_name, flist)]
  
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
  outfile <- paste0(opt$outdir, '/', description, '.json')
  system(sprintf('echo "{" > %s',outfile))
  system(sprintf('cat %s >> %s', opt$json, outfile))
  
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
ref_meta <- fread(opt$refstd, sep='\t', header=TRUE)
ref_meta <- ref_meta[,.(MTP_RefType, MTP_RefDescription, MTP_Ref2DBarcode, MTP_RefLabel)]

# generate JSON file for each reference standard
for (sample_name in ref_standard){
  
  # make a character string to describe replicates
  description <- gsub(' ','-',paste(unname(unlist(ref_meta[as.character(MTP_RefLabel)==sample_name, .(MTP_RefType, MTP_RefDescription)])), collapse='_'))
  description <- gsub(',', '', description)
  
  # generate JSON file for each set of replicates
  outfile <- paste0(opt$outdir, '/', description, '.json')
  system(sprintf('cat %s > %s', opt$json, outfile))
  
  # add description to JSON
  system(sprintf('echo "    \\"atac.title\\" : \\"%s\\"," >> %s', description, outfile))
  system(sprintf('echo >> %s',outfile))
  
  # fastq files for each replicate
  write_fastq_to_json(1, sample_name, read=1)
  write_fastq_to_json(1, sample_name, read=2, last=TRUE)
  
  system(sprintf('echo "}" >> %s',outfile))
}
