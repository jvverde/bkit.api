#!/usr/bin/env perl
use DBM::Deep;
use Data::Dumper;
use strict;

my $dbname = shift or die "Usage $0 db";
my $db = DBM::Deep->new($dbname);
print Dumper $db;
