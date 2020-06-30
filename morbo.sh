#!/usr/bin/env bash
[[ $UID -ne 0 ]] && exec sudo "$0" "$@"
#SDIR=$(readlink -e "$(dirname $0)")

pushd "$(dirname "$0")"
/bin/su -s /bin/bash -c "morbo -v ./script/bkit" rsyncd
popd