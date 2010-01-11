#!/usr/local/bin/perl -w

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl t/lch.t'

#  This scripts tests some of the options available in Interface.pm


BEGIN { $| = 1; print "1..5\n"; }
END {print "not ok 1\n" unless $loaded;}

use UMLS::Interface;
$loaded = 1;
print "ok 1\n";

use strict;
use warnings;

#  initialize option hash and umls
my %option_hash = ();
my $umls        = "";

#  check the realtime option
$option_hash{"realtime"} = 1;

$umls = UMLS::Interface->new(\%option_hash);
if(!$umls) { print "not ok 2\n"; }
else       { print "ok 2\n";     }

my ($errCode, $errString) = $umls->getError();
if($errCode) { print "not ok 3\n"; }
else         { print "ok 3\n";     }

#  check the forcerun option
$option_hash{"forcerun"} = 1;

$umls = UMLS::Interface->new(\%option_hash);
if(!$umls) { print "not ok 4\n"; }
else       { print "ok 4\n";     }

($errCode, $errString) = $umls->getError();
if($errCode) { print "not ok 5\n"; }
else         { print "ok 5\n";     }


