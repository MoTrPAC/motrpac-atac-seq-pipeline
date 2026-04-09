#!/usr/bin/env python3

import argparse
import pandas as pd
import json
import os
import subprocess
import re
from pathlib import Path
from collections import defaultdict
from google.cloud import storage
from typing import Any

class ConfigSummaryTracker:
    """Track summary statistics for each config file"""

    def __init__(self, per_batch=False):
        self.per_batch = per_batch
        self.config_data = defaultdict(lambda: {
            'fastqs': [],
            'vial_labels': set(),
            'pids': set(),
            'batch': None,
            'treatment_type': None  # Description without batch prefix
        })
        self.treatment_counts = defaultdict(set)  # treatment_type -> set of batches

    def add_sample(self, config_file, fastq, vial_label, pid=None, batch=None, treatment_type=None):
        """Add a sample to the config tracking"""
        self.config_data[config_file]['fastqs'].append(fastq)
        if vial_label:
            self.config_data[config_file]['vial_labels'].add(str(vial_label))
        if pid:
            self.config_data[config_file]['pids'].add(str(pid))
        if batch:
            self.config_data[config_file]['batch'] = batch
        if treatment_type:
            self.config_data[config_file]['treatment_type'] = treatment_type
            self.treatment_counts[treatment_type].add(batch)

    def write_summary(self, output_path):
        """Write summary TSV file"""
        rows = []
        for config_file, data in sorted(self.config_data.items()):
            config_name = os.path.basename(config_file)
            row = {
                'config_file': config_name,
                'total_fastqs': len(data['fastqs']),
                'unique_vial_labels': len(data['vial_labels']),
                'unique_pids': len(data['pids']),
                'vial_labels': ';'.join(sorted(data['vial_labels'])),
                'pids': ';'.join(sorted(data['pids']))
            }
            if self.per_batch:
                row['batch'] = data['batch'] or ''
                row['treatment_type'] = data['treatment_type'] or ''
                row['batches_with_same_treatment'] = len(self.treatment_counts.get(data['treatment_type'], set()))
            rows.append(row)

        df = pd.DataFrame(rows)

        # Reorder columns for per-batch mode
        if self.per_batch:
            cols = ['config_file', 'batch', 'treatment_type', 'batches_with_same_treatment',
                    'total_fastqs', 'unique_vial_labels', 'unique_pids', 'vial_labels', 'pids']
            df = df[cols]

        df.to_csv(output_path, sep='\t', index=False)
        print(f"\nConfig summary written to: {output_path}")
        print(f"  Total configs: {len(df)}")
        print(f"  Total FASTQs: {df['total_fastqs'].sum()}")
        print(f"  Total unique vial labels: {df['unique_vial_labels'].sum()}")
        print(f"  Total unique PIDs: {df['unique_pids'].sum()}")
        if self.per_batch:
            print(f"  Unique treatment types: {len(self.treatment_counts)}")


class FastqTracker:
    """Track FASTQ files and reasons for inclusion/exclusion"""

    def __init__(self):
        self.all_fastqs = []
        self.included = {}  # fastq -> config_file
        self.excluded = defaultdict(list)  # reason -> [fastq_files]
        self.batch_sources = defaultdict(set)  # config_file -> set of batch numbers

    def add_fastq(self, fastq, batch_num):
        self.all_fastqs.append((fastq, batch_num))

    def mark_included(self, fastq, config_file, batch_num):
        self.included[fastq] = config_file
        self.batch_sources[config_file].add(batch_num)

    def mark_excluded(self, fastq, reason, batch_num):
        self.excluded[reason].append((fastq, batch_num))

    def report(self):
        print("\n" + "="*80)
        print("FASTQ FILE TRACKING REPORT")
        print("="*80)
        print(f"\nTotal FASTQ files found: {len(self.all_fastqs)}")
        print(f"Files included in configs: {len(self.included)}")
        print(f"Files excluded: {len(self.all_fastqs) - len(self.included)}")

        if self.excluded:
            print("\n" + "-"*80)
            print("EXCLUSION REASONS:")
            print("-"*80)
            for reason, fastqs in sorted(self.excluded.items()):
                print(f"\n{reason}: {len(fastqs)} files")
                batch_counts = defaultdict(int)
                for _, batch_num in fastqs:
                    batch_counts[batch_num] += 1
                print(f"  By batch: {dict(sorted(batch_counts.items()))}")

                for fastq, batch_num in sorted(fastqs)[:10]:
                    print(f"  - Batch {batch_num}: {os.path.basename(fastq)}")
                if len(fastqs) > 10:
                    print(f"  ... and {len(fastqs) - 10} more")

        multi_batch = {k: v for k, v in self.batch_sources.items() if len(v) > 1}
        if multi_batch:
            print("\n" + "-"*80)
            print(f"MULTI-BATCH CONFIGS: {len(multi_batch)} config files combine data from multiple batches")
            print("-"*80)
            for config_file, batches in sorted(list(multi_batch.items())[:10]):
                config_name = os.path.basename(config_file)
                batch_list = ', '.join(sorted(batches, key=lambda x: int(x) if x.isdigit() else x))
                print(f"  {config_name}")
                print(f"    Batches: {batch_list}")
            if len(multi_batch) > 10:
                print(f"  ... and {len(multi_batch) - 10} more")

        print("\n" + "="*80 + "\n")


def load_json_from_gcs(gcs_path: str) -> Any:
    """Load JSON file from Google Cloud Storage."""
    result = subprocess.run(
        ['gsutil', 'cat', gcs_path],
        capture_output=True,
        text=True,
        check=True
    )
    return json.loads(result.stdout)


def load_bic_label_data(dict_path: str, data_path: str) -> pd.DataFrame:
    """
    Load BIC Label Data and apply categorical mappings.

    Returns DataFrame with vialLabel and mapped fields including:
    - ageGroup_label: Human-readable age group
    - protocol_label: Human-readable protocol/phase name
    """
    print("Loading BIC Label Data...")

    # Load data dictionary
    print(f"  Loading dictionary from {dict_path}...")
    data_dict = load_json_from_gcs(dict_path)

    # Load main data
    print(f"  Loading data from {data_path}...")
    data = load_json_from_gcs(data_path)
    df = pd.DataFrame(data)

    print(f"  Loaded {len(df)} BIC label records")

    # Apply categorical mappings for fields we care about
    for field_name, metadata in data_dict.items():
        categories = metadata.get('categories')

        if field_name in df.columns and categories:
            # Create new column with mapped labels
            new_col_name = f"{field_name}_label"
            df[new_col_name] = df[field_name].astype(str).map(categories)

    # Keep only relevant columns
    keep_cols = ['vialLabel', 'ageGroup', 'ageGroup_label', 'protocol', 'protocol_label']
    keep_cols = [c for c in keep_cols if c in df.columns]

    df_bic = df[keep_cols].copy()

    # Deduplicate on vialLabel (keep first occurrence)
    df_bic = df_bic.drop_duplicates(subset=['vialLabel'], keep='first')

    print(f"  BIC data: {len(df_bic)} unique vialLabels")
    print(f"  Columns: {', '.join(df_bic.columns)}")

    return df_bic


def get_fastq_list(fastq_path, gcp=False):
    """Get list of FASTQ files from GCP bucket or local directory"""
    if gcp:
        cmd = f'gsutil ls {fastq_path} | grep "fastq.gz"'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        fastq_list = result.stdout.strip().split('\n')
    else:
        fastq_list = [str(f) for f in Path(fastq_path).glob("*.fastq.gz")]

    fastq_list = [f for f in fastq_list if f and 'Undetermined' not in f]
    return fastq_list


def extract_sample_name(fastq_path):
    """Extract sample name from FASTQ filename"""
    basename = os.path.basename(fastq_path)
    match = re.match(r'(.+?)_R[12]\.fastq\.gz', basename)
    return match.group(1) if match else None


def load_data_dictionary(dict_path):
    """Load and parse the data dictionary for decoding numeric codes"""
    print(f"Loading data dictionary from {dict_path}...")

    df_dict = pd.read_csv(dict_path, sep='\t')

    # Create a lookup dictionary: {column: {key: val}}
    lookup = {}
    for _, row in df_dict.iterrows():
        column = row['column']
        key = row['key']
        val = row['val']

        if column not in lookup:
            lookup[column] = {}
        lookup[column][key] = val

    print(f"  Loaded mappings for: {', '.join(lookup.keys())}")
    return lookup


def decode_phenotype_values(df, data_dict):
    """Decode numeric phenotype values using data dictionary"""
    df_decoded = df.copy()

    # Map of phenotype columns to their dictionary keys
    decode_map = {
        'registration___sex': 'sex',
        'key___intervention': 'intervention',
        'key___sacrifice_time': 'sacrificeTime',
        'bic___study_group_timepoint': 'sacrificeTime',
        'study_group_timepoint': 'sacrificeTime',  # Training phase uses this column
    }

    for pheno_col, dict_key in decode_map.items():
        if pheno_col in df_decoded.columns and dict_key in data_dict:
            # Create a new decoded column
            decoded_col = f'{pheno_col}_decoded'
            df_decoded[decoded_col] = df_decoded[pheno_col].map(data_dict[dict_key])

            # If mapping was successful, replace the original column
            if df_decoded[decoded_col].notna().any():
                df_decoded[pheno_col] = df_decoded[decoded_col]
            df_decoded.drop(columns=[decoded_col], inplace=True)

    return df_decoded


def decode_sample_metadata(df, data_dict):
    """Decode sample metadata values (like Tissue from sample type codes)"""
    df_decoded = df.copy()

    # Decode Tissue if it contains numeric sample type codes
    if 'Tissue' in df_decoded.columns and 'sampleTypeCode' in data_dict:
        # Try to map Tissue values as integers to sample type codes
        decoded_col = 'Tissue_decoded'

        def safe_decode(val):
            try:
                code = int(val)
                return data_dict['sampleTypeCode'].get(code, val)
            except (ValueError, TypeError):
                return val

        df_decoded[decoded_col] = df_decoded['Tissue'].apply(safe_decode)

        # If any values were decoded, use the decoded column
        if (df_decoded[decoded_col] != df_decoded['Tissue']).any():
            df_decoded['Tissue'] = df_decoded[decoded_col]
        df_decoded.drop(columns=[decoded_col], inplace=True)

    return df_decoded


def load_phenotype_data():
    """Load and combine all phenotype files from motrpac-data-hub"""
    print("Loading phenotype data from motrpac-data-hub...")

    client = storage.Client()
    bucket = client.bucket('motrpac-data-hub')

    gs_rat_pheno_tables = []
    blobs = bucket.list_blobs(prefix='phenotype/rat')

    for blob in blobs:
        if 'pheno_viallabel_data' in blob.name:
            gs_rat_pheno_tables.append(f"gs://motrpac-data-hub/{blob.name}")
            print(f"  Found: {blob.name}")

    print(f"\nLoading {len(gs_rat_pheno_tables)} phenotype files...")
    dfs = []

    for gs_path in gs_rat_pheno_tables:
        print(f"  Loading {os.path.basename(gs_path)}...")
        df = pd.read_csv(gs_path, sep='\t', low_memory=False)
        dfs.append(df)

    df_vial_pheno = pd.concat(dfs, ignore_index=True)
    print(f"Combined phenotype data: {len(df_vial_pheno)} rows")
    return df_vial_pheno


def load_sample_metadata_for_batch(batch_num, blob_path, bucket_base, batch_label, fastq_list=None):
    """Load sample_metadata file for a specific batch

    Tries in order:
    1. sample_metadata_*.csv (Stanford format)
    2. sample_metadata.csv (Stanford format without date)
    3. metadata_dmaqc_*.csv (Sinai format)

    For Sinai metadata, extracts tissue from sampleTypeCode_value column

    Args:
        fastq_list: List of FASTQ files for this batch (used to filter DMAQC metadata)
    """
    # Try sample_metadata_*.csv first (Stanford format)
    wildcard_pattern = f"{bucket_base}/{blob_path}/sample_metadata_*.csv"

    try:
        cmd = f'gsutil ls {wildcard_pattern}'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            # Get the first matching file
            file_path = result.stdout.strip().split('\n')[0]
            print(f"  Loading sample metadata: {file_path}")
            df = pd.read_csv(file_path)
            return df
    except:
        pass

    # Fallback to sample_metadata.csv without date suffix
    try:
        pattern = f"{bucket_base}/{blob_path}/sample_metadata.csv"
        cmd = f'gsutil ls {pattern}'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode == 0:
            print(f"  Loading sample metadata: {pattern}")
            df = pd.read_csv(pattern)
            return df
    except:
        pass

    # Try DMAQC metadata file (Sinai format)
    try:
        dmaqc_pattern = f"{bucket_base}/{blob_path}/metadata_dmaqc_*.csv"
        cmd = f'gsutil ls {dmaqc_pattern}'
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip():
            file_path = result.stdout.strip().split('\n')[0]
            print(f"  Loading DMAQC metadata: {file_path}")
            df = pd.read_csv(file_path)

            # DMAQC files contain samples from multiple batches
            # Filter to only samples that have FASTQs in this batch
            if fastq_list and 'vialLabel' in df.columns:
                batch_viallabels = set()
                for fastq in fastq_list:
                    sample_name = extract_sample_name(fastq)
                    if sample_name:
                        batch_viallabels.add(sample_name)
                df = df[df['vialLabel'].astype(str).isin(batch_viallabels)]

            # Convert DMAQC format to sample_metadata format
            if 'sampleTypeCode_value' in df.columns:
                df['Tissue'] = df['sampleTypeCode_value'].str.replace(r'^Rat\s+', '', regex=True)
                df['Tissue'] = df['Tissue'].str.replace(r'\s+Powder$', '', regex=True)

            if 'vialLabel' in df.columns:
                df['vial_label'] = df['vialLabel']
                if 'Vial_label' not in df.columns:
                    df['Vial_label'] = df['vialLabel']

            if 'Sample_type' not in df.columns:
                df['Sample_type'] = 'study'

            return df
    except Exception as e:
        print(f"  Error loading DMAQC metadata: {e}")
        pass

    print(f"  Warning: No sample_metadata or DMAQC metadata file found for {batch_label}")
    return None


def clean_description(desc):
    """Clean description string for filename"""
    desc = desc.replace(' ', '-')
    desc = desc.replace(',', '')
    desc = re.sub(r'[()]', '', desc)
    return desc


def write_json_config(outfile, base_json_path, description, replicates, fastq_list_all,
                      age_group=None, protocol=None):
    """Write JSON configuration file for a set of replicates

    Parameters
    ----------
    outfile : str
        Output JSON file path
    base_json_path : str
        Path to base JSON template
    description : str
        Description for this config
    replicates : list
        List of replicate IDs
    fastq_list_all : list
        List of all FASTQ files
    age_group : str, optional
        Unused. Retained for call-site compatibility.
    protocol : str, optional
        Unused. Retained for call-site compatibility.
    """
    with open(base_json_path, 'r') as f:
        base_json = f.read()

    title = os.path.splitext(os.path.basename(outfile))[0]

    lines = []
    lines.append('{')
    lines.append(f'    "atac.title" : "{title}",')
    lines.append(f'    "atac.description" : "{title}",')
    lines.append('')
    lines.append(base_json)

    for i, replicate in enumerate(replicates, start=1):
        is_last = (i == len(replicates))
        # Convert replicate to string for matching in FASTQ paths
        replicate_str = str(replicate)
        rep_fastqs = [f for f in fastq_list_all if replicate_str in f]

        r1_files = sorted([f for f in rep_fastqs if '_R1.fastq.gz' in f])
        lines.append(f'    "atac.fastqs_rep{i}_R1" : [')
        for j, r1 in enumerate(r1_files):
            comma = '' if j == len(r1_files) - 1 else ','
            lines.append(f'        "{r1}"{comma}')
        lines.append('    ],')
        lines.append('')

        r2_files = sorted([f for f in rep_fastqs if '_R2.fastq.gz' in f])
        comma = '' if is_last else ','
        lines.append(f'    "atac.fastqs_rep{i}_R2" : [')
        for j, r2 in enumerate(r2_files):
            comma2 = '' if j == len(r2_files) - 1 else ','
            lines.append(f'        "{r2}"{comma2}')
        lines.append(f'    ]{comma}')
        lines.append('')

    lines.append('}')

    os.makedirs(os.path.dirname(outfile) if os.path.dirname(outfile) else '.', exist_ok=True)
    with open(outfile, 'w') as f:
        f.write('\n'.join(lines))


def main():
    parser = argparse.ArgumentParser(description='Generate JSON config files using sample_metadata and phenotype data')
    parser.add_argument('-j', '--json', required=True, help='Global JSON parameters file')
    parser.add_argument('-r', '--refstd', required=True, help='Path to Reference Standards TXT file')
    parser.add_argument('-d', '--datadict', required=True, help='Path to data dictionary TXT file')
    parser.add_argument('-b', '--batches', required=True, help='Path to batches TSV file')
    parser.add_argument('-o', '--outdir', required=True, help='Output directory for config files')
    parser.add_argument('--bucket-base', default='gs://motrpac-portal-transfer-stanford/atac-seq/rat',
                       help='Base GCP bucket path')
    parser.add_argument('--bic-dict', required=False,
                       help='GCS path to BIC Label Data dictionary JSON file')
    parser.add_argument('--bic-data', required=False,
                       help='GCS path to BIC Label Data JSON file')
    parser.add_argument('--per-batch', action='store_true',
                       help='Process batches separately instead of combining. Config files will include batch name.')

    args = parser.parse_args()

    tracker = FastqTracker()
    summary_tracker = ConfigSummaryTracker(per_batch=args.per_batch)
    os.makedirs(args.outdir, exist_ok=True)

    # Load data dictionary
    data_dict = load_data_dictionary(args.datadict)

    # Load phenotype data
    df_pheno = load_phenotype_data()

    # Decode phenotype values
    df_pheno = decode_phenotype_values(df_pheno, data_dict)

    # Load BIC Label Data if provided
    df_bic = None
    if args.bic_dict and args.bic_data:
        df_bic = load_bic_label_data(args.bic_dict, args.bic_data)
    else:
        print("\nWarning: BIC Label Data not provided. Age group and protocol fields will not be included.")
        print("  Use --bic-dict and --bic-data to include these fields.\n")

    # Determine which columns to use for grouping
    pheno_cols = df_pheno.columns.tolist()

    # Find available columns for each field
    # Check both simplified names (from merged acute file) and complex names (from training file)
    intervention_col = None
    for col in ['intervention', 'key___intervention']:
        if col in pheno_cols:
            intervention_col = col
            break

    sex_col = None
    for col in ['sex', 'registration___sex']:
        if col in pheno_cols:
            sex_col = col
            break

    # For sacrifice time, check multiple possible columns
    # Merged files use 'sacrifice_time', training uses 'study_group_timepoint', acute uses 'bic___study_group_timepoint'
    sacrifice_time_col = None
    for col in ['sacrifice_time', 'bic___study_group_timepoint', 'study_group_timepoint', 'key___sacrifice_time']:
        if col in pheno_cols:
            sacrifice_time_col = col
            break

    print(f"\nUsing phenotype columns:")
    print(f"  Intervention: {intervention_col}")
    print(f"  Sex: {sex_col}")
    print(f"  Sacrifice time: {sacrifice_time_col}")

    # Read batches file
    # Support both 2-column and 3-column formats:
    # 2-column: batch_num, blob_path (uses --bucket-base)
    # 3-column: batch_num, blob_path, bucket_base (overrides --bucket-base for that batch)
    print("\nReading batches configuration...")

    # Read file to determine number of columns
    with open(args.batches, 'r') as f:
        first_line = f.readline().strip()
        num_cols = len(first_line.split('\t'))

    if num_cols == 2:
        batches_df = pd.read_csv(args.batches, sep='\t', header=None, names=['batch_num', 'blob_path'])
        batches_df['bucket_base'] = args.bucket_base
        print(f"Found {len(batches_df)} batches to process (using default bucket: {args.bucket_base})")
    elif num_cols == 3:
        batches_df = pd.read_csv(args.batches, sep='\t', header=None, names=['batch_num', 'blob_path', 'bucket_base'])
        print(f"Found {len(batches_df)} batches to process (using batch-specific buckets)")
    else:
        raise ValueError(f"Batches file must have 2 or 3 columns, found {num_cols}")

    # Collect FASTQ files and sample metadata for all batches
    all_fastq_lists = {}
    fastq_to_batch = {}
    all_sample_metadata = []

    for _, row in batches_df.iterrows():
        batch_num = str(row['batch_num'])  # This is now like "Stanford-1" or "Sinai-1"
        blob_path = row['blob_path']
        bucket_base = row['bucket_base']

        fastq_path = f"{bucket_base}/{blob_path}/fastq_raw"
        print(f"\n{batch_num}: {fastq_path}")

        fastq_list = get_fastq_list(fastq_path, gcp=True)
        all_fastq_lists[batch_num] = fastq_list

        for fq in fastq_list:
            tracker.add_fastq(fq, batch_num)
            fastq_to_batch[fq] = batch_num

        print(f"  Found {len(fastq_list)} FASTQ files")

        # Load sample metadata (pass fastq_list for DMAQC filtering)
        sample_meta = load_sample_metadata_for_batch(batch_num, blob_path, bucket_base, batch_num, fastq_list=fastq_list)
        if sample_meta is not None:
            sample_meta['batch_num'] = batch_num
            all_sample_metadata.append(sample_meta)

    # Combine all data
    combined_fastq_list = []
    for batch_fastqs in all_fastq_lists.values():
        combined_fastq_list.extend(batch_fastqs)

    print(f"\nTotal FASTQ files: {len(combined_fastq_list)}")

    if all_sample_metadata:
        df_sample_meta = pd.concat(all_sample_metadata, ignore_index=True)
        print(f"Total sample metadata rows: {len(df_sample_meta)}")

        # Decode sample metadata values
        df_sample_meta = decode_sample_metadata(df_sample_meta, data_dict)

        # Merge sample metadata with phenotype data
        # Try to merge on vialLabel or similar ID column
        # Handle case variations: Vial_label, vial_label, vialLabel, viallabel
        merge_col = None

        # First, normalize column names in sample_metadata for easier matching
        # Create a mapping of lowercase to actual column name
        meta_cols_lower = {col.lower(): col for col in df_sample_meta.columns}
        pheno_cols_lower = {col.lower(): col for col in df_pheno.columns}

        # Determine which vial column to use
        # Sample metadata typically has Vial_label -> vial_label
        # Phenotype data may have viallabel, vial_label, or vialLabel
        # Prefer vial_label if both have it, otherwise find common column
        meta_vial_col = None
        pheno_vial_col = None

        # Check what sample_metadata has
        if 'vial_label' in meta_cols_lower:
            meta_vial_col = meta_cols_lower['vial_label']
        elif 'viallabel' in meta_cols_lower:
            meta_vial_col = meta_cols_lower['viallabel']

        # Check what phenotype has - prefer the column with the most non-null values
        vial_candidates = [(variant, pheno_cols_lower[variant]) for variant in ['vial_label', 'viallabel', 'viallabel'] if variant in pheno_cols_lower]
        if vial_candidates:
            best_col = max(vial_candidates, key=lambda x: df_pheno[x[1]].notna().sum())
            pheno_vial_col = best_col[1]

        if meta_vial_col and pheno_vial_col:
            # Drop other vial columns in phenotype to avoid duplicates after renaming
            other_vial_cols = [c for c in df_pheno.columns if 'vial' in c.lower() and c != pheno_vial_col]
            if other_vial_cols:
                df_pheno = df_pheno.drop(columns=other_vial_cols)

            # Rename both to 'vial_label' for merging
            df_sample_meta = df_sample_meta.rename(columns={meta_vial_col: 'vial_label'})
            df_pheno = df_pheno.rename(columns={pheno_vial_col: 'vial_label'})
            merge_col = 'vial_label'
        else:
            merge_col = None

        # Initialize pid_col before merge block
        pid_col = None

        if merge_col:
            print(f"\nMerging on column: {merge_col}")

            # Deduplicate phenotype data - keep only essential columns and first occurrence of each vial_label
            # This prevents cartesian product explosion
            # Include ALL possible timepoint columns since different phases use different ones
            timepoint_cols = ['bic___study_group_timepoint', 'study_group_timepoint', 'key___sacrifice_time']
            timepoint_cols_present = [c for c in timepoint_cols if c in df_pheno.columns]

            # Find PID column - try multiple possible names
            pid_col = None
            for col in ['pid', 'PID', 'participant_id', 'registration___pid']:
                if col in df_pheno.columns:
                    pid_col = col
                    break

            essential_pheno_cols = [merge_col, sex_col, intervention_col] + timepoint_cols_present
            if pid_col:
                essential_pheno_cols.append(pid_col)
            essential_pheno_cols = [c for c in essential_pheno_cols if c and c in df_pheno.columns]
            df_pheno_dedup = df_pheno[essential_pheno_cols].drop_duplicates(subset=[merge_col], keep='first')

            # Drop pid column from sample_meta if it exists (phenotype pid is authoritative)
            if pid_col and pid_col in df_sample_meta.columns:
                df_sample_meta = df_sample_meta.drop(columns=[pid_col])

            df_combined = pd.merge(df_sample_meta, df_pheno_dedup, on=merge_col, how='left')
            print(f"Merged data: {len(df_combined)} rows")

            # Merge with BIC Label Data if available
            if df_bic is not None:
                df_bic_renamed = df_bic.rename(columns={'vialLabel': merge_col})

                def normalize_vial_label(val):
                    """Convert vial label to clean string without .0"""
                    try:
                        return str(int(float(val)))
                    except (ValueError, TypeError):
                        return str(val)

                df_bic_renamed[merge_col] = df_bic_renamed[merge_col].apply(normalize_vial_label)
                df_combined[merge_col] = df_combined[merge_col].apply(normalize_vial_label)
                df_combined = pd.merge(df_combined, df_bic_renamed, on=merge_col, how='left')

            # Coalesce timepoint columns - different phases use different column names
            # Create a unified timepoint column from whichever column has data
            if 'bic___study_group_timepoint' in df_combined.columns and 'study_group_timepoint' in df_combined.columns:
                df_combined['unified_timepoint'] = df_combined['bic___study_group_timepoint'].fillna(df_combined['study_group_timepoint'])
            elif 'bic___study_group_timepoint' in df_combined.columns:
                df_combined['unified_timepoint'] = df_combined['bic___study_group_timepoint']
            elif 'study_group_timepoint' in df_combined.columns:
                df_combined['unified_timepoint'] = df_combined['study_group_timepoint']
            elif 'key___sacrifice_time' in df_combined.columns:
                df_combined['unified_timepoint'] = df_combined['key___sacrifice_time']

            # Separate experimental samples from reference standards
            # Use Sample_type or Sample_category if available (prefer Sample_type as it's what we set for DMAQC)
            sample_type_col = None
            for col_name in ['Sample_type', 'Sample_category']:
                col_lower = col_name.lower()
                if col_lower in meta_cols_lower:
                    candidate_col = meta_cols_lower[col_lower]
                    # Only use this column if it has non-null values
                    if df_combined[candidate_col].notna().any():
                        sample_type_col = candidate_col
                        break

            # To be considered experimental, a sample must:
            # 1. Be marked as 'study' in Sample_category/Sample_type (if available)
            # 2. Have phenotype data (check multiple columns as some may be NaN)
            # Check if ANY key phenotype columns are populated (sex, intervention, timepoint)
            has_pheno_cols = []
            if sex_col and sex_col in df_combined.columns:
                has_pheno_cols.append(df_combined[sex_col].notna())
            if intervention_col and intervention_col in df_combined.columns:
                has_pheno_cols.append(df_combined[intervention_col].notna())
            if 'unified_timepoint' in df_combined.columns:
                has_pheno_cols.append(df_combined['unified_timepoint'].notna())

            # Has pheno if ANY of these columns is not null
            if has_pheno_cols:
                has_pheno = pd.concat(has_pheno_cols, axis=1).any(axis=1)
            else:
                has_pheno = pd.Series([False] * len(df_combined))

            if sample_type_col and sample_type_col in df_combined.columns:
                is_study = df_combined[sample_type_col] == 'study'
                is_ref = df_combined[sample_type_col] == 'ref'
                is_unknown = df_combined[sample_type_col].isna()

                # Experimental samples: marked as 'study' OR (unknown Sample_type AND has phenotype)
                is_experimental = (is_study | (is_unknown & has_pheno)) & has_pheno

                # Reference standards: marked as 'ref' OR (unknown Sample_type AND NO phenotype)
                is_refstd = is_ref | (is_unknown & ~has_pheno)

                df_experimental = df_combined[is_experimental].copy()
                df_refstd_from_meta = df_combined[is_refstd].copy()

                # Track samples excluded due to missing phenotype data
                is_study_but_no_pheno = is_study & ~has_pheno
                excluded_no_pheno = df_combined[is_study_but_no_pheno]
                for _, row in excluded_no_pheno.iterrows():
                    val = row[merge_col]
                    if pd.isna(val) or str(val).lower() == 'nan':
                        sample_name = 'unknown'
                    else:
                        try:
                            sample_name = str(int(float(val)))
                        except (ValueError, TypeError):
                            sample_name = str(val)
                    sample_fastqs = [f for f in combined_fastq_list if sample_name in f]
                    for fastq in sample_fastqs:
                        fastq_batch = fastq_to_batch.get(fastq, 'unknown')
                        tracker.mark_excluded(fastq, "Sample missing phenotype data", fastq_batch)
            else:
                df_experimental = df_combined[has_pheno].copy()
                df_refstd_from_meta = df_combined[~has_pheno].copy()

            print(f"Experimental samples: {len(df_experimental)}")
            print(f"Reference standards: {len(df_refstd_from_meta)}")

            df_combined = df_experimental
        else:
            print("\nWarning: Could not find common column for merging")
            df_combined = df_sample_meta
            df_refstd_from_meta = pd.DataFrame()
    else:
        print("\nWarning: No sample metadata loaded")
        df_combined = pd.DataFrame()
        df_refstd_from_meta = pd.DataFrame()

    # Extract sample names
    sample_names = set()
    for fastq in combined_fastq_list:
        sample_name = extract_sample_name(fastq)
        if sample_name:
            sample_names.add(sample_name)

    print(f"Unique sample names: {len(sample_names)}")

    # Helper function to safely convert vial labels
    def safe_vial_to_str(series):
        """Safely convert vial label series to list of strings"""
        result = []
        for val in series.dropna().unique():
            if pd.isna(val) or val in ['nan', 'None', '']:
                continue
            try:
                # Try to convert to float then int to remove .0
                result.append(str(int(float(val))))
            except (ValueError, TypeError):
                # If conversion fails, just use as string
                result.append(str(val))
        return result

    # Identify reference standards
    # These are samples that are either:
    # 1. In sample_metadata but not in phenotype data (df_refstd_from_meta)
    # 2. Not in sample_metadata at all (in FASTQ but not in metadata)
    if not df_combined.empty and merge_col:
        experimental_sample_names = safe_vial_to_str(df_combined[merge_col])
    else:
        experimental_sample_names = []

    if not df_refstd_from_meta.empty and merge_col:
        refstd_from_meta_names = safe_vial_to_str(df_refstd_from_meta[merge_col])
    else:
        refstd_from_meta_names = []

    # Samples not in experimental data are potential reference standards
    ref_standard_names = [s for s in sample_names if s not in experimental_sample_names]

    print(f"Experimental samples: {len(experimental_sample_names)}")
    print(f"Reference standards: {len(ref_standard_names)}")

    # Group by experimental conditions and generate configs
    if not df_combined.empty:
        print("\nGenerating JSON files for sample groups...")

        group_cols = []
        # In per-batch mode, add batch_num as the first grouping column
        if args.per_batch and 'batch_num' in df_combined.columns:
            group_cols.append('batch_num')

        if 'Tissue' in df_combined.columns:
            group_cols.append('Tissue')
        if intervention_col and intervention_col in df_combined.columns:
            group_cols.append(intervention_col)
        if 'unified_timepoint' in df_combined.columns:
            group_cols.append('unified_timepoint')
        if sex_col and sex_col in df_combined.columns:
            group_cols.append(sex_col)
        # Add age group from BIC data to filename
        if 'ageGroup_label' in df_combined.columns:
            group_cols.append('ageGroup_label')
        # Add protocol from BIC data to filename
        if 'protocol_label' in df_combined.columns:
            group_cols.append('protocol_label')

        print(f"Grouping by: {group_cols}")
        if args.per_batch:
            print("  (per-batch mode: batches processed separately)")

        if group_cols and merge_col in df_combined.columns:
            grouped = df_combined.groupby(group_cols, dropna=False)

            config_count = 0
            for name, group in grouped:
                # Use safe conversion function for replicates
                replicates = safe_vial_to_str(group[merge_col])

                name_tuple = name if isinstance(name, tuple) else (name,)

                # In per-batch mode, extract batch name and create treatment_type without it
                if args.per_batch and 'batch_num' in group_cols:
                    batch_name = str(name_tuple[0])
                    treatment_parts = [str(v) for v in name_tuple[1:]]  # Skip batch_num
                    treatment_type = clean_description('_'.join(treatment_parts))
                    desc_parts = [batch_name] + treatment_parts
                    description = clean_description('_'.join(desc_parts))
                else:
                    batch_name = None
                    treatment_type = None
                    desc_parts = [str(v) for v in name_tuple]
                    description = clean_description('_'.join(desc_parts))

                if not description or description in ['', 'nan', 'None', '<NA>']:
                    continue

                # Extract BIC metadata from the group (use first non-null value)
                age_group = None
                protocol = None
                if 'ageGroup_label' in group.columns:
                    age_group_vals = group['ageGroup_label'].dropna().unique()
                    if len(age_group_vals) > 0:
                        age_group = str(age_group_vals[0])
                if 'protocol_label' in group.columns:
                    protocol_vals = group['protocol_label'].dropna().unique()
                    if len(protocol_vals) > 0:
                        protocol = str(protocol_vals[0])

                # In per-batch mode, filter FASTQs to only include files from this batch
                if args.per_batch and batch_name:
                    batch_fastq_list = [f for f in combined_fastq_list if fastq_to_batch.get(f) == batch_name]
                else:
                    batch_fastq_list = combined_fastq_list

                outfile = os.path.join(args.outdir, f'{description}.json')
                write_json_config(outfile, args.json, description, replicates, batch_fastq_list,
                                age_group=age_group, protocol=protocol)

                # Get PIDs for this group (if pid_col exists)
                group_pids = set()
                if pid_col and pid_col in group.columns:
                    for pid_val in group[pid_col].dropna().unique():
                        try:
                            group_pids.add(str(int(float(pid_val))))
                        except (ValueError, TypeError):
                            group_pids.add(str(pid_val))

                for replicate in replicates:
                    for fastq in batch_fastq_list:
                        if replicate in fastq:
                            fastq_batch = fastq_to_batch[fastq]
                            tracker.mark_included(fastq, outfile, fastq_batch)
                            summary_tracker.add_sample(outfile, fastq, replicate, pid=None,
                                                      batch=batch_name, treatment_type=treatment_type)

                # Add all PIDs from this group to the config summary
                for pid in group_pids:
                    summary_tracker.config_data[outfile]['pids'].add(pid)

                config_count += 1

            print(f"Created {config_count} config files")

    # Handle reference standards
    if ref_standard_names:
        print("\nGenerating JSON files for reference standards...")
        ref_meta = pd.read_csv(args.refstd, sep='\t')

        # Build mapping of sample_name -> (ref_type, ref_desc, batch)
        ref_sample_info = {}
        for sample_name in ref_standard_names:
            ref_row = ref_meta[ref_meta['MTP_RefLabel'].astype(str) == sample_name]

            if ref_row.empty:
                for fastq in combined_fastq_list:
                    if sample_name in fastq:
                        batch_num = fastq_to_batch[fastq]
                        tracker.mark_excluded(fastq, "Reference standard not found in reference standards file", batch_num)
                continue

            ref_type = ref_row.iloc[0]['MTP_RefType']
            ref_desc = ref_row.iloc[0]['MTP_RefDescription']

            # Find which batch this sample belongs to
            sample_batch = None
            for fastq in combined_fastq_list:
                if sample_name in fastq:
                    sample_batch = fastq_to_batch[fastq]
                    break

            ref_sample_info[sample_name] = (ref_type, ref_desc, sample_batch)

        # Group reference standards
        if args.per_batch:
            # Group by (batch, ref_type, ref_desc)
            ref_configs = {}
            for sample_name, (ref_type, ref_desc, batch) in ref_sample_info.items():
                key = (batch, ref_type, ref_desc)
                if key not in ref_configs:
                    ref_configs[key] = []
                ref_configs[key].append(sample_name)
        else:
            # Group by (ref_type, ref_desc) only
            ref_configs = {}
            for sample_name, (ref_type, ref_desc, batch) in ref_sample_info.items():
                key = (None, ref_type, ref_desc)
                if key not in ref_configs:
                    ref_configs[key] = []
                ref_configs[key].append(sample_name)

        ref_count = 0
        for (batch, ref_type, ref_desc), sample_list in ref_configs.items():
            treatment_type = clean_description(f'{ref_type}_{ref_desc}')
            if args.per_batch and batch:
                description = clean_description(f'{batch}_{ref_type}_{ref_desc}')
                # Filter FASTQs to only include files from this batch
                batch_fastq_list = [f for f in combined_fastq_list if fastq_to_batch.get(f) == batch]
            else:
                description = treatment_type
                batch_fastq_list = combined_fastq_list
            outfile = os.path.join(args.outdir, f'{description}.json')

            write_json_config(outfile, args.json, description, sample_list, batch_fastq_list)

            for sample_name in sample_list:
                for fastq in batch_fastq_list:
                    if sample_name in fastq:
                        fastq_batch = fastq_to_batch[fastq]
                        tracker.mark_included(fastq, outfile, fastq_batch)
                        # Reference standards don't have PIDs
                        summary_tracker.add_sample(outfile, fastq, sample_name, pid=None,
                                                  batch=batch if args.per_batch else None,
                                                  treatment_type=treatment_type if args.per_batch else None)

            ref_count += 1

        print(f"Created {ref_count} config files for reference standards")

    tracker.report()

    # Write config summary file
    summary_output = os.path.join(args.outdir, 'config_summary.tsv')
    summary_tracker.write_summary(summary_output)

    print(f"\nDone! Generated config files in {args.outdir}")


if __name__ == '__main__':
    main()
