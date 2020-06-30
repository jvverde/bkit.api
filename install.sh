#!/usr/bin/env bash
[[ $UID -ne 0 ]] && exec sudo "$0" "$@"

find . -name "*.pm" -print0|xargs -r0I{} grep -Pio '(?<=^use)\s+[^;\s]+' "{}"|sort -u|xargs -rI{} cpanm "{}"
find . -name "*.pm" -print0|xargs -r0I{} grep -Pio "(?<=plugin)(?:[^\w]+)\w+" "{}"|sed -E 's/[^a-z]+//i'|xargs -rI{} cpanm "Mojolicious::Plugin::{}"
cpanm Minion::Backend::SQLite --sudo

