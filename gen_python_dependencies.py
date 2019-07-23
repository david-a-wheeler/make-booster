#!/usr/bin/python3
"""
Generate Makefile dependencies of a Python program given as file $1.
WARNING: Do *NOT* use this on untrusted input, as it runs the code of $1.

The expectation is that this script will be run with input on some filename
BBB.py, and its output will go to deps/BBB.py.d
BBB will typically be a path including a directory. We intentionally do
*not* remove the directory, but instead create directories as needed,
so that we can easily handle multiple directories of code.

The idea is that a user of BBB.py will depend on the
'executable collection' (ec) deps/BBB.py.ec, which is changed every time:
    * the dependency data deps/BBB.py.d is changed.
      This should be already handled by the Makefile, and in particular
      this must always be forced to update whenever **/BBB.py itself changes.
    * The ec for every module directly imported by BBB.py is changed, e.g.,
      if BBB.py imports CCC, then we depend on deps/CCC.py.ec.
    * Any (optional) inputs used by BBB.py changes (as reported by INPUTS)

This output will contain the following:

For each CCC that BBB imports:
    deps/**/BBB.py.ec: deps/**/CCC.py.ec

If BBB set optional INPUTS:
    deps/**/BBB.py.inputs: BBB_INPUTS
    deps/**/BBB.py.ec: deps/**/BBB.py.inputs
"""

import sys
import os
import re

# Library importlib.util is quirky.  You can't just use importlib.util,
# because importlib.util.spec_from_file_location(...) may fail with:
# AttributeError: module 'importlib' has no attribute 'util'
# Instead, you have to use from...import for it to work. See:
# https://stackoverflow.com/questions/39660934/
# error-when-using-importlib-util-to-check-for-library

from importlib import util

# We will *ONLY* return dependencies in this directory or lower.
# It's odd, but it's a simple & effective way to exclude external packages.
REQUIRED_PATH_PREFIX = os.getcwd()

# This should have been a trivial program to write, but Python
# introspection didn't provide an easy way for me to do exactly
# what I wanted to do:
# * The built-in __import__ lets you easily find a specific global value,
#   such as INPUTS.  That enables us to have calculated INPUTS,
#   so we *do* use that to look for INPUTS.
#   However, __import__ does NOT let us discover imports of the form
#   "import XYZ from ABC", and it also fails on conditional imports
#   (and import that only occurs when some "if" condition is true).
# * ModuleFinder lets us discover *every* module that is imported,
#   even system modules.  However, it gives us too much of the wrong thing.
#   We can get *close* to what we want this way:
#   #####
#   from modulefinder import ModuleFinder
#   finder = ModuleFinder()
#   finder.run_script(python_file)
#   for key, mod in finder.modules.items():
#       if key != '__main__':
#           if not mod.__file__: # Built into Python (in C)?
#               return
#           if not mod.__file__.startswith(REQUIRED_PATH_PREFIX):
#               return
#           # We depend on mod.__file__ - but it may be indirect
#   #####
#   but this approach also includes the *indirect* dependencies.
#   That's a disaster because the more direct dependencies may change,
#   and if something is removed the Makefile could mysteriously stop working.
#   It also fails on conditional imports.
#   The approach discussed here is subject to many errors:
#   https://stackoverflow.com/questions/4922520/
#   determining-if-a-given-python-module-is-a-built-in-module
#
# So to find the imports we instead process the .py file as a text file,
# looking for "import NAME as", "import LIST" or "from NAME import LIST".
# We then use __import__ on each of those *imported* modules
# to see if they're in our current dir or below.
# Finally, if the file contains "INPUTS = ", we import the original file
# to get the value of INPUTS.
# This is much more reliable, and in particular, it handles Python applications
# that can't themselves be imported (since we only import what *they* import)
# as long as non-importable files don't define INPUTS.
# This seems more reliable than the alternatives.
# This does require "reasonable formatting", specifically, any one import
# MUST be on a single line and it must begin the line (after any indents).
# It fails on dynamically-generated imports, but at that point the user
# needs to step in :-).
# We *do* import the module to look for the INPUTS variable, since that
# allows INPUTS to be computed more flexibly.

def generate_import_dependency(python_file, module_name, line_number):
    "Generate dependency on module_name IF it's custom"
    clean_name = module_name.strip()
    try:
        mod = __import__(clean_name)
    except ModuleNotFoundError:
        print(f'{python_file}:{line_number} - ' \
              f'Error, module not found: {clean_name}', file=sys.stderr)
        exit(1)
    if '__file__' not in dir(mod): # Is it built into Python (in C)?
        return
    mod_file = mod.__file__
    if not mod_file.startswith(REQUIRED_PATH_PREFIX):
        return
    stripped_mod_file = mod_file[len(REQUIRED_PATH_PREFIX)+1:]
    # Generate deps/**/BBB.py.ec: deps/**/CCC.py.ec
    print(f'deps/{python_file}.ec: deps/{stripped_mod_file}.ec')

IMPORT_AS_PATTERN = re.compile(r'\s*import\s+([^;#]+)\s+as\s')
IMPORT_PATTERN = re.compile(r'\s*import\s+([^;#]+)')
FROM_IMPORT_PATTERN = re.compile(r'\s*from\s+([^\s;#]+)\s+import\s')
INPUTS_SET = re.compile(r'\s*INPUTS\s*=')
HAS_TESTS = re.compile(r'\s*def\s+test_')

def process_imports(python_file):
    "Generate dependencies for imports in python_file; returns if INPUT exists"
    inputs_was_set = False
    has_tests = False
    with open(python_file) as python_file_object:
        for line_number, line in enumerate(python_file_object):
            if re.match(INPUTS_SET, line):
                inputs_was_set = True
            if re.match(HAS_TESTS, line):
                has_tests = True
            # import MODULE_NAME as NAME
            results = re.match(IMPORT_AS_PATTERN, line)
            if results:
                module_name = results[1]
                generate_import_dependency(python_file, module_name, line_number)
                continue
            # import LIST
            results = re.match(IMPORT_PATTERN, line)
            if results:
                for module_name in results[1].split(','):
                    generate_import_dependency(python_file, module_name, line_number)
                continue
            # from MODULE_NAME import LIST
            results = re.match(FROM_IMPORT_PATTERN, line)
            if results:
                module_name = results[1]
                generate_import_dependency(python_file, module_name, line_number)
                # No need to continue, there are no other options
    if has_tests:
        # Tell Makefile that running "make test" should include this file.
        print(f'test: tested/{python_file}.test')
    return inputs_was_set

def process_inputs(python_file):
    "If python_file sets INPUTS, generate relevant dependencies"
    # We can't directly use this:
    #   input_module = __import__(python_file)
    # because __import__ requires a module name, not a file name.
    # So instead we have to resort to some complicated machinery to load it.
    module_name = os.path.basename(python_file).rstrip('.py')
    spec = util.spec_from_file_location(module_name, python_file)
    module = util.module_from_spec(spec)
    spec.loader.exec_module(module)
    # "module" is now the loaded form of python_file - do we have INPUTS?
    if 'INPUTS' in dir(module):
        # Generate .PHONY: **/BBB.py.inputs
        # print(f'.PHONY: {python_file}.inputs')
        announced_inputs = module.INPUTS
        if isinstance(announced_inputs, str):
            announced_inputs = list(announced_inputs)
        formatted_inputs = ' '.join(announced_inputs)
        # Generate deps/**/BBB.py.inputs: BBB_INPUTS
        print(f'deps/{python_file}.inputs: {formatted_inputs}')
        # Generate deps/**/BBB.py.ec: deps/**/BBB.py.inputs
        print(f'deps/{python_file}.ec: deps/{python_file}.inputs')

def main(python_file):
    "Main function"
    # Provide nice error report if file doesn't exist.
    if not os.path.isfile(python_file):
        print(f'File does not exist: {python_file}', file=sys.stderr)
        sys.exit(1)
    # We check for INPUTS and only process_inputs if it exists.
    # That way, if a Python program doesn't import cleanly, we can still
    # handle it as long as it doesn't define INPUTS
    inputs_was_set = process_imports(python_file)
    if inputs_was_set:
        process_inputs(python_file)

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f'{sys.argv[0]}: Error: requires exactly one argument')
        exit(1)
    main(sys.argv[1])
