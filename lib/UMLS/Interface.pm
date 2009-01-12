# UMLS::Interface version 0.01
# (Last Updated $Id: Interface.pm,v 1.41 2009/01/12 21:03:30 btmcinnes Exp $)
#
# Perl module that provides a perl interface to the
# UMLS taxonomy of medical terms 
#
# Copyright (c) 2004-2009,
#
# Bridget T. McInnes, University of Minnesota Twin Cities
# bthomson at cs.umn.edu
#
# Siddharth Patwardhan, University of Utah, Salt Lake City
# sidd at cs.utah.edu
# 
# Serguei Pakhomov, University of Minnesota Twin Cities
# pakh0002 at umn.edu
#
# Ted Pedersen, University of Minnesota, Duluth
# tpederse at d.umn.edu
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to 
#
# The Free Software Foundation, Inc., 
# 59 Temple Place - Suite 330, 
# Boston, MA  02111-1307, USA.

package UMLS::Interface;

use strict;
use warnings;
use DBI;
use bytes;
use vars qw($VERSION);

$VERSION = '0.07';

my $debug = 0;

my %roots = ();

my $umlsRoot = "C0085567";

my $taxnum  = 1;

my $version = "";

my $max_depth = 0;

#  list of allowable sources 
my $sources   = "";
my %sab_hash  = ();
my %sab_names = ();

#  list of allowable relations
my $relations       = "";
my $childRelations  = "";
my $parentRelations = "";

#  upper level taxonomy
my %parentTaxonomy   = ();
my %childrenTaxonomy = ();

my $childFile  = "";
my $parentFile = "";

#  trace variables
my %trace = ();

my $sourceDB  = "";
my $tableName = "";
my $tableFile = "";
my $cycleFile = "";
my %cycleHash = ();

# UMLS-specific stuff ends ----------

# -------------------- Class methods start here --------------------

################# function unchanged from v0.01 2003
#  Method to create a new UMLS::Interface object
sub new
{
    my $self = {};
    my $className = shift;
    my $paramHash = shift;

    # Initialize Error String and Error Code.
    $self->{'errorString'} = "";
    $self->{'errorCode'} = 0;

    # Bless the object.
    bless($self, $className);

    # Initialize the object.
    $self->_initialize($paramHash);

    return $self;
}

################# function unchanged from v0.01 2003
# Method to destroy the created object.
# Gets called automatically during garbage collection.
sub disconnect
{
    my $self = shift;

    if($self) {
	my $db = $self->{'db'};
	$db->disconnect() if($db);
    }
}

################# function unchanged from v0.01 2003
# Method that returns the error string and error
# code from the last method call on the object.
sub getError
{
    my $self      = shift;
    my $dontClear = shift;

    my $returnCode = $self->{'errorCode'};
    my $returnString = $self->{'errorString'};

    $returnString =~ s/^\n+//;

    if(!(defined $dontClear && $dontClear)) {
	$self->{'errorString'} = "";
	$self->{'errorCode'} = 0;
    }
    return ($returnCode, $returnString);
}

################# function unchanged from v0.01 2003
# Method that returns the root node of a taxonomy.
sub root
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);

    $self->{'traceString'} = "";

    my @array = keys %roots;

    return @array; 
}

################# function unchanged from v0.01 2003
# Method to return the maximum depth of a taxonomy.
sub depth
{
    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";

    #  determine the cycles and depth of the taxonomy if not already done
    my $depthCheck = $self->_setDepth();
    
    return $max_depth;

}

################# function unchanged from v0.01 2003
# Method to return the version of the backend database.
sub version
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);

    $self->{'traceString'} = "";

    return $version;
}

################# modified version from v0.01 2003
################# modified function as of v0.03
# Method to initialize the UMLS::Interface object.
#  Code from original UML-Interface program written 
#  by Siddharth Patwardhan but modified by Bridget 
#  McInnes
sub _initialize
{
    my $self = shift;
    my $params = shift;

    return undef if(!defined $self || !ref $self);
    $params = {} if(!defined $params);

    #  get all the parameters
    my $multitax     = $params->{'multitax'};
    my $database     = $params->{'database'};
    my $hostname     = $params->{'hostname'};
    my $socket       = $params->{'socket'};
    my $port         = $params->{'port'};
    my $username     = $params->{'username'};
    my $password     = $params->{'password'};
    my $config       = $params->{'config'};
    my $cyclefile    = $params->{'cyclefile'};
    
    #  to store the database object
    my $db;

    #  variables required during initialization
    my $sth;
    my $table;
    my $arrRef;
    my $r;
    my %tables;

    if(! defined $database) { $database = "umls";            }
    if(! defined $socket)   { $socket   = "/tmp/mysql.sock"; }
    if(! defined $hostname) { $hostname = "localhost";       }

    #  create the database object...
    if(defined $username and defined $password) {
	if($debug) { print "Connecting with username and password\n"; }
	$db = DBI->connect("DBI:mysql:database=$database;mysql_socket=$socket;host=$hostname",$username, $password, {RaiseError => 1});
    }
    else {
	if($debug) { print "Connecting using the my.cnf file\n"; }
	my $dsn = "DBI:mysql:umls;mysql_read_default_group=client;";
	$db = DBI->connect($dsn);
    } 

    if(!$db || $db->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->_initialize()) - ";
	$self->{'errorString'} .= "Unable to open database";
	$self->{'errorString'} .= (($db) ? (": ".($db->errstr())) : ("."));
	$self->{'errorCode'} = 2;
	return;	
    }

    $db->{'mysql_enable_utf8'} = 1;
    $db->do('SET NAMES utf8');

    #  check if the tables exist...
    $sth = $db->prepare("show tables");
    $sth->execute();
    if($sth->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->_initialize()) - ";
	$self->{'errorString'} .= "Unable run query: ".($sth->errstr());
	$self->{'errorCode'} = 2;
	return;
    }
    
    while(($table) = $sth->fetchrow()) {
	$tables{$table} = 1;
    }
    $sth->finish();

    if(!defined $tables{"MRCONSO"}) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->_initialize()) - ";
	$self->{'errorString'} .= "Table MRCONSO not found in database.";
	$self->{'errorCode'} = 2;
	return;	
    }
    if(!defined $tables{"MRREL"}) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->_initialize()) - ";
	$self->{'errorString'} .= "Table MRREL not found in database.";
	$self->{'errorCode'} = 2;
	return;	
    }
    if(!defined $tables{"MRDOC"}) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->_initialize()) - ";
	$self->{'errorString'} .= "Table MRDOC not found in database.";
	$self->{'errorCode'} = 2;
	return;	
    }
    if(!defined $tables{"MRSAB"}) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->_initialize()) - ";
	$self->{'errorString'} .= "Table MRSAB not found in database.";
	$self->{'errorCode'} = 2;
	return;	
    }

    #  get the version info...
    $arrRef = $db->selectcol_arrayref("select EXPL from MRDOC where VALUE = \'mmsys.version\'");
    if($db->err()) {
	$self->{'errorCode'} = 2;
	$self->{'errorString'} .= "\nError (UMLS::Interface->_initialize()) - ";
	$self->{'errorString'} .= "Error executing database query: ".($db->errstr());
	return ();
    }
    if(scalar(@{$arrRef}) < 1) {
	$self->{'errorCode'} = 2;
	$self->{'errorString'} .= "\nError (UMLS::Interface->_initialize()) - ";
	$self->{'errorString'} .= "No version info in table MRDOC.";
	return ();
    }
    ($version) = @{$arrRef}; 
    
    #  set te information needed for self
    $self->{'db'}           = $db;
    $self->{'username'}     = $username;
    $self->{'password'}     = $password;
    $self->{'hostname'}     = $hostname;
    $self->{'socket'}       = $socket;
    $self->{'cyclefile'}    = $cyclefile;
    
    $self->{'traceString'}  = "";
    $self->{'cache'}        = {};
    $self->{'maxCacheSize'} = 1000;
    $self->{'cacheQ'}       = ();

  #  set the configuration
    my $configCheck;
    if(defined $config) { $configCheck = $self->_config($config); }
    else                { $configCheck = $self->_config();        }
    if(! (defined $configCheck)) { return (); }


    #  set the root nodes
    if($debug) { print "Setting the root(s)\n"; }
    $self->_setRoots();
    
    #  get appropriate version output
    my $ver = $version;
    $ver=~s/-/_/g;
    
    my $umlsinterface = $ENV{UMLSINTERFACE_CONFIGFILE_DIR};

    if(! (defined $umlsinterface) ) {    
	my $answerFlag    = 0;
	my $interfaceFlag = 0;
	
	while(! ($interfaceFlag) ) {

	    print STDERR "The UMLSINTERFACE_CONFIGFILE_DIR environment\n";
	    print STDERR "variable has not been defined yet. Please \n";
	    print STDERR "enter a location that the UMLS-Interface can\n";
	    print STDERR "use to store its configuration files:\n";
	    
	    $umlsinterface = <STDIN>; chomp $umlsinterface;

	    while(! ($answerFlag)) {
		print STDERR "Is $umlsinterface the correct location?\n";
		my $answer = <STDIN>; chomp $answer;
		if($answer=~/(Y|N|y|n|yes|no|Yes|No)/) { 
		    $answerFlag    = 1; 
		    $interfaceFlag = 1;   
		}
	    }

	    print STDERR "I am working on having the program set the environment\n";
	    print STDERR "variable for you but that is not working yet. Until then\n";
	    print STDERR "if you don't mind setting it after this run, that would\n";
	    print STDERR "great. It can be set in csh as follows:\n\n";
	    print STDERR " setenv UMLSINTERFACE_CONFIGFILE_DIR $umlsinterface\n\n";
	    print STDERR "And in bash shell:\n\n";
	    print STDERR " export UMLSINTERFACE_CONFIGFILE_DIR=$umlsinterface\n\n";
	    print STDERR "I will work on getting it to set itself. Thanks!\n\n";
	}
    }
    
    #  set table and cycle and upper level relations files
    $sourceDB   = "$ver";
    $childFile  = "$umlsinterface/$ver";
    $parentFile = "$umlsinterface/$ver";
    $tableFile  = "$umlsinterface/$ver";
    $cycleFile  = "$umlsinterface/$ver";
    $tableName  = "$ver";

    foreach my $sab (sort keys %sab_names) {
    	$tableFile  .= "_$sab";
    	$cycleFile  .= "_$sab";
	$tableName  .= "_$sab";
	$childFile  .= "_$sab";
	$parentFile .= "_$sab";
	$sourceDB   .= "_$sab";
    }
    
    while($relations=~/=\'(.*?)\'/g) {
	my $rel = $1;
	$tableFile  .= "_$rel";
	$cycleFile  .= "_$rel";
	$tableName  .= "_$rel";
	$childFile  .= "_$rel";
	$parentFile .= "_$rel";
	$sourceDB   .= "_$rel";
    }
    
    $tableFile  .= "_table";
    $cycleFile  .= "_cycle";
    $tableName  .= "_table";
    $childFile  .= "_child";
    $parentFile .= "_parent";

    if($debug) {
	print "Database  : $sourceDB\n";
	print "Table File: $tableFile\n";
	print "Cycle File: $cycleFile\n";
	print "Table Name: $tableName\n";
	print "Child File: $childFile\n";
	print "ParentFile: $parentFile\n";
    }
}

################# modified version from v0.01 2003
################# modified function as of v0.03
#  Method to check if a concept ID exists in the 
#  database.
sub exists
{    
    my $self = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);

    my $function = "exists";

    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
    
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
	
    my $arrRef;
    my $count;

    $self->{'traceString'} = "";
    return () if(!defined $concept);
    
    if($sources ne "") {
	$arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where CUI='$concept' and $sources");
	if($self->checkError($function)) { return (); }
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where CUI='$concept'");
	if($self->checkError($function)) { return (); }
    }
    
    $count = scalar(@{$arrRef});
    if($count > $count) {
	$self->{'errorCode'} = 2 if($self->{'errCode'} < 1);
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->exists()) - ";
	$self->{'errorString'} .= "Internal error: Duplicate concept rows.";
    }
    
    return 1 if($count);
    
    return 0;
}

################# modified version from v0.01 2003
################# modified function as of v0.03
#  Method to set the roots that exist in the UMLS view
sub _setRoots {

    my $self = shift;
    return () if(!defined $self || !ref $self);
    
    my $function = "_setRoots";
    &_debug($function);
    
    $roots{$umlsRoot}++;
}

################# modified version from v0.01 2003
################# modified function as of v0.03
# Method that returns a list of concepts (@concepts)
# related to a concept $concept through a relation $rel
sub getRelated
{
    my $self    = shift;
    my $concept = shift;
    my $rel     = shift;

    return () if(!defined $self || !ref $self);

    my $function = "getRelated";
    &_debug($function);
    
    if(!$concept || !$rel) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
    
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return 1;
    }    

    #  return all the relations 'rel' for cui 'concept'
    my $arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and REL='$rel' and ($sources) and CVF is null");
    if($self->checkError($function)) { return(); }
        
    return @{$arrRef};
}

################# modified version from v0.01 2003
################# modified function as of v0.03
# Method to map terms to a conceptID
sub getTermList
{
    my $self = shift;
    my $concept = shift;

    return 0 if(!defined $self || !ref $self);
    
    my $function = "getTermList";
    &_debug($function);
    
 
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    } 
    
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    } 

    $self->{'traceString'} = "";

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

    
    my $arrRef = $db->selectcol_arrayref("select distinct STR from MRCONSO where CUI='$concept' and $sources");
    if($self->checkError($function)) { return(); }


    
    my %retHash = ();
    foreach my $tr (@{$arrRef}) {
        $tr =~ s/^\s+//;
        $tr =~ s/\s+$//;
        $tr =~ s/\s+/ /g;
        $retHash{lc($tr)} = 1;
    }
    
    return keys(%retHash);
}

################# modified version from v0.01 2003
################# modified function as of v0.03
# Method to map CUIs to a term.
sub getConceptList
{
    my $self = shift;
    my $term = shift;

    return () if(!defined $self || !ref $self);

    my $function = "getConceptList";
    #&_debug($function);
    
    if(!$term) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	return ();
    }

    $self->{'traceString'} = "";

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    my $arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where STR='$term' and ($sources)");
    if($self->checkError($function)) { return (); }
    
    return @{$arrRef};
    
}

################# modified version from v0.01 2003
################# modified function as of v0.03
# Method to find all the paths from a concept to
# the root node of the is-a taxonomy.
sub pathsToRoot
{
    my $self = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);

    my $function = "pathsToRoot";
    &_debug($function);

    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 


    #  determine the cycles and depth of the taxonomy if not already done
    my $depthCheck = $self->_setDepth();
    
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
    
    $self->{'traceString'} = "";
    
    #  check that concept1 and concept2 exist
    if($self->_checkConceptExists($concept) eq 0) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($concept) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }
    
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    my $paths = $sdb->selectcol_arrayref("select PATH from $tableName where CUI=\'$concept\'");
    if($self->checkError($function)) { return (); }
    
    return $paths;
    
}

################# new function as of v0.03
#  Method to set the Upper Level Taxonomy. Each CUI in the MRREL 
#  file that does not have a parent is linked to its source CUI
#  with a generic parent / child relationship. The source CUIs 
#  are then either considered the root nodes or linked to the 
#  UMLS CUI to create a single root node.
sub _updateTaxonomy {
    my $self = shift;
    
    return undef if(!defined $self || !ref $self);

    my $function = "_updateTaxonomy";
    &_debug($function);

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
	}    
    
    $self->{'traceString'} = "";
    
    #  clear out the parent and child taxonomy hash tables
    %parentTaxonomy   = ();
    %childrenTaxonomy = ();
    
    # open the parent and child files to store the upper level taxonomy information
    open(CHD, ">$childFile")  || die "Could not open $childFile\n";
    open(PAR, ">$parentFile") || die "Could not open $parentFile\n";
	
    #  select all the CUI1s from MRREL - takes approximately 6 minutes
    my $allCui1 = $db->selectcol_arrayref("select CUI1 from MRREL where ($relations) and ($sources) and (CVF is null)");
    if($self->checkError($function)) { return undef; }
	
    my $allCui2 = $db->selectcol_arrayref("select CUI2 from MRREL where ($relations) and ($sources) and (CVF is null)");
    if($self->checkError($function)) { return undef; }
		
    my @allCuis = (@{$allCui1}, @{$allCui2});
    
    if($debug) { print "Got all of the CUIs\n"; }
		     
    #  select all the CUI1s from MRREL that have a parent link
    my $parCuis = $db->selectcol_arrayref("select CUI1 from MRREL where ($parentRelations) and ($sources) and (CVF is null)");
    if($self->checkError($function)) { return undef; }
    
    if($debug) { print "Get all of the parent CUIs\n"; }
    
    #  load the cuis that have a parent into a temporary hash
    my %parCuisHash = ();
    foreach my $cui (@{$parCuis}) { $parCuisHash{$cui}++; }
    
    #  load the cuis that do not have a parent into the parent 
    #  and chilren taxonomy for the upper level
    foreach my $cui (@allCuis) {
	
	#  if the cui has a parent move on
	if(exists $parCuisHash{$cui})    { next; }
	
	#  already seen this cui so move on
	if(exists $parentTaxonomy{$cui}) { next; }
	
	#  if the cui does not belong to the designated source 
	#  move on
	my @sabs = $self->getSab($cui);
	
	foreach my $sab (@sabs) {
	    
	    #  if we are not interested in the source move on
	    if(! exists ($sab_names{$sab}) ) { next; }
	    
	    my $sab_cui = $self->_getSabCui($sab);
	    
	    if($sab_cui eq $cui) { next; }
	    
	    push @{$parentTaxonomy{$cui}}, $sab_cui;
	    push @{$childrenTaxonomy{$sab_cui}}, $cui;
	    
	    print PAR "$cui $sab_cui\n";
	    print CHD "$sab_cui $cui\n";
	}
    }
   
    #  add the sab cuis to the parentTaxonomy
    foreach my $sab_cui (sort keys %sab_hash) {
	push @{$parentTaxonomy{$sab_cui}}, $umlsRoot;
	print PAR "$sab_cui $umlsRoot\n";
    }
    
    close PAR; close CHD;
    
    #  print out some information
    my $pkey = keys %parentTaxonomy;
    my $ckey = keys %childrenTaxonomy;

    if($debug) {
	print "Taxonomy is set:\n";
	print "  parentTaxonomy: $pkey\n";
	print "  childrenTaxonomy: $ckey\n\n";
    }
    
    return 0;
}

sub _setUpperLevelTaxonomy {
    
    my $self = shift;

    return undef if(!defined $self || !ref $self);

    my $function = "_setUpperLevelTaxonomy";
    &_debug($function);
    #&_printTime();

    if( (-e $childFile) and (-e $parentFile) ) {

	open(PAR, $parentFile) || die "Could not open $parentFile\n";	
	open(CHD, $childFile)  || die "Could not open $childFile\n";
	
	while(<PAR>) {
	    chomp;
	    if($_=~/^\s*$/) { next; }
	    my ($cui, $sab_cui) = split/\s+/;
	    push @{$parentTaxonomy{$cui}}, $sab_cui;
	}

	while(<CHD>) {
	    chomp;
	    if($_=~/^\s*$/) { next; }
	    my ($sab_cui, $cui) = split/\s+/;
	    push @{$childrenTaxonomy{$sab_cui}}, $cui;
	}
    }
    else {
	my $db = $self->{'db'};
	if(!$db) {
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "A db is required.";
	    $self->{'errorCode'} = 2;
	    return undef;
	}    
	
	$self->{'traceString'} = "";
	
	# mark the cycles;
	my $cycleCheck = $self->_markCycles();
	if(!defined $cycleCheck) { 
	    print "$self->{'errorString'}\n";
	    return ();
	}
	
	# open the parent and child files to store the upper level taxonomy information
	open(CHD, ">$childFile")  || die "Could not open $childFile\n";
	open(PAR, ">$parentFile") || die "Could not open $parentFile\n";
	
	#  select all the CUI1s from MRREL - takes approximately 6 minutes
	my $allCui1 = $db->selectcol_arrayref("select CUI1 from MRREL where ($relations) and ($sources)");
	if($self->checkError($function)) { return undef; }
	
	my $allCui2 = $db->selectcol_arrayref("select CUI2 from MRREL where ($relations) and ($sources)");
	if($self->checkError($function)) { return undef; }
		
	my @allCuis = (@{$allCui1}, @{$allCui2});
	
	if($debug) { print "Got all of the CUIs\n"; }
		     
	#  select all the CUI1s from MRREL that have a parent link
	my $parCuis = $db->selectcol_arrayref("select CUI1 from MRREL where ($parentRelations) and ($sources)");
	if($self->checkError($function)) { return undef; }
	
	if($debug) { print "Get all of the parent CUIs\n"; }
	
	#  load the cuis that have a parent into a temporary hash
	my %parCuisHash = ();
	foreach my $cui (@{$parCuis}) { $parCuisHash{$cui}++; }
	
	#  load the cuis that do not have a parent into the parent 
	#  and chilren taxonomy for the upper level
	foreach my $cui (@allCuis) {
	    
	    #  if the cui has a parent move on
	    if(exists $parCuisHash{$cui})    { next; }
	    
	    #  already seen this cui so move on
	    if(exists $parentTaxonomy{$cui}) { next; }
	    
	    #  if the cui does not belong to the designated source 
	    #  move on
	    my @sabs = $self->getSab($cui);
	    
	    foreach my $sab (@sabs) {
		
		#  if we are not interested in the source move on
		if(! exists ($sab_names{$sab}) ) { next; }
		
		my $sab_cui = $self->_getSabCui($sab);
	    
		if($sab_cui eq $cui) { next; }
		
		push @{$parentTaxonomy{$cui}}, $sab_cui;
		push @{$childrenTaxonomy{$sab_cui}}, $cui;
		
		print PAR "$cui $sab_cui\n";
		print CHD "$sab_cui $cui\n";
	    }
	}
   
	#  add the sab cuis to the parentTaxonomy
	foreach my $sab_cui (sort keys %sab_hash) {
	    push @{$parentTaxonomy{$sab_cui}}, $umlsRoot;
	    print PAR "$sab_cui $umlsRoot\n";
	}
	
	close PAR; close CHD;
    }
    
    #  print out some information
    my $pkey = keys %parentTaxonomy;
    my $ckey = keys %childrenTaxonomy;
    
    if($debug) {
	print "Taxonomy is set:\n";
	print "  parentTaxonomy: $pkey\n";
	print "  childrenTaxonomy: $ckey\n\n";
    }

    #&_printTime();
    
    return 0;
}

#  connect the database to the source db that holds
#  the path tables for user specified source(s) and 
#  relation(s)
sub _connectSourceDB {
    my $self = shift;
    
    my $sdb = "";

    if(defined $self->{'username'}) {
	
	    my $username = $self->{'username'};
	    my $password = $self->{'password'};
	    my $hostname = $self->{'hostname'};
	    my $socket   = $self->{'socket'};
	    
	    $sdb = DBI->connect("DBI:mysql:database=$sourceDB;mysql_socket=$socket;host=$hostname",$username, $password, {RaiseError => 1});
    }
    else {
	my $dsn = "DBI:mysql:$sourceDB;mysql_read_default_group=client;";
	$sdb = DBI->connect($dsn);
    }
    
    $self->{'sdb'} = $sdb;
	
    return $sdb;
}

sub _markCycles
{
    my $self = shift;

    return () if(!defined $self || !ref $self);

    my $function = "_markCycles";
    &_debug($function);
    #&_printTime();

    #  check that the database exists
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    #  reset the cycle information back to null
    my $ara = $db->do("update MRREL set CVF=NULL where CVF=1");
    
    #  set the cycle information for CUIs that a relation with themselves
    my $arb = $db->do("update MRREL set CVF=1 where CUI1=CUI2");

    #  check if cycle file was defined
    my $cyclefile = $self->{'cyclefile'};
    if(defined $cyclefile) {

	open(CYCLE, $cyclefile) || die "Could not open cycle file: $cyclefile\n";
	while(<CYCLE>) {
	    chomp;
	    my @array = split/\|/;

	    my $cui1 = $array[0];
	    my $cui2 = $array[1];
	    my $rel  = $array[2];
	    my $real = $array[3];
	    
	    if($rel=~/$relations/) {
		
		if($rel=/PAR/) {
		    my $ara = $db->do("update MRREL set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='PAR' and ($sources)");
		    my $arb = $db->do("update MRREL set CVF=1 where CUI2='$cui1' and CUI2='$cui1' and REL='CHD' and ($sources)");
		}
		
		if($rel=/RB/) {
		    my $ara = $db->do("update MRREL set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='RB' and ($sources)");
		    my $arb = $db->do("update MRREL set CVF=1 where CUI2='$cui1' and CUI2='$cui1' and REL='RN' and ($sources)");
		}
		
		if($rel=/CHD/) {
		    my $ara = $db->do("update MRREL set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='CHD' and ($sources)");
		    my $arb = $db->do("update MRREL set CVF=1 where CUI2='$cui1' and CUI2='$cui1' and REL='PAR' and ($sources)");
		}

		if($rel=/RN/) {
		    my $ara = $db->do("update MRREL set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='RN' and ($sources)");
		    my $arb = $db->do("update MRREL set CVF=1 where CUI2='$cui1' and CUI2='$cui1' and REL='RB' and ($sources)");
		}
		
	    }
	}
    }

    #&_printTime();
}

################# new function as of v0.03
#  This function obtains the maximum depth of the 
#  taxonomy given the sources that are used.
sub _setDepth {

    my $self = shift;

    return () if(!defined $self || !ref $self);

    my $function = "_setDepth";
    &_debug($function);
    
    #  check that the database exists
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

    #  set the auxillary database that holds the path information
    my $sdb = $self->{'sdb'};

    #  set the upper level taxonomyIn 
    my $taxCheck = $self->_setUpperLevelTaxonomy();
    if(!defined $taxCheck) { 
	print "$self->{'errorString'}\n";
	return ();
    }

    #  get teh version
    my $version = $self->version();
    
    #  get the tables from the umls database
    my $sth = $db->prepare("show databases");
    $sth->execute();
    if($sth->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->_initialize()) - ";
	$self->{'errorString'} .= "Unable run query: ".($sth->errstr());
	$self->{'errorCode'} = 2;
	return ();
    }
    
    my $database  = "";
    my %databases = ();
    while(($database) = $sth->fetchrow()) {
	$databases{$database} = 1;
    }
    $sth->finish();
    
    #my $ar3 = $db->do("update MRREL set CVF=NULL where CVF=1");
    
    #  check to see if tableFile is loaded into 
    #  the database if it isn't get it loaded
    #  otherwise just connect to it
    if(defined $databases{$sourceDB}) {
	$sdb = $self->_connectSourceDB();	
	if($self->checkError($function)) { return (); }
    }
    else {
	#  create the source database and set up connection
	my $cd = $db->do("create database $sourceDB");
	$sdb = $self->_connectSourceDB();	
	if($self->checkError($function)) { return (); }
	
	if($debug) { print "No Path table exists\n"; }
	
	#  check if tableFile exists in the default_options 
	#  directory, if so load it into the database
	if(-e $tableFile) {
	    
	    if($debug) { print "Path table file exists\n"; }
	    
	    #  create the table in the umls database
	    my $ar1 = $sdb->do("CREATE TABLE IF NOT EXISTS $tableName (CUI char(8), DEPTH int, PATH varchar(1000))");
	    if($self->checkError($function)) { return (); }
	    
	    #  load the path information into the table
	    open(TABLE, $tableFile) || die "Could not open $tableFile\n";
	    while(<TABLE>) {
		chomp;
		if($_=~/^\s*$/) { next; }
		my ($cui, $depth, $path) = split/\t/;
		my $arrRef = $sdb->do("INSERT INTO $tableName (CUI, DEPTH, PATH) VALUES(\'$cui\', '$depth', \'$path\')");		
	    }
	    if($self->checkError($function)) { return (); }
	    
	}
	#  otherwise create the tableFile and put the 
	#  information in the file and the database
	else  {
	    
	    if($debug) { print "Neither the path table or file exists\n"; }

	    my $sourceList = "";
	    foreach my $sab (sort keys %sab_names) { 
		$sourceList .= "$sab, "; 
	    }
   
	    print "You have requested the following sources $sourceList.\n";
	    print "In order to use these an index needs to be created.\n";
	    print "This could be very time consuming. If the index is not\n";
	    print "created, you will not be able to use this command with\n";
	    print "these sources.\n\n";
	    print "Do you want to continue with index creation (y/n)";
	    
	    my $answer = <STDIN>; chomp $answer;
	    
	    if($answer=~/(N|n)/) {
		print "Exiting program now.\n\n";
		exit;
	    }
	    
	    #  create the table in the umls database
	    my $ar1 = $sdb->do("CREATE TABLE IF NOT EXISTS $tableName (CUI char(8), DEPTH int, PATH varchar(1000))");
	    if($self->checkError($function)) { return (); }
	    
	    my $ar8 = $db->do("update MRREL  set CVF=NULL where CVF=1");
	    my $ar3 = $db->do("update MRREL  set CVF=1 where CUI1=CUI2");

	    #  for each root - this is for when we allow multiple roots
	    #  right now though we only have one - the umlsRoot
	    foreach my $root (sort keys %roots) {
		
		if($self->checkError($function)) { return (); }
		$self->_initializeDepthFirstSearch($root, 0, $root);
	    }
	    
	    if($debug) { print "The depth first search is over\n"; }
	    
	    #  load cycle information into a file
	    open(CYCLE, ">$cycleFile") || die "Could not open file $cycleFile"; 
	    foreach my $cui1 (sort keys %cycleHash) {
		foreach my $cui2 (sort keys %{$cycleHash{$cui1}}) {
		    print CYCLE "$cui1 $cui2 $cycleHash{$cui1}{$cui2}\n";
		}
	    } 
	    close CYCLE;
	    
	    if($debug) { print "Cycle file has been created\n"; }
	    
	    #if($debug) { print "Update taxonomy\n"; }
	    #$self->_updateTaxonomy();
	}
	
	#  create index on the newly formed table
	my $index = $sdb->do("create index CUIINDEX on $tableName (CUI)");
	if($self->checkError($function)) { return (); }
    }

    if($debug) { print "Cycle file has been created\n"; }
        
    #  set the maximum depth
    my $d = $sdb->selectcol_arrayref("select max(DEPTH) from $tableName");
    if($self->checkError($function)) { return (); }
   
    $max_depth = shift @{$d};
}

sub _debug
{

    my $function = shift;
    if($debug) { print "In $function\n"; }
}



################# new function as of v0.03
#  This sets the sources that are to be used. These sources 
#  are found in the config file. The defaults are:
sub _config {

    my $self = shift;
    my $file = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "_config";
    &_debug($function);
    
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    


    $self->{'traceString'} = "";
   
    if(defined $file) {
	
	my %includesab = ();
	my %excludesab = ();
	my %includerel = ();
	my %excluderel = ();

	open(FILE, $file) || die "Could not open configuration file: $file\n"; 

	while(<FILE>) {
	    chomp;
	    
	    #  if blank line skip
	    if($_=~/^\s*$/) { next; }

	    if($_=~/([A-Z]+)\s+\:\:\s+(include|exclude)\s+(.*)/) {
	    
		my $type = $1; 
		my $det  = $2;
		my $list = $3;
		
		my @array = split/\s*\,\s*/, $list;
		foreach my $element (@array) {
		    if($type eq "SAB" and $det eq "include")    { $includesab{$element}++; }
		    elsif($type eq "SAB" and $det eq "exclude") { $excludesab{$element}++; }
		    elsif($type eq "REL" and $det eq "include") { $includerel{$element}++; }
		    elsif($type eq "REL" and $det eq "exclude") { $excluderel{$element}++; }
		    else {
			$self->{'errorCode'} = 2;
			$self->{'errorString'} .= "\nError (UMLS::Interface->_config()) - ";
			$self->{'errorString'} .= "Configuration file entry not valid ($_).";
			return ();
		    }
		}
	    }
	    else {
		$self->{'errorCode'} = 2;
		$self->{'errorString'} .= "\nError (UMLS::Interface->_config()) - ";
		$self->{'errorString'} .= "Configuration file format not correct ($_).";
		return ();
	    }
	}
	
	my $includesabkeys = keys %includesab;
	my $excludesabkeys = keys %excludesab;
	my $includerelkeys = keys %includerel;
	my $excluderelkeys = keys %excluderel;

	#  check for errors
	if($includesabkeys > 0 and $excludesabkeys > 0) {
	    $self->{'errorCode'} = 2;
	    $self->{'errorString'} .= "\nError (UMLS::Interface->_config()) - ";
	    $self->{'errorString'} .= "Configuration file can not have an include ";
	    $self->{'errorString'} .= "and exclude list of sources (sab)\n";
	    return ();
	}
	if($includerelkeys > 0 and $excluderelkeys > 0) {
	    $self->{'errorCode'} = 2;
	    $self->{'errorString'} .= "\nError (UMLS::Interface->_config()) - ";
	    $self->{'errorString'} .= "Configuration file can not have an include ";
	    $self->{'errorString'} .= "and exclude list of relations (rel)\n";
	    return ();
	}
	
	if($includerelkeys > 0) {
	    my $relcount = 0;
	    my @parents  = ();
	    my @children = ();
	    foreach my $rel (sort keys %includerel) {
		
		$relcount++;
	       
		if($relcount == $includerelkeys) { $relations .="REL=\'$rel\'";     }
		else                             { $relations .="REL=\'$rel\' or "; }
		
                if($rel=~/(PAR|RB)/) { push @parents, $rel; }
		if($rel=~/(CHD|RN)/) { push @children, $rel; }
                #if($rel=~/(PAR)/) { push @parents, $rel; }
		#if($rel=~/(CHD)/) { push @children, $rel; }
		#if($rel=~/(RB)/) { push @parents, $rel; }
		#if($rel=~/(RN)/) { push @children, $rel; }
	    }
	    
	    for my $i (0..($#parents-1)) { 
		$parentRelations .= "REL=\'$parents[$i]\' or "; 
	    } $parentRelations .= "REL=\'$parents[$#parents]\'"; 
	    
	    for my $i (0..($#children-1)) { 
		$childRelations .= "REL=\'$children[$i]\' or "; 
	    } $childRelations .= "REL=\'$children[$#children]\'";     
	}
	
	#  uses the relations that are set in the includrelkeys or excluderelkeys
	if($excluderelkeys > 0) {
	    
	    my $arrRef = $db->selectcol_arrayref("select distinct REL from MRREL");
	    if($self->checkError($function)) { return (); }
	   
	    my $arrRefkeys = $#{$arrRef} + 1;
	    my $relcount   = 0;
	    my @parents    = ();
	    my @children   = ();
	    foreach my $rel (@{$arrRef}) {
		
		$relcount++;
		
		if(exists $excluderel{$rel}) { next; }

		if($relcount == $arrRefkeys) { $relations .="REL=\'$rel\'";     }
		else                         { $relations .="REL=\'$rel\' or "; }

		#if($rel=~/(PAR|RB)/) { push @parents, $rel; }
		#if($rel=~/(CHD|RN)/) { push @children, $rel; }
		if($rel=~/(PAR)/) { push @parents, $rel; }
		if($rel=~/(CHD)/) { push @children, $rel; }
		#if($rel=~/(RB)/) { push @parents, $rel; }
		#if($rel=~/(RN)/) { push @children, $rel; }
	    }

	    for my $i (0..($#parents-1)) { 
		$parentRelations .= "REL=\'$parents[$i]\' or "; 
	    } $parentRelations .= "REL=\'$parents[$#parents]\'"; 
	    
	    for my $i (0..($#children-1)) { 
		$childRelations .= "REL=\'$children[$i]\' or "; 
	    } $childRelations .= "REL=\'$children[$#children]\'"; 

	}
	if($includesabkeys > 0) {
	    my $sabcount = 0;
	    foreach my $sab (sort keys %includesab) {
		
		$sabcount++;

		if($sabcount == $includesabkeys) { $sources .="SAB=\'$sab\'";     }
		else                             { $sources .="SAB=\'$sab\' or "; }
		
		my $cui = $self->_getSabCui($sab);
		
		if(! (defined $cui) ) {
		    
		    $self->{'errorCode'} = 2;
		    $self->{'errorString'} .= "\nError (UMLS::Interface->_config()) - ";
		    $self->{'errorString'} .= "SAB ($sab) is not valid. ";
		    return ();
		}
		
		$sab_names{$sab}++; 
		$sab_hash{$cui}++;
	    }
	}
	if($excludesabkeys > 0) {

	    my $arrRef = $db->selectcol_arrayref("select distinct SAB from MRREL and ($relations)");
	    if($self->checkError($function)) { return (); }
	   
	    my $arrRefkeys = $#{$arrRef} + 1;
	    my $sabcount   = 0;
	    foreach my $sab (@{$arrRef}) {

		$sabcount++;
		
		if(exists $excludesab{$sab}) { next; }
		if($sabcount == $arrRefkeys) { $sources .="SAB=\'$sab\'";     }
		else                         { $sources .="SAB=\'$sab\' or "; }
		
		my $cui = $self->_getSabCui($sab);
		
		if(! (defined $cui) ) {
		    
		    $self->{'errorCode'} = 2;
		    $self->{'errorString'} .= "\nError (UMLS::Interface->_config()) - ";
		    $self->{'errorString'} .= "SAB ($sab) is not valid. ";
		    return ();
		}
		
		$sab_names{$sab}++; 
		$sab_hash{$cui}++;
		
	    }
	}
    }

    #  there is no configuration file so set the default
    else {

	#  get the CUIs of the default sources
	#my $icdcui = $self->_getSabCui('ICD9CM');
	#my $sctcui = $self->_getSabCui('SNOMEDCT');
	#my $ncicui = $self->_getSabCui('NCI');
	my $mshcui = $self->_getSabCui('MSH');

	if(! (defined $mshcui) ) {
	    $self->{'errorCode'} = 2;
	    $self->{'errorString'} .= "\nError (UMLS::Interface->_config()) - ";
	    $self->{'errorString'} .= "SAB (MSH) is not valid. ";
	    return ();
	}
	#if(! (defined $sctcui) ) {
	    #$self->{'errorCode'} = 2;
	    #$self->{'errorString'} .= "\nError (UMLS::Interface->_config()) - ";
	    #$self->{'errorString'} .= "SAB (SNOMEDCT) is not valid. ";
	    #return ();
	#}
	#if(! (defined $ncicui) ) {
	    #$self->{'errorCode'} = 2;
	    #$self->{'errorString'} .= "\nError (UMLS::Interface->_config()) - ";
	    #$self->{'errorString'} .= "SAB (NCI) is not valid. ";
	    #return ();
	#}
	
	#  set default sources
	#$sources = "SAB=\'ICD9CM\' or SAB=\'SNOMEDCT\' or SAB=\'NCI\'";
	#$sources = "SAB=\'SNOMEDCT\'";
	$sources = "SAB=\'MSH\'";
	
	#$sab_names{'ICD9CM'}++; 
	#$sab_hash{$icdcui}++;

	$sab_names{'MSH'}++; 
	$sab_hash{$mshcui}++;
	
	#$sab_names{'SNOMEDCT'}++; 
	#$sab_hash{$sctcui}++;
	
	#  set default relations
	#$relations = "REL=\'CHD\' or REL=\'PAR\' or REL=\'RB\' or REL=\'RN\'";	
	$relations = "REL=\'CHD\' or REL=\'PAR\'";
	#$relations = "REL=\'RN\' or REL=\'RB\'";
	
	#  set default parent and child relations
	#$parentRelations = "REL=\'PAR\' or REL=\'RB\'";
	#$childRelations  = "REL=\'CHD\' or REL=\'RN\'";
	$parentRelations = "REL=\'PAR\'";
	$childRelations  = "REL=\'CHD\'";
	#$parentRelations = "REL=\'RB\'";
	#$childRelations  = "REL=\'RN\'";
    }

    if($debug) {
	print "SOURCE   : $sources\n";
	print "RELATIONS: $relations\n";
	print "PARENTS  : $parentRelations\n";
	print "CHILDREN : $childRelations\n\n";
    }
}

################# new function as of v0.03
#  Takes as input a SAB and returns its corresponding
#  UMLS CUI. Keep in mind this is the root cui not 
#  the version cui that is returned. The information 
#  for this is obtained from the MRSAB table
sub _getSabCui
{
    my $self = shift;
    my $sab  = shift;

    return () if(!defined $self || !ref $self);

    my $function = "_getSabCui";   
    #&_debug($function);

    if(!$sab) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    


    $self->{'traceString'} = "";
    
    my $arrRef = $db->selectcol_arrayref("select distinct RCUI from MRSAB where RSAB='$sab'");
    if($self->checkError($function)) { return (); }
    
    if(scalar(@{$arrRef}) < 1) {
	$self->{'errorCode'} = 2;
	$self->{'errorString'} .= "\nError (UMLS::Interface->_getSabCui()) - ";
	$self->{'errorString'} .= "No CUI info in table MRSAB for $sab.";
	return ();
    }
    
    if(scalar(@{$arrRef}) > 1) {
	$self->{'errorCode'} = 2 if($self->{'errCode'} < 1);
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->_getSabCui()) - ";
	$self->{'errorString'} .= "Internal error: Duplicate concept rows.";
	return ();
    }
    
    return (pop @{$arrRef});
}

################# new function as of v0.03
#  Takes as input a CUI and returns true or false
#  whether the CUI originated from a given users 
#  view of the UMLS
sub _checkSab 
{
    my $self = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);

    my $function = "_checkSab";
    &_debug($function);
    
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }

    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
    
    my @sabs = $self->getSab($concept);
    
    foreach my $sab (@sabs) {
	if(exists $sab_names{$sab}) { return 1; }
    }
    
    return 0;
}

################# new function as of v0.03
#  Takes as input a CUI and returns all of 
#  the sources in which it originated from
#  given the users view of the UMLS
sub getSab
{
    my $self = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);
 
   my $function = "getSab";
    #&_debug($function);
    
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
 
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

    $self->{'traceString'} = "";
    
    my $arrRef = $db->selectcol_arrayref("select distinct SAB from MRCONSO where CUI='$concept'");    
    if($self->checkError($function)) { return (); }
    
    if(scalar(@{$arrRef}) < 1) {
	$self->{'errorCode'} = 2;
	$self->{'errorString'} .= "\nError (UMLS::Interface->_getSab)) - ";
	$self->{'errorString'} .= "No version info in table MRDOC.";
	return ();
    }

    return @{$arrRef};
}


################# new function as of v0.03
#  Returns the children of a concept - the relations that 
#  are considered children are predefined by the user.
#  The default are the RN and CHD relations
sub getChildren
{
    my $self    = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "getChildren";
    #&_debug($function);

    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }

    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    $self->{'traceString'} = "";

    #  if the concept is the umls root node cui return
    #  the source's cuis
    if($concept eq $umlsRoot) {
	return (keys %sab_hash);
    }
    #  if the concept is a source cui return its children
    #  in the childrenTaxonomy
    elsif(exists $childrenTaxonomy{$concept}) {
	return @{$childrenTaxonomy{$concept}};
    }
    #  otherwise everything is normal so return its children
    else {
	my $arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and ($childRelations) and ($sources) and CVF is null");
	if($self->checkError($function)) { return (); }

	return @{$arrRef}; 
    }
}

################# new function as of v0.03
#  Returns the parents of a concept - the relations that 
#  are considered parents are predefined by the user.
#  The default are the PAR and RB relations
sub getParents
{
    my $self    = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "getParents";
    #&_debug($function);

    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }

    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    $self->{'traceString'} = "";
    

    #  if the cui does not have a parent return its 
    #  source's cui
    if(exists $parentTaxonomy{$concept}) {
	return @{$parentTaxonomy{$concept}};
    }
    #  if the cui is a root return an empty array
    elsif(exists $roots{$concept}) {
	my @returnarray = ();
	return @returnarray; # empty array
    }
    #  if the cui is a source cui but not a root return the umls root
    if( (exists $sab_hash{$concept}) and (! (exists $roots{$concept})) ) {
	return "$umlsRoot";
    }
    #  otherwise everything is normal so return its parents
    else {
	my $arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and ($parentRelations) and ($sources) and CVF is null");
	if($self->checkError($function)) { return (); }
	return @{$arrRef}; 
    }
}

################# new function as of v0.03
#  Depth First Search (DFS) in order to determine 
#  the maximum depth of the taxonomy 
sub _initializeDepthFirstSearch
{
    my $self    = shift;
    my $concept = shift;
    my $d       = shift;
    my $root    = shift;
    
    return () if(!defined $self || !ref $self);
    
    my $function = "_initializeDepthFirstSearch";
    &_debug($function);

    if($debug) { print "$concept: $d: $root\n"; }
    
    if(!(defined $concept) || !(defined $d) || !(defined $root)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();

    }
   
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    open(TABLEFILE, ">$tableFile") || die "Could not open $tableFile";
    
    my @children = $self->getChildren($concept);
    foreach my $child (@children) {
	my @array = (); my $path = \@array;
	$self->_depthFirstSearch($child, $d,$path,*TABLEFILE);
    }
}

################# new function as of v0.03
#  Depth First Search (DFS) in order to determine 
#  the maximum depth of the taxonomy 
sub _depthFirstSearch
{
    my $self    = shift;
    my $concept = shift;
    my $d       = shift;
    my $array   = shift;
    local(*F)   = shift;
        
    my $function = "_depthFirstSearch";
    
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }

    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }

    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
    
    $d++;
    
    my @path = @{$array};
    push @path, $concept;
    
    my $series = join " ", @path;
    
    #  load information into the table
    my $arrRef = $sdb->do("INSERT INTO $tableName (CUI, DEPTH, PATH) VALUES(\'$concept\', '$d', \'$series\')");
    if($self->checkError($function)) { return (); }
    
    #  print information into the file
    print F "$concept\t$d\t$series\n";
    
    #  get all the children
    my @children = $self->getChildren($concept);
    
    #  search through the children
    foreach my $child (@children) {
	
	#  check if child cui has already in the path
	my $flag = 0;
	foreach my $cui (@path) {
	    if($cui eq $child) { $flag = 1; }
	}

	#  if it isn't continue on with the depth first search
	if($flag == 0) {
	    $self->_depthFirstSearch($child, $d, \@path,*F);
	}
	#  otherwise mark it and stop that path
	else { $self->_storeCycle($child, $concept); }
    }
}

################# new function as of v0.03
#  storing the cycle in a hash table
sub _storeCycle
{
    my $self = shift;
    my $cui1 = shift;
    my $cui2 = shift;
    
 
    my $function = "_storeCycle";
    
    if(!$cui1 or !$cui2) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    } 
    
    $cycleHash{$cui1}{$cui2} = $parentRelations;
    $cycleHash{$cui2}{$cui1} = $childRelations;
}

################# added function as of v0.03
################# modified from Semantic-Similarity
#  find the shortest path between two concepts
sub findShortestPath
{
    my $self     = shift;
    my $concept1 = shift;
    my $concept2 = shift;

    return () if(!defined $self || !ref $self);
    
    # Initialize traces.
    $self->{'traceString'} = "" if($self->{'trace'});
    
    my $function = "findShortestPath";
   
    # undefined input cannot go unpunished.
    if(!$concept1 || !$concept2) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->findShortestPath()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }

    if($self->validCui($concept1)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept1).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
    
    if($self->validCui($concept2)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept2).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    #  check that concept1 and concept2 exist
    return () if(! (defined $self->_checkConceptExists($concept1)));
    return () if(! (defined $self->_checkConceptExists($concept2)));
    
    #  determine the cycles and depth of the taxonomy if not already done
    my $depthCheck = $self->_setDepth();
    
    my($lcs, $path) = $self->_findShortestPath($concept1, $concept2);
    
    if(! defined $path) {
	my @array = ();
	$path=\@array;
    }
    
    return @{$path};
}   

################# added function as of v0.03
################# modified from Semantic-Similarity
sub findLeastCommonSubsumer
{   

    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;
    
    return () if(!defined $self || !ref $self);

    my $function = "findLeastCommonSubsumer";
    &_debug($function);
    
    # Undefined input cannot go unpunished.
    if(!$concept1 || !$concept2) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }
    
    if($self->validCui($concept1)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept1).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
    
    if($self->validCui($concept2)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept2).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
    
    # Initialize traces.
    $self->{'traceString'} = "" if($self->{'trace'});
    
    #  check that concept1 and concept2 exist
    if($self->_checkConceptExists($concept1) eq 0) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($concept1) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }
    if($self->_checkConceptExists($concept2) eq 0) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($concept2) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }
    
    my($lcs, $path) = $self->_findShortestPath($concept1, $concept2);

    return $lcs;
}


################# added function as of v0.03
################# modified from Semantic-Similarity
#  this function finds the shortest path between 
#  two concepts and returns the path. in the process 
#  it determines the least common subsumer for that 
#  path so it returns both
sub _findShortestPath
{
    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;

    return () if(!defined $self || !ref $self);

    my $function = "_findShortestPath";
    #&_debug($function);
    
    # Undefined input cannot go unpunished.
    if(!$concept1 || !$concept2) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }
    if($self->validCui($concept1)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept1).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
    
    if($self->validCui($concept2)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept2).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    # Initialize traces.
    $self->{'traceString'} = "" if($self->{'trace'});
    
    #  check that concept1 and concept2 exist
    if($self->_checkConceptExists($concept1) eq 0) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($concept1) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }
    if($self->_checkConceptExists($concept2) eq 0) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($concept2) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }
        
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }
   
    my $lcs;
    my %lcsPaths;
    my %lcsLengths;
    

    # Now check if the similarity value for these two concepts is,
    # in fact, in the cache... if so return the cached value.
    if($self->{'doCache'} && defined $self->{'pathCache'}->{"${concept1}::$concept2"}) {
	if(defined $self->{'traceCache'}->{"${concept1}::$concept2"}) {
	    $self->{'traceString'} = $self->{'traceCache'}->{"${concept1}::$concept2"} 
	    if($self->{'trace'});
	}
	return ($self->{'lcsCache'}=>{"${concept1}::$concept2"}, 
		$self->{'pathCache'}->{"${concept1}::$concept2"});
    
    }

    # Now get down to really finding the relatedness of these two.
    # Get the paths to root.
    my $lTrees = $self->pathsToRoot($concept1);
    my $rTrees = $self->pathsToRoot($concept2);
    
    
    # [trace]
    if($self->{'trace'}) {
	foreach my $lTree (@{$lTrees}) {
	    $self->{'traceString'} .= "HyperTree: ".(join("  ", @{$lTree}))."\n\n";
	}
	foreach my $rTree (@{$rTrees}) {
	    $self->{'traceString'} .= "HyperTree: ".(join("  ", @{$rTree}))."\n\n";
	}
    }
    # [/trace]

    # Find the shortest path in these trees.
    %lcsLengths = ();
    %lcsPaths   = ();
    foreach my $lTree (@{$lTrees}) {
	foreach my $rTree (@{$rTrees}) {
	    $lcs = $self->_getLCSfromTrees($lTree, $rTree);
	    if(defined $lcs) {
		
		my $lCount  = 0;
		my $rCount  = 0;
		my $length  = 0;
		my $concept = "";
		
		my @lArray  = ();
		my @rArray  = ();
		
		my @lTreeArray = split/\s+/, $lTree;
		my @rTreeArray = split/\s+/, $rTree;
		
		foreach $concept (reverse @lTreeArray) {
		    $lCount++;
		    push @lArray, $concept;
		    last if($concept eq $lcs);

		}
		foreach $concept (reverse @rTreeArray) {
		    $rCount++;
		    last if($concept eq $lcs);
		    push @rArray, $concept;
		    
		}

		#  length of the path
		if(exists $lcsLengths{$lcs}) {
		    if($lcsLengths{$lcs} > ($rCount + $lCount - 1)) {
			$lcsLengths{$lcs} = $rCount + $lCount - 1;
			@{$lcsPaths{$lcs}} = (@lArray, (reverse @rArray));
		    }
		}
		else {
		    $lcsLengths{$lcs} = $rCount + $lCount - 1;
		    @{$lcsPaths{$lcs}} = (@lArray, (reverse @rArray));
		}
	    }
	}
    }
    
    # If no paths exist 
    if(!scalar(keys(%lcsPaths))) {
	# [trace]
	if($self->{'trace'}) {
	    $self->{'traceString'} .= "Relatedness 0. No intersecting paths found.\n";
	}
	# [/trace]
	return 0;
    }

    ($lcs) = sort {$lcsLengths{$a} <=> $lcsLengths{$b}} keys(%lcsLengths);

    # [trace]
    if($self->{'trace'}) {
	$self->{'traceString'} .= "LCS: $lcs   ";
	$self->{'traceString'} .= "Path length: $lcsLengths{$lcs}.\n\n";
    }
    # [/trace]


    #  set the Cache
    if($self->{'doCache'}) {
	$self->{'pathCache'}->{"${concept1}::$concept2"}  = $lcsPaths{$lcs};
	$self->{'lcsCache'}->{"${concept1}::$concept2"}   = $lcs;
	$self->{'traceCache'}->{"${concept1}::$concept2"} = $self->{'traceString'} 
	if($self->{'trace'});
	push(@{$self->{'cacheQ'}}, "${concept1}::$concept2");
	if($self->{'maxCacheSize'} >= 0) {
	    while(scalar(@{$self->{'cacheQ'}}) > $self->{'maxCacheSize'}) {
		my $delItem = shift(@{$self->{'cacheQ'}});
		delete $self->{'pathCache'}->{$delItem};
		#delete $self->{'lcsCache'}=>{$delItem};
		delete $self->{'traceCache'}->{$delItem};
	    }
	}
    }
    return ($lcs, $lcsPaths{$lcs});
}

################# added function as of v0.03
sub _checkConceptExists {

    my $self    = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "_checkConceptExists";
    #&_debug($function);
    
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }
    
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }
    
    my $arrRef = $db->selectcol_arrayref("select count(*) from MRREL where (CUI1='$concept' or CUI2='$concept') and ($sources) and ($relations) and (CVF is null)");
    
    my $count = shift @{$arrRef};
    
    if($count eq 0) {
	return 0;
    }
    return 1;
    
}

################# added function as of v0.03
################# modified from Semantic-Similarity
# Subroutine to get the Least Common Subsumer of two
# paths to the root of a taxonomy
sub _getLCSfromTrees
{
    my $self      = shift;
    my $arrayref1 = shift;
    my $arrayref2 = shift;
    
    return () if(!defined $self || !ref $self);
    
    my $function = "_getLCSfromTrees";
    
    if(!$arrayref1 || !$arrayref2) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }

    my @array1 = split/\s+/, $arrayref1;
    my @array2 = split/\s+/, $arrayref2;

    my @tree1 = reverse @array1;
    my @tree2 = reverse @array2;
    my $tmpString = " ".join(" ", @tree2)." ";
    
    foreach my $element (@tree1) {
	if($tmpString =~ / $element /) {
	    return $element;
	}
    }
    
    return undef;
}

################# added function as of v0.03
# Subroutine to get the definition of a given CUI
sub getStDef
{
    my $self = shift;
    my $st   = shift;

    my $function = "getStDef";
    &_debug($function);
    
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }

    if(!$st) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }

    my $arrRef = $db->selectcol_arrayref("select DEF from SRDEF where ABR=\'$st\'");
    if($self->checkError($function)) { return (); }
    
    return (shift @{$arrRef});
} 


sub getCuiDef
{
    
    my $self    = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);

    my $function = "getCuiDef";
    &_debug($function);
    
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }

    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }
    
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 


    $self->{'traceString'} = "";
    
    my $arrRef = $db->selectcol_arrayref("select DEF from MRDEF where CUI=\'$concept\'");
    if($self->checkError($function)) { return (); }
    
    return (@{$arrRef});
}


sub validCui
{
    my $self = shift;
    my $concept = shift;
    
    return () if(!defined $self || !ref $self);
    
    my $function = "validCui";
    
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }
    
    if($concept=~/C[0-9][0-9][0-9][0-9][0-9][0-9][0-9]/) {
	return 0;
    }
    else {
	return 1;
    }
}

sub checkError
{
    my $self     = shift;
    my $function = shift;
    
    my $db = $self->{'db'};
    if($db->err()) {
	$self->{'errorCode'} = 2;
	$self->{'errorString'} .= "\nError (UMLS::Interface function: $function ) - ";
	$self->{'errorString'} .= "Error executing database query: ".($db->errstr());
	return 1;
    }
    return 0;
}


sub dropTable
{
    
    my $self    = shift;

    return () if(!defined $self || !ref $self);

    my $function = "dropTable";
    &_debug($function);

    $self->_connectSourceDB();
    
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }



    my $cd = $sdb->do("drop database $sourceDB");

    return $sourceDB;
    
}

##############################################################################
#  function to create a timestamp
##############################################################################
sub _timeStamp {

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

    $year += 1900;
    $mon++;
    my $d = sprintf("%4d%2.2d%2.2d",$year,$mon,$mday);
    my $t = sprintf("%2.2d%2.2d%2.2d",$hour,$min,$sec);
    
    my $stamp = $d . $t;

    return $stamp;
}

sub _printTime {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

    $year += 1900;
    $mon++;
    
    my $d = sprintf("%4d%2.2d%2.2d",$year,$mon,$mday);
    my $t = sprintf("%2.2d%2.2d%2.2d",$hour,$min,$sec);
    
    print "$t\n";

}


1;

__END__

# Plain-old-Documentation

=head1 NAME

UMLS::Interface - Perl interface to the Unified Medical Language System

=head1 SYNOPSIS

  use UMLS::Interface;

  my $interface = UMLS::Interface->new();

  die "Initialization error.\n" if(!defined $interface);

  ($errCode, $errString) = $interface->getError();

  my $rootID   = $interface->root();

  my $tDepth   = $interface->depth();

  my $ver      = $interface->version();

  my $bool     = $interface->validCui($CUI);
  
  my $bool     = $interface->exists($CUI);

  my @sources  = $interface->getSab($CUI);
  
  my @children = $interface->getChildren($CUI);
  
  my @parents  = $interface->getParents($CUI);

  my @cList    = $interface->getRelated($CUI, $relation);

  my @tList    = $interface->getTermList($term);

  my @cList    = $interface->getConceptList($CUI);

  my @paths    = $interface->pathsToRoot($CUI);

  my @path     = $interface->findShortestPath($CUI1, $CUI2);

  my $lcs      = $interface->findLeastCommonSubsummer($CUI1, $CUI2);
  
  my @cuidefs  = $interface->getCuiDef($CUI);

  my $stdef    = $interface->getStDef($ST);

  $interface->dropTable();

  $interface->disconnect();

=head1 ABSTRACT

This package provides a Perl interface to the Unified Medical Language 
System. The package is set up to access pre-specified sources of the UMLS
present ina mysql database.  The package was essentially created for use 
with the UMLS::Similarity package formeasuring the semantic relatedness 
of concepts.

=head1 INSTALL

To install the module, run the following magic commands:

  perl Makefile.PL
  make
  make test
  make install

This will install the module in the standard location. You will, most
probably, require root privileges to install in standard system
directories. To install in a non-standard directory, specify a prefix
during the 'perl Makefile.PL' stage as:

  perl Makefile.PL PREFIX=/home/sid

It is possible to modify other parameters during installation. The
details of these can be found in the ExtUtils::MakeMaker
documentation. However, it is highly recommended not messing around
with other parameters, unless you know what you're doing.

=head1 DESCRIPTION

This package provides a Perl interface to Snomed CT, a taxonomy of
medical concepts. The package is set up to access Snomed CT present in
a mysql database. Some perl programs also require access to the
SEMCLUST database, which is a database of clusters of concepts. This
interface provides access to SEMCLUST as well. The package was
essentially created for use with the Semantic::Similarity package for
measuring the semantic relatedness of concepts.

=head2 DATABASE SETUP

The interface assumes that the UMLS is present as a mysql database. 
The name of the database can be passed as configuration options at 
initialization. However, if the names of the databases are not 
provided at initialization, then default value is used -- the 
database for the UMLS is called 'umls'. 

The UMLS database must contain four tables: 
	1. MRREL
	2. MRCONSO
	3. MRSAB
	4. MRDOC

All other tables in the databases will be ignored, and any of these
tables missing would raise an error.

A script explaining how to install the UMLS and the mysql database 
are in the INSTALL file.

=head2 INITIALIZING THE MODULE

To create an instance of the interface object, using default values
for all configuration options:

  use UMLS::Interface;
  my $interface = UMLS::Interface->new();

Database connection options can be passed through the my.cnf file. For 
example: 
           [client]
	    user            = <username>
	    password	    = <password>
	    port	    = 3306
	    socket          = /tmp/mysql.sock
	    database        = umls

Or through the by passing the connection information when first 
instantiating an instance. For example:

    $umls = UMLS::Interface->new({"driver" => "mysql", 
				  "database" => "$database", 
				  "username" => "$opt_username",  
				  "password" => "$opt_password", 
				  "hostname" => "$hostname", 
				  "socket"   => "$socket"}); 

  'driver'       -> Default value 'mysql'. This option specifies the Perl 
                    DBD driver that should be used to access the
                    database. This implies that the some other DBMS
                    system (such as PostgresSQL) could also be used,
                    as long as there exist Perl DBD drivers to
                    access the database.
  'umls'         -> Default value 'umls'. This option specifes the name
                    of the UMLS database.
  'hostname'     -> Default value 'localhost'. The name or the IP address
                    of the machine on which the database server is
                    running.
  'socket'       -> Default value '/tmp/mysql.sock'. The socket on which 
                    the database server is using.
  'port'         -> The port number on which the database server accepts
                    connections.
  'username'     -> Username to use to connect to the database server. If
                    not provided, the module attempts to connect as an
                    anonymous user.
  'password'     -> Password for access to the database server. If not
                    provided, the module attempts to access the server
                    without a password.

More information is provided in the INSTALL file Stage 5 Step D (search for 
'Step D' and you will find it).
 
=head2 Configuration file

There exist a configuration files to specify which source and what relations 
are to be used. The default source is the Medical Subject Heading (MSH) 
vocabulary and the default relations are the PAR/CHD relation. 


  'config' -> File containing the source and relation parameters

The configuration file can be passed through the instantiation of 
the UMLS-Interface. Similar to passing the connection options. For 
example:

    $umls = UMLS::Interface->new({"driver"      => "mysql", 
				  "database"    => $database, 
				  "username"    => $opt_username,  
				  "password"    => $opt_password, 
				  "hostname"    => $hostname, 
				  "socket"      => $socket,
                                  "config"      => $configfile});

    or

    $umls = UMLS::Interface->new({"config" => $configfile});

The format of the configuration file is as follows:

SAB :: <include|exclude> <source1, source2, ... sourceN>

REL :: <include|exclude> <relation1, relation2, ... relationN>

For example, if we wanted to use the MSH vocabulary with only 
the RB/RN relations, the configuration file would be:

SAB :: include MSH
REL :: include RB, RN

or 

SAB :: include MSH
REL :: exclude PAR, CHD

=head1 SEE ALSO

Perl(1), Semantic::Similarity(3)

=head1 AUTHOR

Bridget T McInnes <bthomson@cs.umn.edu>
Ted Pedersen <tpederse@d.umn.edu>

=head1 COPYRIGHT

 Copyright (c) 2007-2009
 Bridget T. McInnes, University of Minnesota
 bthomson at cs.umn.edu

 Ted Pedersen, University of Minnesota Duluth
 tpederse at d.umn.edu

 Siddharth Patwardhan, University of Utah, Salt Lake City
 sidd@cs.utah.edu
 
 Serguei Pakhomov, University of Minnesota Twin Cities
 pakh0002@umn.edu

This program is free software; you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation; either version 2 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with
this program; if not, write to 

 The Free Software Foundation, Inc.,
 59 Temple Place - Suite 330,
 Boston, MA  02111-1307, USA.

=cut
