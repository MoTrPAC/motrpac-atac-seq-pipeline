#!/bin/R
# Nicole Gay
# 15 May 2020 
# Fix and merge ATAC-seq QC 

#Usage : Rscript src/merge_atac_qc.R -w ~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final/sample_metadata_20200928.csv -q ~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final/qc/atac_qc.tsv -m ~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final/rep_to_sample_map.csv -a ~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final/merged_chr_info.csv -o ~/test_mnt/PASS/atac-seq/stanford/batch4_20200928/Output/final/

library(data.table)
library(optparse)

option_list <- list(
  make_option(c("-w", "--sample_meta"), help = "Absolute path to wetlab sample metadata file, e.g. sample_metadata_YYYYMMDD.csv"),
  make_option(c("-q", "--atac_qc"), help = "Absolute path to pipeline qc metrics file output of qc2tsv tool, e.g. atac_qc.tsv"),
  make_option(c("-a", "--align_stats"), help = "Absolute path to genome alignment stats file, e.g. merged_chr_info.csv"),
  make_option(c("-o", "--outdir", help = "Absolute path to output directory for the merged qc reports"))

)

opt_parse_inst <- OptionParser(option_list = option_list)

opt <- parse_args(opt_parse_inst)

if (is.null(opt$sample_meta) |
  is.null(opt$atac_qc) |
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
align_stat <- fread(opt$align_stats, sep = ',', header = T)

###################################################################################
## fix ENCODE QC
###################################################################################

# fix other "general" cols
cols <- colnames(encode)[grepl('general', colnames(encode))]
cols <- cols[cols != 'general.description']
for (col in cols) {
  print(col)
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
workflow_qc <- encode[replicate == 'rep1', c('general.description', workflow_level), with = F]
viallabel_qc <- encode[, colnames(encode)[!colnames(encode) %in% workflow_level], with = F]

###################################################################################
## merge all sample-level QC
###################################################################################

# merge with wet lab QC
m1 <- merge(viallabel_qc, wet, by.x = 'general.title', by.y = 'vial_label')
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

head(m2)

# write out merged QC
outfile <- paste0(trimws(opt$outdir, which = 'right', whitespace = '/'), '/', 'merged_atac_qc.tsv')
write.table(m2, file = outfile, sep = '\t', col.names = T, row.names = F, quote = F)

# write out workflow-level QC
outfile_workflow <- paste0(opt$outdir, '/', 'encode_workflow_level_atac_qc.tsv')
write.table(workflow_qc, file = outfile_workflow, sep = '\t', col.names = T, row.names = F, quote = F)
