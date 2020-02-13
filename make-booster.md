# Advanced Data Pipelines Using Make

"Make-booster" is a makefile fragment intended to simplify
creating data pipelines with Python and GNU make.
In particular, it helps reliably *reproduce* results
and it automatically determines what needs to run.

Make-booster requires GNU make.
POSIX make simply doesn't have enough capabilities to enable
creating this in a reasonable amount of time.
Instead, we need various GNU make extensions.
In practice, most people who use make use GNU make.

See the README file for a brief description of what make-booster does,
how to install it, and a quickstart on how to use it.

This document provides much more detail on the background
(many data pipelines use make), the problems when doing so, and
technical specifics about how we implemented this.

## Background: Many data pipelines use make

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

For example, imagine we have a program `BBB.py` that includes a module CC,
module CC is implemented by file `CCC.py`, and
`CCC.py` internally has commands that read a fixed file `F.txt`.
A rule that runs `BBB.py` should depend not only on `BBB.py`, but also on
`CCC.py` and `F.txt`.
If this information is hand-maintained it is likely to go wrong.

This is exactly the kind of problem `make` is designed to handle,
but we did not find much literature on how to handle data pipelines
when using `make` and Python.
We were inspired by
["A Super-Simple Makefile for Medium-Sized C/C++ Projects"](https://spin.atomicobject.com/2016/08/26/makefile-c-projects/)
and
<http://make.mad-scientist.net/papers/advanced-auto-dependency-generation/>.
We use Python, and Python automatically handles import dependencies
when a program is *run*, but that is not enough to determine whether or
not a program should be run at all.

Note: We used GNU make extensions to implement this solution.
The POSIX standard for makefiles currently lacks too many capabilities
to be limited to it for this purpose.

## Solution: Source and executable contexts

Our solution is to add rules to compute a file's
"source context" (SC) and "executable context" (EC)
as part of automatically generating a file's "dependency information"
(.d file). We need to define these terms (where file BBB, etc.,
can be a relative directory structure):

* The source context (SC) of some file BBB is the set of files that,
  if changed, should cause re-execution of any source code scanner
  that examines file BBB and all its transitive dependencies.
  For example, if `BBB.py` includes module `CC` (stored in file `CC.py`),
  file `CC.py` includes module `DD` (stored in file `DD.py`),
  and `DD.py` when executed reads file `F.txt`, the source context (SC)
  of `BBB.py` is `CC.py DD.py` but not `F.txt`.
  In a makefile the SC of some file BBB is represented by the empty
  file `deps/BBB.sc`.
* The internal inputs of some file `BBB` is the set of files reported to
  be read by file `BBB`.
  In a makefile the internal inputs of some file BBB (if any) is represented
  by the empty file `deps/BBB.inputs`.
* The executable context (EC) of some file BBB is the set of files that,
  if changed, should cause re-execution of any command that runs BBB.
  Given the same scenario, the executable context of file `BBB.py` is
  is `CC.py DD.py F.txt`. Notice that the executable context (EC) is
  always the union of the files in the source context (SC) with the
  internal inputs of every file in the source context.
  In a makefile the EC of some file BBB is represented by the empty
  file `deps/BBB.ec`.
* The dependency file of some file BBB is a file that reports the
  dependencies of file BBB, and is normally automatically generated.
  Note that you need different tools to generate different dependency files
  (e.g., a tool for Python3 is needed for Python3 programs).
  Make-booster comes with a tool for Python3.
  In a makefile the dependency file of some file BBB is file `deps/BBB.d`,
  and that dependency file contains the dependency information.

## Convincing make to generate dependency data

We intentionally put all this information in the "deps/" subdirectory,
so that the repository is not littered by many subdirectories doing
different kinds of tracking.

We need rules for automatically generating dependency files and using them.

When GNU make runs, we tell it early on to "include" all of the
dependency files (`deps/*.d`) for corresponding .py (Python) files.
If there are any Python files, GNU make will try to load those dependency
files, and will regenerate them (using rules we provide) if the
dependency files don't exist or are older than their corresponding Python files.
Once GNU make generates the dependency files (if necessary), it will
load them and use that information to determine what to do next.

So early in `booster.makefile` we have this to tell GNU make
how to create our dependency files (.d files) for Python, where
`GEN_PYTHON_DEPENDENCIES` has the default value of
`make-booster/gen_python_dependencies.py`:

~~~~Makefile
deps/%.py.d: %.py
	$(MKDIR_P) $(dir $@)
        $(PYTHON3) $(GEN_PYTHON_DEPENDENCIES) $< > $@
~~~~

By default this uses a dependency generator program provided by `make-booster`.
This generator reads Python source code to find import statements,
then prints to standard output the dependency data in Makefile format.
This program is specific to Python; in general you need to use different
tools to report the dependencies for different languages.
This rule must be stated *before* we "include" dependency files
(GNU make needs to know the rule to create included files before
they are included, so that if the file is missing it knows how to create it).

We also need to tell make to use this dependency information. To do this,
booster.makefile has something like this (we've simplified it here):

~~~~Makefile
PYTHON_SRC := $(shell find $(SRC_DIR) -name '*.py')
PYTHON_DEPS := $(PYTHON_SRC:%.py=deps/%.py.d)
-include $(PYTHON_DEPS)
~~~~*

If you are adding another programming language named LANG, you would need to
add similar constructs.
Basically, add a new dependency target `deps/%.LANG.d: %.LANG`
with a similar rule for creating dependency files,
declare `LANG_SRC` and `LANG_DEPS` variables, and use `-include $(LANG_DEPS)`
to cause the system to generate and use those dependencies.
Of course, you'll also need a program that can read files in that
language to report its dependencies.
The information below, which shows how we do it for Python, should
be instructive on how to do it for other languages.

That is enough to get started, but there is a subtlety when
doing this for real.
We also need to declare the .sc, .ec, and .d files as make secondaries.
This has two effects.
First, these internal files in the `deps/ directory
will be considered a kind of intermediate file;
make won't bother creating or updating these files unless some *other*
file forces their creation or updating.
That way, merely creating the dependency or context data won't cause
the unnecessary execution of something else.
Second, they will not be deleted if they happen to be created
(this is a minor optimization).
This is true regardless of programming language, so we can use the
`ALL_SRC` value (which is set of the list of all source files)
to find them all:

~~~~Makefile
# Include dependencies in Makefile, and keep .sc, .ec, and .d files around
ALL_SCS := $(ALL_SRC:%=deps/%.sc)
ALL_ECS := $(ALL_SRC:%=deps/%.ec)
ALL_DEPS := $(ALL_SRC:%=deps/%.d)
# Disable deleting these; we use their presence to prevent unneeded rework
.SECONDARY: $(ALL_SCS) $(ALL_ECS) $(ALL_DEPS)
~~~~

If you're adding another language, you'll need to set `ALL_SRC`
to the other source files you're using.
Make-booster automatically includes .py and .sh files in the
source directory (by default `scripts`, but you can set it to something
else by setting `SRC_DIR`)


## Contents of dependency files for implementing contexts

Now that we've convinced GNU make to create dependency files,
we now need to discuss what those files must contain.
In particular, these dependency files must implement our contexts.

We do not need add anything more
to tell `make` that it should regenerate a dependency file
whenever a change occurs in the file it was created from.
The dependency-generation rule earlier declared that dependency.
For example, `deps/%.py.d: %.py` says that whenever the file `%.py`
changes, `make` must recreate the dependency file.

We need to implement the source context (SC). For file BBB, we implement
the source context as the file `deps/BBB.sc`, so within the dependency file
we need to say that `deps/BBB.sc` depends on BBB and on every file CCC
that is imported by BBB. We can implement the first part using a
pattern within `booster.makefile`, which will also generate our
marker file indicating that the source context is current up to that date
(note that this is a general rule; all source contexts depend at
least on the source file it represents):

~~~~
deps/%.sc: %
	$(MKDIR_P) $(dir $@)
	touch $@
~~~~

Note that this is truly generic; you don't need to modify this for
any particular programming language.

For the second part (dependency on every file CCC imported by BBB),
our Python dependency generator can generate these from each Python file BBB:

~~~~
deps/BBB.sc: deps/CCC.sc # For each import by BBB of another file CCC
~~~~

We also need to implement the executable context (EC), and we will
do it in similar way.
For file BBB, we implement
the executable context as the file `deps/BBB.ec`, so within the dependency file
we need to say that `deps/BBB.ec` depends on BBB, on every executable
context of each file CCC imported by BBB, and (if present)
every internal input declared by BBB.
The number of imports, internal inputs, or both could be zero.
We could make a cross-dependency from executable contexts to source
contexts, but we don't want to force creation of something when it is
not needed, so we will implement these as separate rules.
We will create general-purpose rules in `booster.makefile`
(again these are language-independent):

~~~~Makefile
# Executable context (.ec).
deps/%.ec: %
	$(MKDIR_P) $(dir $@)
	touch $@
# Special inputs
deps/%.inputs:
	$(MKDIR_P) $(dir $@)
	touch $@
~~~~

Our Python dependency generator will generate the following
from each Python file BBB:

~~~~
deps/BBB.ec: deps/CCC.ec # For each import by BBB of another file CCC

deps/BBB.ec: deps/BBB.inputs # If BBB has internal inputs
deps/BBB.inputs: FFF # For each import by BBB of another file FFF
~~~~

Detecting the imports chould be relatively easy to implement in
most languages in most cases, e.g., search for "import".
Detecting internal inputs is hard, so this to work
during automatic dependency generation, we need
a source code convention for reporting internal inputs.
In our make-booster package, our Python dependency generator
is named `gen_python_dependencies`.
It examines each given Python file BBB and
looks for a global variable named INPUTS, and if present,
it runs the file BBB and reads its results.

If a source file uses *dynamic* imports that isn't easy to automate.
We discourage dynamic imports, as that makes analysis in general difficult.
However, if you must do it, we need to be told what its result is.
E.g., the developer can hand-add to the makefile statements like this
to express that `WEIRD.py.sc` depends on surprise-dependency.py
in both its source context and executable context:

~~~~
deps/WEIRD.py.sc: surprise-dependency.py
deps/WEIRD.py.ec: surprise-dependency.py
~~~~

Users can also add such makefile statements for internal inputs,
but those are more common, so it made sense to implement specific support.

## Tests

In our terminology a "test" is some kind of dynamic execution of a
program, starting at some point, that returns 0 (no error) if there was
no problem and non-zero (error) if there was a problem.

We support `make test` to run all tests.
However, we only want tests to be run when there could be a different result.

We create test representation file "deps/BBB.test" every time a test succeeds
with BBB as the starting point for the test.
This test representation file depends on the executable context (ec)
of that file BBB.  This enables us to skip tests
that cannot have a changed answer (presuming the underlying environment
has not changed).  A test of BBB depends on the executable context of BBB.
Therefore, our rule is something like this in `booster.makefile`
(where `PYTHON_TESTER` defaults to `pytest`):

~~~~Makefile
deps/%.py.test: %.py deps/%.py.ec
	$(MKDIR_P) $(dir $@)
        $(PYTHON_TESTER) $< && touch $@
~~~~

If we only did that, nothing would ask that the corresponding test
would be executed, so we need more.

We use pytest for our Python test framework.
To support pytest,
our Python dependency generator looks for `def test_` in
a Python program, and if found in some file BBB, we include the
generated dependency file `deps/BBB.d` a rule that
`test` depends on `deps/BBB.test`, like this:

~~~~Makefile
test: deps/BBB.test # If BBB includes a test function.
~~~~

Our starting test rule simply provides a name to ensure that
"make test" can always be used:

~~~~Makefile
test:
~~~~

Now "make test" will run all depend on all the dependencies with a
test function, and pytest will be run on all them.
Tests will be skipped if there was no change in their executable context
(because if there is no change, the test results will be the same).
You can force re-running all tests by removing all `.test` files:

~~~~sh
find deps/ -name '*.test'  -exec rm {}+ \;
~~~~*

## Scans

In our terminology a "scan" is execution of all relevant
static source code analyzers.
We want to enable scanning source code using `make scan`.

A complication is that there are two kinds of source code analysis:

* A "single file" analyzer *only* looks at a single source
  file (the one it was told to analyze),
  and there is no kind of transitive analysis of other files
  when examining a particular file (e.g., shellcheck).
* A "transitive" analyzer may look at multiple source files when told
  to analyze at a single file, because it may do transitive analysis of
  other files referred to by the first file.
  Believe it or not, modern pylint is in this category.
  Pylint is *mostly* single file, but it does some import checks,
  which means that a change in any transitively-imported file
  can cause pylint to report a failure.

This is different from testing. Testing is always transitive, and is
also affected by the internal inputs of the program being tested.

We first need to tell the system what files we have scanners for.

~~~~
scan: $(patsubst %,deps/%.scan,$(PYTHON_SRC) $(SHELL_SRC))
~~~~

If you are adding your own language, you can simply state another
"scan:" rule with the set of files you can scan.

When adding a single file analyzer, you declare dependency *directly*
on the file being analyzed (scanned).
Here is the provided make-booster rule for scanning shell files
(the default value of `SHELL_SCANNER` is `shellcheck`,
a single file analyzer):

~~~~
deps/%.sh.scan: %.sh
        $(MKDIR_P) $(dir $@)
        $(SHELL_SCANNER) $< && touch $@
~~~~

When adding a transitive analyzer, you declare a dependency on the
source context of the given file.
Here is the provided make-booster rule for scanning Python files
(the default value of `PYTHON_SCANNER` is `pylint`,
which *does* check imports and is thus a transitive analyzer):

~~~~
deps/%.py.scan: deps/%.py.sc
        $(MKDIR_P) $(dir $@)
        $(PYTHON_SCANNER) $< && touch $@
~~~~

??? Clarify how to replace with another tool than pylint
??? Clarify how to add other languages
??? Clarify how to disable specific built-in tools & do something else

Scans are considered successful if they return no error (return code 0).
Once you've run a successful scan, that scan will not be run again
until you make a change that forces them to be re-run.
You can force re-running all scans by removing all `.scan` files:

~~~~sh
find deps/ -name '*.scan'  -exec rm {}+ \;
~~~~*

## Reporting scripts that commands depend on

Developers need to declare in their Makefiles the scripts a command uses.
Developers simply include this in their dependency list if they
depend on script BBB:

~~~~
$(call uses,BBB)
~~~~

For this to work the make-booster defines "uses", which gives the name
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

??? Use "exec" so running a scanner doesn't force execution of all else

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

Some `make` users would incorrectly write the following thinking that
this means that “both BB and CC are simultaneously created
by running the command”:

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

The bad news is that this doesn’t help us today, and using it requires that
all users of the Makefile have a version of GNU make with this support.

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

## Other comments

The `booster.makefile` intentionally has commands like mkdir and
touch on their own line instead of using `&&`.
GNU make runs simple commands by exec'ing them directly
(as an optimization), while more complex routines must be
run through a shell (and thus a shell has to start up and parse them).
Since these can happen many times, we intentionally use the simpler
form in many cases so that a shell
doesn't need to be invoked and process the command.
