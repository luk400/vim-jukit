import os
import sys
import json


def main():
    print("\nTEST RESULTS:")
    print("\n--------------------\n")
    dir_ = os.path.dirname(os.path.abspath(__file__))
    json_file = os.path.join(dir_, "..", "..", "tests", "jukit_tests_summary.json")

    with open(json_file, "r") as f:
        test_results = json.load(f)

    failed = []
    for k, v in test_results.items():
        has_failed = int(v[0]) == 0
        if has_failed:
            failed.append(k)

        fail_info =  f" - addidional info: \n    {v[1]}" if (len(str(v[1])) and has_failed) else ""
        print(f"Test '{k}' {'passed' if int(v[0]) == 1 else 'failed'}{fail_info}")

    print("\n--------------------\n")
    if len(failed):
        sys.tracebacklimit = 0
        raise Exception(f"The following tests have failed: {failed}")
    else:
        print("All tests passed!")


if __name__ == "__main__":
    main()
