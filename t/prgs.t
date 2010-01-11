#!/usr/local/bin/perl -w

# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl t/lch.t'

#  This scripts tests the functionality of the utils/ programs

use strict;
use warnings;

use Test::More tests => 53;

BEGIN{ use_ok ('File::Spec') }

my $perl     = $^X;
my $util_prg = "";

my $output   = "";

#######################################################################################
#  check the findLeastCommonSubsumer.pl program
#######################################################################################

$util_prg = File::Spec->catfile('utils', 'findLeastCommonSubsumer.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/Two terms and\/or CUIs are required\s+Type findLeastCommonSubsumer.pl --help for help\.\s+Usage\: findLeastCommonSubsumer\.pl \[OPTIONS\] \[CUI1\|TERM1\] \[CUI2\|TERM2\]\s*/);

#  check when only one input is given on the command line 
$output = `$perl $util_prg hand 2>&1`;
like ($output, qr/Two terms and\/or CUIs are required\s+Type findLeastCommonSubsumer.pl --help for help\.\s+Usage\: findLeastCommonSubsumer\.pl \[OPTIONS\] \[CUI1\|TERM1\] \[CUI2\|TERM2\]\s*/);


#######################################################################################
#  check the findMaximumCuiDepth.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'findMaximumCuiDepth.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No term was specified on the command line\s+Type findMaximumCuiDepth.pl --help for help.\s+Usage\: findMaximumCuiDepth\.pl \[OPTIONS\] \[TERM\|CUI\]\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/Warning \(UMLS\:\:Interface\-\>getTermList\(\)\) \- Incorrect input value \(C98\)/);

#######################################################################################
#  check the findMinimumCuiDepth.pl program
#####################################################################
##################
$util_prg = File::Spec->catfile('utils', 'findMinimumCuiDepth.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No term was specified on the command line\s+Type findMinimumCuiDepth.pl --help for help.\s+Usage\: findMinimumCuiDepth\.pl \[OPTIONS\] \[TERM\|CUI\]\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/Warning \(UMLS\:\:Interface\-\>getTermList\(\)\) \- Incorrect input value \(C98\)/);

#######################################################################################
#  check the findPathToRoot.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'findPathToRoot.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No term was specified on the command line\s+Type findPathToRoot.pl --help for help.\s+Usage\: findPathToRoot\.pl \[OPTIONS\] \[CUI\|TERM\]\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/Warning \(UMLS\:\:Interface\-\>getTermList\(\)\) \- Incorrect input value \(C98\)/);

#######################################################################################
#  check the findShortestPath.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'findShortestPath.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/Two terms and\/or CUIs are required\s+Type findShortestPath.pl --help for help.\s+Usage\: findShortestPath\.pl \[OPTIONS\] \[CUI1\|TERM1\] \[CUI2\|TERM2\]\s*/);

#  check when only one input is given on the command line 
$output = `$perl $util_prg 2>&1`;
like ($output, qr/Two terms and\/or CUIs are required\s+Type findShortestPath.pl --help for help.\s+Usage\: findShortestPath\.pl \[OPTIONS\] \[CUI1\|TERM1\] \[CUI2\|TERM2\]\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 hand 2>&1`;
like ($output, qr/ERROR\: The concept \(C98\) is not valid\./);

#######################################################################################
#  check the getChildren.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'getChildren.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No term was specified on the command line\s+Type getChildren.pl --help for help.\s+Usage\: getChildren\.pl \[OPTIONS\] \[CUI\|TERM\]\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/Warning \(UMLS\:\:Interface\-\>getTermList\(\)\) \- Incorrect input value \(C98\)/);

#######################################################################################
#  check the getParents.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'getParents.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No term was specified on the command line\s+Type getParents.pl --help for help.\s+Usage\: getParents\.pl \[OPTIONS\] \[CUI\|TERM\]\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/Warning \(UMLS\:\:Interface\-\>getTermList\(\)\) \- Incorrect input value \(C98\)/);

#######################################################################################
#  check the getCuiDef.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'getCuiDef.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No term was specified on the command line\s+Type getCuiDef.pl --help for help.\s+Usage\: getCuiDef\.pl \[OPTIONS\] \[CUI\|TERM\]\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/ERROR\: The concept \(C98\) is not valid\./);

#######################################################################################
#  check the getRelated.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'getRelated.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/A term and relation must be specified\s+Type getRelated.pl --help for help.\s+Usage\: getRelated\.pl \[OPTIONS\] \[CUI\|TERM\]\s*/);

#  check when only one input is specified on the  command line 
$output = `$perl $util_prg hand 2>&1`;
like ($output, qr/A term and relation must be specified\s+Type getRelated.pl --help for help.\s+Usage\: getRelated\.pl \[OPTIONS\] \[CUI\|TERM\]\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 SIB 2>&1`;
like ($output, qr/Warning \(UMLS\:\:Interface\-\>getTermList\(\)\) \- Incorrect input value \(C98\)/);

#######################################################################################
#  check the getRelations.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'getRelations.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No term was specified on the command line\s+Type getRelations.pl --help for help.\s+Usage\: getRelations\.pl \[OPTIONS\] \[CUI\|TERM\]\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/Warning \(UMLS\:\:Interface\-\>getTermList\(\)\) \- Incorrect input value \(C98\)/);

#######################################################################################
#  check the getSts.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'getSts.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No term was specified on the command line\s+Type getSts.pl --help for help.\s+Usage\: getSts\.pl \[OPTIONS\] \[TERM\|CUI\]\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/Warning \(UMLS\:\:Interface\-\>getTermList\(\)\) \- Incorrect input value \(C98\)/);

#######################################################################################
#  check the getStDef.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'getStDef.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No semantic type was specified on the command line\s+Type getStDef.pl --help for help.\s+Usage\: getStDef\.pl \[OPTIONS\] \<semantic type\>\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg dkj 2>&1`;
like ($output, qr/There are no definitions for the semantic type \(dkj\)/);

#######################################################################################
#  check the queryCui.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'queryCui.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No CUI was specified on the command line\s+Type queryCui.pl --help for help.\s+Usage\: queryCui\.pl \[OPTIONS\] CUI\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/ERROR\: The concept \(C98\) is not valid\./);

#######################################################################################
#  check the queryTerm.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'queryTerm.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No term was specified on the command line\s+Type queryTerm.pl --help for help.\s+Usage\: queryTerm\.pl \[OPTIONS\] TERM\s*/);

#  check when invalid term is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/No CUIs are associated with C98\./);

#######################################################################################
#  check the queryCui-Sab.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'queryCui-Sab.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/No CUI was specified on the command line\s+Type queryCui-Sab.pl --help for help.\s+Usage\: queryCui-Sab\.pl \[OPTIONS\] CUI\s*/);

#  check when invalid CUI is entered
$output = `$perl $util_prg C98 2>&1`;
like ($output, qr/ERROR\: The concept \(C98\) is not valid\./);
 
#######################################################################################
#  check the removeConfigData.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'removeConfigData.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/Configuration file was not specified on the command line\s+Type removeConfigData.pl --help for help.\s+Usage\: removeConfigData\.pl \[OPTIONS\] CONFIGFILE\s*/);

#######################################################################################
#  check the dfs.pl program
#######################################################################################
$util_prg = File::Spec->catfile('utils', 'dfs.pl');
ok(-e $util_prg);

#  check no command line inputs
$output = `$perl $util_prg 2>&1`;
like ($output, qr/The config file was not specified on the command line\s+Type dfs.pl --help for help.\s+Usage\: dfs\.pl CONFIGFILE \[OPTIONS\]\s*/);

#  check when invalid configuration file is entered
$output = `$perl $util_prg config 2>&1`;
like ($output, qr/Could not open configuration file\: config/);