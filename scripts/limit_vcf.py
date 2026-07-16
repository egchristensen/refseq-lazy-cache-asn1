#!/usr/bin/env python3
"""Keep a valid VCF header and at most N data records from stdin."""

import argparse
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--max-records", type=int, required=True)
args = parser.parse_args()
if args.max_records < 1:
    parser.error("--max-records must be positive")

count = 0
for line in sys.stdin:
    if line.startswith("#"):
        sys.stdout.write(line)
    elif count < args.max_records:
        sys.stdout.write(line)
        count += 1
