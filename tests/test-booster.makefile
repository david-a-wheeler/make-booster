# Makefile for testing make-booster

all: check all-without-check
.PHONY: all

# Before we load booster.makefile, assign special settings so that our
# test framework will work properly (e.g., we're not one directory above it).
# It's important to do that in this makefile so that when debugging
# tests this makefile "just works".
SRC_DIR := test-src
GEN_PYTHON_DEPENDENCIES := ../gen_python_dependencies.py
ifdef PYTHONPATH
OLD_PYTHONPATH := :$(PYTHONPATH)
endif
export PYTHONPATH = test-src$(OLD_PYTHONPATH)

# Include the booster.makefile (the key thing we're testing!)
# Note that we use "../" instead of "make-booster/" because this test suite
# is *inside* the tests/ subdirectory.
include ../booster.makefile

# Now implement rest of makefile

check: $(if $(SKIP_SCANS),,scan) test
.PHONY: check

test-results/x.dat: $(call uses,test-src/show-args.sh)
	$(MKDIR_P) $(dir $@)
	test-src/show-args.sh this is a test > $@

test-results/bbb-output.dat: $(call uses,test-src/bbb.py)
	$(MKDIR_P) $(dir $@)
	$(PYTHON3) test-src/bbb.py > $@

# Produce combo.dat by running demonkey.sh with inputs x.dat and bbb-output.dat
test-results/combo.dat: \
  test-results/x.dat \
  test-results/bbb-output.dat \
  $(call uses,test-src/demonkey.sh)
	# The following debug line may help debug make-booster,
	# echo "Note: combo: uses expands to: $(call uses,test-src/demonkey.sh)"
	test-src/demonkey.sh $< $(word 2,$^) > $@

all-without-check: test-results/combo.dat
