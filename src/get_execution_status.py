import asyncio
import json
import argparse
from datetime import datetime
from pathlib import Path
from typing import Dict

from aiohttp import ClientSession
from tqdm import tqdm


async def get_status(
    workflow_id: str, session: ClientSession
) -> Dict[str, Dict[str, str]]:
    """
    This function gets the status of a workflow.
    :param workflow_id: The workflow ID
    :param session: The aiohttp session
    :return:
    """
    res = await session.get(
        f"http://localhost:8000/api/workflows/v1/query",
        params={"id": workflow_id, "additionalQueryResultFields": "labels"},
    )
    res_json = await res.json()
    # get the status of the workflow
    wf_metadata = res_json["results"][0]
    status = wf_metadata["status"]
    # and the label of the workflow (the submitted JSON filename or other custom label)
    labels = wf_metadata.get("labels", {})
    label = labels.get("caper-str-label", None)
    return {workflow_id: {"status": status, "label": label}}


async def get_metadata(workflow_id, session: ClientSession):
    res = await session.get(
        f"http://localhost:8000/api/workflows/v1/{workflow_id}/metadata"
    )
    res_json = await res.json()
    calls = res_json["calls"]
    calls_dict = {}
    # iterate through the various call attempts
    for call_name, call_attempts in calls.items():
        attempts = (0, 1)
        # find the latest attempt and its index (sometimes the latest attempt comes out
        # of order, although this is rare, we need to account for it)
        for i, attempt in enumerate(call_attempts):
            # compare the latest attempt to the current attempt
            is_latest = max(attempts[1], attempt["attempt"])
            if is_latest:
                attempts = (i, attempt["attempt"])

        # set the latest attempt
        latest_task_attempt = call_attempts[attempts[0]]

        # get the status of the latest attempt
        task_status = latest_task_attempt["executionStatus"]
        # we only want to fetch the rest of the metadata if the task is running
        if task_status != "Done":
            task_dict = {
                "attempt": latest_task_attempt["attempt"],
                "cromwell_status": task_status,
                "backend_status": latest_task_attempt.get("backendStatus"),
                "logs": latest_task_attempt.get("backendLogs", {}).get("log", None),
            }
            task_execution_events = latest_task_attempt.get("executionEvents", None)
            if task_execution_events:
                task_dict["execution_events"] = task_execution_events
        else:
            task_dict = task_status

        calls_dict[call_name] = task_dict

    return calls_dict


async def loop_execution_status(submission_map_fp: str):
    """
    This function loops over the workflow IDs in the submission map and prints the status
    continually until all workflows are done.

    :param submission_map_fp: The path to the submission map file (created by submit.sh)
    """
    submit_fp = Path(submission_map_fp)
    # load all the workflow IDs that we want to monitor
    with open(submit_fp, "r") as f:
        submission_map = json.load(f)

    num_submissions = len(submission_map)

    # we want to keep track of whether we are on the first loop to overwrite stdout
    first_loop = True
    # keep track of the number of previous lines, again for overwriting stdout
    prev_line_count = 0
    prev_submissions = set()
    pbar = tqdm(total=num_submissions, desc="Workflow status", unit=" workflows")
    while True:
        # get the status of all the workflows
        async with ClientSession() as session:
            futures = []
            for pair in submission_map:
                t = asyncio.create_task(get_status(pair["workflow_id"], session))
                futures.append(t)
            # gather all the futures
            finished = await asyncio.gather(*futures)

        # create a single dictionary of all the workflow IDs and their statuses and
        # filter workflows that are not running
        status_dict = {
            k: v
            for d in finished
            for k, v in d.items()
            if v.get("status") != "Succeeded" and v.get("status") != "Failed"
        }

        iteration_submissions = set(status_dict.keys())
        pbar.update(num_submissions - len(status_dict))
        finished_submissions = list(prev_submissions.difference(iteration_submissions))
        if len(finished_submissions) > 0:
            pbar.write(f"Finished workflows: {finished_submissions} at {datetime.now()}")

        # break if there are no more workflows that have not "succeeded" or "failed"
        if len(status_dict) == 0:
            print("\x1b[1A\x1b[2K" * prev_line_count)
            print("All workflows are done!")
            break

        # get metadata of non-succeeded workflows only
        async with ClientSession() as session:
            futures = []
            # submit our futures
            for k in status_dict.keys():
                t = asyncio.create_task(get_metadata(k, session))
                futures.append(t)
            # gather all the futures
            finished = await asyncio.gather(*futures)

        # add a calls key for metadata about the latest calls
        for k, v in zip(status_dict.keys(), finished):
            status_dict[k]["calls"] = v

        # sort the workflows by their status
        sorted_status_dict = {
            k: v
            for k, v in sorted(status_dict.items(), key=lambda item: item[1]["status"])
        }

        fmt_status_dict = json.dumps(sorted_status_dict, indent=4)

        with open(f"{submit_fp.stem}_status.json", "w") as f:
            json.dump(sorted_status_dict, f, indent=4)

        # we want to erase what we wrote previously by sending the escape sequence
        # the number of times we wrote to stdout previously
        if not first_loop:
            print("\x1b[1A\x1b[2K" * prev_line_count)

        # print the status of the workflows
        print(fmt_status_dict)
        # update the number of lines we wrote to stdout
        first_loop = False
        prev_line_count = len(fmt_status_dict.splitlines()) + 1
        # pause for a bit
        await asyncio.sleep(15)


def main():
    parser = argparse.ArgumentParser(
        description="This script renders the execution " "status of the pipeline"
    )
    parser.add_argument(
        "workflow_id_file", help="Workflow ID map, generated by submit.sh", type=str
    )
    args = parser.parse_args()
    try:
        asyncio.run(loop_execution_status(args.workflow_id_file))
    except KeyboardInterrupt:
        print("KeyboardInterrupt received, exiting...")
        exit()


if __name__ == "__main__":
    main()
