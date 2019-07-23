# Advanced Data Pipelines Using Make

"Make-booster" is a makefile fragment intended to simplify
creating data pipelines with Python and GNU make.
It requires GNU make.

In particular:

* If a Python script is modified (including one that is transitively
  included by other Python scripts),
  all the processes that depend on that script are rerun.
  This dependency calculation of Python scripts is done automatically.
* Tests and source code scans will be also run if a Python file is changed.
* We enable "Delete on Error" to avoid accidentally including
  corrupted data in final results.
* We support "grouped targets" to correctly handle processes that generate
  multiple files.

To use it, just add this to your Makefile:

~~~~
include make-booster/booster.makefile
~~~~

The text below tries to first describe the problems we're trying to solve,
then it discusses how we solve them.

## Many data pipelines use make

Many projects involve a "data pipeline" that
loads multiple data sources, processes them
through potentially multiple stages, and produces a result.

A common and useful way to handle data pipelines is to use
`make` (typically GNU make).
With `make` you can easily specify what depends on what;
`make` will then run only the programs necessary to run, in the right order,
and it has built-in support for parallel computing.
Examples of using `make` in data processing include
["Reproducible bioinformatics pipelines using Make" by Byron J. Smith](http://byronjsmith.com/make-bml/),
["make: intelligent plumbing for your analysis pipeline"](https://blogs.aalto.fi/marijn/2016/02/19/make-intelligent-plumbing-for-your-analysis-pipeline/).
["Why Use Make" by Mike Bostock (2013)](https://bost.ocks.org/mike/make/),
(which discusses using make in a data transformation process),
["Make for Data Scientists" by Paul Butler (2012-10-15)](http://blog.kaggle.com/2012/10/15/make-for-data-scientists/),
["Cookiecutter Data Science" from DrivenData](https://drivendata.github.io/cookiecutter-data-science/),
and
["Minimal make"](https://kbroman.org/minimal_make/).

Our overall goal is to ensure that we can reliably *reproduce*
our results.  This lets us justify our results and
clearly documents all our assumptions
(all real work *must* have assumptions - the issue is to document them).
Where applicable we consider the recommendations in
["Good Enough Practices in Scientific Computing" by Greg Wilson, Jennifer Bryan, Karen Cranston, Justin Kitzes, Lex Nederbragt, and Tracy K. Teal, published June 22, 2017 (preprint 14 Oct 2016), PLoS Computational Biology](https://arxiv.org/pdf/1609.00037v2.pdf) or
https://journals.plos.org/ploscompbiol/article?id=10.1371/journal.pcbi.1005510 .

## Problem

However, data processing steps often involve complications that
are not widely discussed in the literature.

For example, imagine we have a program `BBB.py` that includes `CCC.py`, and
`CCC.py` internally has commands that read a fixed file `F.txt`.
A rule that runs `BBB.py` should depend not only on `BBB.py`, but also
`CCC.py` and `F.txt`, and if this information is
hand-maintained it is likely to go wrong.

This is exactly the kind of problem `make` is designed to handle,
but we did not find much literature on how to handle data pipelines.
We were inspired by
["A Super-Simple Makefile for Medium-Sized C/C++ Projects"](https://spin.atomicobject.com/2016/08/26/makefile-c-projects/)
and
http://make.mad-scientist.net/papers/advanced-auto-dependency-generation/ .
We use Python, and Python automatically handles import dependencies
when a program is *run*, but that is not enough to determine whether or
not a program should be run at all.

Note: We used GNU make extensions to implement this.
The POSIX standard for makefiles currently lacks too many capabilities
to be limited to it for this purpose.

## Executable contexts

Our solution is to add rules to document a program's
"executable context" (EC).
The EC of some file BBB is the set of files that, if changed,
should cause re-execution of any command that runs BBB.

In practice, we implement the EC of file BBB as the file "deps/BBB.ec",
which in turn depends on the following:

1. the dependency data file "deps/BBB.d".
   This automatically-generated file reports dependencies in Makefile format,
   and this dependency data file depends on file BBB.
2. The EC for every module directly imported by BBB.
   So if BBB imports CCC, then deps/BBB.ec depends on deps/CCC.ec.
3. Any (optional) inputs read by BBB.py during execution.
   These are called "special inputs" and are represented as `deps/BBB.inputs`.
   These will be found by a program that looks for them
   during automatic dependency generation.  For this to work we need
   a source code convention for reporting special inputs;
   in Python programs we look for a global variable named INPUTS.

We need a rule for creating the files that represent
executable contexts and special inputs:

~~~~
# Executable context (.ec).
deps/%.ec: deps/%.d
	$(MKDIR_P) $(dir $@)
	touch $@
# Special inputs
deps/%.inputs:
	$(MKDIR_P) $(dir $@)
	touch $@
~~~~


We need rules for automatically generating dependency files.

~~~~
# Dependency file, which is auto-generated and loaded into the Makefile.
# This is only for Python3; other rules would be needed for other languages.
deps/%.py.d: %.py
	$(MKDIR_P) $(dir $@)
	$(PYTHON3) make-booster/gen_python_dependencies.py $< > $@
~~~~

We created a `make-booster/gen_python_dependencies.py` file
that reads source code to find import statements,
and then prints to standard output its dependency data in Makefile format.

We need to have the Makefile use this dependency information.
We first need to identify the source code, e.g.,

~~~~Makefile
PYTHON_SRC := $(shell find $(SRC_DIR) -name '*.py')
SHELL_SRC := $(shell find $(SRC_DIR) -name '*.sh')
ALL_SRC := $(PYTHON_SRC) $(SHELL_SRC)
~~~~

and later read them in.
We also need to declare the .ec and .d files as secondaries so that they
are not deleted once their processing is done.

~~~~
# Include dependencies in Makefile, and keep .de and .ec files
PYTHON_ECS := $(PYTHON_SRC:%.py=deps/%.py.ec)
PYTHON_DEPS := $(PYTHON_SRC:%.py=deps/%.py.d)
# Disable deleting these; we use their presence to prevent unneeded rework
.SECONDARY: $(PYTHON_ECS) $(PYTHON_DEPS)

-include $(PYTHON_DEPS)
~~~~

## Tests

We support `make test` to run all tests.
However, we only want tests to be run when there could be a different result.

We create test representation file "tested/BBB.test" every time a test succeeds
with BBB as the starting point.  That enables us to skip tests
that cannot have a changed answer (presuming the underlying environment
has not changed).  A test of BBB depends on the executable context of BBB.
Therefore, our rule is:

~~~~
tested/%.py.test: %.py deps/%.py.ec
	$(MKDIR_P) $(dir $@)
	pytest $< && touch $@
~~~~

Our Python dependency generator looks for `def test_` in
a Python program, and if found in some file BBB, we add a rule that
`test` depends on `tested/BBB.test` as part of its `.d` file that
is already included.

Our starting test rule simply provides a name to ensure that
"make test" can always be used:

~~~~
test:
~~~~

## Scans

We want to enable scanning source code using `make scan`.
We expressly list the kinds of files we have scanners for.

~~~~
scan: $(patsubst %,scanned/%.scan,$(PYTHON_SRC) $(SHELL_SRC))
~~~~

Here is a rule for scanning with pylint
(which does not do any imports):

~~~~
scanned/%.py.scan: %.py
	$(MKDIR_P) $(dir $@)
	pylint $< && touch $@
~~~~

Here is a rule for scanning shell files with shellcheck:

~~~~
scanned/%.sh.scan: %.sh
	$(MKDIR_P) $(dir $@)
	shellcheck $< && touch $@
~~~~


## Reporting scripts that commands depend on

We need developers to report the scripts a command uses.
Developers simply include this in their dependency list if they
depend on script BBB:

~~~~
$(call uses,BBB)
~~~~

For this to work we must define "uses", which gives the name
of the file representing the provided file's executable context.

In practice, we modify "uses" to also provide the name of the
file that represents a successful scan (unless `SKIP_SCANS` is set);
this requires a successful source code scan before the rule can be run
(encouraging people to fix their scan problems).

One annoyance: People often put a space after a comma, and GNU make
interprets this as a filename with a leading space.
We use `strip` so a space after a comma is not misinterpreted.

~~~~
uses = deps/$(strip $(1)).ec $(if $(SKIP_SCANS),,scanned/$(strip $(1)).scan)
~~~~

## Resulting rules

The expected result is a large Makefile with many rules,
where each rule looks like this:

~~~~
RESULT.csv: \
  INPUT.csv \
  $(call uses,scripts/MYSCRIPT.py)
	$(PYTHON3) scripts/MYSCRIPT.py < $< > $@
~~~~

## Delete on Error

By default this sets `.DELETE_ON_ERROR`.

As the GNU Make documentation says:
"Usually when a recipe line fails, if it has changed the target file
at all, the file is corrupted and cannot be used—or at least it is
not completely updated. Yet the file’s time stamp says that it is
now up to date, so the next time make runs, it will not try to update
that file. The situation is just the same as when the shell is killed
by a signal; see Interrupts. So generally the right thing to do is to
delete the target file if the recipe fails after beginning to change the
file. make will do this if .DELETE_ON_ERROR appears as a target. This is
almost always what you want make to do, but it is not historical practice;
so for compatibility, you must explicitly request it."
https://www.gnu.org/software/make/manual/html_node/Errors.html#Errors

If you need to see the file generated during an error, use:
`make KEEP_FILES_ON_ERROR=true ...`

## Grouped targets

This also implements grouped targets.
If two or more files (say BB and CC) are generated by a single command,
have them all depend on and generate a "marker" (sentinel) like this:

~~~~
$(call grouped_target,BB CC,BBCC.marker)
BBCC.marker: .... # dependencies of process to generate BB and CC
<TAB>command to generate BB and CC
<TAB>touch $@
~~~~

If you incorrectly write:

~~~~
BB CC: DD EE
<TAB>command
~~~~

That does *not* mean that “both BB and CC are simultaneously created
by running the command”.  Instead, it means, “If BB is out-of-date
with respect to DD and EE, then run command” and *separately*
“If CC is out-of-date with respect to DD and EE, then run command”.
In short, the command may run *twice*, and that can result in a completed make
run *without* the correct final results (!).

If what you meant was “BB and CC are simultaneously created by
running command”, then what you want is a “grouped target”.
The good news is that a future version of GNU make will include direct
support for grouped targets using the “&:” syntax like this:

~~~~
BB CC &: DD EE
<TAB>command
~~~~

The bad news is that this doesn’t help us today.
Currently, if you want a grouped target, you need to create an
intermediary marker (aka sentinel) that indicates
that all the grouped targets were
created, and then create the single intermediary target with the command
of the group.  It doesn’t matter what the marker is named as long as
it’s not used elsewhere, though a clear name that isn’t TOO long is
a good idea.

The obvious way to implement a marker (aka sentinel) has this form:

~~~~
BB CC: marker ;
marker: DD EE ...
~~~~

however, as noted in _The GNU Make book_ by John Graham-Cumming (2015)
page 96, this has a problem.  If you delete a file that *depends*
on the marker (sentinel), you must also delete the marker or the files
won't be rebuilt.

Using `grouped_target` instead solves this problem.
