import argparse
import json
from pathlib import Path


def open_json(fp):
    """
    Open a JSON file and return the object
    :param fp: The path to the object
    :return: The dictionary object
    """
    with open(fp, mode="r", encoding="utf-8") as open_file:
        obj = json.load(open_file)

    return obj


def main(
    source_json_fp: str, target_json_fp: str, key: str = "label", output_fp: str = None
):
    """
    Merge two JSON objects together. Used when you have failed tasks that you re-ran and
    want to merge the failed tasks' output JSON with the old one.

    :param source_json_fp: The source JSON file
    :param target_json_fp: The target JSON file (objects from this JSON array will overwrite source)
    :param key: The key to merge on, defaults to "label"
    :param output_fp: The output file path
    :return:
    """
    json_a = open_json(source_json_fp)
    json_b = open_json(target_json_fp)

    merged_json_obj = []
    for orig_obj in json_a:
        new_obj = (
            # find the object in json_b that has the same label as the original object
            next((item for item in json_b if item[key] == orig_obj[key]), None)
            # if it exists, use that object, otherwise use the original object
            or orig_obj
        )
        merged_json_obj.append(new_obj)

    # print the object to console (for jq)
    print(json.dumps(merged_json_obj, indent=2))


    final_fp = output_fp or f"merged_{Path(source_json_fp).name}"
    # write the object to a file
    with open(final_fp, "w") as f:
        f.write(json.dumps(merged_json_obj, indent=4))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        "Merge two JSON objects together. Used when you have failed tasks that you "
        "re-ran and want to merge the failed tasks' output JSON with the old one."
    )
    parser.add_argument("source", help="The source JSON file")
    parser.add_argument("target", help="The target JSON file (will be overwrite source)")
    parser.add_argument("--key", help="The key to use for merging", default="label")
    parser.add_argument("--output", help="The output file path", default=None)

    args = parser.parse_args()

    main(args.source, args.target, args.key)
