# UMLS::Interface 
# (Last Updated $Id: Interface.pm,v 1.39 2010/03/11 18:14:04 btmcinnes Exp $)
#
# Perl module that provides a perl interface to the
# Unified Medical Language System (UMLS)
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

use Fcntl;
use strict;
use warnings;
use DBI;
use bytes;

use vars qw($VERSION);

use Digest::SHA1  qw(sha1 sha1_hex sha1_base64);

use bignum qw/hex oct/;


$VERSION = '0.45';

my $debug = 0;

my $option4 = 0; # Teds 1/p
my $option3 = 1; # decendants
my $option2 = 0; # my 1/p

my %roots = ();

my $umlsRoot = "C0085567";

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

#  list of cuis to obtain the path 
#  information for - default is all
my %CuiList = ();

#  trace variables
my %trace = ();

#  path storage
my @path_storage = ();

my $indexDB        = "umlsinterfaceindex";
my $umlsinterface   = $ENV{UMLSINTERFACE_CONFIGFILE_DIR};

my $tableName       = "";
my $parentTable     = "";
my $childTable      = "";
my $tableFile       = "";
my $parentTableHuman= "";
my $childTableHuman = "";
my $tableNameHuman  = "";
my $cycleFile       = "";
my $configFile      = "";
my $childFile       = "";
my $parentFile      = "";
my $propTable       = "";
my $propTableHuman  = "";

my $markFlag   = 0;
my $umlsall    = 0;

my $option_verbose     = 0;
my $option_forcerun    = 0;
my $option_cuilist     = 0;
my $option_realtime    = 0;
my $option_propagation = 0;

my %propagationFreq  = ();
my %propagationHash  = ();
my %propagationTemp  = ();

my %propagationTuiHash = ();
my $propagationTuiTotal = 0;

my $propagationFile  = "";
my $propagationTotal = 0;

my $propagation_tokens = 0;
my $observed_types     = 0;
my $unobserved_types   = 0;

my %cycleHash       = ();


# UMLS-specific stuff ends ----------

# -------------------- Class methods start here --------------------

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

# Method to destroy the created object.
sub disconnect
{
    my $self = shift;

    if($self) {
	my $db = $self->{'db'};
	$db->disconnect() if($db);
    }
}

# Method that returns the error string and error code from the last method call on the object.
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

# Method that returns the root node of a taxonomy.
sub root
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);

    $self->{'traceString'} = "";

    return $umlsRoot; 
}

# Method to return the maximum depth of a taxonomy.
sub depth
{
    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";

    #  get the depth and set the path information
    if($option_realtime) {
	my @array = ();
      	$self->_getMaxDepth($umlsRoot, 0, \@array);
	if($self->checkError("_getMaxDepth")) { return (); }
    }
    else {
	$self->_setDepth();
	if($self->checkError("_setDepth")) { return (); }
    }
    
    return $max_depth;

}

#  Get the maximum depth when using verbose mode
sub _getMaxDepth
{
    my $self    = shift;
    my $concept = shift;
    my $d       = shift;
    my $array   = shift;
    
    my $function = "_getMaxDepth";
    
    #  check concept was obtained
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }

    #  check valide concept
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
     
    #  set the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    #  increment the depth
    $d++;
    
    #  check to see if it is the max depth
    if(($d) > $max_depth) { $max_depth = $d; }

    #  if concept is one of the following just return
    #C1274012|Ambiguous concept (inactive concept)
    if($concept=~/C1274012/) { return; }
    #C1274013|Duplicate concept (inactive concept)
    if($concept=~/C1274013/) { return; }
    #C1276325|Reason not stated concept (inactive concept)
    if($concept=~/C1276325/) { return; }
    #C1274014|Outdated concept (inactive concept)
    if($concept=~/C1274014/) { return; }
    #C1274015|Erroneous concept (inactive concept)
    if($concept=~/C1274015/) { return; }
    #C1274021|Moved elsewhere (inactive concept)
    if($concept=~/C1274021/) { return; }

    #  set up the new path
    my @path = @{$array};
    push @path, $concept;
    my $series = join " ", @path;
    
    #  get all the children
    my @children = $self->getChildren($concept);
    if($self->checkError("getChildren")) { return (); }
    
    #  search through the children
    foreach my $child (@children) {
	
	#  check if child cui has already in the path
	my $flag = 0;
	foreach my $cui (@path) {
	    if($cui eq $child) { $flag = 1; }
	}
	
	#  if it isn't continue on with the depth first search
	if($flag == 0) {
	    $self->_getMaxDepth($child, $d, \@path);
	    if($self->checkError("_getMaxDepth")) { return (); }
	}
    }
}

# Method to return the version of the backend database.
sub version
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";
    
    return $version;
}

# Method to set the global parameter options
sub _setOptions 
{
    my $self = shift;
    my $params = shift;

    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";

    $params = {} if(!defined $params);

    my $function = "_setOptions";
    &_debug($function);

    #  get all the parameters
    my $forcerun     = $params->{'forcerun'};
    my $verbose      = $params->{'verbose'};
    my $cuilist      = $params->{'cuilist'};
    my $realtime     = $params->{'realtime'};
    my $propagation  = $params->{'propagation'};
    my $debugoption  = $params->{'debug'};

    if(defined $forcerun || defined $verbose || defined $cuilist || 
       defined $realtime || defined $debugoption) {
	print STDERR "\nUser Options:\n";
    }

    #  check if the debug option has been been defined
    if(defined $debugoption) { 
	$debug = 1; 
	print STDERR "   --debug option set\n";
    }

    #  check if the propagation option has been identified
    if(defined $propagation) {
	$option_propagation = 1;
	$propagationFile    = $propagation;
    }
    
    #  check if the realtime option has been identified
    if(defined $realtime) {
	$option_realtime = 1;
	
	print STDERR "   --realtime option set\n";
    }

    #  check if verbose run has been identified
    if(defined $verbose) { 
	$option_verbose = 1;
	
	print STDERR "   --verbose option set\n";
    }

    #  check if a forced run has been identified
    if(defined $forcerun) {
	$option_forcerun = 1;
	
	print STDERR "   --forcerun option set\n";
    }

    #  check if the cuilist option has been set
    if(defined $cuilist) {
	$option_cuilist = 1;

    	print STDERR "   --cuilist option set\n";
    }

    print STDERR "\n";
}

#  method to set the umlsinterface index database
sub _setDatabase 
{
    my $self   = shift;
    my $params = shift;

    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";
    
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
    
    print STDERR "$database\n";

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
    if(!$db || $db->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Unable to open database";
	$self->{'errorString'} .= (($db) ? (": ".($db->errstr())) : ("."));
	$self->{'errorCode'} = 2;
	return;	
    }

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

#  check if the UMLS tables required all exist
sub _checkTablesExist
{

    my $self = shift;

    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";

    my $function = "_checkTablesExist";
    
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

    #  check if the tables exist...
    my $sth = $db->prepare("show tables");
    $sth->execute();
    if($sth->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Unable run query: ".($sth->errstr());
	$self->{'errorCode'} = 2;
	return;
    }

    my $table = "";
    my %tables = ();
    while(($table) = $sth->fetchrow()) {
	$tables{$table} = 1;
    }
    $sth->finish();

    if(!defined $tables{"MRCONSO"} and !defined $tables{"mrconso"}) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Table MRCONSO not found in database.";
	$self->{'errorCode'} = 2;
	return;	
    }
    if(!defined $tables{"MRDEF"} and !defined $tables{"mrdef"}) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Table MRDEF not found in database.";
	$self->{'errorCode'} = 2;
	return;	
    }
    if(!defined $tables{"SRDEF"} and !defined $tables{"srdef"}) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Table SRDEF not found in database.";
	$self->{'errorCode'} = 2;
	return;	
    }
    if(!defined $tables{"MRREL"} and !defined $tables{"mrrel"}) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Table MRREL not found in database.";
	$self->{'errorCode'} = 2;
	return;	
    }
       if(!defined $tables{"MRDOC"} and !defined $tables{"mrdoc"}) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Table MRDOC not found in database.";
	$self->{'errorCode'} = 2;
	return;	
    }
    if(!defined $tables{"MRSAB"} and !defined $tables{"mrsab"}) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Table MRSAB not found in database.";
	$self->{'errorCode'} = 2;
	return;	
    }
}

#  set the version
sub _setVersion
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";

    my $function = "_setVersion";

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    my $arrRef = $db->selectcol_arrayref("select EXPL from MRDOC where VALUE = \'mmsys.version\'");
    if($db->err()) {
	$self->{'errorCode'} = 2;
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Error executing database query: ".($db->errstr());
	return ();
    }
    if(scalar(@{$arrRef}) < 1) {
	$self->{'errorCode'} = 2;
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "No version info in table MRDOC.";
	return ();
    }
    
    ($version) = @{$arrRef}; 
}    

#  set the configuration environment variable
sub _setConfigurationVariable
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";

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

#  set the table and file names that store the upper level taxonomy and path information
sub _setTableAndFileNames
{

    my $self = shift;

    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";

    #  get the database name that we are using
    my $database = $self->{'database'};
    
    #  set appropriate version output
    my $ver = $version;
    $ver=~s/-/_/g;
    
    #  set table and cycle and upper level relations files
    $childFile  = "$umlsinterface/$ver";
    $parentFile = "$umlsinterface/$ver";
    $tableFile  = "$umlsinterface/$ver";
    
    $cycleFile  = "$umlsinterface/$ver";
    $configFile = "$umlsinterface/$ver";
    
    $tableName  = "$ver";
    $parentTable= "$ver";
    $childTable = "$ver";
    $propTable  = "$ver";
    
    print STDERR "UMLS-Interface Configuration Information\n";
    print STDERR "  Sources:\n";
    foreach my $sab (sort keys %sab_names) {
    	$tableFile  .= "_$sab";
	$childFile  .= "_$sab";
	$parentFile .= "_$sab";

    	$cycleFile  .= "_$sab";
	$configFile .= "_$sab";
	$tableName  .= "_$sab";
	$parentTable.= "_$sab";
	$childTable .= "_$sab";
	$propTable  .= "_$sab";

	print STDERR "    $sab\n";
	
	
    }
    
    print STDERR "  Relations:\n";
    while($relations=~/=\'(.*?)\'/g) {
	my $rel = $1;
	$rel=~s/\s+//g;
	$tableFile  .= "_$rel";
	$childFile  .= "_$rel";
	$parentFile .= "_$rel";
	$cycleFile  .= "_$rel";	
	$configFile .= "_$rel";
	$tableName  .= "_$rel";	
	$parentTable.= "_$rel";
	$childTable .= "_$rel";
	$propTable  .= "_$rel";

	print STDERR "    $rel\n";
    }
    
    $tableFile  .= "_table";
    $childFile  .= "_child";
    $parentFile .= "_parent";
    $cycleFile  .= "_cycle";
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
	print STDERR "  Configuration file:\n";
	print STDERR "    $configFile\n";
    }
    
    print STDERR "  Database: \n";
    print STDERR "    $database\n\n";
}

#  create the configuration file 
sub _setConfigFile
{
    my $self   = shift;

    return undef if(!defined $self || !ref $self);
    $self->{'traceString'} = "";
    
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

#  if the cuilist option is specified load the information
sub _loadCuiList 
{
    my $self    = shift;
    my $cuilist = shift;
    
    my $function = "_loadCuiList";

    if(defined $cuilist) {
	open(CUILIST, $cuilist) || die "Could not open the cuilist file: $cuilist\n"; 
	while(<CUILIST>) {
	    chomp;
	    
	    if($self->validCui($_)) {
		$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
		$self->{'errorString'} .= "Incorrect input value ($_) in cuilist.";
		$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
		return undef;
	    }
	    
	    $CuiList{$_}++;
	} 
    }
}


# Method to initialize the UMLS::Interface object.
sub _initialize
{
    my $self = shift;
    my $params = shift;

    return undef if(!defined $self || !ref $self);
    $params = {} if(!defined $params);

    #  get some of the parameters
    my $multitax     = $params->{'multitax'};
    my $config       = $params->{'config'};
    my $cyclefile    = $params->{'cyclefile'};
    my $cuilist      = $params->{'cuilist'};
    my $database     = $params->{'database'};

    #  set function name
    my $function = "_initialize";

    #  to store the database object
    my $db = $self->_setDatabase($params);
    if($self->checkError($function)) { return (); }	

    #  set up the options
    $self->_setOptions($params);
    if($self->checkError($function)) { return (); }	

    #  check that all of the tables required exist in the db
    $self->_checkTablesExist();
    if($self->checkError($function)) { return (); }	

    #  set the version information
    $self->_setVersion();
    if($self->checkError($function)) { return (); }	

    #  set the additional information needed for self
    $self->{'traceString'}  = "";
    $self->{'cache'}        = {};
    $self->{'maxCacheSize'} = 1000;
    $self->{'cacheQ'}       = ();

    #  set the configuration
    $self->_config($config); 
    if($self->checkError("_config")) { return (); } 
    
    #  set the root nodes
    $self->_setRoots();
    if($self->checkError("_setRoots")) { return (); }	
    
    #  set the umls interface configuration variable
    $self->_setConfigurationVariable();
    if($self->checkError("_setConfigurationVariable")) { return (); }	

    #  set the table and file names for indexing
    $self->_setTableAndFileNames();
    if($self->checkError("_setTableAndFileNames")) { return (); }	
    
    #  set the configfile
    $self->_setConfigFile();
    if($self->checkError("_setConfigFile")) { return (); }	
    
    #  load the cuilist if it has been defined
    $self->_loadCuiList($cuilist);
    if($self->checkError("_loadCuiList")) { return (); }	

    #  create the index database
    $self->_createIndexDB();
    if($self->checkError("_createIndexDB")) { return (); }	
    
    #  connect to the index database
    $self->_connectIndexDB();
    if($self->checkError("_connectIndexDB")) { return (); }	

    #  set the upper level taxonomy
    $self->_setUpperLevelTaxonomy();
    if($self->checkError("_setUpperLevelTaxonomy")) { return (); }

    #  propogate counts up if it has been defined 
    #  the database must be up to do this
    $self->_propogateCounts();
    if($self->checkError("_propogateCounts")) { return (); }	
    

}

#  Method to check if a concept ID exists in the database.
sub exists
{    
    my $self = shift;
    my $concept = shift;

    my $function = "exists";

    return () if(!defined $self || !ref $self);

    $self->{'traceString'} = "";

    #  check parameter exists
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
    
    #  check if valid concept
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    #  set up database
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

    my $arrRef = "";    
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where CUI='$concept'");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where CUI='$concept' and $sources");
    }
    if($self->checkError($function)) { return (); }
    
    my $count = scalar(@{$arrRef});
    if($count > $count) {
	$self->{'errorCode'} = 2 if($self->{'errCode'} < 1);
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->exists()) - ";
	$self->{'errorString'} .= "Internal error: Duplicate concept rows.";
    }
    
    return 1 if($count);
    
    return 0;
}

#  Method to set the roots that exist in the UMLS view
sub _setRoots {

    my $self = shift;
    
    my $function = "_setRoots";
    &_debug($function);

    return () if(!defined $self || !ref $self);
    
    $roots{$umlsRoot}++;
}

# Method that returns a list of concepts (@concepts) related 
# to a concept $concept through a relation $rel
sub getRelated
{
    my $self    = shift;
    my $concept = shift;
    my $rel     = shift;

    return () if(!defined $self || !ref $self);

    my $function = "getRelated";
    &_debug($function);
    &_input($function, "$concept $rel"); 

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
    my $arrRef = "";
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and REL='$rel' and CUI2!='$concept'");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and REL='$rel' and ($sources) and CUI2!='$concept'");
    }
    
    #  check for errors
    if($self->checkError($function)) { return(); }
    
    #  print the output if debug
    my $output = join " ", @{$arrRef};
    &_output($function, $output);

    return @{$arrRef};
}

# Method to map terms to a conceptID
sub getTermList
{
    my $self = shift;
    my $concept = shift;

    return 0 if(!defined $self || !ref $self);
    
    my $function = "getTermList";
    
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

    my %retHash = ();
    if($concept eq $umlsRoot) {
	$retHash{"**UMLS ROOT**"}++;
	return keys(%retHash);    
    }

    $self->{'traceString'} = "";

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

    my $arrRef = "";
    
    #  get the strings associated to the CUI
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select distinct STR from MRCONSO where CUI='$concept'");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct STR from MRCONSO where CUI='$concept' and ($sources or SAB='SRC')");
    }
    
    if($self->checkError($function)) { return(); }

    foreach my $tr (@{$arrRef}) {
        $tr =~ s/^\s+//;
        $tr =~ s/\s+$//;
        $tr =~ s/\s+/ /g;
        $retHash{lc($tr)} = 1;
    }
    
    return keys(%retHash);
}

# Method to map terms to a conceptID
sub getAllTerms
{
    my $self = shift;
    my $concept = shift;

    return 0 if(!defined $self || !ref $self);
    
    my $function = "getAllTerms";
    &_debug($function);
    &_input($function, $concept); 
 
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

    my %retHash = ();

    if($concept eq $umlsRoot) {
	$retHash{"**UMLS ROOT**"}++;
	return keys(%retHash);    
    }

    $self->{'traceString'} = "";

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

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
    
    foreach my $str (sort keys %strhash) {
	my $sabs = join ", ", @{$strhash{$str}};
	my $index = "$str - $sabs";
	$retHash{$index}++;
    }

    #  return the output if debug is on
    my $output = keys %retHash;
    &_output($function, $output);

    return keys(%retHash);
}

# Method to map CUIs to a term.
sub getConceptList
{
    my $self = shift;
    my $term = shift;

    return () if(!defined $self || !ref $self);

    my $function = "getConceptList";
    &_debug($function);
    &_input($function, $term); 

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
    
    my $arrRef = "";
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where STR='$term'");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct CUI from MRCONSO where STR='$term' and ($sources)");
    }
    
    if($self->checkError($function)) { return (); }
    

    my $output = join " ", @{$arrRef};
    &_output($function, $output);

    return @{$arrRef};
    
}


# Method to find all the paths from a concept to
# the root node of the is-a taxonomy.
sub pathsToRoot
{
    my $self = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);

    my $function = "pathsToRoot";
    &_debug($function);
    &_input($function, $concept);

    $self->{'traceString'} = "";
    
    #  check that concept exists
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
    
    #  check that the concept is valid
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    #  check that concept exists
    if(!($self->checkConceptExists($concept))) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($concept) doesn't exist.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    #  set the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

    #  if the realtime option is set get the paths otherwise 
    #  they are or should be stored in the database 
    my $paths = "";
    if($option_realtime) {
	@path_storage = ();
	my @array     = (); 
	$self->_cuiToRoot($concept);
	$paths = \@path_storage;
    }
    else {

	$self->_setDepth();
	if($self->checkError("_setDepth")) { return (); }
	
	#  get the paths
	$paths = $sdb->selectcol_arrayref("select PATH from $tableName where CUI=\'$concept\'");
	if($self->checkError($function)) { return (); }

    }

    #  remove paths that contain an inactive concept
    my @gpaths = ();
    foreach my $path (@{$paths}) {
	#C1274012|Ambiguous concept (inactive concept)
	if($path=~/C1274012/) { next; }
	#C1274013|Duplicate concept (inactive concept)
	if($path=~/C1274013/) { next; }
	#C1276325|Reason not stated concept (inactive concept)
	if($path=~/C1276325/) { next; }
	#C1274014|Outdated concept (inactive concept)
	if($path=~/C1274014/) { next; }
	#C1274015|Erroneous concept (inactive concept)
	if($path=~/C1274015/) { next; }
	#C1274021|Moved elsewhere (inactive concept)
	if($path=~/C1274021/) { next; }

	push @gpaths, $path;
    }

    #  print the output if debug is set
    my $output = join "\n", @gpaths;
    &_output($function, $output);

    return \@gpaths;
    
}

#  this function sets the taxonomy arrays
sub _setTaxonomyArrays 
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);

    my $function = "_setTaxonomyArrays";
    &_debug($function);

    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    #  set the parent taxonomy
    my $sql = qq{ SELECT CUI1, CUI2 FROM $parentTable};
    my $sth = $sdb->prepare( $sql );
    $sth->execute();
    my($cui1, $cui2);
    $sth->bind_columns( undef, \$cui1, \$cui2 );
    while( $sth->fetch() ) {
	push @{$parentTaxonomy{$cui1}}, $cui2;    
    } $sth->finish();
    
    
    #  set the child taxonomy
    $sql = qq{ SELECT CUI1, CUI2 FROM $childTable};
    $sth = $sdb->prepare( $sql );
    $sth->execute();
    $sth->bind_columns( undef, \$cui1, \$cui2 );
    while( $sth->fetch() ) {
	push @{$childrenTaxonomy{$cui1}}, $cui2;    
    } $sth->finish();
}

#  this function creates the taxonomy tables if they don't
#  already exist in the umlsinterfaceindex database
sub _createTaxonomyTables
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);

    my $function = "_createTaxonomyTables";
    &_debug($function);

    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }

    #  create parent table
    $sdb->do("CREATE TABLE IF NOT EXISTS $parentTable (CUI1 char(8), CUI2 char(8))");
    if($self->checkError($function)) { return (); }
    
    #  create child table
    $sdb->do("CREATE TABLE IF NOT EXISTS $childTable (CUI1 char(8), CUI2 char(8))");
    if($self->checkError($function)) { return (); }
    
    #  create the index table if it doesn't already exist
    $sdb->do("CREATE TABLE IF NOT EXISTS tableindex (TABLENAME blob(1000000), HEX char(41))");
    if($self->checkError($function)) { return (); }
    
    #  add them to the index table
    $sdb->do("INSERT INTO tableindex (TABLENAME, HEX) VALUES ('$parentTableHuman', '$parentTable')");
    if($self->checkError($function)) { return (); }   
    $sdb->do("INSERT INTO tableindex (TABLENAME, HEX) VALUES ('$childTableHuman', '$childTable')");
    if($self->checkError($function)) { return (); }   
}    

#  this function loads the taxonomy tables if the
#  configuration files exist for them
sub _loadTaxonomyTables 
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_loadTaxonomyTables";
    &_debug($function);
    
    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    open(PAR, $parentFile) || die "Could not open $parentFile\n";	
    open(CHD, $childFile)  || die "Could not open $childFile\n";
    
    
    #  load parent table
    while(<PAR>) {
	chomp;
	if($_=~/^\s*$/) { next; }
	my ($cui1, $cui2) = split/\s+/;
	
	my $arrRef = $sdb->do("INSERT INTO $parentTable (CUI1, CUI2) VALUES ('$cui1', '$cui2')");	    
	if($self->checkError($function)) { return (); }   
    }
    
    #  load child table
    while(<CHD>) {
	chomp;
	if($_=~/^\s*$/) { next; }
	my ($cui1, $cui2) = split/\s+/;
	my $arrRef = $sdb->do("INSERT INTO $childTable (CUI1, CUI2) VALUES ('$cui1', '$cui2')");	    
	if($self->checkError($function)) { return (); }
    }
    close PAR; close CHD; 
}

sub getCuiList
{
    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_getCuiList";
    &_debug($function);

    #  set up the database
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }    
    
    $self->{'traceString'} = "";
        
    #  get the sabs in the config file
    my @sabs = ();
    if($umlsall) {
	my $s = $db->selectcol_arrayref("select distinct SAB from MRREL");
	@sabs = @{$s};
    }
    else {
	foreach my $sab (sort keys %sab_names) { push @sabs, $sab; }
    }

    my %hash = ();    
    #  for each of the sabs in the configuratino file
    foreach my $sab (@sabs) {
	
	#  get the cuis for that sab
	my $cuis = $self->_getCuis($sab);
	
	#  add the cuis to the propagation hash
	foreach my $cui (@{$cuis}) { $hash{$cui} = 0 };
    }
    
    #  add upper level taxonomy
    foreach my $cui (sort keys %parentTaxonomy)   { $hash{$cui} = 0; }
    foreach my $cui (sort keys %childrenTaxonomy) { $hash{$cui} = 0; }
    
    return \%hash;
}

sub getCuisFromSource {
    
    my $self = shift;
    my $sab = shift;
    
    my $function = "getCuisFromSource";

    &_debug($function);
    &_input($function, $sab);  

    my $arrRef = $self->_getCuis($sab);
    
    my $output = join " ", @{$arrRef};

    &_output($function, $output);

    return ($arrRef);
}

sub _getCuis
{

    my $self = shift;
    my $sab  = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_getCuis";
    &_debug($function);

    #  set up the database
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }    
    
    $self->{'traceString'} = "";
    
    if($debug) { print STDERR "select CUI1 from MRREL where ($relations) and (SAB=\'$sab\')\;\n"; }
    my $allCui1 = $db->selectcol_arrayref("select CUI1 from MRREL where ($relations) and (SAB=\'$sab\')\;");
    if($self->checkError($function)) { return undef; }
    
    if($debug) { print STDERR "select CUI2 from MRREL where ($relations) and (SAB=\'$sab\')\n"; }
    my $allCui2 = $db->selectcol_arrayref("select CUI2 from MRREL where ($relations) and (SAB=\'$sab\')");
    if($self->checkError($function)) { return undef; }
    
    my @allCuis = (@{$allCui1}, @{$allCui2});
    
    return \@allCuis;
}

#  this function creates the upper level taxonomy between the 
#  the sources and the root UMLS node
sub _createUpperLevelTaxonomy
{
    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_createUpperLevelTaxonomy";
    &_debug($function);
    
    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
        
    #  set up the database
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }    
    
    $self->{'traceString'} = "";
 
    # open the parent and child files to store the upper level 
    #  taxonomy information if the verbose option is defined
    if($option_verbose) {
	open(CHD, ">$childFile")  || die "Could not open $childFile\n";
	open(PAR, ">$parentFile") || die "Could not open $parentFile\n";
    }
    
    my @sabs = ();
    if($umlsall) {
	my $s = $db->selectcol_arrayref("select distinct SAB from MRREL");
	@sabs = @{$s};
    }
    else {
	foreach my $sab (sort keys %sab_names) { push @sabs, $sab; }
    }
    
    foreach my $sab (@sabs) {
	
	#  get the sab's cui
	my $sab_cui = $self->_getSabCui($sab);
	
	#  select all the CUIs from MRREL 
	my $allCuis = $self->_getCuis($sab);
	
	#  select all the CUI1s from MRREL that have a parent link
	if($debug) { print STDERR "selecting CUIs from MRREL that have parent link for $sab\n"; }
	my $parCuis = $db->selectcol_arrayref("select CUI1 from MRREL where ($parentRelations) and (SAB=\'$sab\')");
        if($self->checkError($function)) { return undef; }
	
	#  load the cuis that have a parent into a temporary hash
	my %parCuisHash = ();
	foreach my $cui (@{$parCuis}) { $parCuisHash{$cui}++; }
    
	#  load the cuis that do not have a parent into the parent 
	#  and chilren taxonomy for the upper level
	foreach my $cui (@{$allCuis}) {
	
	    #  if the cui has a parent move on
	    if(exists $parCuisHash{$cui})    { next; }
	
	    #  already seen this cui so move on
	    if(exists $parentTaxonomy{$cui}) { next; }
	
		
	    if($sab_cui eq $cui) { next; }
	    
	    push @{$parentTaxonomy{$cui}}, $sab_cui;
	    push @{$childrenTaxonomy{$sab_cui}}, $cui;

	    $sdb->do("INSERT INTO $parentTable (CUI1, CUI2) VALUES ('$cui', '$sab_cui')");	    
	    if($self->checkError($function)) { return (); }   		
	    
	    $sdb->do("INSERT INTO $childTable (CUI1, CUI2) VALUES ('$sab_cui', '$cui')");	    
	    if($self->checkError($function)) { return (); } 
	    
	    #  print this information to the parent and child 
	    #  file is the verbose option has been set
	    if($option_verbose) {
		print PAR "$cui $sab_cui\n";
		print CHD "$sab_cui $cui\n";
	    }
	}
        
        #  add the sab cuis to the parent and children Taxonomy
	push @{$parentTaxonomy{$sab_cui}}, $umlsRoot;
	push @{$childrenTaxonomy{$umlsRoot}}, $sab_cui;

	#  print it to the table if the verbose option is set
	if($option_verbose) { 
	    print PAR "$sab_cui  $umlsRoot\n"; 
	    print CHD "$umlsRoot $sab_cui\n"; 
	}
	
	#  store this information in the database
	$sdb->do("INSERT INTO $parentTable (CUI1, CUI2) VALUES ('$sab_cui', '$umlsRoot')");	    
	if($self->checkError($function)) { return (); }   		
	
	$sdb->do("INSERT INTO $childTable (CUI1, CUI2) VALUES ('$umlsRoot', '$sab_cui')"); 
	if($self->checkError($function)) { return (); }   		
    }
    
    #  close the parent and child tables if opened
    if($option_verbose) { close PAR; close CHD; }

    #  print out some information
    my $pkey = keys %parentTaxonomy;
    my $ckey = keys %childrenTaxonomy;
    
    if($debug) {
	print STDERR "Taxonomy is set:\n";
	print STDERR "  parentTaxonomy: $pkey\n";
	print STDERR "  childrenTaxonomy: $ckey\n\n";
    }
}

#  this function sets the upper level taxonomy between 
#  the sources and the root UMLS node
sub _setUpperLevelTaxonomy 
{
    
    my $self = shift;
    
    my $function = "_setUpperLevelTaxonomy";
    #&_debug($function);
    
    return undef if(!defined $self || !ref $self);
    
    #  set the sourceDB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    #  check if the taxonomy is already set
    my $ckeys = keys %childrenTaxonomy;
    my $pkeys = keys %parentTaxonomy;
    if($pkeys > 0) { return; }
    
    #  check if the parent and child tables exist and if they do just return otherwise create them
    if($self->_checkTableExists($childTable) and $self->_checkTableExists($parentTable)) {
	$self->_setTaxonomyArrays();
	if($self->checkError("_setTaxonomyArrays")) { return (); }   
	return;
    }
    else {
	$self->_createTaxonomyTables();
	if($self->checkError("_createTaxonomyTables")) { return (); }   
    }
    
    
    #  if the parent and child files exist just load them into the database
    if( (-e $childFile) and (-e $parentFile) ) {

	$self->_loadTaxonomyTables();
	if($self->checkError("_loadTaxonomyTables")) { return (); }   
    }
    #  otherwise we need to create them
    else {
       
	$self->_createUpperLevelTaxonomy();
	if($self->checkError("_createUpperLevelTaxonomy")) { return (); }   
    }
}

#  connect the database to the source db that holds
#  the path tables for user specified source(s) and 
#  relation(s)
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

#  this function creates the umlsinterfaceindex database connection
sub _createIndexDB {
    
    my $self = shift;
    
    return () if(!defined $self || !ref $self);
    
    my $function = "_createIndexDB";
    &_debug($function);
    
    #  check that the database exists
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    #  show all of the databases
    my $sth = $db->prepare("show databases");
    $sth->execute();
    if($sth->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->_initialize()) - ";
	$self->{'errorString'} .= "Unable run query: ".($sth->errstr());
	$self->{'errorCode'} = 2;
	return ();
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
	if($self->checkError($function)) { return (); }   		
    }
}

#  this functino marks the cycles if the cyclefile is provided    
sub _markCycles
{
    my $self = shift;

    return () if(!defined $self || !ref $self);

    my $function = "_markCycles";
    &_debug($function);

    #  get cycle file
    my $cyclefile = $self->{'cyclefile'};
    
    if(defined $cyclefile) { 
	
	#  check that the database exists
	my $db = $self->{'db'};
	if(!$db) {
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "A db is required.";
	    $self->{'errorCode'} = 2;
	    return ();
	}    
	
	open(CYCLE, $cyclefile) || die "Could not open cycle file: $cyclefile\n";

	while(<CYCLE>) {
	    chomp;
	    my @array = split/\|/;
	    
	    my $cui1 = $array[0];
	    my $cui2 = $array[1];
	    my $rel  = $array[2];
	    my $rela = $array[3];
	    
	    if($rel=~/$relations/) {
		if($umlsall) {
		    $db->do("update MRREL set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='$rel'");
		}
		else {
		    $db->do("update MRREL set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='$rel' and ($sources)");
		}
		if($self->checkError($function)) { return (); }   		
	    }
	}
    }
}

#  function checks to see if a given table exists
sub _checkTableExists {
    
    my $self  = shift;
    my $table = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "_checkTableExists";
    
    #  check that the database exists
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    my $sth = $sdb->prepare("show tables");
    $sth->execute();
    if($sth->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Unable run query: ".($sth->errstr());
	$self->{'errorCode'} = 2;
	return;
    }
    
    my $t      = "";
    my %tables = ();
    while(($t) = $sth->fetchrow()) {
	$tables{lc($t)} = 1;
	
    }
    $sth->finish();
    
    if(! (exists$tables{lc($table)})) { 
	return 0; 
    }
    else                         { 
	return 1; 
    }
}

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
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    #  if the path infomration has not been stored
    if(! ($self->_checkTableExists($tableName))) {
	
	#  check if tableFile exists in the default_options directory, if so load it into the database
	if(-e $tableFile) {
	    
	    #  create the table in the umls database
	    my$sdb->do("CREATE TABLE IF NOT EXISTS $tableName (CUI char(8), DEPTH int, PATH varchar(450))");
	    if($self->checkError($function)) { return (); }
	    
	    $sdb->do("INSERT INTO tableindex (TABLENAME, HEX) VALUES ('$tableNameHuman', '$tableName')");
	    if($self->checkError($function)) { return (); }   

	    #  load the path information into the table
	    open(TABLE, $tableFile) || die "Could not open $tableFile\n";
	    while(<TABLE>) {
		chomp;
		if($_=~/^\s*$/) { next; }
		my ($cui, $depth, $path) = split/\t/;
		$sdb->do("INSERT INTO $tableName (CUI, DEPTH, PATH) VALUES(\'$cui\', '$depth', \'$path\')");
		if($self->checkError($function)) { return (); }
	    }
	}
	#  otherwise create the tableFile and put the information in the file and the database
	else  {
	    
	    my $sourceList = "";
	    foreach my $sab (sort keys %sab_names) { 
		$sourceList .= "$sab, "; 
	    } chop $sourceList; chop $sourceList;
   
	    
	    print STDERR "You have requested the following sources $sourceList.\n";
	    print STDERR "In order to use these you either need to create an index\n";
	    print STDERR "or resubmit this command using --realtime. Creating\n";
	    print STDERR "an index can be very time-consuming, but once it is\n";
	    print STDERR "built your commands will run faster than with --realtime.\n\n";


	    if($option_forcerun == 0) {
		print STDERR "Do you want to continue with index creation (y/n)";
	    
		my $answer = <STDIN>; chomp $answer;
	    
		if($answer=~/(N|n)/) {
		    print STDERR "Exiting program now.\n\n";
		    exit;
		}
	    }
	    else {
		print "Running index ... \n";
	    }
	    
	    #  mark the CVF
	    #$self->_resetCVF();
	    #if($self->checkError("_resetCVF")) { return (); }   		
	    #$self->_markCVF();
	    #if($self->checkError("_markCVF")) { return (); }   		

	    # mark the cycles;
	    $self->_markCycles();
	    if($self->checkError("_markCycles")) { return (); }   		

	    #  create the table in the umls database
	    $sdb->do("CREATE TABLE IF NOT EXISTS $tableName (CUI char(8), DEPTH int, PATH varchar(450))");
	    if($self->checkError($function)) { return (); }
	    
	    #  insert the name into the index
	    $sdb->do("INSERT INTO tableindex (TABLENAME, HEX) VALUES ('$tableNameHuman', '$tableName')");
	    if($self->checkError($function)) { return (); }   


	    #  for each root - this is for when we allow multiple roots
	    #  right now though we only have one - the umlsRoot
	    foreach my $root (sort keys %roots) {
		$self->_initializeDepthFirstSearch($root, 0, $root);
		if($self->checkError("_initializeDepthFirstSearch")) { return (); }
	    }
	    
	    #  load cycle information into a file
	    $self->_loadCycleInformation();
	    if($self->checkError("_loadCycleInformation")) { return (); }
	}
	
        #  create index on the newly formed table
	my $indexname = "$tableName" . "_CUIINDEX";
	my $index = $sdb->do("create index $indexname on $tableName (CUI)");
	if($self->checkError($function)) { return (); }
    }
    
    #  set the maximum depth
    my $d = $sdb->selectcol_arrayref("select max(DEPTH) from $tableName");
    if($self->checkError($function)) { return (); }
    $max_depth = shift @{$d}; 
}

sub _loadCycleInformation
{

    my $self = shift;
    
    if($option_verbose) {
	open(CYCLE, ">$cycleFile") || die "Could not open file $cycleFile"; 
	foreach my $cui1 (sort keys %cycleHash) {
	    foreach my $cui2 (sort keys %{$cycleHash{$cui1}}) {
		print CYCLE "$cui1 $cui2 $cycleHash{$cui1}{$cui2}\n";
	    }
	} 
	close CYCLE;
	
	my $temp = chmod 0777, $cycleFile;
    }
}

sub _debug
{
    my $function = shift;
    if($debug) { print STDERR "In $function\n"; }
}

sub _output
{
    my $function = shift;
    my $output   = shift;

    if($debug) { print STDERR "  OUTPUT for $function: $output\n"; }
}

sub _input
{
    my $function = shift;
    my $input    = shift;

    if($debug) { print STDERR "  INPUT for $function: $input\n"; }
}

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
	
	my %includesab  = ();
	my %excludesab  = ();
	my %includerel  = ();
	my %excluderel  = ();
	my %includerela = ();
	my %excluderela = ();

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
		    if(   $type eq "SAB"  and $det eq "include") { $includesab{$element}++;  }
		    elsif($type eq "SAB"  and $det eq "exclude") { $excludesab{$element}++;  }
		    elsif($type eq "REL"  and $det eq "include") { $includerel{$element}++;  }
		    elsif($type eq "REL"  and $det eq "exclude") { $excluderel{$element}++;  }
		    elsif($type eq "RELA" and $det eq "include") { $includerela{$element}++; }
		    elsif($type eq "RELA" and $det eq "exclude") { $excluderela{$element}++; }
		}
	    }
	    else {
		$self->{'errorCode'} = 2;
		$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
		$self->{'errorString'} .= "Configuration file format not correct ($_).";
		return ();
	    }
	}
	
	my $includesabkeys  = keys %includesab;
	my $excludesabkeys  = keys %excludesab;
	my $includerelkeys  = keys %includerel;
	my $excluderelkeys  = keys %excluderel;
	my $includerelakeys = keys %includerela;
	my $excluderelakeys = keys %excluderela;

	#  check for errors
	if($includesabkeys > 0 and $excludesabkeys > 0) {
	    $self->{'errorCode'} = 2;
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "Configuration file can not have an include ";
	    $self->{'errorString'} .= "and exclude list of sources (sab)\n";
	    return ();
	}
	if($includerelkeys > 0 and $excluderelkeys > 0) {
	    $self->{'errorCode'} = 2;
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "Configuration file can not have an include ";
	    $self->{'errorString'} .= "and exclude list of relations (rel)\n";
	    return ();
	}
	
	#  set the relations
	$self->_setRelations($includerelkeys, $excluderelkeys, \%includerel, \%excluderel);
	if($self->checkError("_setRelations")) { return (); }

	#  set the sabs
	$self->_setSabs($includesabkeys, $excludesabkeys, \%includesab, \%excludesab);
	if($self->checkError("_setSabs")) { return (); }

	#  set the relas
	$self->_setRelas($includerelakeys, $excluderelakeys, \%includerela, \%excluderela);
	if($self->checkError("_setRelas")) { return (); }

	#  check the relations
	#$self->_checkRelations();
	#if($self->checkError("_checkRelations")) { return (); }

    }

    #  there is no configuration file so set the default
    else {

	#  get the CUIs of the default sources
	my $mshcui = $self->_getSabCui('MSH');
	if($self->checkError($function)) { return (); }

	if(! (defined $mshcui) ) {
	    $self->{'errorCode'} = 2;
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "SAB (MSH) is not valid. ";
	    return ();
	}
	$sources = "SAB=\'MSH\'";
	$sab_names{'MSH'}++; 
	$sab_hash{$mshcui}++;
	
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

#  checks the relations
sub _checkRelations 
{

    my $self = shift;

    my $function = "_checkRelations";
    &_debug($function);

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

    my %hash = ();
    my $sth  = "";
    
    #  get all of the possible RELs
    if($umlsall) {
	$sth = $db->prepare("select distinct REL from MRREL;");
    }
    else {
	$sth = $db->prepare("select distinct REL from MRREL where $sources");
    }
    $sth->execute();
    if($sth->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Unable run query: ".($sth->errstr());
	$self->{'errorCode'} = 2;
	return ();
    }
	
    #  get all the relas for the children
    my $rel = "";
    while(($rel) = $sth->fetchrow()) {
	if(defined $rel) {
	   $hash{$rel}++;
	}
    }
    $sth->finish();
    
    #  get all of the possible RELAs
    if($umlsall) {
	$sth = $db->prepare("select distinct RELA from MRREL;");
    }
    else {
	$sth = $db->prepare("select distinct RELA from MRREL where $sources");
    }
    $sth->execute();
    if($sth->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Unable run query: ".($sth->errstr());
	$self->{'errorCode'} = 2;
	return ();
    }
	
    #  get all the relas
    my $rela = "";
    while(($rela) = $sth->fetchrow()) {
	if(defined $rela) {
	   $hash{$rela}++;
	}
    }
    $sth->finish();

    while($relations=~/REL=\'(.*?)\'/g) {
	my $r = $1;
	if(! (exists $hash{$r})) {
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "Relation ($r) doesn't exist for the given source. ";
	    $self->{'errorCode'} = 2;
	}
    }
    
}

#  sets the rela variables from the information in the config file
sub _setRelas
{
    my $self           = shift;
    my $includerelakeys = shift;
    my $excluderelakeys = shift;
    my $includerela     = shift;
    my $excluderela     = shift;


    my $function = "_setRelas";
    &_debug($function);
    
    return () if(!defined $self || !ref $self);



    $self->{'traceString'} = "";

    #  check the parameters are defined
    if(!(defined $includerelakeys) || !(defined $excluderelakeys) || 
       !(defined $includerela)     || !(defined $excluderela)) {
	$self->{'errorCode'} = 2;
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	return ();
    }
    
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    #  initalize the hash tables that will hold children and parent relas
    my %childrelas  = ();
    my %parentrelas = ();
    
    #  if the includerelakeys or excluderelakeys are set then get the relas for the child 
    #  and parent relations.
    if($includerelakeys > 0 or $excluderelakeys > 0) {

	
	
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
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "Unable run query: ".($sth->errstr());
	    $self->{'errorCode'} = 2;
	    return ();
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
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "There are no RELA relations for the given sources";
	    $self->{'errorCode'} = 2;
	    return ();
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
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "Unable run query: ".($sth->errstr());
	    $self->{'errorCode'} = 2;
	    return ();
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
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "There are no RELA relations for the given sources 4";
	    $self->{'errorCode'} = 2;
	    return ();
	}
	
    }
    
    #  uses the relas that are set in the includrelakeys or excluderelakeys
    if($includerelakeys > 0) {
	
	my @crelas = ();
	my @prelas = ();
	my $relacount = 0;
	
	$relations .= "and (";
	foreach my $rela (sort keys %{$includerela}) {
	    
	    $relacount++;
	    
	    if($relacount == $includerelakeys) { $relations .="RELA=\'$rela\'";     }
	    else                               { $relations .="RELA=\'$rela\' or "; }
	    
	    
	    if(exists $childrelas{$rela})     { push @crelas, "RELA=\'$rela\'";  }
	    elsif(exists $parentrelas{$rela}) { push @prelas, "RELA=\'$rela\'";  }
	    else {
		$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
		$self->{'errorString'} .= "RELA relation ($rela) does not exist for the given sources ";
		$self->{'errorCode'} = 2;
		return ();
	    }
	}
	$relations .= ")";
	
	my $crelasline = join " or ", @crelas;
	my $prelasline = join " or ", @prelas;
	
	$parentRelations .= " and ($prelasline)";
	$childRelations  .= " and ($crelasline)";
    }
    if($excluderelakeys > 0) {
	
	my $arrRef = $db->selectcol_arrayref("select distinct RELA from MRREL");
	if($self->checkError($function)) { return (); }
	
	my $arrRefkeys = $#{$arrRef} + 1;
	my $relacount   = 0;
	my @crelas = ();
	my @prelas = ();
	
	$relations .= "and (";
	foreach my $rela (@{$arrRef}) {
	    
	    $relacount++;
	    
	    if(exists ${$excluderela}{$rela}) { next; }
	    
	    if($relacount == $arrRefkeys) { $relations .="RELA=\'$rela\'";     }
	    else                          { $relations .="RELA=\'$rela\' or "; }
	    
	    if(exists $childrelas{$rela})  { push @crelas, "RELA=\'$rela\'";  }
	    if(exists $parentrelas{$rela}) { push @prelas, "RELA=\'$rela\'";  }
	} 
	$relations .= ")";
	
	my $crelasline = join " or ", @crelas;
	my $prelasline = join " or ", @prelas;
	
	$parentRelations .= " and ($prelasline)";
	$childRelations  .= " and ($crelasline)";
    }
}

sub _setUMLS_ALL
{
    my $self = shift;
    
    my $function = "_setUMLS_ALL";
    &_debug($function);

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    my $arrRef = $db->selectcol_arrayref("select distinct SAB from MRREL where $relations");
    if($self->checkError($function)) { return (); }

    foreach my $sab (@{$arrRef}) {

	my $cui = $self->_getSabCui($sab);
	if($self->checkError($function)) { return (); }
	
	if(! (defined $cui) ) {
	    $self->{'errorCode'} = 2;
	    $self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	    $self->{'errorString'} .= "SAB ($sab) is not valid. ";
	    return ();
	}
	
	$sab_names{$sab}++; 
	$sab_hash{$cui}++;
	    
    }
}
    
#  sets the source variables from the information in the config file
sub _setSabs
{
    my $self           = shift;
    my $includesabkeys = shift;
    my $excludesabkeys = shift;
    my $includesab     = shift;
    my $excludesab     = shift;


    my $function = "_setSabs";
    &_debug($function);
    
    return () if(!defined $self || !ref $self);

    $self->{'traceString'} = "";

    #  check the parameters are defined
    if(!(defined $includesabkeys) || !(defined $excludesabkeys) || 
       !(defined $includesab)     || !(defined $excludesab)) {
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

    #  uses the sources (sabs) that are set in the includsabkeys or excludesabkeys
    if($includesabkeys > 0) {
	my $sabcount = 0;
	foreach my $sab (sort keys %{$includesab}) {
	    
	    $sabcount++;
	    
	    if($sab eq "UMLS_ALL") { 
		$umlsall = 1;
		$sources = "UMLS_ALL";
		&_setUMLS_ALL();
		next;
	    }
	    
	    if($sabcount == $includesabkeys) { $sources .="SAB=\'$sab\'";     }
	    else                             { $sources .="SAB=\'$sab\' or "; }
	    
	    my $cui = $self->_getSabCui($sab);
	    if($self->checkError($function)) { return (); }
	    
	    if(! (defined $cui) ) {
		$self->{'errorCode'} = 2;
		$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
		$self->{'errorString'} .= "SAB ($sab) is not valid. ";
		return ();
	    }
	    
	    $sab_names{$sab}++; 
	    $sab_hash{$cui}++;
	}
    }
    if($excludesabkeys > 0) {
	my $arrRef = $db->selectcol_arrayref("select distinct SAB from MRREL where $relations");
	if($self->checkError($function)) { return (); }
	
	my $arrRefkeys = $#{$arrRef} + 1;
	my $sabcount   = 0;
	foreach my $sab (@{$arrRef}) {
	    
	    $sabcount++;
	    
	    if(exists ${$excludesab}{$sab}) { next; }
	    if($sabcount == $arrRefkeys) { $sources .="SAB=\'$sab\'";     }
	    else                         { $sources .="SAB=\'$sab\' or "; }
	    
	    my $cui = $self->_getSabCui($sab);
	    if($self->checkError($function)) { return (); }
	    
	    if(! (defined $cui) ) {
		$self->{'errorCode'} = 2;
		$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
		$self->{'errorString'} .= "SAB ($sab) is not valid. ";
		return ();
	    }
	    
	    $sab_names{$sab}++; 
	    $sab_hash{$cui}++;
	    
	}
    }
}

#  sets the relations, parentRelations and childRelations
#  variables from the information in the config file
sub _setRelations
{
    my $self           = shift;
    my $includerelkeys = shift;
    my $excluderelkeys = shift;
    my $includerel     = shift;
    my $excluderel     = shift;


    my $function = "_setRelations";
    &_debug($function);
    
    return () if(!defined $self || !ref $self);

    $self->{'traceString'} = "";

    #  check the parameters are defined
    if(!(defined $includerelkeys) || !(defined $excluderelkeys) || 
       !(defined $includerel)     || !(defined $excluderel)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    $parentRelations = "(";
    $childRelations  = "(";
    $relations       = "(";
    
    if($includerelkeys > 0) {
	my $relcount = 0;
	my @parents  = ();
	my @children = ();
	foreach my $rel (sort keys %{$includerel}) {
	    
	    $relcount++;
	    
	    if($relcount == $includerelkeys) { $relations .= "REL=\'$rel\'";     }
	    else                             { $relations .= "REL=\'$rel\' or "; }
	    
	    if   ($rel=~/(PAR|RB)/) { push @parents, $rel; }
	    elsif($rel=~/(CHD|RN)/) { push @children, $rel; }
	    else {
		push @parents, $rel;
		push @children, $rel;
	    }
	}
	
	for my $i (0..($#parents-1)) { 
	    $parentRelations .= "REL=\'$parents[$i]\' or "; 
	} $parentRelations .= "REL=\'$parents[$#parents]\'"; 
	
	for my $i (0..($#children-1)) { 
	    $childRelations .= "REL=\'$children[$i]\' or "; 
	} $childRelations .= "REL=\'$children[$#children]\'";     
    }	
    if($excluderelkeys > 0) {
	
	my $arrRef = $db->selectcol_arrayref("select distinct REL from MRREL");
	if($self->checkError($function)) { return (); }
	
	my $arrRefkeys = $#{$arrRef} + 1;
	my $relcount   = 0;
	my @parents    = ();
	my @children   = ();
	foreach my $rel (@{$arrRef}) {
	    
	    $relcount++;
	    
	    if(exists ${$excluderel}{$rel}) { next; }
	    
	    if($relcount == $arrRefkeys) { $relations .="REL=\'$rel\'";     }
	    else                         { $relations .="REL=\'$rel\' or "; }
	    
	    if($rel=~/(PAR|RB)/)    { push @parents, $rel; }
	    elsif($rel=~/(CHD|RN)/) { push @children, $rel; }	
	    else {
		push @parents, $rel;
		push @children, $rel;
	    }
	}
	
	if($#parents >= 0) {
	    for my $i (0..($#parents-1)) { 
		$parentRelations .= "REL=\'$parents[$i]\' or "; 
	    } $parentRelations .= "REL=\'$parents[$#parents]\'"; 
	}
	
	if($#children >= 0) {
	    for my $i (0..($#children-1)) { 
		$childRelations .= "REL=\'$children[$i]\' or "; 
	    } $childRelations .= "REL=\'$children[$#children]\'"; 
	}
	
    }
    
    $parentRelations .= ") ";
    $childRelations  .= ") ";
    $relations       .= ") ";
}

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

    if($umlsall) { 
	return $umlsRoot;
    }
    
    $self->{'traceString'} = "";
    
    my $arrRef = $db->selectcol_arrayref("select distinct RCUI from MRSAB where RSAB='$sab'");
    if($self->checkError($function)) { return (); }
    
    if(scalar(@{$arrRef}) < 1) {
	$self->{'errorCode'} = 2;
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "No CUI info in table MRSAB for $sab.";
	return ();
    }
    
    if(scalar(@{$arrRef}) > 1) {
	$self->{'errorCode'} = 2 if($self->{'errCode'} < 1);
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Internal error: Duplicate concept rows.";
	return ();
    }
    
    return (pop @{$arrRef});
}

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
    &_input($function, $concept); 
 
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
	if(exists $sab_names{$sab}) { 
	    &_output($function, "1");
	    return 1; 
	}
    }
    
    &_output($function, "0");
    return 0;
}

#  Takes as input a CUI and returns all of 
#  the sources in which it originated from
#  given the users view of the UMLS
sub getSab
{
    my $self = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);
 
    my $function = "getSab";
    
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
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "No version info in table MRDOC.";
	return ();
    }

    return @{$arrRef};
}

#  Returns the children of a concept - the relations that 
#  are considered children are predefined by the user.
#  The default are the RN and CHD relations
sub getChildren
{
    my $self    = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "getChildren";
        
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

    #  otherwise everything is normal so return its children
    else {
	my $arrRef = "";
	if($umlsall) {
	    $arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and ($childRelations) and CUI2!='$concept'");
	}
	else {
	    $arrRef = $db->selectcol_arrayref("select distinct CUI2 from MRREL where CUI1='$concept' and ($childRelations) and ($sources) and CUI2!='$concept'");
	}
	if($self->checkError($function)) { return (); }
	
	my @array = ();
	if(exists $childrenTaxonomy{$concept}) {
	    @array = (@{$childrenTaxonomy{$concept}}, @{$arrRef});
	}
	else {
	    @array = @{$arrRef};
	}
	return @array; 
    }
}


#  Returns the parents of a concept - the relations that 
#  are considered parents are predefined by the user.
#  The default are the PAR and RB relations
sub getParents
{
    my $self    = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "getParents";

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
        
    #  if the cui is a root return an empty array
    if(exists $roots{$concept}) {
	my @returnarray = ();
	return @returnarray; # empty array
    }
    #  if the cui is a source cui but not a root return the umls root
    elsif( (exists $sab_hash{$concept}) and (! (exists $roots{$concept})) ) {
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
	if($self->checkError($function)) { return (); }
	
	my @array = ();
	if(exists $parentTaxonomy{$concept}) {
	    @array = (@{$parentTaxonomy{$concept}}, @{$arrRef});
	}
	else {
	    @array = @{$arrRef};
	}
	return @array; 
    }
}

#  Returns the relations of a concept given a specified source
sub getRelations
{
    my $self    = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "getRelations";
    &_debug($function);
    &_input($function, $concept); 

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
    
    #  get the Relations
    my $arrRef = "";
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select distinct REL from MRREL where (CUI1='$concept' or CUI2='$concept') and CUI1!=CUI2");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select distinct REL from MRREL where (CUI1='$concept' or CUI2='$concept') and ($sources) and CUI1!=CUI2");
    }
    if($self->checkError($function)) { return (); }

    my $output = join " ", @{$arrRef};
    &_output($function, $output);
    
    return @{$arrRef};
}

#  Returns the relations and its source between two concepts
sub getRelationsBetweenCuis
{
    my $self     = shift;
    my $concept1 = shift;
    my $concept2 = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "getRelationBetweenCuis";
    &_debug($function);
    &_input($function, "$concept1 $concept2"); 

    if(!$concept1) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
    if(!$concept2) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
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
    
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    $self->{'traceString'} = "";

    my @array = ();

    if($concept1 eq $umlsRoot) { 
	push @array, "CHD (source)";
	return @array;
    }
    
    #  get the Relations
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
    

    my $output = join " ", @array;
    &_output($function, $output);

    return @array;
}


#  Depth First Search (DFS) in order to determine 
#  the maximum depth of the taxonomy and obtain 
#  all of the path information
sub _initializeDepthFirstSearch
{
    my $self    = shift;
    my $concept = shift;
    my $d       = shift;
    my $root    = shift;
    
    return () if(!defined $self || !ref $self);
    
    my $function = "_initializeDepthFirstSearch";
    &_debug($function);
    &_input($function, "$concept $d $root");  

    #  check the parameters are defined
    if(!(defined $concept) || !(defined $d) || !(defined $root)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
   
    #  check if concept is valid
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    #  check if verbose mode
    if($option_verbose) {
	open(TABLEFILE, ">$tableFile") || die "Could not open $tableFile";
    }

    #  get the children
    my @children = $self->getChildren($concept);
    if($self->checkError("getChildren")) { return (); }

    #  foreach of the children continue down the taxonomy
    foreach my $child (@children) {
	my @array = (); 
	push @array, $concept; 
	my $path  = \@array;
	$self->_depthFirstSearch($child, $d,$path,*TABLEFILE);
    }
    
    #  close the table file if in verbose mode
    if($option_verbose) {
	close TABLEFILE;
    
	#  set the table file permissions
	my $temp = chmod 0777, $tableFile;
    }
}

sub _forbiddenConcept
{
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

    return 0;
}

sub getIC
{
    my $self     = shift;
    my $concept  = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "getIC";
    &_debug($function);
    &_input($function, $concept); 

    if(! ($self->checkConceptExists($concept))) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($concept) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }
    my $prob = $propagationHash{$concept} / ($propagationTotal);
    
    my $output = ($prob > 0 and $prob < 1) ? -log($prob) : 0;
    &_output($function, $output);

    return ($prob > 0 and $prob < 1) ? -log($prob) : 0;
}

sub getFreq
{
    my $self = shift;
    my $concept = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "getFreq";
    &_debug($function);
    &_input($function, $concept); 

    if(! ($self->checkConceptExists($concept))) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($concept) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }

    my $output = $propagationHash{$concept};
    &_output($function, $output);

    return $propagationHash{$concept};
}

sub getPropagationCuis
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "getPropagationCuis";
    &_debug($function);
    
    #  set the database
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    #  get the sabs in the config file
    my @sabs = ();
    if($umlsall) {
	my $s = $db->selectcol_arrayref("select distinct SAB from MRREL");
	@sabs = @{$s};
    }
    else {
	foreach my $sab (sort keys %sab_names) { push @sabs, $sab; }
    }

    my %hash = ();    
    #  for each of the sabs in the configuratino file
    foreach my $sab (@sabs) {
	
	#  get the cuis for that sab
	my $cuis = $self->_getCuis($sab);
	
	#  add the cuis to the propagation hash
	foreach my $cui (@{$cuis}) { $hash{$cui} = 0 };
    }
    
    #  add upper level taxonomy
    foreach my $cui (sort keys %parentTaxonomy)   { $hash{$cui} = 0; }
    foreach my $cui (sort keys %childrenTaxonomy) { $hash{$cui} = 0; }
    
    return \%hash;
}

sub _initializePropagationHash
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_initializePropagationHash";
    &_debug($function);
    
    #  set the database
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    #  select all the CUIs from MRREL for the defined $source
    my $allCui1 = ""; my $allCui2 = "";
    if($umlsall) {
	if($debug) { print STDERR "select CUI1 from MRREL where ($relations)\n"; }
       	$allCui1 = $db->selectcol_arrayref("select CUI1 from MRREL where ($relations)");
	if($self->checkError($function)) { return undef; }
	if($debug) { print STDERR "select CUI2 from MRREL where ($relations)\n"; }
	$allCui2 = $db->selectcol_arrayref("select CUI2 from MRREL where ($relations)");
	if($self->checkError($function)) { return undef; }
    }
    else {
	if($debug) { print STDERR "select CUI1 from MRREL where ($relations) and ($sources)\n"; }
	$allCui1 = $db->selectcol_arrayref("select CUI1 from MRREL where ($relations) and ($sources)");
	if($self->checkError($function)) { return undef; }
	if($debug) { print STDERR "select CUI2 from MRREL where ($relations) and ($sources)\n"; }
	$allCui2 = $db->selectcol_arrayref("select CUI2 from MRREL where ($relations) and ($sources)");
	if($self->checkError($function)) { return undef; }
    }

    #  clear out the hash just in case
    %propagationHash = ();

    my $smooth = 1;
    print STDERR "SMOOTH: $smooth\n";

    #  add the cuis to the propagation hash
    foreach my $cui (@{$allCui1}) { 
	if($option3) { $propagationHash{$cui} = ""; }
	else         { $propagationHash{$cui} = 0;  }
	$propagationFreq{$cui} = $smooth;
    }
    foreach my $cui (@{$allCui2}) { 
	if($option3) { $propagationHash{$cui} = ""; }
	else         { $propagationHash{$cui} = 0;  }
	$propagationFreq{$cui} = $smooth;
    }
    
    #  add upper level taxonomy
    foreach my $cui (sort keys %parentTaxonomy)   { 
	if($option3) { $propagationHash{$cui} = ""; }
	else         { $propagationHash{$cui} = 0;  }
	$propagationFreq{$cui} = $smooth;
    }
    foreach my $cui (sort keys %childrenTaxonomy) { 
	if($option3) { $propagationHash{$cui} = ""; }
	else         { $propagationHash{$cui} = 0;  }
	$propagationFreq{$cui} = $smooth;
    }
}

sub _loadPropagationFreq
{
    my $self = shift;

   return undef if(!defined $self || !ref $self);
    
    my $function = "_loadPropagationFreq";
    &_debug($function);
    
    #  collect the counts for the required cuis
    open(FILE, $propagationFile) || die "Could not open propagation file: $propagationFile\n";
    my $N = 0;
    while(<FILE>) {
	chomp;
	if($_=~/^#/)    { next; }
	if($_=~/^\s*$/) { next; }
	
	my ($freq, $cui, $str) = split/\|/;

	#  negative numbers are used as codes - they don't mean anything
	if($freq < 0) { next; }
    
        $N += $freq;
        #$N++;
	
	if(exists $propagationFreq{$cui}) {
	    $propagationFreq{$cui} += $freq;
	}
    }
    
    my $pkeys = keys %propagationFreq;
    $N += $pkeys;

    print STDERR "PROPAGATION TOTAL : $N\n";

    $propagationTotal = $N;


}

sub _loadPropagationTables
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_loadPropagationTables";
    &_debug($function);
    
    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

    #  create the table
    $sdb->do("CREATE TABLE IF NOT EXISTS $propTable (CUI char(8), FREQ double precision(17,4))");
    if($self->checkError($function)) { return (); }
    #  load the table
    my $N = 0;
    foreach my $cui (sort keys %propagationHash) {
	my $freq = $propagationHash{$cui};
	$sdb->do("INSERT INTO $propTable (CUI, FREQ) VALUES ('$cui', '$freq')");
	if($self->checkError($function)) { return (); }   
	$N += $freq;
    }
    
    $sdb->do("INSERT INTO $propTable (CUI, FREQ) VALUES ('PT', '$propagationTotal')");
    if($self->checkError($function)) { return (); }   
    
    #  set N (the total propagation count)
    #$propagationTotal = $N;
    #$propagationTotal = $self->getFreq($umlsRoot);
    
    #  add them to the index table
    $sdb->do("INSERT INTO tableindex (TABLENAME, HEX) VALUES ('$propTableHuman', '$propTable')");
    if($self->checkError($function)) { return (); }   

}

sub _setPropagationHash
{
    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_setPropagationHash";
    &_debug($function);

    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    #  set the parent taxonomy
    my $sql = qq{ SELECT CUI, FREQ FROM $propTable};
    my $sth = $sdb->prepare( $sql );
    $sth->execute();
    my($cui, $freq);
    $sth->bind_columns( undef, \$cui, \$freq );
    my $N = 0;
    while( $sth->fetch() ) {
	if($cui=~/PT/) {
	    $propagationTotal = $freq;
	}
	else {
	    $propagationHash{$cui} = $freq;
	    $N += $freq;
	}
    } $sth->finish();
    
    #  set N (the total propagation count)
    #$propagationTotal = $N;
    #$propagationTotal = $self->getFreq($umlsRoot);
}

sub getPropagationCount
{
    my $self = shift;
    my $concept = shift;
    
    my $function = "getPropagationCount";
    &_debug($function);

    $self->_propogateCounts();

    #  check the concept is there
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
 
    #  check that the concept is valid
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    if(exists $propagationHash{$concept}) {
	return $propagationHash{$concept};
    }
    else {
	return -1;
    }

}

sub _propogateCounts
{

    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    
    if($option_propagation) {

	my $function = "_propogateCounts";
	&_debug($function);

	#  check if the parent and child tables exist and 
	#  if they do just return otherwise create them
	my $pkey = keys (%propagationHash);

        #  if propagation hash
	if($pkey > 0) { return; }
	
	elsif($self->_checkTableExists($propTable)) {
	    #  load the propagation hash from the database
	    $self->_setPropagationHash();

	    #  set smoothing variables
	    #$self->_setSmoothingVariables();
	    
	    #  set propogation TUI hash
	    #$self->_setPropagationTuiHash();

	}
	else {
	    	    	    
	    #  initialize the propagation hash
	    $self->_initializePropagationHash();
	    
	    #  load the propagation frequency hash
	    $self->_loadPropagationFreq();
	    
	    if($option3) {
		#  propogate the counts
		&_debug("_propagation3");
		my @array = ();
		$self->_propagation3($umlsRoot, \@array);
	    
		#  tally up the propagation counts
		$self->_tallyCounts();
	    }
	    else {
		#  propogate the counts
		&_debug("_propagation");
		my @array = ();
		$self->_propagation($umlsRoot, \@array);
	    }
	    
	    #  load the propagation tables
	    $self->_loadPropagationTables();
	    
	    #  set smoothing variables
	    #$self->_setSmoothingVariables();
	    
	    #  set the propogation TUI hash
	    #$self->_setPropagationTuiHash();
	}
    }
}

sub _setPropagationTuiHash
{
    my $self = shift;

    my $function = "_setPropagationTuiHash";
    &_debug($function);
    
    foreach my $cui (sort keys %propagationHash) {
	my @sts = $self->getSt($cui);
	foreach my $st (@sts) {
	    $propagationTuiHash{$st}++;
	    $propagationTuiTotal++;
	}
    }
}

sub _setSmoothingVariables 
{
    my $self = shift;

    my $function = "_setSmoothingVariables";
    &_debug($function);

    #  set the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }

    #  set propagation tokens
    $propagation_tokens = $propagationHash{$umlsRoot};

    #  set observed types
    my $arrRef1 = $sdb->selectcol_arrayref("select count(*) from $propTable where FREQ = 0");
    if($self->checkError($function)) { return (); }
    $unobserved_types = shift @{$arrRef1};

    #  set unobserved types
    my $arrRef2 = $sdb->selectcol_arrayref("select count(*) from $propTable;");
    if($self->checkError($function)) { return (); }
    my $total_types = shift @{$arrRef2};
    $observed_types = $total_types - $unobserved_types;

}

sub _propagation
{
    my $self    = shift;
    my $concept = shift;
    my $array   = shift;

    my $function = "_propagation";
    
    #  check the concept is there
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
 
    #  check that the concept is valid
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
      
    #  set the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    #  set up the new path
    my @intermediate = @{$array};
    push @intermediate, $concept;
    my $series = join " ", @intermediate;

    #  we have already been down this route if the propagation count
    #  for this concept has already been tallied so just return the 
    #  count
    if($propagationHash{$concept} > 0) { return $propagationHash{$concept}; }

    #  get the frequency of the concept
    my $count = $propagationFreq{$concept};

    #  if defined $option2 we are going to use the 1/p counts
    if($option2) {
	#  get the parents of the concept
	my @parents = $self->getParents($concept);
	if($self->checkError("getParents")) { return (); }
	if($#parents >= 0) {
	    $count = $count / ($#parents+1);
	}
    }
    #  get all the children
    my @children = $self->getChildren($concept);
    if($self->checkError("getChildren")) { return (); }

    my $havechildflag = 0;
    #  search through the children
    foreach my $child (@children) {
	
	#  check that the concept is not one of the forbidden concepts
	if($self->_forbiddenConcept($concept)) { next; }
	
	#  check if child cui has already in the path
	my $flag = 0;
	foreach my $cui (@intermediate) {
	    if($cui eq $child) { $flag = 1; }
	}
	
	#  if it isn't continue on with the depth first search
	if($flag == 0) {  
	    $count += $self->_propagation($child, \@intermediate);    
	    $havechildflag++;
	}
    }
    
    #if($havechildflag == 0) { $count++; }
    
    if($option4) {
	#  get the parents of the concept
	my @parents = $self->getParents($concept);
	if($self->checkError("getParents")) { return (); }
	if($#parents >= 0) {
	    $count = $count / ($#parents+1);
	}
    }
        
    #  update the propagation count
    $propagationHash{$concept} = $count;

    open(OUT, ">>out") || die "OUT\n";
    print OUT "$concept $count $havechildflag $#children\n";
    close OUT;
    #  return the count
    return $count;
}

sub _tallyCounts
{

    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_tallyCounts";
    &_debug($function);
    
    foreach my $cui (sort keys %propagationHash) {
	my $set    = $propagationHash{$cui};
	my $pcount = $propagationFreq{$cui};

	my %hash = ();
	while($set=~/(C[0-9][0-9][0-9][0-9][0-9][0-9][0-9])/g) {
	    my $c = $1;
	    if(! (exists $hash{$c}) ) {
		$pcount += $propagationFreq{$c};
		$hash{$c}++;
	    }
	}
	
	$propagationHash{$cui} = $pcount;
    }
}

sub _propagation3
{
    my $self    = shift;
    my $concept = shift;
    my $array   = shift;

    my $function = "_propagation";
    
    #  check the concept is there
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
 
    #  check that the concept is valid
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
      
    #  set the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    #  set up the new path
    my @intermediate = @{$array};
    push @intermediate, $concept;
    my $series = join " ", @intermediate;

    #  initialize the set
    my $set = $propagationHash{$concept};

    #  if the propagation hash already contains a list of CUIs it
    #  is from its decendants so it has been here before so all we 
    #  have to do is return the list of ancestors with it added
    if($set ne "") { 
	$set .= " $concept";
	return $set; 
    }

    #  get all the children
    my @children = $self->getChildren($concept);
    if($self->checkError("getChildren")) { return (); }
    
    #  search through the children   
    foreach my $child (@children) {
	
	#  check that the concept is not one of the forbidden concepts
	if($self->_forbiddenConcept($concept)) { next; }
	
	#  check if child cui has already in the path
	my $flag = 0;
	foreach my $cui (@intermediate) {
	    if($cui eq $child) { $flag = 1; }
	}
	
	#  if it isn't continue on with the depth first search
	if($flag == 0) {  
	    $set .= " ";
	    $set .= $self->_propagation3($child, \@intermediate);    
	}
    }
    
    #  remove duplicates from the set
    my $rset = _breduce($set);

    #  store the set in the propagation hash
    $propagationHash{$concept} = $rset;
    
    #  add the concept to the set
    $rset .= " $concept";
    
    #  return the set
    return $rset;
}

sub _breduce {
    
   
    local($_)= @_;
    my (@words)= split;
    my (%newwords);
    for (@words) { $newwords{$_}=1 }
    join ' ', keys(%newwords);
}

sub _cuiToRoot
{
    my $self    = shift;
    my $concept = shift;

    my $function = "_cuiToRoot";
    &_debug($function);
    &_input($function, $concept);

    #  set the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    #  set the stack
    my @stack = ();
    push @stack, $concept;

    #  set the count
    my %visited = ();

    #  set the paths
    my @paths = ();
    my @empty = ();
    push @paths, \@empty;
    
    while($#stack >= 0) {
	
	my $concept = $stack[$#stack];
	my $path    = $paths[$#paths];

	#  set up the new path
	my @intermediate = @{$path};
	my $series = join " ", @intermediate;
	push @intermediate, $concept;

	#  check that the concept is not one of the forbidden concepts
	if($self->_forbiddenConcept($concept)) { 
	    pop @stack; pop @paths;
	    next;
	}

	#  check if concept has been visited already
	my $found = 0;
	if(exists $visited{$concept}) { 
	    foreach my $s (sort keys %{$visited{$concept}}) {
		if($series eq $s) {
		    $found = 1;
		}
	    }
	}
	
	if($found == 1) {
	    pop @stack; pop @paths;
	    next; 
	}
	else { $visited{$concept}{$series}++; }
	
	
	#  if the concept is the umls root - we are done
	if($concept eq $umlsRoot) { 
	    #  this is a complete path to the root so push it on the paths 
	    my @reversed = reverse(@intermediate);
	    my $rseries  = join " ", @reversed;
	    push @path_storage, $rseries;
	}
	
	#  get all the parents
	my @parents = $self->getParents($concept);
	if($self->checkError("getParents")) { return (); }
	
	#  if there are no children we are finished with this concept
	if($#parents < 0) {
	    pop @stack; pop @paths;
	    next;
	}

	#  search through the children
	my $stackflag = 0;
	foreach my $parent (@parents) {
	
	    #  check if child cui has already in the path
	    my $flag = 0;
	    foreach my $cui (@intermediate) {
		if($cui eq $parent) { $flag = 1; }
	    }

	    #  if it isn't continue on with the depth first search
	    if($flag == 0) {
		push @stack, $parent;
		push @paths, \@intermediate;
		$stackflag++;
	    }
	}
	
	#  check to make certain there were actually children
	if($stackflag == 0) {
	    pop @stack; pop @paths;
	}
    }
}

#  Depth First Search (DFS) 
sub _depthFirstSearch
{
    my $self    = shift;
    my $concept = shift;
    my $d       = shift;
    my $array   = shift;
    local(*F)   = shift;
        
    my $function = "_depthFirstSearch";
    
    #  check concept was obtained
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }

    #  check valide concept
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
     
    #  set the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }
    
    #  increment the depth
    $d++;
    
    #  if concept is one of the following just return
    #C1274012|Ambiguous concept (inactive concept)
    if($concept=~/C1274012/) { return; }
    #C1274013|Duplicate concept (inactive concept)
    if($concept=~/C1274013/) { return; }
    #C1276325|Reason not stated concept (inactive concept)
    if($concept=~/C1276325/) { return; }
    #C1274014|Outdated concept (inactive concept)
    if($concept=~/C1274014/) { return; }
    #C1274015|Erroneous concept (inactive concept)
    if($concept=~/C1274015/) { return; }
    #C1274021|Moved elsewhere (inactive concept)
    if($concept=~/C1274021/) { return; }

    #  set up the new path
    my @path = @{$array};
    push @path, $concept;
    my $series = join " ", @path;
    
    #  load path information into the table
    if($option_cuilist) {
	if(exists $CuiList{$concept}) {
	    my $arrRef = $sdb->do("INSERT INTO $tableName (CUI, DEPTH, PATH) VALUES(\'$concept\', '$d', \'$series\')");
	    if($self->checkError($function)) { return (); }
	}
    } 
    else {
	my $arrRef = $sdb->do("INSERT INTO $tableName (CUI, DEPTH, PATH) VALUES(\'$concept\', '$d', \'$series\')");
	if($self->checkError($function)) { return (); }
    }
    
    #  print information into the file if verbose option is set
    if($option_verbose) { 
	if($option_cuilist) {
	    if(exists $CuiList{$concept}) {
		print F "$concept\t$d\t$series\n"; 
	    }
	} else { print F "$concept\t$d\t$series\n"; }
    }
    
    #  get all the children
    my @children = $self->getChildren($concept);
    if($self->checkError("getChildren")) { return (); }
    
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
	    if($self->checkError("_depthFirstSearch")) { return (); }
	}
	#  otherwise mark it and stop that path
	#else { 
	    #$self->_storeCycle($child, $concept); 
	    #if($self->checkError("_storeCycle")) { return (); }
	#}
    }
}

#  function returns the minimum depth of a concept
sub findMinimumDepth
{
    my $self = shift;
    my $cui  = shift;

    return () if(!defined $self || !ref $self);

    my $function = "findMinimumDepth";
    &_debug($function);
    &_input($function, $cui);  

    #  check the cui is there
    if(!$cui) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return ();
    }
    
    #  check that it is valid
    if($self->validCui($cui)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($cui).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    #  check that the cui exists
    if(! ($self->checkConceptExists($cui))) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($cui) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }


    #  get the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    #  if it is in the parent taxonomy 
    if(exists $parentTaxonomy{$cui}) { return 1; }
    

    my $min = 9999;
    
    if($option_realtime) {
	#  initialize the path storage
	@path_storage = ();
	my @array     = (); 
	
	$self->_cuiToRoot($cui, \@array);
	
	# get the minimum depth
	foreach my $p (@path_storage) {
	    @array = split/\s+/, $p;
	    if( ($#array+1) < $min) { $min = $#array + 1; }
	}
    }
    else {

	#  set the depth
	$self->_setDepth();
	if($self->checkError("_setDepth")) { return (); }
	
	#  otherwise look for its minimum depth
	my $d = $sdb->selectcol_arrayref("select min(DEPTH) from $tableName where CUI=\'$cui\'");
	if($self->checkError($function)) { return (); }
	
	#  return the minimum depth
	$min = shift @{$d}; $min++;
    }
    
    return $min;
}

#  function returns maximum depth of a concept
sub findMaximumDepth
{
    my $self = shift;
    my $cui  = shift;

    my $function = "findMaximumDepth";
    &_debug($function);
    &_input($function, $cui);
    
    return () if(!defined $self || !ref $self);
    
    #  check the cui is there
    if(!$cui) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }
    
    #  check that it is valid
    if($self->validCui($cui)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($cui).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 

    if(! ($self->checkConceptExists($cui))) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($cui) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }
        
    #  get the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    

    #  initialize max
    my $max = 0;

    #  if realtime option is set
    if($option_realtime) {
	#  initialize the path storage
	@path_storage = ();
	my @array     = (); 
	
	#  get all the paths from the cui to the root
	$self->_cuiToRoot($cui, \@array);
	
	# get the maximum depth
	foreach my $p (@path_storage) {
	    @array = split/\s+/, $p;
	    if( ($#array+1) > $max) { $max = $#array + 1; }
	}
    }
    #  otherwise
    else {
	#  set the depth
	$self->_setDepth();
	if($self->checkError("_setDepth")) { return (); }
		
	my $d = $sdb->selectcol_arrayref("select max(DEPTH) from $tableName where CUI=\'$cui\'");
	if($self->checkError($function)) { return (); }
	$max = shift @{$d}; $max++;
    }

    #  print the oputput if debug option is set
    &_output($function, $max);
    
    #  return the maximum depth
    return $max;    
}

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

#  find the shortest path between two concepts
sub findShortestPath
{
    my $self     = shift;
    my $concept1 = shift;
    my $concept2 = shift;

    my $function = "findShortestPath";
    &_debug($function);
    &_input($function, "$concept1 $concept2");
    
    return () if(!defined $self || !ref $self);
    
    $self->{'traceString'} = "" if($self->{'trace'});
      
    # undefined input cannot go unpunished.
    if(!$concept1 || !$concept2) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function) - ";
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
    if(! ($self->checkConceptExists($concept1))) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($concept1) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }
    if(! ($self->checkConceptExists($concept2))) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept ($concept2) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }

    #  find the shortest path(s) and lcs - there may be more than one
    my $hash = $self->_findShortestPath($concept1, $concept2);
    
    my @paths = (); my $output = "";
    foreach my $path (sort keys %{$hash}) {
	if($path=~/C[0-9]+/) {
	    push @paths, $path;
	    $output .= "$path\n";
	}
    } chop $output;
    
    &_output($function, $output);

    return @paths;
}

#  this function sets the CVF row to NULL 
sub _resetCVF 
{
    my $self = shift;

    return () if(!defined $self || !ref $self);

    my $function = "_resetCVF";
    &_debug($function);
    

    #  check that the database exists
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    #  reset the cycle information back to null
    $db->do("update MRREL set CVF=NULL");
    if($self->checkError($function)) { return (); }
    
    $markFlag = 0;
}

#  this function marks the CVF row with 1 if CUI1=CUI2
sub _markCVF {
    my $self = shift;

    return () if(!defined $self || !ref $self);

    my $function = "_markCVF";
    &_debug($function);
    

    #  check that the database exists
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return ();
    }    
    
    $db->do("update MRREL  set CVF=1 where CUI1=CUI2");
    if($self->checkError($function)) { return (); }

    $markFlag = 1;
}

#  this function returns the least common subsummer between two concepts
sub findLeastCommonSubsumer
{   

    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;
    
    return () if(!defined $self || !ref $self);

    my $function = "findLeastCommonSubsumer";
    &_debug($function);
    &_input($function, "$concept1 $concept2"); 
    
    $self->{'traceString'} = "" if($self->{'trace'});

    # Undefined input cannot go unpunished.
    if(!$concept1 || !$concept2) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }
   
    #  check that concept1 and concept2 are valid
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
    if(! ($self->checkConceptExists($concept1))) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept 1 ($concept1) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }
    if(!($self->checkConceptExists($concept2))) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Concept 2 ($concept2) doesn't exist.";
	$self->{'errorCode'} = 2;
	return undef;
    }
    
    #  find the shortest path(s) and lcs - there may be more than one
    my $hash = $self->_findShortestPath($concept1, $concept2);

    my @lcses = ();
    foreach my $path (sort keys %{$hash}) {
	if(${$hash}{$path}=~/C[0-9]+/) {
	    push @lcses, ${$hash}{$path};
	}
    }
    
    #  print the output parameters if debug is on
    my $output = join " ", @lcses;
    &_output($function, $output);
    
    return @lcses;
}

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
    &_debug($function);
    &_input($function, "$concept1 $concept2");

    $self->{'traceString'} = "" if($self->{'trace'});
    
    #  get the database
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }

    # Get the paths to root for each ofhte concepts
    my $lTrees = $self->pathsToRoot($concept1);
    if($self->checkError("pathsToRoot")) { return (); }

    my $rTrees = $self->pathsToRoot($concept2);
    if($self->checkError("pathsToRoot")) { return (); }
   
    
    # set the trace
    if($self->{'trace'}) {
	foreach my $lTree (@{$lTrees}) {
	    $self->{'traceString'} .= "HyperTree: ".(join("  ", @{$lTree}))."\n\n";
	}
	foreach my $rTree (@{$rTrees}) {
	    $self->{'traceString'} .= "HyperTree: ".(join("  ", @{$rTree}))."\n\n";
	}
    }

    # Find the shortest path in these trees.
    my %lcsLengths = ();
    my %lcsPaths   = ();
    my $lcs        = "";
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
	# set trace
	if($self->{'trace'}) {
	    $self->{'traceString'} .= "No intersecting paths found.\n";
	}
	return 0;
    }

    #  get the lcses and their associated path(s)
    my %rhash    = ();
    my $prev_len = -1;
    my $output   = "";
    foreach my $lcs (sort {$lcsLengths{$a} <=> $lcsLengths{$b}} keys(%lcsLengths)) {
	if( ($prev_len == -1) or ($prev_len == $lcsLengths{$lcs}) ) {
	    my $path = join " ", @{$lcsPaths{$lcs}};
	    $rhash{$path} = $lcs;
	    $output .= "$lcs : $path\n";
	}
	else { last; }
	$prev_len = $lcsLengths{$lcs};
    } chop $output;
    
    #  print the output if debug is on
    &_output($function, $output);

    #  return a reference to the hash containing the lcses and their path(s)
    return \%rhash;
}

#  Method to check to see if a concept exists
sub checkConceptExists {

    my $self    = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);
    
    my $function = "checkConceptExists";
    &_debug($function);
    &_input($function, $concept);

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
    
    #  check to see if it is the root
    if($concept eq $umlsRoot) { &_output($function, "1"); return 1; }

    #  check to see if it exists in the upper level taxonomy
    if(exists $parentTaxonomy{$concept})   {  &_output($function, "1"); return 1; }
    if(exists $childrenTaxonomy{$concept}) {  &_output($function, "1"); return 1; }
    
    #  get the count from MRREL
    my $arrRef = "";
    if($umlsall) {
	$arrRef = $db->selectcol_arrayref("select count(*) from MRREL where (CUI1='$concept' or CUI2='$concept') and ($relations)");
    }
    else {
	$arrRef = $db->selectcol_arrayref("select count(*) from MRREL where (CUI1='$concept' or CUI2='$concept') and ($sources) and ($relations)");
    }
    if($self->checkError($function)) { return (); }

    my $count = shift @{$arrRef};

    my $output = ($count == 0) ? 0 : 1; 
    &_output($function, $output); 
    
    return ($count == 0) ? 0 : 1; 
}

# Subroutine to get the Least Common Subsumer of two paths to the root of a taxonomy
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

# Subroutine to get the definition of a given CUI
sub getSt {
    my $self = shift;
    my $cui   = shift;

    my $function = "getSt";
    &_debug($function);
    
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }

    if(!$cui) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }

    my $arrRef = $db->selectcol_arrayref("select TUI from MRSTY where CUI=\'$cui\'");
    if($self->checkError($function)) { return (); }
    
    return (shift @{$arrRef});
}


# Subroutine to get the name of a semantic type given its abbreviation
sub getStString
{
    my $self = shift;
    my $st   = shift;

    my $function = "getStString";
    &_debug($function);
    &_input($function, $st); 

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

    my $arrRef = $db->selectcol_arrayref("select STY_RL from SRDEF where ABR=\'$st\'");
    if($self->checkError($function)) { return (); }
    
    return (shift @{$arrRef});
} 


# Subroutine to get the name of a semantic type given its TUI (UI)
sub getStAbr
{
    my $self = shift;
    my $tui   = shift;

    my $function = "getStString";
    &_debug($function);
    &_input($function, $tui); 

    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }

    if(!$tui) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }

    my $arrRef = $db->selectcol_arrayref("select ABR from SRDEF where UI=\'$tui\'");
    if($self->checkError($function)) { return (); }
    
    return (shift @{$arrRef});
} 


# Subroutine to get the definition of a given TUI
sub getStDef
{
    my $self = shift;
    my $st   = shift;

    my $function = "getStDef";
    &_debug($function);
    &_input($function, $st); 

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

#  Subroutine to get a CUIs definition
sub getCuiDef
{
    
    my $self    = shift;
    my $concept = shift;

    my $function = "getCuiDef";
    &_debug($function);
    &_input($function, $concept); 

    return () if(!defined $self || !ref $self);
    
    $self->{'traceString'} = "";
   
    #  check if concept was obtained
    if(!$concept) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Undefined input values.";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    }
    
    #  check if valid concept
    if($self->validCui($concept)) {
	$self->{'errorString'} .= "\nWarning (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "Incorrect input value ($concept).";
	$self->{'errorCode'} = 2 if($self->{'errorCode'} < 1);
	return undef;
    } 
   
    #  get database
    my $db = $self->{'db'};
    if(!$db) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }

    #  get the definitions
    my $arrRef = $db->selectcol_arrayref("select DEF from MRDEF where CUI=\'$concept\'");

   
	
    if($self->checkError($function)) { return (); }
    
    return (@{$arrRef});
}

#  Subroutine to check if CUI is valid
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

#  check error function
sub checkError
{
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

   
    if($code == 2) {
	return 1;
    }
    return 0;
}

#  returns the table names in both human readable and hex form
sub returnTableNames
{
    my $self = shift;
    
    my %hash = ();
    $hash{$parentTableHuman} = $parentTable;
    $hash{$childTableHuman}  = $childTable;
    $hash{$tableNameHuman}   = $tableName;

    return \%hash;
}

#  removes the configuration tables
sub dropConfigTable
{
    
    my $self    = shift;

    return () if(!defined $self || !ref $self);

    my $function = "dropConfigTable";
    &_debug($function);

    my $sdb = $self->_connectIndexDB();
        
    if(!$sdb) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
	$self->{'errorString'} .= "A db is required.";
	$self->{'errorCode'} = 2;
	return undef;
    }


    #  show all of the tables
    my $sth = $sdb->prepare("show tables");
    $sth->execute();
    if($sth->err()) {
	$self->{'errorString'} .= "\nError (UMLS::Interface->$function()) - ";
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
	if($self->checkError($function)) { return (); }
    }
    if(exists $tables{$childTable}) {	
	$sdb->do("drop table $childTable");
	if($self->checkError($function)) { return (); }
    }
    if(exists $tables{$tableName}) {	
	$sdb->do("drop table $tableName");
	if($self->checkError($function)) { return (); }
    }
    if(exists $tables{$propTable}) {
	$sdb->do("drop table $propTable");
	if($self->checkError($function)) { return (); }
    }
    if(exists $tables{"tableindex"}) {	

	$sdb->do("delete from tableindex where HEX='$parentTable'");
	if($self->checkError($function)) { return (); }
	
	$sdb->do("delete from tableindex where HEX='$childTable'");
	if($self->checkError($function)) { return (); }
	
	$sdb->do("delete from tableindex where HEX='$tableName'");
	if($self->checkError($function)) { return (); }
	
	$sdb->do("delete from tableindex where HEX='$propTable'");
	if($self->checkError($function)) { return (); }
    }
}

#  removes the configuration files
sub removeConfigFiles
{
    my $self = shift;
    return () if(!defined $self || !ref $self);
    
    my $function = "removeConfigFiles";
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
    if(-e $cycleFile) {
	system "rm $cycleFile";
    }

}
    


#  function to create a timestamp
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
sub _printTime {
    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);

    $year += 1900;
    $mon++;
    
    my $d = sprintf("%4d%2.2d%2.2d",$year,$mon,$mday);
    my $t = sprintf("%2.2d%2.2d%2.2d",$hour,$min,$sec);
    
    print STDERR "$t\n";

}


1;

__END__

=head1 NAME

UMLS::Interface - Perl interface to the Unified Medical Language System (UMLS)

=head1 SYNOPSIS

 use UMLS::Interface;

 $umls = UMLS::Interface->new(); 

 die "Unable to create UMLS::Interface object.\n" if(!$umls);

 ($errCode, $errString) = $umls->getError();

 die "$errString\n" if($errCode);

 my $root = $umls->root();

 my $term1    = "blood";

 my @tList1   = $umls->getConceptList($term1);

 my $cui1     = pop @tList1;

 if($umls->checkConceptExists($cui1) == 0) { 
    print "This concept ($cui1) doesn't exist\n";
 } else { print "This concept ($cui1) does exist\n"; }

 my $term2    = "cell";

 my @tList2   = $umls->getConceptList($term2);

 my $cui2     = pop @tList2;

 my $exists1  = $umls->checkConceptExists($cui1);

 my $exists2  = $umls->checkConceptExists($cui2);

 if($exists1) { print "$term1($cui1) exists in your UMLS view.\n"; }

 else         { print "$term1($cui1) does not exist in your UMLS view.\n"; }
 
 if($exists2) { print "$term2($cui2) exists in your UMLS view.\n"; }

 else         { print "$term2($cui2) does not exist in your UMLS view.\n"; }

 print "\n";

 my @cList1   = $umls->getTermList($cui1);

 my @cList2   = $umls->getTermList($cui2);

 print "The terms associated with $term1 ($cui1):\n";

 foreach my $c1 (@cList1) {

    print " => $c1\n";

 } print "\n";

 print "The terms associated with $term2 ($cui2):\n";

 foreach my $c2 (@cList2) {

    print " => $c2\n";

 } print "\n";

 my $lcs = $umls->findLeastCommonSubsumer($cui1, $cui2);

 print "The least common subsumer between $term1 ($cui1) and \n";

 print "$term2 ($cui2) is $lcs\n\n";

 my @shortestpath = $umls->findShortestPath($cui1, $cui2);

 print "The shortest path between $term1 ($cui1) and $term2 ($cui2):\n";

 print "  => @shortestpath\n\n";

 my $pathstoroot   = $umls->pathsToRoot($cui1);

 print "The paths from $term1 ($cui1) and the root:\n";

 foreach  $path (@{$pathstoroot}) {

    print "  => $path\n";

 } print "\n";

 my $mindepth = $umls->findMinimumDepth($cui1);

 my $maxdepth = $umls->findMaximumDepth($cui1);

 print "The minimum depth of $term1 ($cui1) is $mindepth\n";

 print "The maximum depth of $term1 ($cui1) is $maxdepth\n\n";

 my @children = $umls->getChildren($cui2); 

 print "The child(ren) of $term2 ($cui2) are: @children\n\n";

 my @parents = $umls->getParents($cui2);

 print "The parent(s) of $term2 ($cui2) are: @parents\n\n";

 my @relations = $umls->getRelations($cui2);

 print "The relation(s) of $term2 ($cui2) are: @relations\n\n";

 my @rel_sab = $umls->getRelationsBetweenCuis($cui1, "C1524024");

 print "The relation (source) between $cui1 and $cui2 :\n";

 print "@rel_sab\n";
   
 my @siblings = $umls->getRelated($cui2, "SIB");

 print "The sibling(s) of $term2 ($cui2) are: @siblings\n\n";

 my @definitions = $umls->getCuiDef($cui1);

 print "The definition(s) of $term1 ($cui1) are:\n";

 foreach $def (@definitions) {

    print "  => $def\n"; $i++;

 } print "\n";

 my @sabs = $umls->getSab($cui1);

 print "The sources containing $term1 ($cui1) are: @sabs\n";

 print "The semantic type(s) of $term1 ($cui1) and the semantic\n";

 print "definition are:\n";

 my @sts = $umls->getSt($cui1);

 foreach my $st (@sts) {

    my $abr = $umls->getStAbr($st);

    my $string = $umls->getStString($abr);
    
    my $def    = $umls->getStDef($abr);

    print "  => $string ($abr) : $def\n";
    
 } print "\n";

 $umls->removeConfigFiles();

 $umls->dropConfigTable();


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

=head2 DATABASE SETUP

The interface assumes that the UMLS is present as a mysql database. 
The name of the database can be passed as configuration options at 
initialization. However, if the names of the databases are not 
provided at initialization, then default value is used -- the 
database for the UMLS is called 'umls'. 

The UMLS database must contain six tables: 
	1. MRREL
	2. MRCONSO
	3. MRSAB
	4. MRDOC
        5. MRDEF
        6. MRSTY
        7. SRDEF
        
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
  'umls'         -> Default value 'umls'. This option specifies the name
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

You can also pass other parameters which controls the functionality 
of the Interface.pm module. 

    $umls = UMLS::Interface->new({"forcerun" => "1",
				  "realtime" => "1",
				  "cuilist"  => "file",  
				  "verbose"  => "1"});

  'forcerun'     -> This parameter will bypass any command prompts such 
                    as asking if you would like to continue with the index 
                    creation. 

  'realtime'     -> This parameter will not create a database of path 
                    information (what we refer to as the index) but obtain
                    the path information about a concept on the fly
  
  'cuilist'      -> This parameter contains a file containing a list 
                    of CUIs in which the path information should be 
                    store for - if the CUI isn't on the list the path 
                    information for that CUI will not be stored

  'verbose'      -> This parameter will print out the table information 
                    to a config file in the UMLSINTERFACECONFIG directory


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

If you run the an example program in the utils/ directory, an 
example of the default configuration file will be printed out 
in the configuration directory (the configuration directory 
can be specified during the first run - go run one and you 
will see what I mean).

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
