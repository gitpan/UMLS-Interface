#!/usr/local/bin/perl -w                                                        
                                                                                
# Before `make install' is performed this script should be runnable with        
# `make test'. After `make install' it should work as `perl access.t'           
                                                                                
##################### We start with some black magic to print on failure.       

use strict;
use warnings;

use Test::More tests => 14;

BEGIN {use_ok 'UMLS::Interface'}
BEGIN{ use_ok ('File::Spec') }
BEGIN{ use_ok ('File::Path') }
                                                              

#  initialize option hash
my %option_hash = ();

#  set the option hash
$option_hash{"realtime"} = 1;
$option_hash{"t"} = 1;
#$option_hash{"debug"} = 1;

#  connect to the UMLS-Interface
my $umls = UMLS::Interface->new(\%option_hash);
ok($umls);

my ($errCode, $errString) = $umls->getError();
ok(!($errCode));

#  get the version of umls that is being used
my $version = $umls->version();

#  check that no errors occured while obtaining the version
($errCode, $errString) = $umls->getError();
ok(!($errCode));

#  set the key directory (create it if it doesn't exist)
my $keydir = File::Spec->catfile('t','key', $version);
if(! (-e $keydir) ) {
    mkpath($keydir);
}

my $perl     = $^X;
my $util_prg = File::Spec->catfile('utils', 'getAssociatedTerms.pl');

my ($keyfile, $file, $output, $cui, $config);

### Note : if a key for the version of UMLS is being run on 
###        exists we will test our run against the key 
###        otherwise the key will be created
#######################################################################################
#  check mth rb-rn tests
#######################################################################################
$cui    = "C0018563";
$file    = "getAssociatedTerms.mth.rb-rn.$cui";
$keyfile = File::Spec->catfile($keydir, $file);
$config  = File::Spec->catfile('t', 'config', 'config.mth.rb-rn');
$output = `$perl $util_prg --config $config hand 2>&1`;

if(-e $keyfile) {
    ok (open KEY, $keyfile) or diag "Could not open $keyfile: $!";
    my $key = "";
    while(<KEY>) { $key .= $_; } close KEY;
    cmp_ok($output, 'eq', $key);
}
else {
    ok(open KEY, ">$keyfile") || diag "Could not open $keyfile: $!";
    print KEY $output;
    close KEY; 
  SKIP: {
      skip ("Generating key, no need to run test", 1);
    }
}

#######################################################################################
#  check snomedct par-chd tests
#######################################################################################
$cui    = "C0018563";
$file    = "getAssociatedTerms.snomedct.par-chd.$cui";
$keyfile = File::Spec->catfile($keydir, $file);
$config  = File::Spec->catfile('t', 'config', 'config.snomedct.par-chd');
$output = `$perl $util_prg --config $config $cui 2>&1`;

if(-e $keyfile) {
    ok (open KEY, $keyfile) or diag "Could not open $keyfile: $!";
    my $key = "";
    while(<KEY>) { $key .= $_; } close KEY;
    cmp_ok($output, 'eq', $key);
}
else {
    ok(open KEY, ">$keyfile") || diag "Could not open $keyfile: $!";
    print KEY $output;
    close KEY;
  SKIP: {
      skip ("Generating key, no need to run test", 1);
    }
}
#######################################################################################
#  check snomedct par-chd-rb-rn tests
#######################################################################################
$cui    = "C1281583";
$file    = "getAssociatedTerms.snomedct.par-chd-rb-rn.$cui";
$keyfile = File::Spec->catfile($keydir, $file);
$config  = File::Spec->catfile('t', 'config', 'config.snomedct.par-chd-rb-rn');
$output = `$perl $util_prg --config $config $cui 2>&1`;

if(-e $keyfile) {
    ok (open KEY, $keyfile) or diag "Could not open $keyfile: $!";
    my $key = "";
    while(<KEY>) { $key .= $_; } close KEY;
    cmp_ok($output, 'eq', $key);
}
else {
    ok(open KEY, ">$keyfile") || diag "Could not open $keyfile: $!";
    print KEY $output;
    close KEY;
  SKIP: {
      skip ("Generating key, no need to run test", 1);
    }
}

#######################################################################################
#  check msh par-chd tests
#######################################################################################
$cui    = "C0018563";
$file    = "getAssociatedTerms.msh.par-chd.$cui";
$keyfile = File::Spec->catfile($keydir, $file);
$config  = File::Spec->catfile('t', 'config', 'config.msh.par-chd');
$output = `$perl $util_prg --config $config $cui 2>&1`;

if(-e $keyfile) {
    ok (open KEY, $keyfile) or diag "Could not open $keyfile: $!";
    my $key = "";
    while(<KEY>) { $key .= $_; } close KEY;
    cmp_ok($output, 'eq', $key);
}
else {
    ok(open KEY, ">$keyfile") || diag "Could not open $keyfile: $!";
    print KEY $output;
    close KEY;
  SKIP: {
      skip ("Generating key, no need to run test", 1);
    }
}
