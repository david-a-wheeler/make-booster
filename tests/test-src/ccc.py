#!/usr/bin/env python3

"This is module ccc, designed to test importing"

MONKEY_FILE = 'test-src/f.txt'
INPUTS = [MONKEY_FILE]

def monkey():
    "Trivial routine that reads MONKEY_FILE and prints its first line"
    with open(MONKEY_FILE, "r") as myfile:
        first_line = myfile.readline()
        print(first_line)

def test_trivial():
    "Trivial test that should always work."
    return True
