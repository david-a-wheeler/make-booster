##########################################################################
#
# "include" this makefile to simplify some kinds of data processing.
# This requires GNU make.
#
##########################################################################
# The following are generic automation mechanisms so that
# the "right things" will happen in the right order when using Python.
# We use various mechanisms so others can easily incorporate
# other languages, tools, etc. For example "?=" sets a default, which
# you can override by simply setting it to a different value before
# including this file.

# Ensure that the "all" rule is the first rule seen.
# We recommend that users set their default rule themselves, but
# we want to prevent unintentional traps for the unwary.
# That way, if this is the first included file, the traditional "all" rule
# is the default. Users of this makefile can choose the default rule
# by listing it before using "include" or by setting ".DEFAULT_GOAL".
all:

PYTHON3 ?= python3
MKDIR_P ?= mkdir -p

GEN_PYTHON_DEPENDENCIES ?= make-booster/gen_python_dependencies.py

# First, identify the source code we're dealing with
SRC_DIR ?= scripts
PYTHON_SRC := $(shell find $(SRC_DIR) -name '*.py')
SHELL_SRC := $(shell find $(SRC_DIR) -name '*.sh')

# Set ALL_SRC := ... before including this file if you want to add
# other source files.
ifndef ALL_SRC
ALL_SRC :=
endif
ALL_SRC += $(PYTHON_SRC) $(SHELL_SRC)

# "make scan" runs static analysis tools on source code, basically
# running linters that look for style problems & common code errors.
# We create a "check/BASENAME.check" file every time we succeed so we
# we can skip unchanged files.

# If not set otherwise, use shellcheck as the shell scanner.
# To *disable* SHELL_SCANNER, set it to ":"
SHELL_SCANNER ?= shellcheck

# Scan a shell program with SHELL_SCANNER (shellcheck), record its results.
# Note that shellcheck *only* looks at the one file being scanned,
# so we depend on just that file not its source context.
ifneq ($(SHELL_SCANNER),:)
deps/%.sh.scan: %.sh
	$(SHELL_SCANNER) "$*.sh"
	@$(MKDIR_P) $(dir $@)
	@touch $@
endif

# If not set otherwise, use pylint as the python scanner.
# To *disable* PYTHON_SCANNER, set it to ":"
PYTHON_SCANNER ?= pylint

# Scan a Python program with PYTHON_SCANNER, record its results
# Note: newer versions of pylint *do* check imports.
# Therefore, pylint needs to depend on the source context, not just that file.
ifneq ($(SHELL_SCANNER),:)
deps/%.py.scan: deps/%.py.sc
	$(PYTHON_SCANNER) "$*.py"
	@$(MKDIR_P) $(dir $@)
	@touch $@
endif

# Invoke the correct scanners for each type of source file.
# We expressly list the kinds of files we have scanners for.
# IF you add your own languages, add "scan" entries if you can scan them.
.PHONY: scan
ifndef SKIP_SCANS
scan: $(patsubst %,deps/%.scan,$(PYTHON_SRC))
scan: $(patsubst %,deps/%.scan,$(SHELL_SRC))
endif

# If not set otherwise, use pytest as the Python tester.
PYTHON_TESTER ?= pytest

# We create a "deps/BBB.test" file every time a test succeeds
# with BBB as the starting point.  That enables us to skip tests
# that cannot have a changed answer (presuming the underlying environment
# has not changed).  The test of a given Python program depends
# most importantly on the file called for the test, but it also depends on
# that script's entire executable context (if a module we import changes,
# it may cause the program to fail). The .ec includes the .py file, but
# it's convenient to list it separately so that we can use "$<".

deps/%.py.test: %.py deps/%.py.ec
	$(PYTHON_TESTER) "$*.py"
	@$(MKDIR_P) $(dir $@)
	@touch $@

# "make test" runs all tests (testing is a kind of dynamic analysis).
# To add a file to the set of programs to use for testing, add a rule
# so "test" depends on it (e.g., "test: FILE_TO_RUN_AS_TEST").
# How the test is *run* depends on the deps/*.test rule, e.g,
# we test programs ending in ".py" by running "pytest" on them.
# We automatically detect Python programs with tests;
# scripts/gen_python_dependencies.py looks for "def test_...".
# Ideally all Python scripts would be testable, but that requires that they
# be importable (able to be "import"ed without running anything important).
# In addition, pytest considers "no test found" to be an error.
# The scripts/gen_python_dependencies.py file adds dependencies.
# This is empty here, because other rules (including automatically
# generated ones) add the needed dependencies.
.PHONY: test
test:

deps/%.check: deps/%.scan deps/%.test
	@$(MKDIR_P) $(dir $@)
	@touch $@

# Automatically compute dependencies so we will correctly re-run
# whatever data processing needs rerunning (and ideally nothing else).
# E.g., if some process rule runs BBB.py, and
# "BBB.py" imports "CCC" (stored in "CCC.py"), and CCC.py internally
# loads as input some file CCCF1.txt, but CCCF1.txt changes after that
# process ran, then we should rerun that process rule.
#
# These rules were inspired by
# "A Super-Simple Makefile for Medium-Sized C/C++ Projects"
# https://spin.atomicobject.com/2016/08/26/makefile-c-projects/
# and
# http://make.mad-scientist.net/papers/advanced-auto-dependency-generation/

# Source context (.sc). An sc (say deps/BBB.sc) represents
# all of the source files transitively included when examining the source
# files of BBB, but does *not* include run-time inputs.
deps/%.sc: %
	@$(MKDIR_P) $(dir $@)
	@touch $@

# Executable context (.ec). An ec (say deps/BBB.ec) represents
# all of the files transitively depended on when running BBB.
deps/%.ec: %
	@$(MKDIR_P) $(dir $@)
	@touch $@

# Dependency file, which is auto-generated and loaded into the Makefile.
# This is only for Python3; other rules would be needed for other languages.
# We *do* show execution of GEN_PYTHON_DEPENDENCIES, because on a big system
# doing this the first time (or after a change to all source files) will
# take a while, and we want the user to know what is going on.
deps/%.py.d: %.py
	@$(MKDIR_P) $(dir $@)
	$(PYTHON3) $(GEN_PYTHON_DEPENDENCIES) "$<" > "$@"

# This represents the set of INPUTS loaded by a file (if any)
# We're typically informed about these via a deps/**.d dependency file.
deps/%.inputs:
	@$(MKDIR_P) $(dir $@)
	@touch $@

# Include dependencies in Makefile, and keep .sc, .ec, and .d files around
ALL_SCS := $(ALL_SRC:%=deps/%.sc)
ALL_ECS := $(ALL_SRC:%=deps/%.ec)
ALL_DEPS := $(ALL_SRC:%=deps/%.d)
ALL_TEST := $(ALL_SRC:%=deps/%.test)
ALL_SCAN := $(ALL_SRC:%=deps/%.scan)
ALL_CHECK := $(ALL_SRC:%=deps/%.check)
# Disable deleting these; we use their presence to prevent unneeded rework
.SECONDARY: $(ALL_SCS) $(ALL_ECS) $(ALL_DEPS)
.SECONDARY: $(ALL_TEST) $(ALL_SCAN) $(ALL_CHECK)

# Automatically include (and thus compute) Python dependencies.
PYTHON_DEPS := $(PYTHON_SRC:%.py=deps/%.py.d)
ifndef SKIP_DEPS
-include $(PYTHON_DEPS)
endif

# GNU make function: Given $(1), a SINGLE source file we run, return
# its executable chain (ec) representation "deps/NAME.ec" so it
# can be added as a dependency.
# The "$(strip ...)" call removes leading space; without it, a call with
# space after comma such as "$(call uses, NAME)" would cause a weird failure.
# The .ec file in turn depends on that source file, and transitively
# all source files and internal inputs it depends on.
#
# If "REQUIRE_SCANS" is set, run scans before running the program.
# Note that if REQUIRE_SCANS is set, and a scan hasn't be run for a program,
# all processes that depend on the program will be re-rerun EVEN IF
# the scan was successful.
# At one time we forced scanning of a process using this construct:
# $(if $(SKIP_SCANS),,deps/$(strip $(1)).scan)
# That forces scanning the program before running a process
# that uses the program. However, that means that if a scan must be rerun,
# everything using that program would be re-run, *even* if the scan reported
# no problems, and that unexpected execution could itself be a problem.
# The "obvious" solution would be to insert "|" in front of "deps/",
# to make this an "order-only-prerequisite". That would be perfect
# *except* that you then can't use any other statement after this "uses",
# including other uses. We also tried to use eval to do this:
# $(eval $@ : | deps/$(strip $(1)).check)
# However, this fails because "prerequisites cannot be defined in recipes.".
# Another challenge is that not all programs have tests, so depending
# on its corresponding ".check" file for every program is fraught.
# So we've changed it so the default is not to scan, but scans can be
# added if needed.
uses = deps/$(strip $(1)).ec \
       $(if $(REQUIRE_SCANS),deps/$(strip $(1)).scan,)

# Set ".DELETE_ON_ERROR" by default to prevent nasty problems.
# If you need to see the file generated during an error, use:
# make KEEP_FILES_ON_ERROR=true ...
# As the GNU Make documentation says:
# "Usually when a recipe line fails, if it has changed the target file
# at all, the file is corrupted and cannot be used—or at least it is
# not completely updated. Yet the file’s time stamp says that it is
# now up to date, so the next time make runs, it will not try to update
# that file. The situation is just the same as when the shell is killed
# by a signal; see Interrupts. So generally the right thing to do is to
# delete the target file if the recipe fails after beginning to change the
# file. make will do this if .DELETE_ON_ERROR appears as a target. This is
# almost always what you want make to do, but it is not historical practice;
# so for compatibility, you must explicitly request it."
# https://www.gnu.org/software/make/manual/html_node/Errors.html#Errors
ifndef KEEP_FILES_ON_ERROR
.DELETE_ON_ERROR:
endif

# Implement grouped targets.
# If two or more files (say BB and CC) are generated by a single command,
# have them all depend on and generate a "marker" (sentinel) like this:
#
# $(call grouped_target,BB CC,BBCC.marker)
# BBCC.marker: .... # dependencies of process to generate BB and CC
# <TAB>command to generate BB and CC
# <TAB>touch $@
#
# If you incorrectly write:
# BB CC: DD EE
# <TAB>command
# That does *not* mean that “both BB and CC are simultaneously created
# by running the command”.  Instead, it means, “If BB is out-of-date
# with respect to DD and EE, then run command” and *separately*
# “If CC is out-of-date with respect to DD and EE, then run command”.
# In short, the command may run *twice*, and that can result in a completed make
# run *without* the correct final results (!).
#
# If what you meant was “BB and CC are simultaneously created by
# running command”, then what you want is a “grouped target”.
# The good news is that GNU make version 4.3 includes direct
# support for grouped targets using the “&:” syntax like this:
# BB CC &: DD EE
# <TAB>command
# The bad news is that many don't have GNU make version 4.3 or later.
#
# If you want a grouped target, and you lack GNU make version 4.3 or later,
# you need to create an intermediary marker (aka sentinel) that indicates
# that all the grouped targets were
# created, and then create the single intermediary target with the command
# of the group.  It doesn’t matter what the marker is named as long as
# it’s not used elsewhere, though a clear name that isn’t TOO long is
# a good idea.
# The obvious way to implement a marker (aka sentinel) has this form:
# BB CC: marker ;
# marker: DD EE ...
# however, as noted in _The GNU Make book_ by John Graham-Cumming (2015)
# page 96, this has a problem.  If you delete a file that *depends*
# on the marker (sentinel), you must also delete the marker or the files
# won't be rebuilt.  This function resolves the problem by automatically
# deleting the marker when it needs to be deleted.

grouped_target = $(eval $(strip $1): $(strip $2) ; @:)$(foreach f,$1,$(if $(wildcard $f),,$(shell rm -f $2)))
