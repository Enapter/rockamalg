#!/bin/bash

set -eux

out_dir="/opt/res"
cd $out_dir

install_cmd=""
pack_cmd=""
sep=""

for arg in "$@"
do
    rock=${arg//@/ }
    install_cmd+=" $sep luarocks install --keep $rock"
    pack_cmd+=" $sep luarocks pack $rock"
    sep="&&"
done

apk add zip && $install_cmd && $pack_cmd && luarocks-admin make-manifest $out_dir
