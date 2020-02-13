# Make-booster

This project (contained in this directory and below)
provides utility routines intended to greatly simplify data processing
(particularly a data pipeline) using GNU make.
It includes some mechanisms specifically to help Python, as well
as general-purpose mechanisms that can be useful in any system.
In particular, it helps reliably *reproduce* results,
and it automatically determines what needs to run and runs only that
(producing a significant speedup in most cases).

# Specific capabilities

In particular:

* It provides mechanisms to ensure that
  if a Python script is modified (including one that is transitively
  included by other Python scripts), or its internal inputs are modified,
  all the processes that depend on that script (or internal inputs) are rerun.
  This dependency calculation for Python scripts is done automatically
  by a tool included in this pacakge.
* It provides general-purpose mechanisms to help do the same for
  other programming languages.
* By default it enables "Delete on Error" to avoid accidentally including
  corrupted data in final results.
* It supports "grouped targets" to correctly handle processes that generate
  multiple files, without requiring GNU make version 4.3 or later.
* It automatically runs tests as appropriate if some file is changed, but
  only if the test could change its results (by examining transitive
  dependencies).  We include default mechanisms for doing that in Python,
  and hooks to support other languages.
* It will run source code scans run as appropriate if a file
  is changed. It includes defaults to do that in Python and shell, and
  hooks to do that with other languages.

For example, imagine that Python file `BBB.py` says `include CC`, and
file `CC.py` reads from file `F.txt` (and `CC.py` declares its
INPUTS= as described below).
Now if you modify file `F.txt` or `CC.py`, any rule
that runs `BBB.py` will automatically be re-run in the correct order
when you use `make`, even if you didn't directly edit `BBB.py`.

In tests with over 1000 files the overhead for GNU make to figure out
"what to do" was only 0.07 seconds when there was nothing to do.
The first time you ever use it on a project there's some work for it to do
to record information, but that is a one-time cost and even that doesn't
take too long (depending on your project's size).

The approaches used here are not new to software development;
people who use compiled programming languages have used them for decades.
However, many people who use dynamic languages (like Python) to implement
data pipelines are unaware that these mechanisms exist, and we didn't
find ready-make mechanisms to do this for data processing pipelines.
So this is small set of tools on top of GNU make to do the same thing
for data pipelines as is already done for some projects that use
compiled languages.

## Installation

First, `cd` to the directory that contains your main `Makefile`.

Second, download `make-booster` to the `make-booster/` subdirectory, e.g.,
by using:

~~~~sh
git clone
https://github.com/david-a-wheeler/make-booster.git
~~~~

To use it, just add this line to your Makefile:

~~~~
include make-booster/booster.makefile
~~~~

If your source files are `scripts/` you're done; if not, set
`SRC_DIR` to the top level directory for scripts you want monitored for
changes.

In most cases you should also install a Python scanner (`pylint` by default),
shell scanner (`shellcheck` by default), and Python tester
(`pytest` by default).
If you don't like those defaults, set the Make variables
`PYTHON_SCANNER`, `SHELL_SCANNER`, and/or `PYTHON_TESTER` to your
values before including `booster.makefile`.

## Quickstart (how to use this)

### Creating rules with uses

Create Makefile rules as always, where you identify how to generate
some `RESULT` file given one or more `INPUT_FILES` and commands to do so.
In addition, for every Python script MYSCRIPT.py that your commands use,
add as an input `$(call uses,scripts/MYSCRIPT.py)`.
This means that many of your rules will look like this
(replacing `RESULT`, `INPUT_FILES`, and `MYSCRIPT` as needed):

~~~~
RESULT: \
  INPUT_FILES \
  $(call uses,scripts/MYSCRIPT.py)
	$(PYTHON3) scripts/MYSCRIPT.py < $< > $@
~~~~

The call to `uses` will mean that if any file changes that could cause
a change in the result of running `MYSCRIPT.py`, this rule will be re-run.
This dependency calculation of Python scripts is done automatically.

Beware: As with all makefiles, *do not* use filenames with spaces,
control characters, or shell metacharacters (e.g., "$", "#", and parentheses).
Your life will be better if you keep filenames simple.

### Delete on Error

By default this enables "Delete on Error" to avoid accidentally including
corrupted data in final results.  That means that if a rule fails,
the corrupted generated file will be deleted. If you want to keep
that file (e.g., for debugging), use `make KEEP_FILES_ON_ERROR=true ...`.

### Grouped targets

If two or more files (say BB and CC) are generated by a single command,
those generated files are called "grouped targets".
A common mistake when using Makefiles is write grouped targets this way:

~~~~Makefile
BB CC: DD EE # WRONG
<TAB>command
~~~~

This is a mistake because this notation
does *not* mean that “both BB and CC are simultaneously created
by running the command”.  Instead, it means, “If BB is out-of-date
with respect to DD and EE, then run command” and *separately*
“If CC is out-of-date with respect to DD and EE, then run command”.
This will run the command twice, at least doing twice as much work, and
if later rules depend on running command only once (as is often expected)
this can lead to subtle bugs.  For example, some rules may get data from
the first execution, and others may get data from the second, even though
you might have thought they'd get the same data.

GNU make version 4.3 (released on 2020-01-19) added direct
support for grouped targets using the “&:” syntax like this:

~~~~
BB CC &: DD EE
<TAB>command
~~~~

However, not everyone has GNU make 4.3 already installed.

If you want grouped targets, and you don't want to require
GNU make 4.3 or later, make-booster provides a solution.
Instead, when you have grouped targets, use the "grouped target" call
implemented by `make-booster`.
You do this by selecting some file name as a "marker" that the
command has been done and writing in this form:

~~~~
$(call grouped_target,BB CC,BBCC.marker)
BBCC.marker: .... # dependencies of process to generate BB and CC
<TAB>command to generate BB and CC
<TAB>touch $@
~~~~

For more information (including specifics of what it can do and how it works),
see [make-booster.md](make-booster.md).

### Python

If your Python program *internally* opens and reads a fixed filename
(one not noted on the command line), add the following:

~~~~
INPUTS = [ list_of_filenames_read ]
~~~~

You can use arbitrary Python expressions.
When the dependency system sees `INPUTS = ...`, it will run that file,
extract its value of INPUTS, and include that information in the
dependency system.

### Tools

By default this uses `pylint` to check Python program source code,
`shellcheck` to check shell source code, and
`pytest` to run Python tests.
You can configure all of them.

## Test suite

This package comes with a test suite inside the `tests/` subdirectory.
See `tests/test-setup.md` for instructions
on how to set up and run the test suite.
Once set up, you can use `cd tests; ./test-booster` to run the tests.

## License

This software is released under the MIT (expat) license, see
[LICENSE.txt](LICENSE.txt).

The original software is
(C) Copyright 2019-2020 Institute for Defense Analyses (IDA).
Its release as open source software (OSS) was approved on 2019-07-16.
As stated in DFARS 252.227-7014 (Rights in noncommercial computer software
and noncommercial computer software documentation),
the US federal government has unlimited rights in this computer software.
This applies to all of the code included here unless otherwise noted.
Unlimited rights means rights to use, modify, reproduce, release,
perform, display, or disclose computer software or computer software
documentation in whole or in part, in any manner and for any purpose
whatsoever, and to have or authorize others to do so.
