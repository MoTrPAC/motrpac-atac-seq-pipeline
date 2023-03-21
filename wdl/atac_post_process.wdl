version 1.0

task determine_out_dir_from_descrip {
    input {
        String cromwell_outputs_dir
        String croo_output_dir
        String workflow_id
    }

    command <<<
        sample_dir=~{cromwell_outputs_dir}/~{workflow_id}
        descrip=$(gsutil cat "$sample_dir"/call-qc_report/glob-*/qc.json | grep "description" | sed -e 's/.*": "//' -e 's/".*//')

        if [ "$descrip" = "No description" ]; then
            descrip=$(gstil cat "$sample_dir"/call-qc_report/glob-*/qc.json | grep "title" | sed -e 's/.*": "//' -e 's/".*//')
        fi

        echo "~{croo_output_dir}/~{workflow_id}/${descrip/gs:\/\///}/" > croo_out_dir.txt
    >>>

    output {
        String out_dir = read_string("croo_out_dir.txt")
    }

    runtime {
        docker: "us-docker.pkg.dev/motrpac-portal/motrpac-atac-seq/default:1.0.0"
    }
}

task localize_inputs {
    input {
        String cromwell_outputs_dir
        String croo_output_dir
        String workflow_id
        String workflow_label
    }

    command <<<
        CROO_DIR=~{croo_output_dir}/~{workflow_id}/~{workflow_label}
        croo --method copy ~{cromwell_outputs_dir}/~{workflow_id}/metadata.json --out-dir "$CROO_DIR"


        gsutil ls "$CROO_DIR"/qc/qc.json >qc_json.txt
        gsutil ls "$CROO_DIR"/align/rep*/*_R1.trim.bam >bam_file.txt
        gsutil ls "$CROO_DIR/align/rep?/*tagAlign.gz" >tag_align.txt
        gsutil ls "$CROO_DIR/signal/rep?/*pval.signal.bigwig" >signal.txt
    >>>

    output {
        String output_location = "~{croo_output_dir}/~{workflow_id}/~{workflow_label}"
        String qc_json_file_location = read_string("qc_json.txt")
        File bam_file = read_string("bam_file.txt")
        File tagalign_file = read_string("tag_align.txt")
        File signal_file = read_string("signal.txt")
    }

    runtime {
        docker: "us-docker.pkg.dev/motrpac-portal/motrpac-atac-seq/default:1.0.0"
    }
}

task extract_peak_from_gcp {
    input {
        String workflow_label
        String sample_croo_output_dir
    }

    command <<<
        # merged peak file
        gsutil -m cp -n ~{sample_croo_output_dir}/peak/overlap_reproducibility/overlap.optimal_peak.narrowPeak.gz ~{workflow_label}.overlap.optimal_peak.narrowPeak.gz
        gsutil -m cp -n ~{sample_croo_output_dir}/peak/overlap_reproducibility/overlap.optimal_peak.narrowPeak.hammock.gz ~{workflow_label}.overlap.optimal_peak.narrowPeak.hammock.gz

        # pooled signal track
        if [[ ~{workflow_label} != *"GET-STDRef-Set"* ]]; then
            gsutil -m cp -n ~{sample_croo_output_dir}/signal/pooled-rep/basename_prefix.pooled.pval.signal.bigwig ~{workflow_label}.pooled.pval.signal.bigwig
        fi

        # qc.html
        gsutil cp -n ~{sample_croo_output_dir}/qc/qc.html ~{workflow_label}.qc.html
    >>>

    output {
        File overlap_peak = "~{workflow_label}.overlap.optimal_peak.narrowPeak.gz"
        File overlap_hammock = "~{workflow_label}.overlap.optimal_peak.narrowPeak.hammock.gz"
        File pooled_signal = "~{workflow_label}.pooled.pval.signal.bigwig"
        File qc_html = "~{workflow_label}.qc.html"
    }

    runtime {
        docker: "us-docker.pkg.dev/motrpac-portal/motrpac-atac-seq/default:1.0.0"
    }
}

task align_stats {
    input {
        String workflow_label
        File input_bam
    }

    command <<<
        viallabel=$(basename ~{input_bam} | sed "s/_R1.*//")
        echo "$viallabel"

        primary=${viallabel}_primary.bam
        # already sorted
        # keep only primary alignments
        samtools view -b -F 0x900 ~{input_bam} -o "$primary"
        # index
        samtools index "$primary"
        samtools idxstats "$primary" >"~{workflow_label}_chrinfo.txt"

        # get counts
        total=$(awk '{sum+=$3;}END{print sum;}' "~{workflow_label}_chrinfo.txt")
        y=$(grep -E "^chrY" "~{workflow_label}_chrinfo.txt" | head -1 | cut -f 3)
        x=$(grep -E "^chrX" "~{workflow_label}_chrinfo.txt" | head -1 | cut -f 3)
        mt=$(grep -E "^chrM" "~{workflow_label}_chrinfo.txt" | head -1 | cut -f 3)
        auto=$(grep -E "^chr[0-9]" "~{workflow_label}_chrinfo.txt" | cut -f 3 | awk '{sum+=$1;}END{print sum;}')
        contig=$(grep -E -v "^chr" "~{workflow_label}_chrinfo.txt" | cut -f 3 | awk '{sum+=$1;}END{print sum;}')

        pct_y=$(echo "scale=5; ${y}/${total}*100" | bc -l | sed 's/^\./0./')
        pct_x=$(echo "scale=5; ${x}/${total}*100" | bc -l | sed 's/^\./0./')
        pct_mt=$(echo "scale=5; ${mt}/${total}*100" | bc -l | sed 's/^\./0./')
        pct_auto=$(echo "scale=5; ${auto}/${total}*100" | bc -l | sed 's/^\./0./')
        pct_contig=$(echo "scale=5; ${contig}/${total}*100" | bc -l | sed 's/^\./0./')

        # output to file
        echo "${viallabel},${total},${pct_x},${pct_y},${pct_mt},${pct_auto},${pct_contig}" >>"~{workflow_label}_chrinfo.csv"
    >>>

    output {
        File chrinfo_txt = "~{workflow_label}_chrinfo.txt"
        File chrinfo_csv = "~{workflow_label}_chrinfo.csv"
    }

    runtime {
        docker: "us-docker.pkg.dev/motrpac-portal/motrpac-atac-seq/default:1.0.0"
    }
}

task qc2tsv {
    input {
        String qc_filename
        Array[String] qc_json_file_list
    }

    command <<<
        echo ~{sep="\n" qc_json_file_list} > qc_json_file_list.txt
        qc2tsv --file qc_json_file_list.txt --collapse-header > ~{qc_filename}
    >>>

    output {
        File merged_qc_tsv = qc_filename
    }

    runtime {
        docker: "us-docker.pkg.dev/motrpac-portal/motrpac-atac-seq/default:1.0.0"
    }
}

task merge_chrinfo {
    input {
        String prefix
        Array[File] chrinfo_files
    }

    command <<<
        echo 'viallabel,total_primary_alignments,pct_chrX,pct_chrY,pct_chrM,pct_auto,pct_contig' > ~{prefix}_merged_chrinfo.csv
        cat ~{sep=' ' chrinfo_files} >> ~{prefix}_merged_chrinfo.csv
    >>>

    output {
        File merged_chrinfo = "~{prefix}_merged_chrinfo.csv"
    }

    runtime {
        docker: "us-docker.pkg.dev/motrpac-portal/motrpac-atac-seq/default:1.0.0"
    }
}

task merge_atac_qc {
    input {
        String prefix
        File qc_tsv
        File merged_chrinfo
        File sample_metadata_csv
    }

    command <<<
        Rscript merge_atac_qc_human.R -w ~{sample_metadata_csv} -q ~{qc_tsv} -a ~{merged_chrinfo} -o ~{prefix}_merged_atac_qc.csv
    >>>

    output {
        File merged_atac_qc = "~{prefix}_merged_atac_qc.csv"
    }

    runtime {
        docker: "us-docker.pkg.dev/motrpac-portal/motrpac-atac-seq/default:1.0.0"
    }
}

task merge_peaks {
    input {
        Array[File] peak_files
    }

    command <<<
        cat ~{sep=' ' peak_files} >> overlap.optimal_peak.narrowPeak.bed.gz
        echo "Success! done concatenating peak files from all tissues"

        python truncate_narrowpeak_200bp_summit.py --infile overlap.optimal_peak.narrowPeak.bed.gz --outfile overlap.optimal_peak.narrowPeak.200.bed.gz
        echo "Success! finished truncating peaks"

        # sort and merge peaks --> master peak file
        zcat overlap.optimal_peak.narrowPeak.200.bed.gz | bedtools sort | bedtools merge > overlap.optimal_peak.narrowPeak.200.sorted.merged.bed
        echo "Success! Finished sorting and merging"
    >>>

    output {
        File merged_peaks = "overlap.optimal_peak.narrowPeak.bed.gz"
        File merged_filtered_peaks = "overlap.optimal_peak.narrowPeak.200.bed.gz"
        File merged_filtered_sorted_peaks = "overlap.optimal_peak.narrowPeak.200.sorted.merged.bed"
    }

    runtime {
        docker: "us-docker.pkg.dev/motrpac-portal/motrpac-atac-seq/default:1.0.0"
    }
}

task intersect_tag {
    input {
        File tagalign_file
        File merged_filtered_sorted_peaks

        String label
    }

    command <<<
        VIAL_LABEL=$(basename ~{tagalign_file} | sed "s/_.*//")
        echo "$VIAL_LABEL" > counts.txt
        bedtools coverage -nonamecheck -counts -a ~{merged_filtered_sorted_peaks} -b ~{tagalign_file} | cut -f4 >> ~{label}.counts.txt
    >>>

    output {
        File counts = "~{label}.counts.txt"
    }

    runtime {
        docker: "us-docker.pkg.dev/motrpac-portal/motrpac-atac-seq/default:1.0.0"
    }
}

task create_tissue_tag {
    input {
        File merged_filtered_sorted_peaks
        Array[File] counts_files
    }

    command <<<
        echo -e $'chrom\tstart\tend' > index
        cat ~{merged_filtered_sorted_peaks} >> index

        #split the results counts matrix by tissue
        #to do : reimplement in python

        echo ~{counts_files} | awk -F "." '{print $2}' | awk '{print substr($1,8,2)}' | cut -f1 | sort | uniq >> tmp_tids.txt

        while IFS= read -r line; do
            paste index counts.*"${line}"??.txt > "T${line}.atac.counts.txt"
            gzip "T${line}.atac.counts.txt"
        done < tmp_tids.txt

        tar -czvf tissue_tag.tar.gz T*.atac.counts.txt.gz
    >>>

    output {
        File tissue_tag = "tissue_tag.tar.gz"
    }


    runtime {
        docker: "us-docker.pkg.dev/motrpac-portal/motrpac-atac-seq/default:1.0.0"
    }
}


struct WorkflowIdMapObject {
    String workflow_id
    String label
}

workflow atac_post_process {
    input {
        String cromwell_outputs_dir
        String croo_output_dir
        String qc_filename
        String prefix

        File sample_metadata_csv
        File workflow_id_map
    }

    Array[WorkflowIdMapObject] wf_id_map = read_json(workflow_id_map)

    scatter (wf in wf_id_map) {
        call localize_inputs {
            input:
                cromwell_outputs_dir = cromwell_outputs_dir,
                croo_output_dir = croo_output_dir,
                workflow_id = wf.workflow_id,
                workflow_label = wf.label
        }

        call extract_peak_from_gcp {
            input:
                workflow_label = wf.label,
                sample_croo_output_dir = localize_inputs.output_location,
        }

        call align_stats {
            input:
                workflow_label = wf.label,
                input_bam = localize_inputs.bam_file,
        }
    }

    call qc2tsv {
        input:
            qc_filename = qc_filename,
            qc_json_file_list = localize_inputs.qc_json_file_location
    }

    call merge_chrinfo {
        input:
            prefix = prefix,
            chrinfo_files = align_stats.chrinfo_csv
    }

    call merge_atac_qc {
        input:
            prefix = prefix,
            merged_chrinfo = merge_chrinfo.merged_chrinfo,
            sample_metadata_csv = sample_metadata_csv,
            qc_tsv = qc2tsv.merged_qc_tsv
    }

    call merge_peaks {
        input:
            peak_files = extract_peak_from_gcp.overlap_peak
    }

    scatter (pair in zip(localize_inputs.tagalign_file, wf_id_map)) {
        call intersect_tag {
            input:
                tagalign_file = pair.left,
                label = pair.right.label,
                merged_filtered_sorted_peaks = merge_peaks.merged_filtered_sorted_peaks
        }
    }

    call create_tissue_tag {
        input:
            merged_filtered_sorted_peaks = merge_peaks.merged_filtered_sorted_peaks,
            counts_files = intersect_tag.counts
    }

    output {
        File merged_atac_qc = merge_atac_qc.merged_atac_qc
        File merged_filtered_sorted_peaks = merge_peaks.merged_filtered_sorted_peaks
        File create_tissue_tag = create_tissue_tag.tissue_tag
    }
}