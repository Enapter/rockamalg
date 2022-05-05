#!/bin/bash

set -eux

apk add zip

out_dir="/opt/res"
mkdir -p $out_dir && cd $out_dir

for arg in "$@"
do
    rock=${arg//@/ }
    luarocks install $rock
    luarocks pack $rock
done

luarocks-admin make-manifest $out_dir
