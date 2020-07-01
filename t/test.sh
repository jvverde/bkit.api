#!/usr/bin/env bash
set -uE
sdir="$(dirname -- "$(readlink -ne -- "$0")")"        #Full DIR

declare testdir="${1:-"$sdir"}"
shopt -s extglob

cpanm Test::Mojo::Session
sudo usermod -a -G rsyncd "$(id -un)"
sudo chmod g+w /var/bkit/db/*
sudo chmod g+w /etc/bkit/api/bkit.conf
find "$testdir" -type f -name '*.t' -exec perl {} ';'
sudo chmod og-xw /var/bkit/db/*
sudo chmod og-xw /etc/bkit/api/bkit.conf