#!/usr/bin/env python3

"This is Test module bbb, a top-level Python file that imports ccc"

import sys
import ccc

def main():
    "Main function"
    if len(sys.argv) != 1: # Must "import sys" to do this
        print(f'{sys.argv[0]} takes no arguments', file=sys.stderr)
        sys.exit(1)
    ccc.monkey()
    print("Main run")

if __name__ == "__main__":
    main()
