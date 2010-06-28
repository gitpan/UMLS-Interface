# UMLS::Interface::PathFinder
# (Last Updated $Id: PathFinder.pm,v 1.15 2010/06/25 17:53:04 btmcinnes Exp $)
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

package UMLS::Interface::PathFinder;

use Fcntl;
use strict;
use warnings;
use bytes;

use UMLS::Interface::CuiFinder;
use UMLS::Interface::ErrorHandler;

my $pkg = "UMLS::Interface::PathFinder";

my $debug = 0;

my $max_depth = 0;

my $root = "";

my $option_verbose     = 0;
my $option_forcerun    = 0;
my $option_realtime    = 0;
my $option_t           = 0;
my $option_debugpath   = 0;
my $option_cuilist     = 0;
my $option_undirected  = 0;

my $errorhandler = "";
my $cuifinder    = "";

local(*DEBUG_FILE);

# UMLS-specific stuff ends ----------

# -------------------- Class methods start here --------------------

#  method to create a new UMLS::Interface::PathFinder object
sub new {

    my $self = {};
    my $className = shift;
    my $params    = shift;
    my $handler   = shift;
    
    # initialize error handler
    $errorhandler = UMLS::Interface::ErrorHandler->new();
        if(! defined $errorhandler) {
	print STDERR "The error handler did not get passed properly.\n";
	exit;
    }

    #  initialize the cuifinder
    $cuifinder = $handler;
    if(! (defined $handler)) { 
	$errorhandler->_error($pkg, 
			      "new", 
			      "The CuiFinder handler did not get passed properly", 
			      8);
    }

    # bless the object.
    bless($self, $className);

    #iInitialize the object.
    $self->_initialize($params);   

    return $self;
}

# Method to initialize the UMLS::Interface::PathFinder object.
sub _initialize {

    my $self      = shift;
    my $params    = shift;

    #  set function name
    my $function = "_initialize";
    
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }
        
    #  get the umlsinterfaceindex database from CuiFinder
    my $sdb = $cuifinder->_getIndexDB();
    if(!$sdb) { $errorhandler->_error($pkg, $function, "Error with sdb.", 3); }
    $self->{'sdb'} = $sdb;
    
    #  get the root
    $root = $cuifinder->_root();

    #  set up the options
    $self->_setOptions($params);
}


#  method to set the global parameter options
#  input : $params <- reference to a hash
#  output: 
sub _setOptions  {

    my $self = shift;
    my $params = shift;

    my $function = "_setOptions";

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  get all the parameters
    my $forcerun     = $params->{'forcerun'};
    my $verbose      = $params->{'verbose'};
    my $realtime     = $params->{'realtime'};
    my $debugoption  = $params->{'debug'};
    my $t            = $params->{'t'};
    my $debugpath    = $params->{'debugpath'};
    my $cuilist      = $params->{'cuilist'};
    my $undirected   = $params->{'undirected'};

    my $output = "";
    if(defined $forcerun    || defined $verbose   || defined $realtime || 
       defined $debugoption || defined $debugpath || defined $cuilist) { 
	$output .= "\nPathFinder User Options:\n";
    }

    #  check if the debug option has been been defined
    if(defined $debugoption) { 
	$debug = 1; 
	$output .= "   --debug option set\n";
    }
    
    #  print debug if it has been set
    &_debug($function);

    if(defined $t) {
	$option_t = 1;
    }

    #  check if the undirected option is set for shortest path
    if(defined $undirected) { 
	$option_undirected = 1;
	$output .= "  --undirected";
    }
    
    #  check if the cuilist option has been defined
    if(defined $cuilist) { 
	$option_cuilist = 1;
	$output .= "  --cuilist";
    }
    
    
    #  check if debugpath option 
    if(defined $debugpath) {
	$option_debugpath = 1;
	$output .= "   --debugpath $debugpath\n";
	open(DEBUG_FILE, ">$debugpath") || 
	    die "Could not open depthpath file $debugpath\n";
    }

    #  check if the realtime option has been identified
    if(defined $realtime) {
	$option_realtime = 1;
	
	$output .= "   --realtime option set\n";
    }

    #  check if verbose run has been identified
    if(defined $verbose) { 
	$option_verbose = 1;
	
	$output .= "   --verbose option set\n";
    }

    #  check if a forced run has been identified
    if(defined $forcerun) {
	$option_forcerun = 1;
	
	$output .= "   --forcerun option set\n";
    }

    if($option_t == 0) {
	print STDERR "$output\n";
    }
}

#  method to return the maximum depth of a taxonomy.
#  input :
#  output: $string <- string containing the max depth
sub _depth {

    my $self = shift;
    
    my $function = "_depth";

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  get the depth and set the path information
    if($option_realtime) {
	my @array = ();
      	$self->_getMaxDepth($root, 0, \@array);
    }
    else {
	$self->_setIndex();
    }
    
    return $max_depth;
}

#  recursive method to obtain the maximum depth in realtime
#  input : $concept <- string containing cui
#          $d       <- string containing the depth of the cui
#          $array   <- reference to an array containing the current path
#  output: $concept <- string containing cui
#          $d       <- string containing the depth of the cui
#          $array   <- reference to an array containing the current path
sub _getMaxDepth {

    my $self    = shift;
    my $concept = shift;
    my $d       = shift;
    my $array   = shift;

    my $function = "_getMaxDepth";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check concept was obtained
    if(!$concept) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept.", 4);
    }
    
    #  check if valid concept
    if(! ($errorhandler->_validCui($concept)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept) in not valid.", 6);
    }

    #  increment the depth
    $d++;
    
    #  check to see if it is the max depth
    if(($d) > $max_depth) { $max_depth = $d; }

    #  check that the concept is not a forbidden concept
    if($cuifinder->_forbiddenConcept($concept) == 1) { return; }

    #  set up the new path
    my @path = @{$array};
    push @path, $concept;
    my $series = join " ", @path;
    
    #  get all the children
    my @children = $cuifinder->_getChildren($concept);
       
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
	}
    }
}

#  method to find all the paths from a concept to
#  the root node of the is-a taxonomy.
#  input : $concept <- string containing cui
#  output: $array   <- array reference containing the paths
sub _pathsToRoot {

    my $self = shift;
    my $concept = shift;

    my $function = "_pathsToRoot";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check parameter exists
    if(!defined $concept) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept.", 4);
    }
    
    #  check if valid concept
    if(! ($errorhandler->_validCui($concept)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept) in not valid.", 6);
    }
         
    #  if the realtime option is set get the paths otherwise 
    #  they are or should be stored in the database 
    my $paths = ""; 
    if($option_realtime) {
	$paths = $self->_getPathsToRootInRealtime($concept);
    }
    else {
	$paths = $self->_getPathsToRootFromIndex($concept);
    }
    
    return $paths    
}

#  returns all the paths to the root from the concept 
#  this information is stored in the index - if it is
#  not then the index is created
#  input : $string <- string containing the cui (assumed correct)
#  output: $array  <- reference to an array containing the paths
sub _getPathsToRootFromIndex {
    my $self    = shift;
    my $concept = shift;

    my $function = "_getPathToRootFromIndex";
  
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  set the index DB handler
    my $sdb = $self->{'sdb'};
    if(!$sdb) { $errorhandler->_error($pkg, $function, "Error with sdb.", 3); }
    
    #  create the index if it hasn't been created
    $self->_setIndex();

    #  get the table name
    my $tableName = $cuifinder->_getTableName();
    
    #  get the paths from the database
    my $paths = $sdb->selectcol_arrayref("select PATH from $tableName where CUI=\'$concept\'");
    $errorhandler->_checkDbError($pkg, $function, $sdb);
    
    return $paths;
}

#  check the index to make certain it is load properly
#  input : 
#  outupt: 
sub _checkIndex {


    my $self           = shift;
    my $tableFile      = shift;
    my $tableName      = shift;
    my $tableNameHuman = shift;

    my $function = "_checkIndex";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }
    
    #  check the input variables
    if(!$tableFile || !$tableName || !$tableNameHuman)      { 
	$errorhandler->_error($pkg, $function, "Error with input variables.", 4);
    }

    #  set the auxillary database that holds the path information
    my $sdb = $self->{'sdb'};
    if(!$sdb) { $errorhandler->_error($pkg, $function, "Error with sdb.", 3); }

    #  extract the check
    my $arrRef = $sdb->selectcol_arrayref("select CUI from $tableName where CUI=\'CHECK\'");
    
    my $count = $#{$arrRef};
    
    if($count != 0) {
	my $str = "Index did not complete. Remove using the removeConfigData.pl program and re-run.";
	$errorhandler->_error($pkg, $function, $str, 9);
    }
    
}

#  load the index in realtime
#  input : 
#  outupt: 
sub _createIndex {


    my $self           = shift;
    my $tableFile      = shift;
    my $tableName      = shift;
    my $tableNameHuman = shift;

    my $function = "_createIndex";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }
    
    #  check the input variables
    if(!$tableFile || !$tableName || !$tableNameHuman)      { 
	$errorhandler->_error($pkg, $function, "Error with input variables.", 4);
    }

    #  set the auxillary database that holds the path information
    my $sdb = $self->{'sdb'};
    if(!$sdb) { $errorhandler->_error($pkg, $function, "Error with sdb.", 3); }

    print STDERR "You have requested path information about a concept. In\n"; 
    print STDERR "order to obtain this information we need to create an \n";
    print STDERR "index or resubmit this command using --realtime. Creating\n";
    print STDERR "an index can be very time-consuming, but once it is built\n";
    print STDERR "your commands will run faster than with --realtime.\n\n";    

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
    
	    
    #  create the table in the umls database
    $sdb->do("CREATE TABLE IF NOT EXISTS $tableName (CUI char(8), DEPTH int, PATH varchar(450))");
    $errorhandler->_checkDbError($pkg, $function, $sdb);
	    
    #  insert the name into the index
    $sdb->do("INSERT INTO tableindex (TABLENAME, HEX) VALUES ('$tableNameHuman', '$tableName')");
    $errorhandler->_checkDbError($pkg, $function, $sdb);

    #  for each root - this is for when we allow multiple roots
    #  right now though we only have one - the umlsRoot
    $self->_initializeDepthFirstSearch($root, 0, $root);

    #  add a check that the DFS has finished
    $sdb->do("INSERT INTO $tableName (CUI, DEPTH, PATH) VALUES(\'CHECK\', '0', \'\')");
    $errorhandler->_checkDbError($pkg, $function, $sdb);

    #  create index on the newly formed table
    my $indexname = "$tableName" . "_CUIINDEX";
    my $index = $sdb->do("create index $indexname on $tableName (CUI)");
    $errorhandler->_checkDbError($pkg, $function, $sdb);
}

#  creates the index containing all of the path to root information 
#  for each concept in the sources and relations specified in the 
#  configuration file
#  input : 
#  output:
sub _setIndex {

    my $self = shift;

    my $function = "_setIndex";
    &_debug($function);
           
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    my $tableName      = $cuifinder->_getTableName();
    my $tableFile      = $cuifinder->_getTableFile();
    my $tableNameHuman = $cuifinder->_getTableNameHuman();

    #  if the path infomration has not been stored
    if(! ($cuifinder->_checkTableExists($tableName))) {
	
	#  otherwise create the tableFile and put the information in the 
	#  file and the database
	$self->_createIndex($tableFile, $tableName, $tableNameHuman);
	
    }

    #  check Index
    $self->_checkIndex($tableFile, $tableName, $tableNameHuman);

    #  set the maximum depth
    $self->_setMaximumDepth();
}    

#  set the maximum depth variable
#  input :
#  output: 
sub _setMaximumDepth {
    my $self = shift;

    my $function = "_setMaximumDepth";
    
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  set the auxillary database that holds the path information
    my $sdb = $self->{'sdb'};
    if(!$sdb) { $errorhandler->_error($pkg, $function, "Error with sdb.", 3); }

    #  get the table name
    my $tableName = $cuifinder->_getTableName();

    #  set the maximum depth
    my $d = $sdb->selectcol_arrayref("select max(DEPTH) from $tableName");
    $errorhandler->_checkDbError($pkg, $function, $sdb);

    $max_depth = shift @{$d}; 
}

#  print out the function name to standard error
#  input : $function <- string containing function name
#  output: 
sub _debug {
    my $function = shift;
    if($debug) { print STDERR "In UMLS::Interface::PathFinder::$function\n"; }
}

#  A Depth First Search (DFS) in order to determine 
#  the maximum depth of the taxonomy and obtain 
#  all of the path information
#  input : 
#  output: 
sub _initializeDepthFirstSearch {

    my $self    = shift;
    my $concept = shift;
    my $d       = shift;
    my $root    = shift;
    
    my $function = "_initializeDepthFirstSearch";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }
   
    #  check the parameters are defined
    if(!(defined $concept) || !(defined $d) || !(defined $root)) {
	$errorhandler->_error($pkg, $function, "Error with input variables.", 4);
    }

    #  check valid concept
    if(! ($errorhandler->_validCui($concept)) ) {
	$errorhandler->_error($pkg, $function, "Incorrect input value ($concept).", 6);
    }
       
    my $tableFile = $cuifinder->_getTableFile();

    #  check if verbose mode
    if($option_verbose) {
	open(TABLEFILE, ">$tableFile") || die "Could not open $tableFile";
    }
    
    #  get the children
    my @children = $cuifinder->_getChildren($concept);
    
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

#  This is like a reverse DFS only it is not recursive
#  due to the stack overflow errors I received when it was
#  input :
#  output: 
sub _getPathsToRootInRealtime {

    my $self    = shift;
    my $concept = shift;

    return () if(!defined $self || !ref $self);

    my $function = "_getPathsToRootInRealtime";
    &_debug($function);
    
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check concept was obtained
    if(!$concept) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept.", 4);
    }
    
    #  check if valid concept
    if(! ($errorhandler->_validCui($concept)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept) in not valid.", 6);
    }

    #  set the  storage
    my @path_storage = ();

    #  set the stack
    my @stack = ();
    push @stack, $concept;

    #  set the count
    my %visited = ();

    #  set the paths
    my @paths = ();
    my @empty = ();
    push @paths, \@empty;

    #  now loop through the stack
    while($#stack >= 0) {
	
	my $concept = $stack[$#stack];
	my $path    = $paths[$#paths];

	#  set up the new path
	my @intermediate = @{$path};
	my $series = join " ", @intermediate;
	push @intermediate, $concept;
	
        #  print information into the file if debugpath option is set
	if($option_debugpath) { 
	    my $d = $#intermediate+1;
	    print DEBUG_FILE "$concept\t$d\t@intermediate\n"; 
	}
        
	#  check that the concept is not one of the forbidden concepts
	if($cuifinder->_forbiddenConcept($concept)) { 
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
	if($concept eq $root) { 
	    #  this is a complete path to the root so push it on the paths 
	    my @reversed = reverse(@intermediate);
	    my $rseries  = join " ", @reversed;
	    push @path_storage, $rseries;
	}
	
	#  get all the parents
	my @parents = $cuifinder->_getParents($concept);

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

    return \@path_storage;
}

#  Depth First Search (DFS) recursive function to collect the path 
#  information and store it in the umlsinterfaceindex database
#  input : $concept <- string containing the cui 
#          $depth   <- depth of the cui
#          $array   <- reference to an array containing the path
#  output: $concept <- string containing the cui 
#          $depth   <- depth of the cui
#          $array   <- reference to an array containing the path
sub _depthFirstSearch {

    my $self    = shift;
    my $concept = shift;
    my $d       = shift;
    my $array   = shift;
    local(*F)   = shift;
        
    my $function = "_depthFirstSearch";
    
  
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check the parameters are defined
    if(!(defined $concept) || !(defined $d)) {
	$errorhandler->_error($pkg, $function, "Error with input variables.", 4);
    }
    
    #  check if valid concept
    if(! ($errorhandler->_validCui($concept)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept) in not valid.", 6);
    }
    
    #  check that the concept is not a forbidden concept
    if($cuifinder->_forbiddenConcept($concept)) { return; }
    
    #  get the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) { $errorhandler->_error($pkg, $function, "Error with sdb.", 3); }
    
    #  get the table name of the index
    my $tableName = $cuifinder->_getTableName();
    
    #  increment the depth
    $d++;

    #  set up the new path
    my @path = @{$array};
    push @path, $concept;
    my $series = join " ", @path;
    
    #  load path information into the table
    #  check if only a specified set of cui information is required
    if($option_cuilist) {
    
	#  check if it is in the cuilist - and if so insert it the cui
	if($cuifinder->_inCuiList($concept)) { 
	    my $arrRef = $sdb->do("INSERT INTO $tableName (CUI, DEPTH, PATH) VALUES(\'$concept\', '$d', \'$series\')");
	    $errorhandler->_checkDbError($pkg, $function, $sdb);
	}
    } 
    #  otherwise we are loading all of it
    else {
	my $arrRef = $sdb->do("INSERT INTO $tableName (CUI, DEPTH, PATH) VALUES(\'$concept\', '$d', \'$series\')");
	$errorhandler->_checkDbError($pkg, $function, $sdb);
    }
    
    #  print information into the file if verbose option is set
    if($option_verbose) { 
	if($option_cuilist) {
	    if($cuifinder->_inCuiList($concept)) { 
		print F "$concept\t$d\t$series\n"; 
	    }
	} 
	else { print F "$concept\t$d\t$series\n"; }
    }
    
    #  get all the children
    my @children = $cuifinder->_getChildren($concept);

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
    }
}

#  function returns the minimum depth of a concept
#  input : $cui   <- string containing the cui
#  output: $depth <- string containing the depth of the cui
sub _findMinimumDepth {

    my $self = shift;
    my $cui  = shift;

    my $function = "_findMinimumDepth";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check concept was obtained
    if(!$cui) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$cui.", 4);
    }
    
    #  check if valid concept
    if(! ($errorhandler->_validCui($cui)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($cui) in not valid.", 6);
    }
    
    #  get the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) { $errorhandler->_error($pkg, $function, "Error with sdb.", 3); }
    
    #  if it is in the parent taxonomy 
    if($cuifinder->_inParentTaxonomy($cui)) { return 1; }
    
    my $min = 9999;
    
    if($option_realtime) {
	my $paths = $self->_getPathsToRootInRealtime($cui);
	
	# get the minimum depth
	foreach my $p (@{$paths}) { 
	    my @array = split/\s+/, $p;
	    if( ($#array+1) < $min) { $min = $#array + 1; }
	}
    }
    else {
	
	#  set the depth
	$self->_setIndex();

	#  get the table name
	my $tableName = $cuifinder->_getTableName();

	#  get the minimum depth from the table
	my $d = $sdb->selectcol_arrayref("select min(DEPTH) from $tableName where CUI=\'$cui\'");
	$errorhandler->_checkDbError($pkg, $function, $sdb);
	
	#  return the minimum depth
	$min = shift @{$d}; $min++;
    }
    
    return $min;
}

#  function returns maximum depth of a concept
#  input : $cui   <- string containing the cui
#  output: $depth <- string containing the depth of the cui
sub _findMaximumDepth {

    my $self = shift;
    my $cui  = shift;

    my $function = "_findMaximumDepth";
    &_debug($function);
        
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check concept was obtained
    if(!$cui) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$cui.", 4);
    }
    
    #  check if valid concept
    if(! ($errorhandler->_validCui($cui)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($cui) in not valid.", 6);
    }
    
    #  get the database
    my $sdb = $self->{'sdb'};
    if(!$sdb) { $errorhandler->_error($pkg, $function, "Error with sdb.", 3); }
    
    #  initialize max
    my $max = 0;
    #  if realtime option is set
    if($option_realtime) {
	my $paths = $self->_getPathsToRootInRealtime($cui);
	
	# get the maximum depth
	foreach my $p (@{$paths}) { 
	    my @array = split/\s+/, $p;
	    if( ($#array+1) > $max) { $max = $#array + 1; }
	}
    }
    
    #  otherwise
    else {
	#  set the depth
	$self->_setIndex();
	
	#  get the table name
	my $tableName = $cuifinder->_getTableName();
		
	#  get the depth from the table
	my $d = $sdb->selectcol_arrayref("select max(DEPTH) from $tableName where CUI=\'$cui\'");
	$errorhandler->_checkDbError($pkg, $function, $sdb);

	$max = shift @{$d}; $max++;
    }

    #  return the maximum depth
    return $max;    
}

#  find the shortest path between two concepts
#  input : $concept1 <- string containing the first cui
#          $concept2 <- string containing the second
#  output: @array    <- array containing the shortest path(s)
sub _findShortestPath {

    my $self     = shift;
    my $concept1 = shift;
    my $concept2 = shift;

    my $function = "_findShortestPath";
    &_debug($function);
         
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check parameter exists
    if(!defined $concept1) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept1.", 4);
    }
    if(!defined $concept2) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept2.", 4);
    }

    #  check if valid concept
    if(! ($errorhandler->_validCui($concept1)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept1) in not valid.", 6);
    }    
    if(! ($errorhandler->_validCui($concept2)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept2) in not valid.", 6);
    }    

    #  if realtime option is set find the shortest path in realtime 
    #if($option_realtime) {
    #return $self->_findShortestPathInRealTime($concept1, $concept2);
    #}
    #else {
    return $self->_findShortestPathThroughLCS($concept1, $concept2);
    #}
}

#  this function returns the shortest path between two concepts
#  input : $concept1 <- string containing the first cui
#          $concept2 <- string containing the second
#  output: @array    <- array containing the lcs(es)
sub _findShortestPathThroughLCS {
    
    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;
    
    my $function = "_findShortestPathThroughLCS";
    &_debug($function);
    
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check parameter exists
    if(!defined $concept1) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept1.", 4);
    }
    if(!defined $concept2) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept2.", 4);
    }

    #  check if valid concept
    if(! ($errorhandler->_validCui($concept1)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept1) in not valid.", 6);
    }    
    if(! ($errorhandler->_validCui($concept2)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept2) in not valid.", 6);
    }    

    #  find the shortest path(s) and lcs - there may be more than one
    my $hash = $self->_shortestPath($concept1, $concept2);
    
    #  remove the blanks from the paths
    my @paths = (); my $output = "";
    foreach my $path (sort keys %{$hash}) {
	if($path=~/C[0-9]+/) {
	    push @paths, $path;
	}
    } 
    
    #  return the shortest paths (all of them)
    return @paths;
}


#  this function returns the least common subsummer between two concepts
#  input : $concept1 <- string containing the first cui
#          $concept2 <- string containing the second
#  output: @array    <- array containing the lcs(es)
sub _findLeastCommonSubsumer {

    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;
    
    my $function = "_findLeastCommonSubsumer";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check parameter exists
    if(!defined $concept1) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept1.", 4);
    }
    if(!defined $concept2) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept2.", 4);
    }

    #  check if valid concept
    if(! ($errorhandler->_validCui($concept1)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept1) in not valid.", 6);
    }    
    if(! ($errorhandler->_validCui($concept2)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept2) in not valid.", 6);
    }    
    
    #  initialize the array that will contain the lcses
    my @lcses = (); 

    #  get the LCSes
    #if($option_realtime) {
    #@lcses = $self->_findLeastCommonSubsumerInRealTime($concept1, $concept2);
    #}
    #else {

    my $hash = $self->_shortestPath($concept1, $concept2);
    my %lcshash = ();
    if(defined $hash) {
	foreach my $path (sort keys %{$hash}) { 
	    my $c = ${$hash}{$path};
	    if($c=~/C[0-9]+/) { $lcshash{$c}++; }
	}
    }
    foreach my $lcs (sort keys %lcshash) { push @lcses, $lcs; }
    #}
    
    #  return the lcses
    return @lcses;
}

#  this function returns the least common subsummer between two concepts
#  input : $concept1 <- string containing the first cui
#          $concept2 <- string containing the second
#  output: @array    <- array containing the lcs(es)
sub _findLeastCommonSubsumerInRealTime {

    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;
    
    my $function = "_findLeastCommonSubsumer";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check parameter exists
    if(!defined $concept1) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept1.", 4);
    }
    if(!defined $concept2) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept2.", 4);
    }

    #  check if valid concept
    if(! ($errorhandler->_validCui($concept1)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept1) in not valid.", 6);
    }    
    if(! ($errorhandler->_validCui($concept2)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept2) in not valid.", 6);
    }    
    
    #  get the shorest paths
    my @paths = $self->_findShortestPathInRealTime($concept1, $concept2);
    
    #  get the child relations
    my $childstring = $cuifinder->_getChildRelations();

    #  initialize the lcses array
    my %lcses = ();
 
   #  check for the lcs in each of the paths
    foreach my $p (@paths) {
	#  get the path and the first concept
	my @path     = split/\s+/, $p;
	my $concept1 = shift @path;
	my $flag     = 0;
	
	#  loop through the rest of the concepts looking for the first child relation
	foreach my $concept2 (@path) {
	    my @relations = $cuifinder->_getRelationsBetweenCuis($concept1, $concept2);
	    foreach my $item (@relations) {
		$item=~/([A-Z]+) \([A-Z]+\)/;
		my $rel = $1;
		#  if the relation is a child we have the LCS - it is concept1
		if($childstring=~/($rel)/ && $flag == 0) {
		    $lcses{$concept1}++; $flag++;
		}
	    }
	    $concept1 = $concept2;
	}
    }

    #  get the unique lcses - note a single lcs may have more than one path
    my @unique = ();
    foreach my $lcs (sort keys %lcses) { push @unique, $lcs; }

    #  return the unique lcses
    return @unique;
}

#  method to get the Least Common Subsumer of two 
#  paths to the root of a taxonomy
#  input : $array1 <- reference to an array containing 
#                     the paths to the root for cui1
#          $array2 <- same thing for cui2
#  output: $hash   <- reference to a hash containing the
#                     lcs as the key and the path as the hash
sub _getLCSfromTrees {

    my $self      = shift;
    my $arrayref1 = shift;
    my $arrayref2 = shift;
        
    my $function = "_getLCSfromTrees";

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check parameter exists
    if(!defined $arrayref1) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$arrayref1.", 4);
    }
    if(!defined $arrayref2) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$arrayref2.", 4);
    }

    #  get the arrays
    my @array1 = split/\s+/, $arrayref1;
    my @array2 = split/\s+/, $arrayref2;

    #  reverse them
    my @tree1 = reverse @array1;
    my @tree2 = reverse @array2;
    my $tmpString = " ".join(" ", @tree2)." ";

    #  find the lcs
    foreach my $element (@tree1) {
	if($tmpString =~ / $element /) {
	    return $element;
	}
    }
    
    return undef;
}

sub _findShortestPathInRealTime {
    
    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;
    
    my $function = "_findShortestPathInRealTime";
    &_debug($function);
      
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check parameter exists
    if(!defined $concept1) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept1.", 4);
    }
    if(!defined $concept2) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept2.", 4);
    }

    #  check if valid concept
    if(! ($errorhandler->_validCui($concept1)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept1) in not valid.", 6);
    }    
    if(! ($errorhandler->_validCui($concept2)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept2) in not valid.", 6);
    }    
    
    #  set the  storage
    my @path_storage= ();
    my $path_length = 99999;

    #  set the count
    my %visited = ();
    
    #  set the stack with the parents because 
    #  we want to start going up inorder to 
    #  have an LCS
    my @directions = ();
    my @relations  = ();
    my @paths      = ();
    my @stack = $cuifinder->_getParents($concept1);

    #  unless the undirected option is set then 
    #  we require both
    if($option_undirected) {
	my @children = $cuifinder->_getChildren($concept1);
	@stack = (@stack, @children);
    }
    foreach my $element (@stack) {
	my @array      = (); 
	push @paths, \@array;
	push @directions, 0;
	push @relations, "PAR";
    }

    #  now loop through the stack
    while($#stack >= 0) {
	
	my $concept    = pop @stack;
	my $path       = pop @paths;
	my $direction  = pop @directions;
	my $relation   = pop @relations;
	
        #  set up the new path
	my @intermediate = @{$path};
	my $series = join " ", @intermediate;
	push @intermediate, $concept;
	my $distance = $#intermediate;

	#  check if the distance is greater than what we 
	#  already have
	if($distance > $path_length) { next; }

	#  check that the concept is not one of the forbidden concepts
	if($cuifinder->_forbiddenConcept($concept)) { next; }	

        #  check if concept has been visited already through that path
	my $v = "$concept : $series";
	if(exists $visited{$v}) { next; }	
	else { $visited{$v}++; }
	
        #  check if it is our concept2
	if($concept eq $concept2) { 
	    if($distance < $path_length) {
		@path_storage = ();
		push @path_storage, \@intermediate;
		$path_length = $distance;

	    }
	    elsif($distance == $path_length) {
		push @path_storage, \@intermediate;
	    }
	}
	
        #  print information into the file if debugpath option is set
	if($option_debugpath) { 
	    my $d = $#intermediate+1;
	    print DEBUG_FILE "$concept\t$d\t@intermediate\n"; 
	}
	

	#  we are going to start with the parents here; the code 
	#  for both is similar except for the relation/direction
	#  which is why I have the seperate right now - currently 
	

	#  if the previous direction was a child we have a change in direction
	my $dchange = $direction;
      
	#  if the undirected option is set the dchange doesn't matter
	#  otherwise we need to check
	if(!$option_undirected) { 
	    if($relation eq "CHD") { $dchange = $direction + 1; }
	}

	#  if we have not had more than a single direction change
	if($dchange < 2) {
	    #  search through the parents
	    my @parents  = $cuifinder->_getParents($concept);		
	    foreach my $parent (@parents) {
		
		#  check if child cui has already in the path
		my $flag = 0;
		foreach my $cui (@intermediate) {
		    if($cui eq $parent) { $flag = 1; }
		}
		
		#  if it isn't add it to the stack
		if($flag == 0) {
		    unshift @stack, $parent;
		    unshift @paths, \@intermediate;
		    unshift @relations, "PAR";
		    unshift @directions, $dchange;
		}
	    }
	}
	
	#  now with the chilcren if the previous direction was a parent we have
	#  have to change the direction
	$dchange = $direction;
	#  if the undirected option is set the dchange doesn't matter
	#  otherwise we need to check
	if(!$option_undirected) { 
	    if($relation eq "PAR") { $dchange = $direction + 1; }
	}

	#  if we have not had more than a single direction change
	if($dchange < 2) {
	    #  now search through the children
	    my @children = $cuifinder->_getChildren($concept);
	    foreach my $child (@children) {
		
		#  check if child cui has already in the path
		my $flag = 0;
		foreach my $cui (@intermediate) {
		    if($cui eq $child) { $flag = 1; }
		}
		
		#  if it isn't add it to the stack
		if($flag == 0) {
		    unshift @stack, $child;
		    unshift @paths, \@intermediate;
		    unshift @relations, "CHD";
		    unshift @directions, $dchange;
		}
	    }
	}
    }
    
    #  set the return
    my @return_paths = ();
    foreach my $p (@path_storage) {
	unshift @{$p}, $concept1;
	my $string = join " " , @{$p};
	push @return_paths, $string;
    }
    return @return_paths;
}

#  this function finds the shortest path between 
#  two concepts and returns the path. in the process 
#  it determines the least common subsumer for that 
#  path so it returns both
#  input : $concept1 <- string containing the first cui
#          $concept2 <- string containing the second
#  output: $hash     <- reference to a hash containing the 
#                       lcs as the key and the path as the
#                       value
sub _shortestPath {

    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;

    my $function = "_shortestPath";
    &_debug($function);
      
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check parameter exists
    if(!defined $concept1) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept1.", 4);
    }
    if(!defined $concept2) { 
	$errorhandler->_error($pkg, $function, "Error with input variable \$concept2.", 4);
    }

    #  check if valid concept
    if(! ($errorhandler->_validCui($concept1)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept1) in not valid.", 6);
    }    
    if(! ($errorhandler->_validCui($concept2)) ) {
	$errorhandler->_error($pkg, $function, "Concept ($concept2) in not valid.", 6);
    }    

    # Get the paths to root for each ofhte concepts
    my $lTrees = $self->_pathsToRoot($concept1);

    my $rTrees = $self->_pathsToRoot($concept2);
   
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
		    if($lcsLengths{$lcs} >= ($rCount + $lCount - 1)) {
			$lcsLengths{$lcs} = $rCount + $lCount - 1;
			my @fullpath = (@lArray, (reverse @rArray));
			push @{$lcsPaths{$lcs}}, \@fullpath;
		    }
		}
		else {
		    $lcsLengths{$lcs} = $rCount + $lCount - 1;
		    my @fullpath = (@lArray, (reverse @rArray));
		    push @{$lcsPaths{$lcs}}, \@fullpath;
		}
	    }
	}
    }
    
    # If no paths exist 
    if(!scalar(keys(%lcsPaths))) {
	return undef;
    }

    #  get the lcses and their associated path(s)
    my %rhash    = ();
    my $prev_len = -1;
    foreach my $lcs (sort {$lcsLengths{$a} <=> $lcsLengths{$b}} keys(%lcsLengths)) {
	if( ($prev_len == -1) or ($prev_len == $lcsLengths{$lcs}) ) {
	    foreach my $pathref (@{$lcsPaths{$lcs}}) { 
		my $path = join " ", @{$pathref};
		$rhash{$path} = $lcs;
	    }
	}
	else { next;; }
	$prev_len = $lcsLengths{$lcs};
    }
    
    #  return a reference to the hash containing the lcses and their path(s)
    return \%rhash;
}

1;

__END__

=head1 NAME

UMLS::Interface::PathFinder - provides the path information 
for the modules in the UMLS::Interface package.

=head1 DESCRIPTION

This package provides the path information about the CUIs in 
the UMLS for the modules in the UMLS::Interface package.

For more information please see the UMLS::Interface.pm 
documentation. 

=head1 SYNOPSIS

 use UMLS::Interface::CuiFinder;

 use UMLS::Interface::PathFinder;

 %params = ();

 $params{'realtime'} = 1;

 $cuifinder = UMLS::Interface::CuiFinder->new(\%params);

 die "Unable to create UMLS::Interface::CuiFinder object.\n" if(!$cuifinder);

 $pathfinder = UMLS::Interface::PathFinder->new(\%params, $cuifinder); 

 die "Unable to create UMLS::Interface::PathFinder object.\n" if(!$pathfinder);

 $concept = "C0037303";

 $depth = $pathfinder->_depth();

 $array = $pathfinder->_pathsToRoot($concept);

 $depth = $pathfinder->_findMinimumDepth($concept);

 $depth = $pathfinder->_findMaximumDepth($concept);

 $concept1 = "C0037303"; $concept2 = "C0018563";

 @array = $pathfinder->_findShortestPath($concept1, $concept2);

 @array = $pathfinder->_findLeastCommonSubsumer($concept1, $concept2);

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
