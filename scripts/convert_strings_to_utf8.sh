#!/usr/bin/env bash

##  This script fixes wrong Localizable.strings encoding after pulling from Transifex
##  Usage: run from DashWallet root directory: ./scripts/convert_strings_to_utf8.sh

for f in $(find `pwd` -name '*.strings'); do
  vim +"set nobomb | set fenc=utf8 | x" $f
done
