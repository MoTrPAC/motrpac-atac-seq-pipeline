import pandas as pd
import os
import argparse
import json
import subprocess
from datetime import datetime


def parse_args():
    parser = argparse.ArgumentParser(
        prog='send_run_summary.py',
        formatter_class=argparse.RawTextHelpFormatter,
        description=(
            'Generate a run summary from a Cromwell/Caper metadata.json file.\n'
            'The metadata path can be a local file path or a GCS URI (gs://).\n'
        )
    )
    parser.add_argument(
        '--metadata_path', required=True,
        help='Path to metadata.json (local path or gs:// URI)'
    )
    parser.add_argument(
        '--output_dir',
        default='.',
        help=(
            'Directory to write the run summary file.\n'
            'Defaults to the current directory.\n'
            'Filename is set to "<title>_<end_datetime>.txt".'
        )
    )
    return parser.parse_args()


def load_metadata(path):
    """Load metadata.json from a local path or GCS URI."""
    if path.startswith('gs://'):
        result = subprocess.run(
            ['gsutil', 'cat', path],
            capture_output=True, text=True
        )
        if result.returncode != 0:
            raise RuntimeError(f'gsutil cat failed for {path}:\n{result.stderr}')
        return json.loads(result.stdout)
    else:
        if not os.path.exists(path):
            raise FileNotFoundError(f'Metadata file not found: {path}')
        with open(path) as f:
            return json.load(f)


def get_time_diff(ts1_str, ts2_str):
    """Return elapsed time string between two ISO 8601 timestamps."""
    if not ts1_str or not ts2_str:
        return None
    ts1_str = ts1_str.split('.')[0].rstrip('Z')
    ts2_str = ts2_str.split('.')[0].rstrip('Z')
    ts1 = datetime.strptime(ts1_str, '%Y-%m-%dT%H:%M:%S')
    ts2 = datetime.strptime(ts2_str, '%Y-%m-%dT%H:%M:%S')
    return str(ts2 - ts1)


def build_job_report(calls):
    """
    Build a per-task DataFrame from the calls dict.
    Handles scattered tasks (multiple shards per call).
    """
    rows = []
    for job_name, entries in calls.items():
        for entry in entries:
            shard = entry.get('shardIndex', -1)
            start = entry.get('start')
            end = entry.get('end')
            rows.append({
                'job': job_name,
                'shard': shard if shard != -1 else '',
                'status': entry.get('executionStatus'),
                'start': start,
                'end': end,
                'elapsed': get_time_diff(start, end),
                'attempt': entry.get('attempt', 1),
            })

    if not rows:
        return pd.DataFrame(columns=['job', 'shard', 'status', 'start', 'end', 'elapsed', 'attempt'])

    df = pd.DataFrame(rows)
    df = df.sort_values('start', na_position='last').reset_index(drop=True)
    return df


def write_summary(data, outpath):
    inputs = data.get('inputs', {})

    # Use atac.title if available, fall back to workflowName + id
    title = (
        inputs.get('atac.title')
        or f"{data.get('workflowName', 'atac')}_{data.get('id', 'unknown')}"
    )

    workflow_id = data.get('id')
    status = data.get('status')
    start = data.get('start')
    end = data.get('end')
    elapsed = get_time_diff(start, end)

    job_report = build_job_report(data.get('calls', {}))

    with open(outpath, 'w') as f:
        f.write(f'# ENCODE ATAC RUN SUMMARY\n')
        f.write(f'# Title: {title}\n')
        f.write(f'# Workflow ID: {workflow_id}\n')
        f.write(f'# Status: {status}\n')
        f.write(f'# Start: {start}\n')
        f.write(f'# End: {end}\n')
        f.write(f'# Elapsed: {elapsed}\n')

    job_report.to_csv(outpath, mode='a', index=False)
    print(f'Run summary written to: {outpath}')

    return title


def make_output_path(output_dir, title, end_timestamp):
    """Build the output filename from the run title and end timestamp."""
    if end_timestamp:
        # Parse and reformat as YYYY-MM-DD_HHMMSS (filesystem-safe)
        ts = end_timestamp.split('.')[0].rstrip('Z')
        dt = datetime.strptime(ts, '%Y-%m-%dT%H:%M:%S')
        dt_str = dt.strftime('%Y-%m-%d_%H%M%S')
    else:
        dt_str = 'unknown-time'

    filename = f"{title}_{dt_str}.txt"
    os.makedirs(output_dir, exist_ok=True)
    return os.path.join(output_dir, filename)


def main():
    args = parse_args()

    try:
        data = load_metadata(args.metadata_path)
    except (FileNotFoundError, RuntimeError) as e:
        print(f'Error loading metadata: {e}')
        return

    inputs = data.get('inputs', {})
    title = (
        inputs.get('atac.title')
        or f"{data.get('workflowName', 'atac')}_{data.get('id', 'unknown')}"
    )

    outpath = make_output_path(args.output_dir, title, data.get('end'))
    write_summary(data, outpath)


if __name__ == '__main__':
    main()
