#!/bin/sh
echo 'Building hello example with make on-device...'
cd /usr/examples/hello && /usr/bin/make
echo 'Running /usr/examples/hello/hello...'
/usr/examples/hello/hello
