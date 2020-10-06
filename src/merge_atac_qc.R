#!/bin/R
# Nicole Gay
# 15 May 2020 
# Fix and merge ATAC-seq QC 

library(data.table)

wet = fread('sample_metadata_20200327.csv', sep=',', header=T)
wet = unique(wet) # remove duplicate rows
encode = fread('stanford_atac_qc.tsv', sep='\t', header=T)
rep_to_sample_map = fread('rep_to_sample_map.csv', sep=',', header=F)
align_stat = fread('merged_chr_info.csv',sep=',',header=T)

###################################################################################
## fix ENCODE QC
###################################################################################

# refstd are singletons; treat them differently
refstd = encode[grepl('STDRef', general.title)]
refstd[,general.description := general.title]
encode = encode[!grepl('STDRef', general.title)]

# format "general" to fix auto-format from qc2tsv 
# fix description
t1 = encode[1,general.description]
if(grepl(' ',t1)){
  t1 = encode[1,general.title]
  encode[1,general.description := t1]
}
for (i in 1:nrow(encode)){
  if(encode[i,general.description] == ''){
    encode[i,general.description := t1]
  }else{
    t1 = encode[i,general.description]
    if(grepl(' ',t1)){
      t1 = encode[i,general.title]
      encode[i,general.description := t1]
    }
  }
}
# fix other "general" cols
cols = colnames(encode)[grepl('general',colnames(encode))]
cols = cols[cols != 'general.description']
for (col in cols){
  print(col)
  t1 = encode[1,get(col)]
  for (i in 1:nrow(encode)){
    if(encode[i,get(col)] == ''){
      encode[i,(col) := t1]
    }else{
      t1 = encode[i,get(col)]
    }
  }
}

# separate workflow-level and sample-level QC 
workflow_level = colnames(encode)[unlist(encode[, lapply(.SD, function(x) any(is.na(x) | x == ''))])]
# add refstd back in 
encode = rbindlist(list(encode, refstd))
workflow_qc = encode[replicate == 'rep1',c('general.description',workflow_level),with=F]
viallabel_qc = encode[,colnames(encode)[!colnames(encode)%in%workflow_level],with=F]

# match rep to viallabel
colnames(rep_to_sample_map) = c('general.description','replicate','viallabel')
dt = merge(viallabel_qc, rep_to_sample_map, by=c('general.description','replicate'))
stopifnot(nrow(dt)==nrow(viallabel_qc))

###################################################################################
## merge all sample-level QC
###################################################################################

# merge with wet lab QC 
m1 = merge(dt, wet, by.x='viallabel', by.y='vial_label')
stopifnot(nrow(m1) == nrow(dt))
# merge with align stats 
m2 = merge(m1, align_stat, by='viallabel')
stopifnot(nrow(m2) == nrow(dt))
# remove columns of all 0 or all 100 
check_col = function(x){
  if(is.numeric(x)){
    if(sum(x) == 0 | sum(x) == 100*nrow(m2)){
      return(x)
    }
  }
  return(NA)
}
res = lapply(m2, check_col)
res = res[!is.na(res)]
m2[,names(res):=NULL]

head(m2)

# write out merged QC 
write.table(m2, file='merged_atac_qc.tsv', sep='\t', col.names=T, row.names=F, quote=F)

# write out workflow-level QC 
write.table(workflow_qc, file='encode_workflow_level_atac_qc.tsv', sep='\t', col.names=T, row.names=F, quote=F)
