##########################################################################
#
# "include" this makefile to simplify some kinds of data processing.
# This requires GNU make.
#
##########################################################################
# The following are generic automation mechanisms so that
# the "right things" will happen in the right order when using Python.

PYTHON3 ?= python3
MKDIR_P ?= mkdir -p

GEN_PYTHON_DEPENDENCIES ?= make-booster/gen_python_dependencies.py

# First, identify the source code we're dealing with
PYTHON_SRC := $(shell find $(SRC_DIR) -name '*.py')
SHELL_SRC := $(shell find $(SRC_DIR) -name '*.sh')
ALL_SRC := $(PYTHON_SRC) $(SHELL_SRC)

# "make scan" runs static analysis tools on source code, basically
# running linters that look for style problems & common code errors.
# We create a "check/BASENAME.check" file every time we succeed so we
# we can skip unchanged files.

# If not set otherwise, use pylint as the python scanner.
PYTHON_SCANNER ?= pylint

# Scan a Python program with PYTHON_SCANNER, record its results
# Note: pylint does *NOT* do any imports, nor does it run code.
# Therefore, pylint depends *only* on the file it's asked to scan, and
# not on anything that the file imports.
# If we used multiple tools, and some did transitive scans & others did
# intranisive scans, then .scan would need to be declared as SECONDARY and
# depend on .tran and .intran.  There's no need for that complexity.
scanned/%.py.scan: %.py
	$(MKDIR_P) $(dir $@)
	$(PYTHON_SCANNER) $< && touch $@

# If not set otherwise, use pylint as the python scanner.
SHELL_SCANNER ?= shellcheck

# Scan a shell program with shellcheck, record its results
scanned/%.sh.scan: %.sh
	$(MKDIR_P) $(dir $@)
	$(SHELL_SCANNER) $< && touch $@

# Invoke the correct scanners for each type of source file.
# We expressly list the kinds of files we have scanners for.
# TODO: scan scripts/download-patents
.PHONY: scan
scan: $(patsubst %,scanned/%.scan,$(PYTHON_SRC) $(SHELL_SRC))

# We create a "tested/BBB.test" file every time a test succeeds
# with BBB as the starting point.  That enables us to skip tests
# that cannot have a changed answer (presuming the underlying environment
# has not changed).  # The test of a given Python program depends
# most importantly on the file called for the test, but it also depends on
# that script's entire executable context (if a module we import changes,
# it may cause the program to fail).

tested/%.py.test: %.py deps/%.py.ec
	$(MKDIR_P) $(dir $@)
	pytest $< && touch $@

# "make test" runs all tests (testing is a kind of dynamic analysis).
# To add a file to the set of programs to use for testing, add a rule
# so "test" depends on it (e.g., "test: FILE_TO_RUN_AS_TEST").
# How the test is *run* depends on the tested/*... rule, e.g,
# we test programs ending in ".py" by running "pytest" on them.
# We automatically detect determine Python programs with tests;
# scripts/gen_python_dependencies.py looks for "def test_...".
# Ideally all Python scripts would be testable, but that requires that they
# be importable (able to be "import"ed without running anything important).
# In addition, pytest considers "no test found" to be an error.
# The scripts/gen_python_dependencies.py file adds
# This is empty here because other rules (including automatically
# generated ones) add the needed dependencies.
.PHONY: test
test:

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

# Executable context (.ec). An ec (say deps/BBB.ec) represents
# all of the files transitively depended on when running BBB.
deps/%.ec: deps/%.d
	$(MKDIR_P) $(dir $@)
	touch $@

# Dependency file, which is auto-generated and loaded into the Makefile.
# This is only for Python3; other rules would be needed for other languages.
deps/%.py.d: %.py
	$(MKDIR_P) $(dir $@)
	$(PYTHON3) $(GEN_PYTHON_DEPENDENCIES) $< > $@

# This represents the set of INPUTS loaded by a file (if any)
# We're typically informed about these via a deps/**.d dependency file.
deps/%.inputs:
	$(MKDIR_P) $(dir $@)
	touch $@

# Include dependencies in Makefile, and keep .de and .ec files
PYTHON_ECS := $(PYTHON_SRC:%.py=deps/%.py.ec)
PYTHON_DEPS := $(PYTHON_SRC:%.py=deps/%.py.d)
# Disable deleting these; we use their presence to prevent unneeded rework
.SECONDARY: $(PYTHON_ECS) $(PYTHON_DEPS)

ifndef SKIP_DEPS
-include $(PYTHON_DEPS)
endif

# GNU make function: Given $(1), a SINGLE source file we run, return
# its executable chain (ec) representation "deps/NAME.ec".
# The "$(strip ...)" call removes leading space; without it,
# space after comma in "$(call uses, NAME)" would cause a weird failure.
# We also add dependency on "scanned..."; we don't have to do this,
# but doing this means that every file must pass a scan before we run it
# (this will encourage people to fix scan problems ASAP).
uses = deps/$(strip $(1)).ec $(if $(SKIP_SCANS),,scanned/$(strip $(1)).scan)

# Debug makefile - print out PYTHON_DEPS
debug_python_deps:
	@echo "$(PYTHON_DEPS)"

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

# Implemented grouped targets.
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
# The good news is that a future version of GNU make will include direct
# support for grouped targets using the “&:” syntax like this:
# BB CC &: DD EE
# <TAB>command
#
# The bad news is that this doesn’t help us today.
# Currently, if you want a grouped target, you need to create an
# intermediary marker (aka sentinel) that indicates
#  that all the grouped targets were
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
# won't be rebuilt.

grouped_target = $(eval $(strip $1): $(strip $2) ; @:)$(foreach f,$1,$(if $(wildcard $f),,$(shell rm -f $2)))
