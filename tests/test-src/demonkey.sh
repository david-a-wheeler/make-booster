#!/bin/sh

# Concatenate all listed files' contents except for lines with 'monkey'

grep -h -v 'monkey' "$@"
