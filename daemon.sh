#!/usr/bin/env bash
[[ $(id -u) -eq 0 ]] && 
  chgrp rsyncd "$(dirname "$0")" && 
  chmod 775 "$(dirname "$0")" && 
  ARGS="$@" && 
  exec /bin/su -s /bin/bash -c "$0 $ARGS" rsyncd

die() { echo "$*" 1>&2 ; exit 1; }

[[ "$(id -u)" -eq "$(id -u rsyncd)" ]] || die "Must run as sudo or rsyncd" 


pushd "$(dirname "$0")" >/dev/null

./script/bkit daemon -m production -l http://*:8765

popd
