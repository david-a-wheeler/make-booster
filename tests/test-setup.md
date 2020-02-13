# Test setup

Make-booster includes a test suite.
You have to set things up little to run it.

We assume you're on a POSIX system (so shell is already available).

You need to install:
* python3
* pip3 (Python package installer),
* shellcheck (checks shell code)
* pylint (Python linter)
* pytest (Python test framework)

A helpful way to do this is to use "pipenv" (a Python package locking system);
this ensures that you get specific versions of Python packages
that are known to work. But you don't have to use pipenv.

Here are some option on Ubuntu (Fedora/RHEL/etc. are similar).

## Common commands

On Ubuntu you can run this to get some key packages:

~~~~
sudo apt-get install python3 python3-pip shellcheck
~~~~

## Using pipenv

You can use pipenv to install other programs.
The advantage is that you can get *exactly* the same versions
we tested with.

To install the rest with pipenv:

~~~~
# If .local/bin isn't already included by .profile, add it.
grep -q '\.local/bin' ~/.profile || cat >> ~/.profile << "END"
# set PATH so it includes user's private .local/bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi
END
# shellcheck source=/dev/null
. ~/.profile

# Install pipenv and the libraries it manages.
pip3 install pipenv

# This is clearer than pipenv install --ignore-pipfile
# This installs pylint and pytest
pipenv sync
~~~~

From then on, you can run the test suite by running this
(this will automatically use pipenv run if pylint is not available without it):

~~~~
./test-booster
~~~~

If you want to run make directly (e.g., while debugging tests) you'll
need to give some parameters, e.g.:

~~~~
PYTHONPATH='test-src' \
  pipenv run make -f booster.makefile SRC_DIR=test-src deps/test-src/bbb.py.ec
~~~~


## Without using pipenv

If you don't want to use pipenv, you can install pylint and pytest directly:

~~~~
pip3 install pylint pytest
~~~~


You can then run the test by running:

~~~~
./test-booster
~~~~

That looks easier (and it is),
but then there's no control over which version of
pylint and pytest you're running.
The test suite might not work the
same way with different versions of those tools. Good luck.
