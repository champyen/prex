#!/bin/sh
find . -name *.[c\|h] | xargs clang-format -i --style="{BasedOnStyle: WebKit, SortIncludes: false}"