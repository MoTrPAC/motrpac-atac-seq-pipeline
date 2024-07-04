#!/bin/R
# Nicole Gay
# 15 May 2020 
# Fix and merge ATAC-seq QC 

#Usage : Rscript src/merge_atac_qc.R -w ~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final/sample_metadata_20200928.csv -q ~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final/qc/atac_qc.tsv -m ~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final/rep_to_sample_map.csv -a ~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final/merged_chr_info.csv -o ~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final/

library(data.table)
library(optparse)
library(dplyr)
option_list <- list(
  make_option(c("-w", "--sample_meta"), help = "Absolute path to wetlab sample metadata file, e.g. sample_metadata_YYYYMMDD.csv"),
  make_option(c("-q", "--atac_qc"), help = "Absolute path to pipeline qc metrics file output of qc2tsv tool, e.g. atac_qc.tsv"),
  make_option(c("-m", "--sample_mapping_file"), help="Absolute path to replicate to sample mapping file, e.g. rep_to_sample_map.csv"),
  make_option(c("-a", "--align_stats"), help = "Absolute path to genome alignment stats file, e.g. merged_chr_info.csv"),
  make_option(c("-o", "--outdir", help = "Absolute path to output directory for the merged qc reports"))

)

opt_parse_inst <- OptionParser(option_list = option_list)

opt <- parse_args(opt_parse_inst)

if (is.null(opt$sample_meta) |
  is.null(opt$atac_qc) |
  is.null(opt$sample_mapping_file) |
  is.null(opt$align_stats) |
  is.null(opt$outdir)) {
  message("\033[31mERROR! Please provide all required arguments")
  message("\033[34mExample: Rscript src/merge_atac_qc.R -w <sample_metadata_YYYYMMDD.csv> -q <atac_qc.tsv> -m <rep_to_sample_map.csv> -a <merged_chr_info.csv> -o <output_directory>")
  print_help(opt_parse_inst)
  quit("no")
}

wet <- fread(opt$sample_meta, sep = ',', header = TRUE)
wet <- unique(wet) # remove duplicate rows
encode <- fread(opt$atac_qc, sep = '\t', header = T)
rep_to_sample_map = fread(opt$sample_mapping_file, sep=',', header=F)
align_stat <- fread(opt$align_stats, sep = ',', header = T)

###################################################################################
## fix ENCODE QC
###################################################################################

# fix other "general" cols
cols <- colnames(encode)[grepl('general', colnames(encode))]
cols <- cols[cols != 'general.description']
for (col in cols) {
  #print(col)
  t1 <- encode[1, get(col)]
  for (i in seq_len(nrow(encode))) {
    if (as.character(encode[i, get(col)]) == '') {
      encode[i, (col) := t1]
    } else {
      t1 <- encode[i, get(col)]
    }
  }
}
# separate workflow-level and sample-level QC
workflow_level <- colnames(encode)[unlist(encode[, lapply(.SD, function(x) any(is.na(x) | as.character(x) == ''))])]

workflow_qc <- encode[replicate == 'rep1', c('general.title', workflow_level), with = F]
viallabel_qc <- encode[, colnames(encode)[!colnames(encode) %in% workflow_level], with = F]

# match rep to viallabel
colnames(rep_to_sample_map) = c('general.description','replicate','viallabel')
dt = merge(viallabel_qc, rep_to_sample_map, by.x=c('general.title','replicate','general.description'),by.y=c('viallabel','replicate','general.description'))
stopifnot(nrow(dt)==nrow(viallabel_qc))
print(head(dt))
print(names(dt))
print(names(wet))
###################################################################################
## merge all sample-level QC
###################################################################################

# merge with wet lab QC
m1 <- merge(dt, wet, by.x = 'general.title', by.y = 'vial_label')
stopifnot(nrow(m1) == nrow(dt))
# merge with align stats
print(colnames(m1))
print(colnames(align_stat))
m2 <- merge(m1, align_stat, by.x = 'general.title', by.y = 'viallabel')
stopifnot(nrow(m2) == nrow(dt))
# remove columns of all 0 or all 100
check_col <- function(x) {
  if (is.numeric(x)) {
    if (sum(as.numeric(x)) == 0 | all(x == 100)) {
      return(x)
    }
  }
  return(NA)
}

res <- lapply(m2, check_col)
res <- res[!is.na(res)]
m2[, names(res) := NULL]

#head(m2)
#Adding in the viallabel column to make it more explicit
#m2 <- m2 %>% mutate(viallabel = general.title, .before=1)
m2$vial_label=m2$general.title
#m2 <- m2[, c("vial_label", names(m2)[!names(m2) %in% "vial_label"])]
new_m2 <- m2 %>% select(vial_label, everything())
head(new_m2)
# write out merged QC
outfile <- paste0(trimws(opt$outdir, which = 'right', whitespace = '/'), '/', 'merged_atac_qc.tsv')
write.table(new_m2, file = outfile, sep = '\t', col.names = T, row.names = F, quote = F)

# write out workflow-level QC
#outfile_workflow <- paste0(opt$outdir, '/', 'encode_workflow_level_atac_qc.tsv')
#write.table(workflow_qc, file = outfile_workflow, sep = '\t', col.names = T, row.names = F, quote = F)
