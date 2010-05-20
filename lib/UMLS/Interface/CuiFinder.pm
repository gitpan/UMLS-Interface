# UMLS::Interface::CuiFinder
# (Last Updated $Id: CuiFinder.pm,v 1.2 2010/05/20 14:54:43 btmcinnes Exp $)
#
# Perl module that provides a perl interface to the
# Unified Medical Language System (UMLS)
#
# Copyright (c) 2004-2010,
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
# Ying Liu, University of Minnesota
# liux0935 at umn.edu
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

package UMLS::Interface::CuiFinder;

use Fcntl;
use strict;
use warnings;
use DBI;
use bytes;

use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);

my $debug = 0;

my $umlsRoot = "C0085567";

my $version = "";
 
my $max_depth = 0;

#  list of allowable sources 
my $sources      = "";
my %sabHash      = ();
my %sabnamesHash = ();

#  list of allowable relations
my $relations       = "";
my $childRelations  = "";
my $parentRelations = "";

#  upper level taxonomy
my %parentTaxonomyArray = ();
my %childTaxonomyArray  = ();

#  list of interested cuis - default is 
#  all given the specified set of sources
#  and relations. 
my %cuiListHash    = ();

#  database
my $indexDB        = "umlsinterfaceindex";
my $umlsinterface   = $ENV{UMLSINTERFACE_CONFIGFILE_DIR};

my $tableName       = "";
my $parentTable     = "";
my $childTable      = "";
my $tableFile       = "";
my $parentTableHuman= "";
my $childTableHuman = "";
my $tableNameHuman  = "";
my $configFile      = "";
my $childFile       = "";
my $parentFile      = "";
my $propTable       = "";
my $propTableHuman  = "";

my $umlsall    = 0;

my $option_verbose     = 0;
my $option_cuilist     = 0;
my $option_t           = 0;

my $sabDefString       = "";
my %relDefHash         = ();
my %sabDefHash         = ();

local(*DEBUG_FILE);

######################################################################
#  functions to initialize the package
######################################################################

#  method to create a new UMLS::Interface object
#  input : $parameters <- reference to a hash
#  output: $self
sub new {

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


#  method to initialize the UMLS::Interface object.
#  input : $parameters <- reference to a hash
#  output:  
sub _initialize {

    my $self = shift;
    my $params = shift;

    return undef if(!defined $self || !ref $self);
    $params = {} if(!defined $params);

    my $function = "_initialize";
    &_debug($function);

    #  get some of the parameters
    my $config       = $params->{'config'};
    my $cuilist      = $params->{'cuilist'};
    my $database     = $params->{'database'};
    
    #  to store the database object
    my $db = $self->_setDatabase($params);
    if($self->_checkError($function)) { return (); }	

    #  set up the options
    $self->_setOptions($params);
    if($self->_checkError($function)) { return (); }	

    #  check that all of the tables required exist in the db
    $self->_checkTablesExist();
    if($self->_checkError($function)) { return (); }	

    #  set the version information
    $self->_setVersion();
    if($self->_checkError($function)) { return (); }	

    #  set the configuration
    $self->_config($config); 
    if($self->_checkError("_config")) { return (); } 
        
    #  set the umls interface configuration variable
    $self->_setEnvironmentVariable();
    if($self->_checkError("_setEnvironmentVariable")) { return (); }	

    #  set the table and file names for indexing
    $self->_setConfigurationFile();
    if($self->_checkError("_setConfigurationFile")) { return (); }	
    
    #  set the configfile
    $self->_setConfigFile();
    if($self->_checkError("_setConfigFile")) { return (); }	
    
    #  load the cuilist if it has been defined
    $self->_loadCuiList($cuilist);
    if($self->_checkError("_loadCuiList")) { return (); }	

    #  create the index database
    $self->_createIndexDB();
    if($self->_checkError("_createIndexDB")) { return (); }	
    
    #  connect to the index database
    $self->_connectIndexDB();
    if($self->_checkError("_connectIndexDB")) { return (); }	

    #  set the upper level taxonomy
    $self->_setUpperLevelTaxonomy();
    if($self->_checkError("_setUpperLevelTaxonomy")) { return (); }

}

#  this function returns the umls root
#  input : 
#  output: $string <- string containing the root
sub _root {
    
    return $umlsRoot;
}

#  this function sets the upper level taxonomy between 
#  the sources and the root UMLS node
#  input : 
#  output: 
sub _setUpperLevelTaxonomy  {
    
    my $self = shift;
    
    my $function = "_setUpperLevelTaxonomy";
    &_debug($function);
    
    return undef if(!defined $self || !ref $self);
    
    #  set the sourceDB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) { return($self->_error($function, "A db is required.")); }       
    
    #  check if the taxonomy is already set
    my $ckeys = keys %childTaxonomyArray;
    my $pkeys = keys %parentTaxonomyArray;
    if($pkeys > 0) { return; }
    
    #  check if the parent and child tables exist and if they do just return otherwise create them
    if($self->_checkTableExists($childTable) and $self->_checkTableExists($parentTable)) {
	$self->_loadTaxonomyArrays();
	if($self->_checkError("_loadTaxonomyArrays")) { return (); }   
	return;
    }
    else {
	$self->_createTaxonomyTables();
	if($self->_checkError("_createTaxonomyTables")) { return (); }   
    }
    
    
    #  if the parent and child files exist just load them into the database
    if( (-e $childFile) and (-e $parentFile) ) {

	$self->_loadTaxonomyTables();
	if($self->_checkError("_loadTaxonomyTables")) { return (); }   
    }
    #  otherwise we need to create them
    else {
       
	$self->_createUpperLevelTaxonomy();
	if($self->_checkError("_createUpperLevelTaxonomy")) { return (); }   
    }
}

#  this function creates the upper level taxonomy between the 
#  the sources and the root UMLS node
#  this function creates the upper level taxonomy between the 
#  the sources and the root UMLS node
#  input :
#  output: 
sub _createUpperLevelTaxonomy {

    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_createUpperLevelTaxonomy";
    &_debug($function);
    
    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) {	return($self->_error($function, "A db is required.")); }
        
    #  set up the database
    my $db = $self->{'db'};
    if(!$db) { return($self->_error($function, "A db is required.")); }
    
    # open the parent and child files to store the upper level 
    #  taxonomy information if the verbose option is defined
    if($option_verbose) {
	open(CHD, ">$childFile")  || die "Could not open $childFile\n";
	open(PAR, ">$parentFile") || die "Could not open $parentFile\n";
    }
        
    foreach my $sab (sort keys %sabnamesHash) {
	
	#  get the sab's cui
	my $sab_cui = $self->_getSabCui($sab);
	
	#  select all the CUIs from MRREL 
	my $allCuis = $self->_getCuis($sab);
	
	#  select all the CUI1s from MRREL that have a parent link
	if($debug) { print STDERR "selecting CUIs from MRREL that have parent link for $sab\n"; }
	my $parCuis = $db->selectcol_arrayref("select CUI1 from MRREL where ($parentRelations) and (SAB=\'$sab\')");
        if($self->_checkError($function)) { return undef; }
	
	#  load the cuis that have a parent into a temporary hash
	my %parCuisHash = ();
	foreach my $cui (@{$parCuis}) { $parCuisHash{$cui}++; }
    
	#  load the cuis that do not have a parent into the parent 
	#  and chilren taxonomy for the upper level
	foreach my $cui (@{$allCuis}) {
	
	    #  if the cui has a parent move on
	    if(exists $parCuisHash{$cui})    { next; }
	
	    #  already seen this cui so move on
	    if(exists $parentTaxonomyArray{$cui}) { next; }
	
		
	    if($sab_cui eq $cui) { next; }
	    
	    push @{$parentTaxonomyArray{$cui}}, $sab_cui;
	    push @{$childTaxonomyArray{$sab_cui}}, $cui;

	    $sdb->do("INSERT INTO $parentTable (CUI1, CUI2) VALUES ('$cui', '$sab_cui')");	    
	    if($self->_checkError($function)) { return (); }   		
	    
	    $sdb->do("INSERT INTO $childTable (CUI1, CUI2) VALUES ('$sab_cui', '$cui')");	    
	    if($self->_checkError($function)) { return (); } 
	    
	    #  print this information to the parent and child 
	    #  file is the verbose option has been set
	    if($option_verbose) {
		print PAR "$cui $sab_cui\n";
		print CHD "$sab_cui $cui\n";
	    }
	}
        
        #  add the sab cuis to the parent and children Taxonomy
	push @{$parentTaxonomyArray{$sab_cui}}, $umlsRoot;
	push @{$childTaxonomyArray{$umlsRoot}}, $sab_cui;

	#  print it to the table if the verbose option is set
	if($option_verbose) { 
	    print PAR "$sab_cui  $umlsRoot\n"; 
	    print CHD "$umlsRoot $sab_cui\n"; 
	}
	
	#  store this information in the database
	$sdb->do("INSERT INTO $parentTable (CUI1, CUI2) VALUES ('$sab_cui', '$umlsRoot')");	    
	if($self->_checkError($function)) { return (); }   		
	
	$sdb->do("INSERT INTO $childTable (CUI1, CUI2) VALUES ('$umlsRoot', '$sab_cui')"); 
	if($self->_checkError($function)) { return (); }   		
    }
    
    #  close the parent and child tables if opened
    if($option_verbose) { close PAR; close CHD; }

    #  print out some information
    my $pkey = keys %parentTaxonomyArray;
    my $ckey = keys %childTaxonomyArray;
    
    if($debug) {
	print STDERR "Taxonomy is set:\n";
	print STDERR "  parentTaxonomyArray: $pkey\n";
	print STDERR "  childTaxonomyArray: $ckey\n\n";
    }
}


#  this function creates the taxonomy tables if they don't
#  already exist in the umlsinterfaceindex database
#  input : 
#  output: 
sub _createTaxonomyTables {

    my $self = shift;

    return undef if(!defined $self || !ref $self);

    my $function = "_createTaxonomyTables";
    &_debug($function);

    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) { return($self->_error($function, "A db is required.")); }

    #  create parent table
    $sdb->do("CREATE TABLE IF NOT EXISTS $parentTable (CUI1 char(8), CUI2 char(8))");
    if($self->_checkError($function)) { return (); }
    
    #  create child table
    $sdb->do("CREATE TABLE IF NOT EXISTS $childTable (CUI1 char(8), CUI2 char(8))");
    if($self->_checkError($function)) { return (); }
    
    #  create the index table if it doesn't already exist
    $sdb->do("CREATE TABLE IF NOT EXISTS tableindex (TABLENAME blob(1000000), HEX char(41))");
    if($self->_checkError($function)) { return (); }
    
    #  add them to the index table
    $sdb->do("INSERT INTO tableindex (TABLENAME, HEX) VALUES ('$parentTableHuman', '$parentTable')");
    if($self->_checkError($function)) { return (); }   
    $sdb->do("INSERT INTO tableindex (TABLENAME, HEX) VALUES ('$childTableHuman', '$childTable')");
    if($self->_checkError($function)) { return (); }   
}    

#  this function loads the taxonomy tables if the
#  configuration files exist for them
#  input : 
#  output: 
sub _loadTaxonomyTables {

    my $self = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_loadTaxonomyTables";
    &_debug($function);
    
    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) { return($self->_error($function, "A db is required.")); }
    
    open(PAR, $parentFile) || die "Could not open $parentFile\n";	
    open(CHD, $childFile)  || die "Could not open $childFile\n";
    
    
    #  load parent table
    while(<PAR>) {
	chomp;
	if($_=~/^\s*$/) { next; }
	my ($cui1, $cui2) = split/\s+/;
	
	my $arrRef = $sdb->do("INSERT INTO $parentTable (CUI1, CUI2) VALUES ('$cui1', '$cui2')");	    
	if($self->_checkError($function)) { return (); }   
    }
    
    #  load child table
    while(<CHD>) {
	chomp;
	if($_=~/^\s*$/) { next; }
	my ($cui1, $cui2) = split/\s+/;
	my $arrRef = $sdb->do("INSERT INTO $childTable (CUI1, CUI2) VALUES ('$cui1', '$cui2')");	    
	if($self->_checkError($function)) { return (); }
    }
    close PAR; close CHD; 
}

#  this function sets the taxonomy arrays
#  input : 
#  output: 
sub _loadTaxonomyArrays {

    my $self = shift;

    return undef if(!defined $self || !ref $self);

    my $function = "_loadTaxonomyArrays";
    &_debug($function);

    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) { return($self->_error($function, "A db is required.")); }
    
    #  set the parent taxonomy
    my $sql = qq{ SELECT CUI1, CUI2 FROM $parentTable};
    my $sth = $sdb->prepare( $sql );
    $sth->execute();
    my($cui1, $cui2);
    $sth->bind_columns( undef, \$cui1, \$cui2 );
    while( $sth->fetch() ) {
	push @{$parentTaxonomyArray{$cui1}}, $cui2;    
    } $sth->finish();
    
    
    #  set the child taxonomy
    $sql = qq{ SELECT CUI1, CUI2 FROM $childTable};
    $sth = $sdb->prepare( $sql );
    $sth->execute();
    $sth->bind_columns( undef, \$cui1, \$cui2 );
    while( $sth->fetch() ) {
	push @{$childTaxonomyArray{$cui1}}, $cui2;    
    } $sth->finish();
}

#  function checks to see if a given table exists
#  input : $table <- string
#  output: 0 | 1  <- integers
sub _checkTableExists {
    
    my $self  = shift;
    my $table = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "_checkTableExists";
    
    #  check that the database exists
    my $sdb = $self->{'sdb'};
    if(!$sdb) { return($self->_error($function, "A db is required.")); }       
    
    my $sth = $sdb->prepare("show tables");
    $sth->execute();
    if($sth->err()) {
	return($self->_error($function, "Unable run query: ($sth->errstr())"));
    }
    
    my $t      = "";
    my %tables = ();
    while(($t) = $sth->fetchrow()) {
	$tables{lc($t)} = 1;
	
    }
    $sth->finish();
    
    if(! (exists$tables{lc($table)})) { return 0; }
    else                              { return 1; }

}

#  connect the database to the source db that holds
#  the path tables for user specified source(s) and 
#  relation(s)
#  input : 
#  output: $sdb <- reference to the database
sub _connectIndexDB {

    my $self = shift;
    
    &_debug("_connectIndexDB");
    my $sdb = "";

    if(defined $self->{'username'}) {
	
	my $username = $self->{'username'};
	my $password = $self->{'password'};
	my $hostname = $self->{'hostname'};
	my $socket   = $self->{'socket'};
	
	$sdb = DBI->connect("DBI:mysql:database=$indexDB;mysql_socket=$socket;host=$hostname",$username, $password, {RaiseError => 1});
    }
    else {
	my $dsn = "DBI:mysql:$indexDB;mysql_read_default_group=client;";
	$sdb = DBI->connect($dsn);
    }
    
    $self->{'sdb'} = $sdb;
    
    return $sdb;
}

#  return the database connection to the umlsinterfaceindex
sub _getIndexDB {
    my $self = shift;
    
    my $function = "_getIndexDB";
    &_debug($function);

    my $sdb = $self->{'sdb'};
    if(!$sdb) { return($self->_error($function, "A db is required.")); }       
    
    return $sdb;
}

#  this function creates the umlsinterfaceindex database connection
#  input : 
#  output: 
sub _createIndexDB {
    
    my $self = shift;
    
    return () if(!defined $self || !ref $self);
    
    my $function = "_createIndexDB";
    &_debug($function);
    
    #  check that the database exists
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
    
    #  show all of the databases
    my $sth = $db->prepare("show databases");
    $sth->execute();
    if($sth->err()) {
	return($self->_error($function, "Unable run query: ($sth->errstr())"));
    }
    
    #  get all the databases in mysql
    my $database  = "";
    my %databases = ();
    while(($database) = $sth->fetchrow()) {
	$databases{$database}++;
    }
    $sth->finish();
    
    #  removing any spaces that may have been
    #  introduced in while creating its name
    $indexDB=~s/\s+//g;

    #  if the database doesn't exist create it
    if(! (exists $databases{$indexDB})) {
	$db->do("create database $indexDB");
	if($self->_checkError($function)) { return (); }   		
    }
}

#  checks to see if a concept is in the CuiList
#  input : $concept -> string containing the cui
#  output: 1|0      -> indicating if the cui is in the cuilist
sub _inCuiList {
    
    my $self    = shift;
    my $concept = shift;
    
    if(exists $cuiListHash{$concept}) { return 1; }
    else                              { return 0; }
}

    
#  if the cuilist option is specified load the information
#  input : $cuilist <- file containing the list of cuis
#  output: 
sub _loadCuiList {

    my $self    = shift;
    my $cuilist = shift;
    
    my $function = "_loadCuiList";

    if(defined $cuilist) {
	open(CUILIST, $cuilist) || die "Could not open the cuilist file: $cuilist\n"; 
	while(<CUILIST>) {
	    chomp;
	    
	    if($self->_validCui($_)) {
		return($self->_error($function, "Incorrect input value ($_) in cuilist."));
	    }
	    
	    $cuiListHash{$_}++;
	} 
    }
}

#  create the configuration file 
#  input : 
#  output: 
sub _setConfigFile {

    my $self   = shift;

    return undef if(!defined $self || !ref $self);
    
    if($option_verbose) {
        
	my $function = "_setConfigFile";
	&_debug($function);
	
	if(! (-e $configFile)) {
	    
	    open(CONFIG, ">$configFile") ||
		die "Could not open configuration file: $configFile\n";
	    
	    my @sarray = ();
	    my @rarray = ();
	    
	    print CONFIG "SAB :: include ";
	    while($sources=~/=\'(.*?)\'/g)   { push @sarray, $1; }
	    my $slist = join ", ", @sarray;
	    print CONFIG "$slist\n";
	    
	    print CONFIG "REL :: include ";
	    while($relations=~/=\'(.*?)\'/g) { push @rarray, $1; }
	    my $rlist = join ", ", @rarray;
	    print CONFIG "$rlist\n";
	    
	    close CONFIG;
	    
	    my $temp = chmod 0777, $configFile;
	}
    }
}


#  set the table and file names that store the upper level taxonomy and path information
#  input : 
#  output: 
sub _setConfigurationFile {

    my $self = shift;

    return undef if(!defined $self || !ref $self);

    my $function = "_setConfigurationFile";
    &_debug($function);

    #  get the database name that we are using
    my $database = $self->{'database'};
    
    #  set appropriate version output
    my $ver = $version;
    $ver=~s/-/_/g;
    
    #  set table and upper level relations files
    $childFile  = "$umlsinterface/$ver";
    $parentFile = "$umlsinterface/$ver";
    $tableFile  = "$umlsinterface/$ver";
    
    $configFile = "$umlsinterface/$ver";
    
    $tableName  = "$ver";
    $parentTable= "$ver";
    $childTable = "$ver";
    $propTable  = "$ver";
    
    my $output = "";
    $output .= "UMLS-Interface Configuration Information\n";
    $output .= "  Sources:\n";
    foreach my $sab (sort keys %sabnamesHash) {
	$tableFile  .= "_$sab";
	$childFile  .= "_$sab";
	$parentFile .= "_$sab";
	
	$configFile .= "_$sab";
	$tableName  .= "_$sab";
	$parentTable.= "_$sab";
	$childTable .= "_$sab";
	$propTable  .= "_$sab";
	
	$output .= "    $sab\n"; 	
    }
    if($umlsall) { 
	$output .= "    UMLS_ALL\n";
    }

    $output .= "  Relations:\n";
    while($relations=~/=\'(.*?)\'/g) {
	my $rel = $1;
	$rel=~s/\s+//g;
	$tableFile  .= "_$rel";
	$childFile  .= "_$rel";
	$parentFile .= "_$rel";
	$configFile .= "_$rel";
	$tableName  .= "_$rel";	
	$parentTable.= "_$rel";
	$childTable .= "_$rel";
	$propTable  .= "_$rel";

	$output .= "    $rel\n";
    }
    
    $tableFile  .= "_table";
    $childFile  .= "_child";
    $parentFile .= "_parent";
    $configFile .= "_config";
    $tableName  .= "_table";
    $parentTable.= "_parent";
    $childTable .= "_child";
    $propTable .= "_prop";

    #  convert the databases to the hex name
    #  and store the human readable form 
    $tableNameHuman   = $tableName;
    $childTableHuman  = $childTable;
    $parentTableHuman = $parentTable;
    $propTableHuman   = $propTable;

    $tableName   = "a" . sha1_hex($tableNameHuman);
    $childTable  = "a" . sha1_hex($childTableHuman);
    $parentTable = "a" . sha1_hex($parentTableHuman);
    $propTable   = "a" . sha1_hex($propTableHuman);

    if($option_verbose) {
	$output .= "  Configuration file:\n";
	$output .= "    $configFile\n";
    }
    
    $output .= "  Database: \n";
    $output .= "    $database ($version)\n\n";
    
    if($option_t == 0) {
	print STDERR "$output\n";
    }
}

#  set the configuration environment variable
#  input : 
#  output: 
sub _setEnvironmentVariable {

    my $self = shift;

    return undef if(!defined $self || !ref $self);

    if($option_verbose) {
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
		    print STDERR "  Is $umlsinterface the correct location? ";
		    my $answer = <STDIN>; chomp $answer;
		    if($answer=~/[Yy]/) { 
			$answerFlag    = 1; 
			$interfaceFlag = 1;   
		    }
		    else {
			print STDERR "Please entire in location:\n";
			$umlsinterface = <STDIN>; chomp $umlsinterface;
		    }
		}
		
		if(! (-e $umlsinterface) ) {
		    system "mkdir -m 777 $umlsinterface";
		}
		
		print STDERR "Please set the UMLSINTERFACE_CONFIGFILE_DIR variable:\n\n";
		print STDERR "It can be set in csh as follows:\n\n";
		print STDERR " setenv UMLSINTERFACE_CONFIGFILE_DIR $umlsinterface\n\n";
		print STDERR "And in bash shell:\n\n";
		print STDERR " export UMLSINTERFACE_CONFIGFILE_DIR=$umlsinterface\n\n";
		print STDERR "Thank you!\n\n";
	    }
	}
    }
    else {
	$umlsinterface = "";
    }
}

#  sets the relations, parentRelations and childRelations
#  variables from the information in the config file
#  input : $includerelkeys <- integer
#        : $excluderelkeys <- integer
#        : $includerel     <- reference to hash
#        : $excluderel     <- reference to hash
#  output: 
sub _setRelations {

    my $self           = shift;
    my $includerelkeys = shift;
    my $excluderelkeys = shift;
    my $includerel     = shift;
    my $excluderel     = shift;


    my $function = "_setRelations";
    &_debug($function);
    
    return () if(!defined $self || !ref $self);

    #  check the parameters are defined
    if(!(defined $includerelkeys) || !(defined $excluderelkeys) || 
       !(defined $includerel)     || !(defined $excluderel)) {
	return ($self->_error($function, "Undefined input values."));
    }
    
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
	       
    $parentRelations = "(";
    $childRelations  = "(";
    $relations       = "(";
    
    #  get the relations
    my @array = ();
    if($includerelkeys > 0) { 
	@array = keys %{$includerel};
    }
    else {
	
	my $arrRef = $db->selectcol_arrayref("select distinct REL from MRREL");
	if($self->_checkError($function)) { return (); }
	@array = @{$arrRef};
    }
    
    my $relcount = 0;
    my @parents  = ();
    my @children = ();
    foreach my $rel (@array) { 
	
       	$relcount++;
	
	#  if we are excluding check to see if this one should be excluded
	if( ($excluderelkeys > 0) and (exists ${$excluderel}{$rel}) ) { next; }
	
	#  otherwise store the relation in the relations variable
	if($relcount == ($#array+1)) { $relations .= "REL=\'$rel\'";     }
	else                         { $relations .= "REL=\'$rel\' or "; }
	
	#  put it in its proper parent or child array
	if   ($rel=~/(PAR|RB)/) { push @parents, $rel;    }
	elsif($rel=~/(CHD|RN)/) { push @children, $rel;   }
	else { push @parents, $rel; push @children, $rel; }
    
    }
    
    #  set the parentRelations and childRelations variables
    for my $i (0..($#parents-1)) { 
	$parentRelations .= "REL=\'$parents[$i]\' or "; 
    } $parentRelations .= "REL=\'$parents[$#parents]\'"; 
    
    for my $i (0..($#children-1)) { 
	$childRelations .= "REL=\'$children[$i]\' or "; 
    } $childRelations .= "REL=\'$children[$#children]\'";     
    
    $parentRelations .= ") ";
    $childRelations  .= ") ";
    $relations       .= ") ";
    
}

#  sets the source variables from the information in the config file
#  input : $includesabdefkeys <- integer
#        : $excludesabdefkeys <- integer
#        : $includedefsab     <- reference to hash
#        : $excludedefsab     <- reference to hash
#  output: 
sub _setSabDef {

    my $self              = shift;
    my $includesabdefkeys = shift;
    my $excludesabdefkeys = shift;
    my $includesabdef     = shift;
    my $excludesabdef     = shift;


    my $function = "_setSabDef";
    &_debug($function);
    
    return () if(!defined $self || !ref $self);

    #  check the parameters are defined
    if(!(defined $includesabdefkeys) || !(defined $excludesabdefkeys) || 
       !(defined $includesabdef)     || !(defined $excludesabdef)) {
	return ($self->_error($function, "Undefined input values."));
    }
    
    #  check that the db is defined
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    #  get the sabs
    my @array = ();
    if($includesabdefkeys > 0) { 
	@array = keys %{$includesabdef};
    }
    else {
	my $arrRef = $db->selectcol_arrayref("select distinct SAB from MRREL");
	if($self->_checkError($function)) { return (); }
	@array = @{$arrRef};
    }
	
    #  get the sabs
    my $sabcount = 0; my @sabarray = ();
    foreach my $sab (@array) { 
	    
	$sabcount++;
	    
	#  if we are excluding check to see if this sab can be included
	if(($excludesabdefkeys > 0) and (exists ${$excludesabdef}{$sab})) { next; }	
	
	#  otherwise store it in the sabdef hash and store it in the array
	push @sabarray, "SAB=\'$sab\'";

	$sabDefHash{$sab}++;
    }
    
    my $string = join " or ", @sabarray;
    
    $sabDefString = "( $string )";
}

#  sets the relations, parentRelations and childRelations
#  variables from the information in the config file
#  input : $includereldefkeys <- integer
#        : $excludereldefkeys <- integer
#        : $includereldef     <- reference to hash
#        : $excludereldef     <- reference to hash
#  output: 
sub _setRelDef {

    my $self           = shift;
    my $includereldefkeys = shift;
    my $excludereldefkeys = shift;
    my $includereldef     = shift;
    my $excludereldef     = shift;


    my $function = "_setRelDef";
    &_debug($function);
    
    return () if(!defined $self || !ref $self);

    #  check the parameters are defined
    if(!(defined $includereldefkeys) || !(defined $excludereldefkeys) || 
       !(defined $includereldef)     || !(defined $excludereldef)) {
	return ($self->_error($function, "Undefined input values."));
    }
    
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
    
    #  get the relations
    my @array = ();
    if($includereldefkeys > 0) { 
	@array = keys %{$includereldef};
    }
    else {
	
	my $arrRef = $db->selectcol_arrayref("select distinct REL from MRREL");
	if($self->_checkError($function)) { return (); }
	@array = @{$arrRef};
    }
    
    my $relcount = 0;
    
    foreach my $rel (@array) { 
	
       	$relcount++;
	
	#  if we are excluding check to see if this one should be excluded
	if( ($excludereldefkeys > 0) and (exists ${$excludereldef}{$rel}) ) { next; }


	#  otherwise store the relation in the reldef hash	
	$relDefHash{$rel}++;
    }    


    #  now add the TERM and CUI which are not actual relations but should be in 
    #  the relDefHash if in the includereldef or not in the excludereldef or 
    #  nothing has been defined
    if($includereldefkeys > 0) { 
	if(exists ${$includereldef}{"TERM"}) { $relDefHash{"TERM"}++; }
	if(exists ${$includereldef}{"CUI"})  { $relDefHash{"CUI"}++;  }
    }
    elsif($excludereldefkeys > 0) { 
	if(! exists ${$excludereldef}{"TERM"}) { $relDefHash{"TERM"}++; }
	if(! exists ${$excludereldef}{"CUI"})  { $relDefHash{"CUI"}++;  }
    }
    else {
	$relDefHash{"TERM"}++; $relDefHash{"CUI"}++; 
    }
}

#  sets the variables for using the entire umls rather than just a subset    
#  input : 
#  output: 
sub _setUMLS_ALL {
    
    my $self = shift;
    
    my $function = "_setUMLS_ALL";
    &_debug($function);
    
    return () if(!defined $self || !ref $self);

    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
	       
    my $arrRef = $db->selectcol_arrayref("select distinct SAB from MRREL where $relations");
    if($self->_checkError($function)) { return (); }
    
    foreach my $sab (@{$arrRef}) {

	my $cui = $self->_getSabCui($sab);
	if($self->_checkError($function)) { return (); }
	
	if(! (defined $cui) ) {
	    return($self->_error($function, "SAB ($sab) is not valid."));
	}
	
	$sabnamesHash{$sab}++; 
	$sabHash{$cui}++;
	    
    }
}

#  sets the source variables from the information in the config file
#  input : $includesabkeys <- integer
#        : $excludesabkeys <- integer
#        : $includesab     <- reference to hash
#        : $excludesab     <- reference to hash
#  output: 
sub _setSabs {

    my $self           = shift;
    my $includesabkeys = shift;
    my $excludesabkeys = shift;
    my $includesab     = shift;
    my $excludesab     = shift;


    my $function = "_setSabs";
    &_debug($function);
    
    return () if(!defined $self || !ref $self);

    #  check the parameters are defined
    if(!(defined $includesabkeys) || !(defined $excludesabkeys) || 
       !(defined $includesab)     || !(defined $excludesab)) {
	return ($self->_error($function, "Undefined input values."));
    }
    
    #  check that the db is defined
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    #  get the sabs
    my @array = ();
    if($includesabkeys > 0) { 
	@array = keys %{$includesab};
    }
    else {
	my $arrRef = $db->selectcol_arrayref("select distinct SAB from MRREL where $relations");
	if($self->_checkError($function)) { return (); }
	@array = @{$arrRef};
    }
	
    my $sabcount = 0;
    foreach my $sab (@array) { 
	    
	$sabcount++;
	    
	#  if the sab is UMLS_ALL set the flag and be done
	if($sab eq "UMLS_ALL") { 
	    $umlsall = 1;
	    $sources = "UMLS_ALL";
	    &_setUMLS_ALL();
	    last;
	}
	
	#  if we are excluding check to see if this sab can be included
	if(($excludesabkeys > 0) and (exists ${$excludesab}{$sab})) { next; }	
	
	#  include the sab in the sources variable
	if($sabcount == ($#array+1)) { $sources .="SAB=\'$sab\'";     }
	else                         { $sources .="SAB=\'$sab\' or "; }
	
	#  get the sabs cui
	my $cui = $self->_getSabCui($sab);
	if($self->_checkError($function)) { return (); }
	    
	if(! (defined $cui) ) {
	    return($self->_error($function, "SAB ($sab) is not valid."));
	}
	
	#  store the sabs cui and name information
	$sabnamesHash{$sab}++; 
	$sabHash{$cui}++;
    }
}

#  sets the rela variables from the information in the config file
#  input : $includerelakeys <- integer
#        : $excluderelakeys <- integer
#        : $includerela     <- reference to hash
#        : $excluderela     <- reference to hash
#  output: 
sub _setRelas {

    my $self           = shift;
    my $includerelakeys = shift;
    my $excluderelakeys = shift;
    my $includerela     = shift;
    my $excluderela     = shift;


    my $function = "_setRelas";
    &_debug($function);
    
    return () if(!defined $self || !ref $self);

    #  check the parameters are defined
    if(!(defined $includerelakeys) || !(defined $excluderelakeys) || 
       !(defined $includerela)     || !(defined $excluderela)) {
	return ($self->_error($function, "Undefined input values."));
    }
    
    #  if no relas were specified just return
    if($includerelakeys <= 0 and $excluderelakeys <= 0) { return; }

    #  check that the database is defined
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
    
    #  initalize the hash tables that will hold children and parent relas
    my %childrelas  = ();
    my %parentrelas = ();
    
   
    #  get the rela relations that exist for the given set of sources and 
    #  relations for the children relations that are specified in the config
    my $sth = "";
    if($umlsall) {
	$sth = $db->prepare("select distinct RELA from MRREL where $childRelations");
    }
    else {
	$sth = $db->prepare("select distinct RELA from MRREL where $childRelations and ($sources)");
    }
    $sth->execute();
    if($sth->err()) {
	return($self->_error($function, "Unable to run query: ($sth->errstr())"));
    }
    
    #  get all the relas for the children
    my $crela = "";
    while(($crela) = $sth->fetchrow()) {
	if(defined $crela) {
	    if($crela ne "NULL") {
		$childrelas{$crela}++;
	    }
	}
    }
    $sth->finish();
    
    my $crelakeys = keys %childrelas;
    if($crelakeys <= 0) {
	return($self->_error($function, "There are no RELA relations for the given sources"));
    }
    
    
    #  get the rela relations that exist for the given set of sources and 
    #  relations for the children relations that are specified in the config
    if($umlsall) {
	$sth = $db->prepare("select distinct RELA from MRREL where $parentRelations");
    }
    else {
	$sth = $db->prepare("select distinct RELA from MRREL where $parentRelations and ($sources)");
    }
    $sth->execute();
    if($sth->err()) {
	return($self->_error($function, "Unable to run query: ($sth->errstr())"));
    }
    
    #  get all the relas for the parents
    my $prela = "";
    while(($prela) = $sth->fetchrow()) {
	if(defined $prela) {
	    if($prela ne "NULL") {
		$parentrelas{$prela}++;
	    }
	}
    }
    $sth->finish();
    
    my $prelakeys = keys %parentrelas;
    if($prelakeys <= 0) { 
	return ($self->_error($function, "There are no RELA relations for the given sources"));
    }
    
    #  uses the relas that are set in the includrelakeys or excluderelakeys
    my @array = ();
    if($includerelakeys > 0) {
	@array = keys %{$includerela};
    }
    else {
	
	my $arrRef = $db->selectcol_arrayref("select distinct RELA from MRREL where ($sources) and $relations");
	if($self->_checkError($function)) { return (); }
	@array = @{$arrRef};
	shift @array;
    }
    
    my @crelas = ();
    my @prelas = ();
    my $relacount = 0;
    
    my @newrelations = ();
  
    foreach my $r (@array) {
	
	$relacount++;
	
	if( ($excluderelakeys > 0) and (exists ${$excluderela}{$r}) ) { next; }
	
	push @newrelations, "RELA=\'$r\'";     	    
	
	if(exists $childrelas{$r})     { push @crelas, "RELA=\'$r\'";  }
	elsif(exists $parentrelas{$r}) { push @prelas, "RELA=\'$r\'";  }
	else {
	    return ($self->_error($function, "RELA relation ($r) does not exist for the given sources"));
	}
    }
    
    if($#newrelations >= 0) { 
	my $string = join " or ", @newrelations;
    
	$relations .= "and ( $string )";	
    
	my $crelasline = join " or ", @crelas;
	my $prelasline = join " or ", @prelas;
    
	$parentRelations .= " and ($prelasline)";
	$childRelations  .= " and ($crelasline)";
    }
}

#  This sets the sources that are to be used. These sources 
#  are found in the config file. The defaults are:
#  input : $file <- string
#  output: 
sub _config {

    my $self = shift;
    my $file = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "_config";
    &_debug($function);
    
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
       
    if(defined $file) {
	
	my %includesab    = ();
	my %excludesab    = ();
	my %includerel    = ();
	my %excluderel    = ();
	my %includerela   = ();
	my %excluderela   = ();
	my %includereldef = ();
	my %excludereldef = ();
	my %includesabdef = ();
	my %excludesabdef = ();

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
		    if(   $type eq "SAB"    and $det eq "include") { $includesab{$element}++;   }
		    elsif($type eq "SAB"    and $det eq "exclude") { $excludesab{$element}++;   }
		    elsif($type eq "REL"    and $det eq "include") { $includerel{$element}++;   }
		    elsif($type eq "REL"    and $det eq "exclude") { $excluderel{$element}++;   }
		    elsif($type eq "RELA"   and $det eq "include") { $includerela{$element}++;  }
		    elsif($type eq "RELA"   and $det eq "exclude") { $excluderela{$element}++;  }
		    elsif($type eq "RELDEF" and $det eq "include") { $includereldef{$element}++;}
		    elsif($type eq "SABDEF" and $det eq "include") { $includesabdef{$element}++;}
		    elsif($type eq "RELDEF" and $det eq "exclude") { $excludereldef{$element}++;}
		    elsif($type eq "SABDEF" and $det eq "exclude") { $excludesabdef{$element}++;}
		}
	    }
	    else {
		$self->{'errorCode'} = 2;
		$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
		$self->{'errorString'} .= "Configuration file format not correct ($_).";
		return ();
	    }
	}
	
	my $includesabkeys    = keys %includesab;
	my $excludesabkeys    = keys %excludesab;
	my $includerelkeys    = keys %includerel;
	my $excluderelkeys    = keys %excluderel;
	my $includerelakeys   = keys %includerela;
	my $excluderelakeys   = keys %excluderela;
	my $includereldefkeys = keys %includereldef;
	my $excludereldefkeys = keys %excludereldef;
	my $includesabdefkeys = keys %includesabdef;
	my $excludesabdefkeys = keys %excludesabdef;

	#  check for errors
	if($includesabkeys > 0 and $excludesabkeys > 0) {
	    return($self->_error($function, 
				 "Configuration file can not have an include and exclude list of sources"));
	}
	if($includerelkeys > 0 and $excluderelkeys > 0) {
	    return($self->_error($function, 
				 "Configuration file can not have an include and exclude list of relations"));
	}
	
	#  The order matters here so don't mess with it

	#  set the relations
	$self->_setRelations($includerelkeys, $excluderelkeys, \%includerel, \%excluderel);
	if($self->_checkError("_setRelations")) { return (); }

	#  set the sabs
	$self->_setSabs($includesabkeys, $excludesabkeys, \%includesab, \%excludesab);
	if($self->_checkError("_setSabs")) { return (); }

	#  set the relas
	$self->_setRelas($includerelakeys, $excluderelakeys, \%includerela, \%excluderela);
	if($self->_checkError("_setRelas")) { return (); }
	
	#  set the sabs for the CUI and extended definitions
	$self->_setSabDef($includesabdefkeys, $excludesabdefkeys, \%includesabdef, \%excludesabdef);
	if($self->_checkError("_setSabDef")) { return (); }

	#  set the rels for the extended definition
	$self->_setRelDef($includereldefkeys, $excludereldefkeys, \%includereldef, \%excludereldef);
	if($self->_checkError("_setRelDef")) { return (); }
    }

    #  there is no configuration file so set the default
    else {

	#  get the CUIs of the default sources
	my $mshcui = $self->_getSabCui('MSH');
	if($self->_checkError($function)) { return (); }

	if(! (defined $mshcui) ) {
	    return($self->_error($function, "SAB (MSH) is not valid."));
	}
	$sources = "SAB=\'MSH\'";
	$sabnamesHash{'MSH'}++; 
	$sabHash{$mshcui}++;
	
	#  set default relations
	$relations = "REL=\'CHD\' or REL=\'PAR\'";

	#  set default parent and child relations
	$parentRelations = "REL=\'PAR\'";
	$childRelations  = "REL=\'CHD\'";
    }

    if($debug) {
	if($umlsall) { print STDERR "SOURCE   : UMLS_ALL\n"; }
	else         { print STDERR "SOURCE   : $sources\n"; }
	print STDERR "RELATIONS: $relations\n";
	print STDERR "PARENTS  : $parentRelations\n";
	print STDERR "CHILDREN : $childRelations\n\n";
    }
}

#  set the version
#  input : 
#  output: 
sub _setVersion {

    my $self = shift;

    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";

    my $function = "_setVersion";
    &_debug($function);

    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
    
    my $arrRef = $db->selectcol_arrayref("select EXPL from MRDOC where VALUE = \'mmsys.version\'");
    if($db->err()) {
	return ($self->_error($function, "Error executing database query: ($db->errstr())"));
    }
    if(scalar(@{$arrRef}) < 1) {
	return ($self->_error($function, "No version info in table MRDOC."));
    }

    ($version) = @{$arrRef}; 
    
}    


#  check if the UMLS tables required all exist
#  input : 
#  output: 
sub _checkTablesExist {

    my $self = shift;

    return undef if(!defined $self || !ref $self);

    my $function = "_checkTablesExist";
    &_debug($function);

    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    #  check if the tables exist...
    my $sth = $db->prepare("show tables");
    $sth->execute();
    if($sth->err()) {
	return ($self->_error($function, "Unable run query: ($sth->errstr())"));
    }
    
    my $table = "";
    my %tables = ();
    while(($table) = $sth->fetchrow()) {
	$tables{$table} = 1;
    }
    $sth->finish();

    if(!defined $tables{"MRCONSO"} and !defined $tables{"mrconso"}) { 
	return ($self->_error($function, "Table MRCONSO not found in database")); 
    }
    if(!defined $tables{"MRDEF"} and !defined $tables{"mrdef"}) { 
	return ($self->_error($function, "Table MRDEF not found in database")); 
    }
    if(!defined $tables{"SRDEF"} and !defined $tables{"srdef"}) {
 	return ($self->_error($function, "Table SRDEF not found in database")); 
    }
    if(!defined $tables{"MRREL"} and !defined $tables{"mrrel"}) { 
	return ($self->_error($function, "Table MRREL not found in database")); 
    }
    if(!defined $tables{"MRDOC"} and !defined $tables{"mrdoc"}) { 
	return ($self->_error($function, "Table MRDEC not found in database")); 
    }
    if(!defined $tables{"MRSAB"} and !defined $tables{"mrsab"}) { 
	return ($self->_error($function, "Table MRSAB not found in database")); 
    }
}

#  method to set the global parameter options
#  input : $params <- reference to a hash
#  output: 
sub _setOptions  {
    my $self = shift;
    my $params = shift;

    return undef if(!defined $self || !ref $self);

    my $function = "_setOptions";
    &_debug($function);
    
    #  get all the parameters
    my $verbose      = $params->{'verbose'};
    my $cuilist      = $params->{'cuilist'};
    my $t            = $params->{'t'};
    my $debugoption  = $params->{'debug'};
    
    if(defined $t) {
	$option_t = 1;
    }

    my $output = "";
    
    if(defined $verbose || defined $cuilist || defined $debugoption)  {
	$output  .= "\nCuiFinder User Options: \n";
    }

    #  check the debug option
    if(defined $debugoption) { 
	$debug = 1;
	$output .= "  --debug";
    }

    #  check if verbose run has been identified
    if(defined $verbose) { 
	$option_verbose = 1;
	$output .= "   --verbose option set\n";
    }


    #  check if the cuilist option has been set
    if(defined $cuilist) {
	$option_cuilist = 1;
    	$output .= "   --cuilist option set\n";
    }

    if($option_t == 0) {
	print STDERR "$output\n\n";
    }
}

#  method to set the umlsinterface index database
#  input : $params <- reference to a hash
#  output: 
sub _setDatabase  {

    my $self   = shift;
    my $params = shift;

    return undef if(!defined $self || !ref $self);
        
    $params = {} if(!defined $params);

    my $function = "_setDatabase";
    &_debug($function);

    my $database     = $params->{'database'};
    my $hostname     = $params->{'hostname'};
    my $socket       = $params->{'socket'};
    my $port         = $params->{'port'};
    my $username     = $params->{'username'};
    my $password     = $params->{'password'};

    if(! defined $database) { $database = "umls";            }
    if(! defined $socket)   { $socket   = "/var/run/mysqld/mysqld.sock"; }
    if(! defined $hostname) { $hostname = "localhost";       }
    
    my $db = "";

    #  create the database object...
    if(defined $username and defined $password) {
	if($debug) { print STDERR "Connecting with username and password\n"; }
	$db = DBI->connect("DBI:mysql:database=$database;mysql_socket=$socket;host=$hostname",$username, $password, {RaiseError => 1});
    }
    else {
	if($debug) { print STDERR "Connecting using the my.cnf file\n"; }
	my $dsn = "DBI:mysql:umls;mysql_read_default_group=client;";
	$db = DBI->connect($dsn);
    } 

    #  check if there is an error
    if(!$db) { return ($self->_error($function, "A db is required")); }

    $db->{'mysql_enable_utf8'} = 1;
    $db->do('SET NAMES utf8');

    $self->{'db'}           = $db;
    $self->{'username'}     = $username;
    $self->{'password'}     = $password;
    $self->{'hostname'}     = $hostname;
    $self->{'socket'}       = $socket;
    $self->{'database'}     = $database;


    return $db;
}

#  returns all of the cuis given the specified set of sources
#  and relations defined in the configuration file
#  input : $sab   <- string containing a source 
#  output: $array <- reference to array of cuis
sub _getCuis {

    my $self = shift;
    my $sab  = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_getCuis";
    &_debug($function);

    #  check input variables
    if(!$sab) {
	return($self->_error($function, "Undefined input values."));
    }

    #  set up the database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
    
    my $allCui1 = $db->selectcol_arrayref("select CUI1 from MRREL where ($relations) and (SAB=\'$sab\')\;");
    if($self->_checkError($function)) { return undef; }
    
    my $allCui2 = $db->selectcol_arrayref("select CUI2 from MRREL where ($relations) and (SAB=\'$sab\')");
    if($self->_checkError($function)) { return undef; }
    
    my @allCuis = (@{$allCui1}, @{$allCui2});
    
    return \@allCuis;
}

#  Takes as input a SAB and returns its corresponding
#  UMLS CUI. Keep in mind this is the root cui not 
#  the version cui that is returned. The information 
#  for this is obtained from the MRSAB table
#  input : $sab <- string containing source
#  output: $cui <- string containing cui
sub _getSabCui {
    my $self = shift;
    my $sab  = shift;
    
    return undef if(!defined $self || !ref $self);

    my $function = "_getSabCui";   

    #  check input variables
    if(!$sab) {
	return($self->_error($function, "Undefined input values."));
    }

    #  set up db
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    if($umlsall) { 
	return $umlsRoot;
    }
        
    my $arrRef = $db->selectcol_arrayref("select distinct RCUI from MRSAB where RSAB='$sab'");
    if($self->_checkError($function)) { return (); }
    
    if(scalar(@{$arrRef}) < 1) {
	return($self->_error($function, "No CUI info in table MRSAB for $sab."));
    }
    
    if(scalar(@{$arrRef}) > 1) {
	return($self->_error($function, "Internal error: Duplicate concept rows."));
    }
    
    return (pop @{$arrRef});
}


#  method to destroy the created object.
#  input : 
#  output: 
sub _disconnect {
    my $self = shift;

    if($self) {
	my $db = $self->{'db'};
	$db->disconnect() if($db);
    }
}

#  returns the version of the UMLS currently being used
#  input : 
#  output: $version <- string containing version
sub _version {

    my $self = shift;

    return undef if(!defined $self || !ref $self);
    
    return $version;
}


#  set the error string
#  input : $function <- the function the error is coming from
#          $string   <- the error string
#  output: 
sub _error {

    my $self     = shift;
    my $function = shift;
    my $string   = shift;

    return undef if(!defined $self || !ref $self);
        
    $self->{'errorString'} .= "\nError (UMLS::Interface::CuiFinder->$function()) - ";
    $self->{'errorString'} .= $string;
    $self->{'errorCode'} = 2;
}

#  method that returns the error string and error code from the last method call on the object.
#  input : 
#  output: $returnCode, $returnString <- strining containing error information
sub _getError {

    my $self      = shift;

    my $returnCode = $self->{'errorCode'};
    my $returnString = $self->{'errorString'};

    $returnString =~ s/^\n+//;

    $self->{'errorString'} = "";
    $self->{'errorCode'} = 0;
    
    return ($returnCode, $returnString);
}

#  check error function to determine if an error happened within a function
#  input : $function <- string containing name of function
#  output: 0|1 indicating if an error has been thrown 
sub _checkError {
    my $self     = shift;
    my $function = shift;
   
    my $code = $self->{'errorCode'}; 
    
    my $db = $self->{'db'};
    if($db->err()) {
	$self->{'errorCode'} = 2;
	$self->{'errorString'} .= "\nError (UMLS::Interface function: $function ) - ";
	$self->{'errorString'} .= "Error executing database query: ".($db->errstr());
	return 1;
    }

    if($code == 2) { return 1; }
    else           { return 0; }
}

#  print out the function name to standard error
#  input : $function <- string containing function name
#  output: 
sub _debug {
    my $function = shift;
    if($debug) { print STDERR "In UMLS::Interface::CuiFinder::$function\n"; }
}

######################################################################
#  functions to obtain information about the cuis
######################################################################

#  Method to check if a concept ID exists in the database.
#  input : $concept <- string containing a cui
#  output: 1 | 0    <- integers indicating if the cui exists
sub _exists {    

    my $self = shift;
    my $concept = shift;

    my $function = "_exists";

    return undef if(!defined $self || !ref $self);

     #  check parameter exists
    if(!$concept) { return($self->_error($function, "Undefined input values.")); }
    
    #  check if valid concept
    if($self->_validCui($concept)) { return($self->_error($function, "Incorrect input value ($concept).")); }
    
    #  set up database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
    
    my $arrRef = "";    
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where CUI='$concept'");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where CUI='$concept' and $sources");
    }
    if($self->_checkError($function)) { return (); }
    
    my $count = scalar(@{$arrRef});
    if($count > $count) {
	return($self->_error($function, "Internal error: Duplicate concept rows."));
    }
    
    return 1 if($count); return 0;
}

#  method that returns a list of concepts (@concepts) related 
#  to a concept $concept through a relation $rel
#  input : $concept <- string containing cui
#          $rel     <- string containing a relation
#  output: @array   <- array of cuis
sub _getRelated {

    my $self    = shift;
    my $concept = shift;
    my $rel     = shift;

    
    return undef if(!defined $self || !ref $self);

    my $function = "_getRelated";
    #&_debug($function);

    #  verify the input
    if(!$concept || !$rel) {
	return($self->_error($function,"Undefined input values."));
    }
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    } 

    #  get the database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    #  return all the relations 'rel' for cui 'concept'
    my $arrRef = "";
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and REL='$rel' and CUI2!='$concept'");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and REL='$rel' and ($sources) and CUI2!='$concept'");
    }
    
    #  check for errors
    if($self->_checkError($function)) { return(); }
    
    return @{$arrRef};
}

#  method that maps terms to cuis in the sources specified in 
#  in the configuration file by the user
#  input : $concept <- string containing cui
#  output: @array   <- array of terms (strings)
sub _getTermList {
    my $self = shift;
    my $concept = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_getTermList";
    
    #  verify the input
    if(!$concept) { return($self->_error($function,"Undefined input values.")); }    
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    } 

    #  set the return hash
    my %retHash = ();

    #  if the concept is the root return the root string
    if($concept eq $umlsRoot) {
	$retHash{"**UMLS ROOT**"}++;
	return keys(%retHash);    
    }

    #  set the database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    #  get the strings associated to the CUI
    my $arrRef = "";    
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select distinct STR from MRCONSO where CUI='$concept'");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct STR from MRCONSO where CUI='$concept' and ($sources or SAB='SRC')");
    }
    if($self->_checkError($function)) { return(); }

    #  clean up the strings a bit and lower case them
    foreach my $tr (@{$arrRef}) {
        $tr =~ s/^\s+//;
        $tr =~ s/\s+$//;
        $tr =~ s/\s+/ /g;
        $retHash{lc($tr)} = 1;
    }
    
    #  return the strings
    return keys(%retHash);
}

#  method to map terms to any concept in the umls
#  input : $concept <- string containing cui
#  output: @array   <- array containing terms (strings)
sub _getAllTerms {
    my $self = shift;
    my $concept = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_getAllTerms";
    &_debug($function);

    #  verify the input
    if(!$concept) {
	return($self->_error($function,"Undefined input values.")); 
    }    
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    } 

    #  initialize the return hash
    my %retHash = ();

    #  if the concept is the root return the root string
    if($concept eq $umlsRoot) {
	$retHash{"**UMLS ROOT**"}++;
	return keys(%retHash);    
    }

    #  otherwise, set up the db
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    #  get all of the strings with their corresponding sab
    my %strhash = ();
    my $sql = qq{ select STR, SAB from MRCONSO where CUI='$concept' };
    my $sth = $db->prepare( $sql );
    $sth->execute();
    my($str, $sab);
    $sth->bind_columns( undef, \$str, \$sab );
    while( $sth->fetch() ) {
	$str =~ s/^\s+//;
	$str =~ s/\s+$//;
        $str =~ s/\s+/ /g;
	$str = lc($str);
	push @{$strhash{$str}}, $sab;
    } $sth->finish();

    #  set the output 
    foreach my $str (sort keys %strhash) {
	my $sabs = join ", ", @{$strhash{$str}};
	my $index = "$str - $sabs";
	$retHash{$index}++;
    }

    return keys(%retHash);
}

#  method to map CUIs to a terms in the sources 
#  specified in the configuration file
#  input : $term  <- string containing a term
#  output: @array <- array containing cuis
sub _getConceptList {

    my $self = shift;
    my $term = shift;

    return undef if(!defined $self || !ref $self);

    my $function = "_getConceptList";
    &_debug($function);
    
    #  verify the input
    if(!$term) { return($self->_error($function,"Undefined input values.")); }
    
    #  set up the database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
    
    #  get the cuis
    my $arrRef = "";
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where STR='$term'");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where STR='$term' and ($sources)");
    }
    if($self->_checkError($function)) { return (); }
    
    return @{$arrRef};
}

#  method returns all of the cuis in the sources
#  specified in the configuration file
#  input : 
#  output: $hash <- reference to a hash containing cuis
sub _getCuiList {

    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_getCuiList";
    &_debug($function);

    #  if this has already been done just return the stored cuiListHash
    my $elements = keys %cuiListHash;
    if($elements > 0) { 
	return \%cuiListHash;
    }
    

    #  otherwise, set up the database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
        
    #  get the sabs in the config file
    my @sabs = ();
    if($umlsall) {
	my $s = $db->selectcol_arrayref("select distinct SAB from MRREL");
	@sabs = @{$s};
    }
    else {
	foreach my $sab (sort keys %sabnamesHash) { push @sabs, $sab; }
    }

    #  initialize the cui list hash
    %cuiListHash = ();

    #  for each of the sabs in the configuratino file
    foreach my $sab (@sabs) {
	
	#  get the cuis for that sab
	my $cuis = $self->_getCuis($sab);
	
	#  add the cuis to the hash
	foreach my $cui (@{$cuis}) { $cuiListHash{$cui} = 0 };
    }
    
    #  add upper level taxonomy
    foreach my $cui (sort keys %parentTaxonomyArray)   { $cuiListHash{$cui} = 0; }
    foreach my $cui (sort keys %childTaxonomyArray) { $cuiListHash{$cui} = 0; }
    
    return \%cuiListHash;
}

#  returns the cuis from a specified source
#  input : $sab   <- string contain the sources abbreviation
#  output: $array <- reference to an array containing cuis
sub _getCuisFromSource {
    
    my $self = shift;
    my $sab = shift;
    
    my $function = "_getCuisFromSource";

    &_debug($function);

    #  get the cuis from the specified source
    my $arrRef = $self->_getCuis($sab);
    
    return ($arrRef);
}

#  returns all of the sources specified that contain the given cui
#  input : $concept <- string containing the cui 
#  output: @array   <- array contain the sources (abbreviations)
sub _getSab {

    my $self = shift;
    my $concept = shift;

    return undef if(!defined $self || !ref $self);
 
    my $function = "_getSab";
    
    #  verify the input arguments
    if(!$concept) {
	return($self->_error($function,"Undefined input values.")); 
    } 
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    } 
    
    #  connect to the database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    #  select all the sources from the mrconso table
    my $arrRef = $db->selectcol_arrayref("select distinct SAB from MRCONSO where CUI='$concept'");    
    if($self->_checkError($function)) { return (); }
    
    return @{$arrRef};
}

#  returns the children of a concept - the relations that 
#  are considered children are predefined by the user.
#  the default are the RN and CHD relations
#  input : $concept <- string containing a cui
#  output: @array   <- array containing a list of cuis
sub _getChildren {

    my $self    = shift;
    my $concept = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_getChildren";
    
    #  verify the input parameters
    if(!$concept) {
	return($self->_error($function,"Undefined input values.")); 
    }
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    } 

    #  connect to the database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    #  if the concept is the umls root node cui return
    #  the source's cuis
    if($concept eq $umlsRoot) {
	return (keys %sabHash);
    }

    #  otherwise everything is normal so return its children
    else {
	my $arrRef = "";
	if($umlsall) {
	    $arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and ($childRelations) and CUI2!='$concept'");
	}
	else {
	    $arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and ($childRelations) and ($sources) and CUI2!='$concept'");
	}
	if($self->_checkError($function)) { return (); }
	
	#  add the children in the upper taxonomy
	my @array = ();
	if(exists $childTaxonomyArray{$concept}) {
	    @array = (@{$childTaxonomyArray{$concept}}, @{$arrRef});
	}
	else {
	    @array = @{$arrRef};
	}
	return @array; 
    }
}


#  returns the parents of a concept - the relations that 
#  are considered parents are predefined by the user.
#  the default are the PAR and RB relations.
#  input : $concept <- string containing cui
#  outupt: @array   <- array containing a list of cuis
sub _getParents {

    my $self    = shift;
    my $concept = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_getParents";

    #  verify the input
    if(!$concept) {
	return($self->_error($function,"Undefined input values.")); 
    }
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    } 

    #  connect to the database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
        
    #  if the cui is a root return an empty array
    if($concept eq $umlsRoot) { 
	my @returnarray = ();
	return @returnarray; # empty array
    }
    #  if the cui is a source cui but not a root return the umls root
    elsif( (exists $sabHash{$concept}) and ($concept ne $umlsRoot)) { 
	return "$umlsRoot";
    }
    #  otherwise everything is normal so return its parents
    else {
	my $arrRef = "";
	if($umlsall) {
	    $arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and ($parentRelations) and CUI2!='$concept'");
	}
	else {
	    $arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and ($parentRelations) and ($sources) and CUI2!='$concept'");
	}
	if($self->_checkError($function)) { return (); }

	#  add the parents in the upper taxonomy
	my @array = ();
	if(exists $parentTaxonomyArray{$concept}) {
	    @array = (@{$parentTaxonomyArray{$concept}}, @{$arrRef});
	}
	else {
	    @array = @{$arrRef};
	}
	return @array; 
    }
}

#  returns the relations of a concept given a specified source
#  input : $concept <- string containing a cui
#  output: @array   <- array containing strings of relations
sub _getRelations {

    my $self    = shift;
    my $concept = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_getRelations";
    &_debug($function);

    #  verify the input
    if(!$concept) {
	return($self->_error($function,"Undefined input values.")); 
    }
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    }
    
    #  connect to the database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }
    
    #  get the relations
    my $arrRef = "";
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select distinct REL from MRREL where (CUI1='$concept' or CUI2='$concept') and CUI1!=CUI2");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct REL from MRREL where (CUI1='$concept' or CUI2='$concept') and ($sources) and CUI1!=CUI2");
    }
    if($self->_checkError($function)) { return (); }

    return @{$arrRef};
}

#  returns the relations and its source between two concepts
#  input : $concept1 <- string containing a cui
#        : $concept2 <- string containing a cui
#  output: @array    <- array containing the relations
sub _getRelationsBetweenCuis {

    my $self     = shift;
    my $concept1 = shift;
    my $concept2 = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_getRelationBetweenCuis";
    &_debug($function);

    #  verify input
    if( (!$concept1) or (!$concept2) ) {
	return($self->_error($function,"Undefined input values.")); 
    }
    if( ($self->_validCui($concept1)) or ($self->_validCui($concept2)) ) {
	return($self->_error($function, "Incorrect input value."));
    } 
    
    #  connect to the database
    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    my @array = ();

    if($concept1 eq $umlsRoot) { 
	push @array, "CHD (source)";
	return @array;
    }
    
    #  get the relations
    my $sql = "";
    if($umlsall) {
	$sql = qq{ select distinct REL, SAB from MRREL where (CUI1='$concept1' and CUI2='$concept2') };
    }
    else {
	$sql = qq{ select distinct REL, SAB from MRREL where (CUI1='$concept1' and CUI2='$concept2') and ($sources) };
    }
    my $sth = $db->prepare( $sql );
    $sth->execute();
    my($rel, $sab);
    $sth->bind_columns( undef, \$rel, \$sab );
    while( $sth->fetch() ) {
	my $str = "$rel ($sab)";
	push @array, $str;
    } $sth->finish();
    
    return @array;
}

#  checks to see a concept is forbidden
#  input : $concept <- string containing a cui
#  output: 0 | 1    <- integer indicating true or false
sub _forbiddenConcept  {

    my $self = shift;
    my $concept = shift;
    
    #  if concept is one of the following just return
    #C1274012|Ambiguous concept (inactive concept)
    if($concept=~/C1274012/) { return 1; }
    #C1274013|Duplicate concept (inactive concept)
    if($concept=~/C1274013/) { return 1; }
    #C1276325|Reason not stated concept (inactive concept)
    if($concept=~/C1276325/) { return 1; }
    #C1274014|Outdated concept (inactive concept)
    if($concept=~/C1274014/) { return 1; }
    #C1274015|Erroneous concept (inactive concept)
    if($concept=~/C1274015/) { return 1; }
    #C1274021|Moved elsewhere (inactive concept)
    if($concept=~/C1274021/) { return 1; }
    #C1443286|unapproved attribute
    if($concept=~/C1443286/) { return 1; }

    return 0;
}

# Subroutine to get the semantic type's tui of a concept
# input : $cui   <- string containing a concept
# output: @array <- array containing the semantic type's TUIs
#                   associated with the concept
sub _getSt {

    my $self = shift;
    my $cui   = shift;

    my $function = "_getSt";
    &_debug($function);
    
    my $db = $self->{'db'};
    if(!$db)  { return ($self->_error($function, "A db is required")); }

    if(!$cui) { return($self->_error($function,"Undefined input values.")); }

    my $arrRef = $db->selectcol_arrayref("select TUI from MRSTY where CUI=\'$cui\'");
    if($self->_checkError($function)) { return (); }
    
    return (@{$arrRef});
}

#  subroutine to get the name of a semantic type given its abbreviation
#  input : $st     <- string containing the abbreviation of the semantic type
#  output: $string <- string containing the full name of the semantic type
sub _getStString {

    my $self = shift;
    my $st   = shift;

    my $function = "_getStString";
    &_debug($function);

    my $db = $self->{'db'};
    if(!$db) { return ($self->_error($function, "A db is required")); }

    if(!$st) { return($self->_error($function,"Undefined input values.")); }

    my $arrRef = $db->selectcol_arrayref("select STY_RL from SRDEF where ABR=\'$st\'");
    if($self->_checkError($function)) { return (); }
    
    return (shift @{$arrRef});
} 


# subroutine to get the name of a semantic type given its TUI (UI)
#  input : $tui    <- string containing the semantic type's TUI
#  output: $string <- string containing the semantic type's abbreviation
sub _getStAbr {

    my $self = shift;
    my $tui   = shift;

    my $function = "_getStString";
    &_debug($function);
    
    my $db = $self->{'db'};
    if(!$db)  { return ($self->_error($function, "A db is required")); }

    if(!$tui) {	return($self->_error($function,"Undefined input values.")); }

    my $arrRef = $db->selectcol_arrayref("select ABR from SRDEF where UI=\'$tui\'");
    if($self->_checkError($function)) { return (); }
    
    return (shift @{$arrRef});
} 


#  subroutine to get the definition of a given TUI
#  input : $st     <- string containing the semantic type's abbreviation
#  output: $string <- string containing the semantic type's definition
sub _getStDef {

    my $self = shift;
    my $st   = shift;

    my $function = "_getStDef";
    &_debug($function);
  
    my $db = $self->{'db'};
    if(!$db)  { return ($self->_error($function, "A db is required")); }

    if(!$st)  {	return($self->_error($function,"Undefined input values.")); }

    my $arrRef = $db->selectcol_arrayref("select DEF from SRDEF where ABR=\'$st\'");
    if($self->_checkError($function)) { return (); }
    
    return (shift @{$arrRef});
} 

#  subroutine to get the extended definition of a concept from
#  the concept and its surrounding relations as specified in the
#  the configuration file.
#  input : $concept <- string containing a cui
#  output: $array   <- reference to an array containing the definitions
sub _getExtendedDefinition {

    my $self    = shift;
    my $concept = shift;
    
    my $function = "_getExtendedDefinition";
    #&_debug($function);

    return undef if(!defined $self || !ref $self);
   
    #  check if concept was obtained
    if(!$concept) {
	return($self->_error($function,"Undefined input values."));
    }
    
    #  check if valid concept
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    } 
   
    #  get database
    my $db = $self->{'db'};
    if(!$db)  { return ($self->_error($function, "A db is required")); }

    my $sabflag = 1;

    my @defs = ();
    
    my $dkeys = keys %relDefHash;
    
    if( ($dkeys <= 0) or (exists $relDefHash{"PAR"}) ) {
	my @parents   = $self->_getRelated($concept, "PAR");
	foreach my $parent (@parents) {
	    my @odefs = $self->_getCuiDef($parent, $sabflag);
	    foreach my $d (@odefs) {
		my @darray = split/\s+/, $d;
		my $sab = shift @darray;
		my $def = "$concept PAR $parent $sab : " . (join " ", @darray);
		push @defs, $def;
	    }
	}
    }
    if( ($dkeys <= 0) or (exists $relDefHash{"CHD"}) ) {
	my @children   = $self->_getRelated($concept, "CHD");
	foreach my $child (@children) { 
	    my @odefs = $self->_getCuiDef($child, $sabflag);
	    foreach my $d (@odefs) {
		my @darray = split/\s+/, $d;
		my $sab = shift @darray;
		my $def = "$concept CHD $child $sab : " . (join " ", @darray);
		push @defs, $def;
	    }
	}
    }
    if( ($dkeys <= 0) or (exists $relDefHash{"SIB"}) ) {
	my @siblings   = $self->_getRelated($concept, "SIB");
	foreach my $sib (@siblings) {
	    my @odefs = $self->_getCuiDef($sib, $sabflag);
	    foreach my $d (@odefs) {
		my @darray = split/\s+/, $d;
		my $sab = shift @darray;
		my $def = "$concept SIB $sib $sab : " . (join " ", @darray);
		push @defs, $def;
	    }
	}
    }
    if( ($dkeys <= 0) or (exists $relDefHash{"SYN"}) ) {
	my @syns   = $self->_getRelated($concept, "SYN");
	foreach my $syn (@syns) {
	    my @odefs = $self->_getCuiDef($syn, $sabflag);
	    foreach my $d (@odefs) {
		my @darray = split/\s+/, $d;
		my $sab = shift @darray;
		my $def = "$concept SYN $syn $sab : " . (join " ", @darray);
		push @defs, $def;
	    }
	}
    }
    if( ($dkeys <= 0) or (exists $relDefHash{"RB"}) ) {
	my @rbs    = $self->_getRelated($concept, "RB");
	foreach my $rb (@rbs) {
	    my @odefs = $self->_getCuiDef($rb, $sabflag);
	    foreach my $d (@odefs) {
		my @darray = split/\s+/, $d;
		my $sab = shift @darray;
		my $def = "$concept RB $rb $sab : " . (join " ", @darray);
		push @defs, $def;
	    }
	}
    }
    if( ($dkeys <= 0) or (exists $relDefHash{"RN"}) ) {
	my @rns    = $self->_getRelated($concept, "RN");
	foreach my $rn (@rns) {
	    my @odefs = $self->_getCuiDef($rn, $sabflag);
	    foreach my $d (@odefs) {
		my @darray = split/\s+/, $d;
		my $sab = shift @darray;
		my $def = "$concept RN $rn $sab : " . (join " ", @darray);
		push @defs, $def;
	    }
	}
    }
    if( ($dkeys <= 0) or (exists $relDefHash{"RO"}) ) {
	my @ros    = $self->_getRelated($concept, "RO");
	foreach my $ro (@ros) {
	    my @odefs = $self->_getCuiDef($ro, $sabflag);
	    foreach my $d (@odefs) {
		my @darray = split/\s+/, $d;
		my $sab = shift @darray;
		my $def = "$concept RO $ro $sab : " . (join " ", @darray);
		push @defs, $def;
	    }
	}
    }
    if( ($dkeys <= 0) or (exists $relDefHash{"CUI"}) ) {
	my @odefs   = $self->_getCuiDef($concept, $sabflag);
	foreach my $d (@odefs) {
	    my @darray = split/\s+/, $d;
	    my $sab = shift @darray;
	    my $def = "$concept CUI $concept $sab : " . (join " ", @darray);
	    push @defs, $def;
	}
    }
    if( ($dkeys <= 0) or (exists $relDefHash{"TERM"}) ) {
	my @odefs = $self->_getTermList($concept);
	my $def = "$concept TERM $concept nosab : " . (join " ", @odefs);
	push @defs, $def;
    }
    
    return \@defs;
}

#  subroutine to get a CUIs definition
#  input : $concept <- string containing a cui
#  output: @array   <- array of definitions (strings)
sub _getCuiDef {

    my $self    = shift;
    my $concept = shift;
    my $sabflag = shift;

    my $function = "_getCuiDef";
    #&_debug($function);

    return undef if(!defined $self || !ref $self);

    #  check if concept was obtained
    if(!$concept) {
	return($self->_error($function,"Undefined input values."));
    }
    
    #  check if valid concept
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    } 
   
    #  get database
    my $db = $self->{'db'};
    if(!$db)  { return ($self->_error($function, "A db is required")); }

    my $sql = "";
    
    if($sabDefString ne "") { 
	$sql = qq{ SELECT DEF, SAB FROM MRDEF WHERE CUI=\'$concept\' and ($sabDefString) };
    }
    else {
	$sql = qq{ SELECT DEF, SAB FROM MRDEF WHERE CUI=\'$concept\' };
    }

    my $sth = $db->prepare( $sql );
    $sth->execute();
    my($def, $sab);
    my @defs = ();
    $sth->bind_columns( undef, \$def, \$sab );
    while( $sth->fetch() ) {
	if(defined $sabflag) { push @defs, "$sab $def"; }
	else                 { push @defs, $def; }
    } $sth->finish();
    
    return (@defs);
}

#  subroutine to check if CUI is valid
#  input : $concept <- string containing a cui
#  output: 0 | 1    <- integer indicating if the cui is valide
sub _validCui {

    my $self = shift;
    my $concept = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_validCui";
    
    if(!$concept) {
	return($self->_error($function,"Undefined input values."));
    }
    
    if($concept=~/C[0-9][0-9][0-9][0-9][0-9][0-9][0-9]/) {
	return 0;
    }
    else {
	return 1;
    }
}

#  returns the table names in both human readable and hex form
#  input : 
#  output: $hash <- reference to a hash containin the table names 
#          in human readable and hex form
sub _returnTableNames {
    my $self = shift;
    
    my %hash = ();
    $hash{$parentTableHuman} = $parentTable;
    $hash{$childTableHuman}  = $childTable;
    $hash{$tableNameHuman}   = $tableName;

    return \%hash;
}

#  removes the configuration tables
#  input :
#  output: 
sub _dropConfigTable {
    
    my $self    = shift;

    return undef if(!defined $self || !ref $self);

    my $function = "_dropConfigTable";
    &_debug($function);

    #  connect to the database
    my $sdb = $self->_connectIndexDB();
    if(!$sdb) { return($self->_error($function, "A db is required.")); }       

    #  show all of the tables
    my $sth = $sdb->prepare("show tables");
    $sth->execute();
    if($sth->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface::Interface->$function()) - ";
	$self->{'errorString'} .= "Unable run query: ".($sth->errstr());
	$self->{'errorCode'} = 2;
	return ();
    }
    
    #  get all the tables in mysql
    my $table  = "";
    my %tables = ();
    while(($table) = $sth->fetchrow()) {
	$tables{$table}++;
    }
    $sth->finish();
    

    if(exists $tables{$parentTable}) {	
	$sdb->do("drop table $parentTable");
	if($self->_checkError($function)) { return (); }
    }
    if(exists $tables{$childTable}) {	
	$sdb->do("drop table $childTable");
	if($self->_checkError($function)) { return (); }
    }
    if(exists $tables{$tableName}) {	
	$sdb->do("drop table $tableName");
	if($self->_checkError($function)) { return (); }
    }
    if(exists $tables{$propTable}) {
	$sdb->do("drop table $propTable");
	if($self->_checkError($function)) { return (); }
    }
    if(exists $tables{"tableindex"}) {	

	$sdb->do("delete from tableindex where HEX='$parentTable'");
	if($self->_checkError($function)) { return (); }
	
	$sdb->do("delete from tableindex where HEX='$childTable'");
	if($self->_checkError($function)) { return (); }
	
	$sdb->do("delete from tableindex where HEX='$tableName'");
	if($self->_checkError($function)) { return (); }
	
	$sdb->do("delete from tableindex where HEX='$propTable'");
	if($self->_checkError($function)) { return (); }
    }
}

#  removes the configuration files
#  input : 
#  output: 
sub _removeConfigFiles {

    my $self = shift;
    return undef if(!defined $self || !ref $self);
    
    my $function = "_removeConfigFiles";
    &_debug($function);
    
    if(-e $tableFile) {
	system "rm $tableFile";
    }
    if(-e $childFile) {
	system "rm $childFile";
    }
    if(-e $parentFile) {
	system "rm $parentFile";
    }
    if(-e $configFile) {
	system "rm $configFile";
    }

}

#  checks to see if the cui is in the parent taxonomy
#  input : $concept <- string containing a cui
#  output: 1|0      <- indicating if the cui exists in 
#                      the upper level taxonamy
sub _inParentTaxonomy {

    my $self = shift;
    my $concept = shift;

   return undef if(!defined $self || !ref $self);
    
    my $function = "_inParentTaxonomy";
    &_debug($function);
 
    #  check if concept was obtained
    if(!$concept) {
	return($self->_error($function,"Undefined input values."));
    }
    
    #  check if valid concept
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    } 

    if(exists $parentTaxonomyArray{$concept}) { return 1; }
    else                                 { return 0; }
}

#  checks to see if the cui is in the child taxonomy
#  input : $concept <- string containing a cui
#  output: 1|0      <- indicating if the cui exists in 
#                      the upper level taxonamy
sub _inChildTaxonomy {

    my $self = shift;
    my $concept = shift;

   return undef if(!defined $self || !ref $self);
    
    my $function = "_inChildTaxonomy";
    &_debug($function);
 
    #  check if concept was obtained
    if(!$concept) {
	return($self->_error($function,"Undefined input values."));
    }
    
    #  check if valid concept
    if($self->_validCui($concept)) {
	return($self->_error($function, "Incorrect input value ($concept)."));
    } 

    if(exists $childTaxonomyArray{$concept}) { return 1; }
    else                                 { return 0; }
}

    
#  function to create a timestamp
#  input : 
#  output: $string <- containing the time stamp
sub _timeStamp {

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

    $year += 1900;
    $mon++;
    my $d = sprintf("%4d%2.2d%2.2d",$year,$mon,$mday);
    my $t = sprintf("%2.2d%2.2d%2.2d",$hour,$min,$sec);
    
    my $stamp = $d . $t;

    return $stamp;
}

#  function to get the time
#  input : 
#  output: $string <- containing the time
sub _printTime {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

    $year += 1900;
    $mon++;
    
    my $d = sprintf("%4d%2.2d%2.2d",$year,$mon,$mday);
    my $t = sprintf("%2.2d%2.2d%2.2d",$hour,$min,$sec);
    
    print STDERR "$t\n";

}

#  return the file name containing the index table
sub _getTableFile {
    
    return $tableFile;
}


#  return the table name in the index - this is the hex
sub _getTableName {
    
    return $tableName;
}

#  return the table name in the index in human form
sub _getTableNameHuman {
    
    return $tableNameHuman;
}

__END__

=head1 NAME

UMLS::Interface::CuiFinder - Perl interface to support the 
UMLS::Interface.pm which is an interface to the Unified 
Medical Language System (UMLS). 

=head1 SYNOPSIS

 #!/usr/bin/perl

 use UMLS::Interface::CuiFinder;
 
 %params = ();

 $cuifinder = UMLS::Interface::CuiFinder->new(\%params); 

 die "Unable to create UMLS::Interface::CuiFinder object.\n" if(!$cuifinder);

 ($errCode, $errString) = $cuifinder->_getError();

 die "$errString\n" if($errCode);
    
 $root = $cuifinder->_root();

 $version = $cuifinder->_version();

 $concept = "C0018563"; $rel = "PAR";

 @array = $cuifinder->_getRelated($concept, $rel);

 @array = $cuifinder->_getTermList($concept);

 @array = $cuifinder->_getAllTerms($concept);

 $term = shift @array;

 @array = $cuifinder->_getConceptList($term);

 $hash = $cuifinder->_getCuiList();

 $sab = "MSH";

 $array = $cuifinder->_getCuisFromSource($sab);

 @array = $cuifinder->_getSab($concept);

 @array = $cuifinder->_getChildren($concept);

 @array = $cuifinder->_getParents($concept);

 @array = $cuifinder->_getRelations($concept);

 $concept1 = "C0018563"; $concept2 = "C0037303";

 @array = $cuifinder->_getRelationsBetweenCuis($concept1, $concept2);

 @array = $cuifinder->_getSt($concept);

 $abr = "bpoc";

 $string = $cuifinder->_getStString($abr);

 $tui = "T12";

 $string = $cuifinder->_getStAbr($tui);

 $definition = $cuifinder->_getStDef($abr);

 $array = $cuifinder->_getExtendedDefinition($concept);

 @array = $cuifinder->_getCuiDef($concept, $sabflag);

 $bool = $cuifinder->_validCui($concept);

 $bool = $cuifinder->_exists($concept);

 $hash = $cuifinder->_returnTableNames();

 $cuifinder->_dropConfigTable();

 $cuifinder->_removeConfigFiles();

 if(!( $cuifinder->_checkError())) {
     print "No errors: All is good\n";
 }
 else {
     my ($returnCode, $returnString) = $cuifinder->_getError();
     print STDERR "$returnString\n";
 }

=head1 ABSTRACT

This package provides a Perl interface to the Unified Medical Language 
System. The package is set up to access pre-specified sources of the UMLS
present in a mysql database.  The package was essentially created for use 
with the UMLS::Similarity package for measuring the semantic relatedness 
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

This package provides a Perl interface to the Unified Medical 
Language System (UMLS). The UMLS is a knowledge representation 
framework encoded designed to support broad scope biomedical 
research queries. There exists three major sources in the UMLS. 
The Metathesaurus which is a taxonomy of medical concepts, the 
Semantic Network which categorizes concepts in the Metathesaurus, 
and the SPECIALIST Lexicon which contains a list of biomedical 
and general English terms used in the biomedical domain. The 
UMLS-Interface package is set up to access the Metathesaurus
and the Semantic Network present in a mysql database.

For more information please see the UMLS::Interface.pm 
documentation. 

=head1 SEE ALSO

http://tech.groups.yahoo.com/group/umls-similarity/

http://search.cpan.org/dist/UMLS-Similarity/

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
 sidd at cs.utah.edu
 
 Serguei Pakhomov, University of Minnesota Twin Cities
 pakh0002 at umn.edu

 Ying Liu, University of Minnesota Twin Cities
 liux0395 at umn.edu

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
