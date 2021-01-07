#!/bin/sh
find . -name *.[c\|h] | xargs clang-format -i --style=file