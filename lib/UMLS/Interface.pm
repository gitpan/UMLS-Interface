# UMLS::Interface 
# (Last Updated $Id: Interface.pm,v 1.117 2011/05/12 17:21:22 btmcinnes Exp $)
#
# Perl module that provides a perl interface to the
# Unified Medical Language System (UMLS)
#
# Copyright (c) 2004-2011,
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

package UMLS::Interface;

use Fcntl;
use strict;
use warnings;
use DBI;
use bytes;

use UMLS::Interface::CuiFinder;
use UMLS::Interface::PathFinder;
use UMLS::Interface::ICFinder;
use UMLS::Interface::STFinder;
use UMLS::Interface::ErrorHandler;

my $cuifinder    = "";
my $pathfinder   = "";
my $icfinder     = "";
my $stfinder     = "";
my $errorhandler = "";

my $pkg = "UMLS::Interface";

use vars qw($VERSION);

$VERSION = '1.13';

my $debug = 0;

# UMLS-specific stuff ends ----------

# -------------------- Class methods start here --------------------

#  method to create a new UMLS::Interface object
#  input : $params <- reference to hash containing the parameters 
#  output:
sub new {

    my $self      = {};
    my $className = shift;
    my $params    = shift;

    # bless the object.
    bless($self, $className);

    # initialize error handler
    $errorhandler = UMLS::Interface::ErrorHandler->new();
    if(! defined $errorhandler) {
	print STDERR "The error handler did not get passed properly.\n";
	exit;
    }

    #  check options
    $self->_checkOptions($params);

    # Initialize the object.
    $self->_initialize($params);

    return $self;
}

#  initialize the variables and set the parameters
#  input : $params <- reference to hash containing the parameters 
#  output:
sub _initialize {

    my $self = shift;
    my $params = shift;

    my $function = "_initialize";

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  NOTE: The PathFinder and ICFinder require the CuiFinder 
    #        therefore it needs to be initialized the first

    #  set the cuifinder
    $cuifinder = UMLS::Interface::CuiFinder->new($params);
    if(! defined $cuifinder) { 
	my $str = "The UMLS::Interface::CuiFinder object was not created.";
	$errorhandler->_error($pkg, $function, $str, 8);
    }
    
    #  set the pathfinder
    $pathfinder = UMLS::Interface::PathFinder->new($params, $cuifinder);
    if(! defined $pathfinder) { 
	my $str = "The UMLS::Interface::PathFinder object was not created.";
	$errorhandler->_error($pkg, $function, $str, 8);
    }
    
    #  set the icfinder
    $icfinder = UMLS::Interface::ICFinder->new($params, $cuifinder);
    if(! defined $icfinder) { 
	my $str = "The UMLS::Interface::ICFinder object was not created.";
	$errorhandler->_error($pkg, $function, $str, 8);
    }

    #  set the stfinder
    $stfinder = UMLS::Interface::STFinder->new($params, $cuifinder);
    if(! defined $stfinder) { 
	my $str = "The UMLS::Interface::STFinder object was not created.";
	$errorhandler->_error($pkg, $function, $str, 8);
    }
    
}

#  method to re-initialize the interface configuration parameters
#  input: $hash -> reference to hash containing parameters - this
#                  is the same hash that would be used with new()
#  output:
sub reConfig
{
    my $self = shift;
    my $params = shift;

    $cuifinder->_reConfig($params);
}

#  method checks the parameters based to the UMLS::Interface package
#  input : $params <- reference to hash containing the parameters 
#  output:
sub _checkOptions {

    my $self = shift;
    my $params = shift;

    my $function = "_checkOptions";

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  database options
    my $database     = $params->{'database'};
    my $hostname     = $params->{'hostname'};
    my $socket       = $params->{'socket'};
    my $port         = $params->{'port'};
    my $username     = $params->{'username'};
    my $password     = $params->{'password'};
   
    #  cuifinder options
    my $config       = $params->{'config'};
    
    #  pathfinder options
    my $forcerun     = $params->{'forcerun'};
    my $realtime     = $params->{'realtime'};
    my $debugpath    = $params->{'debugpath'};

    #  general options
    my $debugoption  = $params->{'debug'};
    my $verbose      = $params->{'verbose'};
    my $cuilist      = $params->{'cuilist'};

    if( (defined $username) && (!defined $password) ) {
	my $str = "The --password option must be defined when using --username.";
	$errorhandler->_error($pkg, $function, $str, 10);
    }

    if( (!defined $username) && (defined $password) ) {
	my $str = "The --username option must be defined when using --password.";
	$errorhandler->_error($pkg, $function, $str, 10);
    }

    if( (defined $forcerun) && (defined $realtime) ) {
	my $str = "The --forcerun and --realtime option ";
	$str   .= "can not be set at the same time.";
	$errorhandler->_error($pkg, $function, $str, 10);
    }
	
}

#####################################################################
#  methods located in CuiFinder.pm
#####################################################################

#  returns the root
#  input :
#  output: string containing the root
sub root {

    my $self = shift;

    my $root = $cuifinder->_root();

    return $root;
}


#  returns the version of the UMLS currently being used
#  input : 
#  output: string containing the version
sub version {

    my $self = shift;

    my $version = $cuifinder->_version();

    return $version;
}

#  returns the parameters set in the configuration file
#  input: 
#  output : $hash <- reference to hash containing parameters in the 
#                    configuration file - if there was not config
#                    file the hash is empty and defaults are being
#                    use
sub getConfigParameters {
    my $self = shift;

    my $function = "getConfigParameters";

    return $cuifinder->_getConfigParameters();
}

#  returns the sab information from the configuration file
#  input : 
#  output: $string <- containing the SAB line from the config file
sub getSabString {
    
    my $self = shift;
    
    my $function = "getSabString";
    
    return $cuifinder->_getSabString();
}

#  returns the relation information from the configuration file
#  input : 
#  output: $string <- containing the REL line from the config file
sub getRelString {
    
    my $self = shift;
    
    my $function = "getRelString";
    
    return $cuifinder->_getRelString();
}

#  returns the rela information from the configuration file
#  input : 
#  output: $string <- containing the RELA line from the config file
sub getRelaString {
    
    my $self = shift;
    
    my $function = "getRelaString";
    
    return $cuifinder->_getRelaString();
}

#  method that returns a list of concepts (@concepts) related 
#  to a concept $concept through a relation $rel
#  input : $concept <- string containing cui
#          $rel     <- string containing a relation
#  output: $array   <- reference to an array of cuis
sub getRelated {

    my $self    = shift;
    my $concept = shift;
    my $rel     = shift;

    my $array = $cuifinder->_getRelated($concept, $rel);

    return $array;
}

#  method that returns the preferred term of a cui from 
#  the sources specified in the configuration file
#  input : $concept <- string containing cui
#  output: $string  <- string containing the preferred term
sub getPreferredTerm {
    my $self    = shift;
    my $concept = shift;
    
    return $cuifinder->_getPreferredTerm($concept);
}


#  method that returns the preferred term of a cui from entire umls
#  input : $concept <- string containing cui
#  output: $string  <- string containing the preferred term
sub getAllPreferredTerm {
    my $self    = shift;
    my $concept = shift;
    
    return $cuifinder->_getAllPreferredTerm($concept);
}

#  method to map terms to a given cui from the sources 
#  specified in the configuration file using SAB
#  input : $concept <- string containing cui
#  output: $array   <- reference to an array of terms (strings)
sub getTermList {

    my $self    = shift;
    my $concept = shift;
    
    my $array = $cuifinder->_getTermList($concept);

    return $array;
}

#  method to map terms to a given cui from the sources 
#  specified in the configuration file using SABDEF
#  input : $concept <- string containing cui
#  output: $array   <- reference to an array of terms (strings)
sub getDefTermList {

    my $self    = shift;
    my $concept = shift;
    
    my $array = $cuifinder->_getDefTermList($concept);

    return $array;
}

#  method to map terms from the entire UMLS to a given cui
#  input : $concept <- string containing cui
#  output: $array   <- reference to an array containing terms (strings)
sub getAllTerms {

    my $self = shift;
    my $concept = shift;

    my $array = $cuifinder->_getAllTerms($concept);

    return $array;
}

#  method to maps a given term to a set cuis in the sources
#  specified in the configuration file by SAB
#  input : $term  <- string containing a term
#  output: $array <- reference to an array containing cuis
sub getConceptList {

    my $self = shift;
    my $term = shift;

    my $array = $cuifinder->_getConceptList($term);

    return $array;
}

#  method to maps a given term to a set cuis in the sources
#  specified in the configuration file by SABDEF
#  input : $term  <- string containing a term
#  output: $array <- reference to an array containing cuis
sub getDefConceptList {

    my $self = shift;
    my $term = shift;

    my $array = $cuifinder->_getDefConceptList($term);

    return $array;
}

#  method to maps a given term to a set cuis in the sources
#  specified in the configuration file by SABDEF
#  input : $term  <- string containing a term
#  output: $array <- reference to an array containing cuis
sub getSabDefConcepts {

    my $self = shift;
    my $term = shift;

    my $array = $cuifinder->_getSabDefConcepts($term);

    return $array;
}

#  method to maps a given term to a set cuis all the sources
#  input : $term  <- string containing a term
#  output: $array <- reference to an array containing cuis
sub getAllConcepts {

    my $self = shift;
    my $term = shift;

    my $array = $cuifinder->_getAllConcepts($term);

    return $array;
}

#  method returns all the compounds in the sources 
#  specified in the configuration file
#  input:
#  output: $hash <- reference to a hash containing cuis
sub getCompounds {

    my $self = shift;

    my $hash = $cuifinder->_getCompounds();

    return $hash;
}

#  returns all of the cuis in the sources specified in
#  the configuration file
#  input : 
#  output: $hash <- reference to a hash containing cuis
sub getCuiList {    

    my $self = shift;

    my $hash = $cuifinder->_getCuiList();

    return $hash;
}

#  returns the cuis from a specified source 
#  input : $sab   <- string contain the sources abbreviation
#  output: $array <- reference to an array containing cuis
sub getCuisFromSource {
    
    my $self = shift;
    my $sab = shift;
    
    my $array = $cuifinder->_getCuisFromSource($sab);

    return $array;
}

#  takes as input a cui and returns all of the sources in which 
#  it originated from 
#  input : $concept <- string containing the cui 
#  output: $array   <- reference to an array contain the sources (abbreviations)
sub getSab {

    my $self = shift;
    my $concept = shift;

    my $array = $cuifinder->_getSab($concept);

    return $array;
}

#  returns the children of a concept - the relations that 
#  are considered children are predefined by the user in 
#  the configuration file. The default is the CHD relation.
#  input : $concept <- string containing cui
#  outupt: $array   <- reference to an array containing a list of cuis
sub getChildren {

    my $self    = shift;
    my $concept = shift;

    my $array = $cuifinder->_getChildren($concept);

    return $array;
}


#  returns the parents of a concept - the relations that 
#  are considered parents are predefined by the user in 
#  the configuration file.The default is the PAR relation.
#  input : $concept <- string containing cui
#  outupt: $array   <- reference to an array containing a list of cuis
sub getParents {

    my $self    = shift;
    my $concept = shift;

    my $array = $cuifinder->_getParents($concept);

    return $array;
    
}

#  returns the relations of a concept in the source specified 
#  by the user in the configuration file
#  input : $concept <- string containing a cui
#  output: $array   <- reference to an array containing strings of relations
sub getRelations {

    my $self    = shift;
    my $concept = shift;
    
    my $array = $cuifinder->_getRelations($concept);

    return $array;
}

#  returns the relations and its source between two concepts
#  input : $concept1 <- string containing a cui
#        : $concept2 <- string containing a cui
#  output: $array    <- reference to an array containing the relations
sub getRelationsBetweenCuis {

    my $self     = shift;
    my $concept1 = shift;
    my $concept2 = shift;

    my $array = $cuifinder->_getRelationsBetweenCuis($concept1, $concept2);

    return $array;
}

#  subroutine to get the relation(s) between two semantic types
#  input : $st1   <- semantic type abbreviation
#          $st2   <- semantic type abbreviation
#  output: $array <- reference to an array of semantic relation(s)
sub getSemanticRelation {
    
    my $self = shift;
    my $st1  = shift;
    my $st2  = shift;

    my $array = $cuifinder->_getSemanticRelation($st1, $st2);

    return $array;
}
 
#  returns the semantic type(s) of a given cui
# input : $concept <- string containing a concept
# output: $array   <- reference to an array containing the semantic type's TUIs
#                     associated with the concept
sub getSt {

    my $self = shift;
    my $concept   = shift;

    my $array = $cuifinder->_getSt($concept);
    
    return $array;
}

#  method returns the semantic group(s) associated with the concept
#  input : $concept <- string containing cuis
#  output: $array   <- $array reference containing semantic groups
sub getSemanticGroup {

    my $self = shift;
    my $cui  = shift;
    
    my $array = $cuifinder->_getSemanticGroup($cui);

    return $array;
}

#  returns the full name of a semantic type given its abbreviation
#  input : $st     <- string containing the abbreviation of the semantic type
#  output: $string <- string containing the full name of the semantic type
sub getStString {

    my $self = shift;
    my $st   = shift;

    my $string = $cuifinder->_getStString($st);

    return $string;
} 


#  returns the abreviation of a semantic type given its TUI (UI)
#  input : $tui    <- string containing the semantic type's TUI
#  output: $string <- string containing the semantic type's abbreviation
sub getStAbr {

    my $self = shift;
    my $tui   = shift;

    my $abr = $cuifinder->_getStAbr($tui);

    return $abr;
} 

# subroutine to get the name of a semantic type's TUI given its abbrevation
#  input : $string <- string containing the semantic type's abbreviation
#  output: $tui    <- string containing the semantic type's TUI
sub getStTui {
    my $self   = shift;
    my $abbrev = shift;

    my $tui = $cuifinder->_getStTui($abbrev);

    return $tui;
} 


#  returns the definition of the semantic type - expecting abbreviation
#  input : $st     <- string containing the semantic type's abbreviation
#  output: $string <- string containing the semantic type's definition
sub getStDef {

    my $self = shift;
    my $st   = shift;

    my $definition = $cuifinder->_getStDef($st);

    return $definition;
} 

#  returns the extended definition of a cui given the relation 
#  and source information in the configuration file 
#  input : $concept <- string containing a cui
#  output: $array   <- reference to an array containing the definitions
sub getExtendedDefinition {

    my $self    = shift;
    my $concept = shift;

    my $array = $cuifinder->_getExtendedDefinition($concept);

    return $array;
}

#   returns the definition of the cui 
#  input : $concept <- string containing a cui
#          $sabflag <- 0 | 1 whether to include the source in 
#                      with the definition 
#  output: $array   <- reference to an array of definitions (strings)
sub getCuiDef {

    my $self    = shift;
    my $concept = shift;
    my $sabflag = shift;

    my $array = $cuifinder->_getCuiDef($concept, $sabflag);

    return $array;
}

#  checks to see a CUI is valid
#  input : $concept <- string containing a cui
#  output: 0 | 1    <- integer indicating if the cui is valide
sub validCui {

    my $self = shift;
    my $concept = shift;
    
    my $bool = $cuifinder->_validCui($concept);

    return $bool;
    
}

#  Method to check if a concept ID exists in the database.
#  input : $concept <- string containing a cui
#  output: 1 | 0    <- integers indicating if the cui exists
sub exists() {
    
    my $self = shift;
    my $concept = shift;
    
    my $bool = $cuifinder->_exists($concept);

    return $bool;
}   

#  returns the table names in both human readable and hex form
#  input : 
#  output: $hash <- reference to a hash containin the table names 
#          in human readable and hex form
sub returnTableNames {

    my $self = shift;
    
    my $hash = $cuifinder->_returnTableNames();

    return $hash;

}

#  removes the configuration tables
#  input : 
#  output:
sub dropConfigTable {
    
    my $self    = shift;

    $cuifinder->_dropConfigTable();

    return;
    
}

#  removes the configuration files
#  input :
#  output: 
sub removeConfigFiles {

    my $self = shift;

    $cuifinder->_removeConfigFiles();

    return; 
}

#####################################################################
#  methods located in PathFinder.pm
#####################################################################

#  method to return the maximum depth of a taxonomy.
#  input : 
#  output: $string <- string containing the depth
sub depth {
    my $self = shift;

    my $depth = $pathfinder->_depth();

    return $depth;
}

#  method to find all the paths from a concept to
#  the root node of the is-a taxonomy.
#  input : $concept <- string containing cui
#  output: $array   <- array reference containing the paths
sub pathsToRoot
{
    my $self    = shift;
    my $concept = shift;

    my $array = $pathfinder->_pathsToRoot($concept);

    return $array;
}

#  function returns the minimum depth of a concept given the
#  sources and relations specified in the configuration file
#  input : $concept <- string containing the cui
#  output: $int      <- string containing the depth of the cui
sub findMinimumDepth {

    my $self     = shift;
    my $concept  = shift;
    
    my $depth = $pathfinder->_findMinimumDepth($concept);

    return $depth;
}
  

#  function returns the maximum depth of a concept given the 
#  sources and relations specified in the configuration file
#  input : $concept <- string containing the cui
#  output: $int     <- string containing the depth of the cui
sub findMaximumDepth {

    my $self    = shift;
    my $concept = shift;
    
    my $depth = $pathfinder->_findMaximumDepth($concept);

    return $depth;
}    

#  method that finds the number of cuis closer to concept1 than concept2
#  input : $concept1  <- the first concept
#          $concept2  <- the second concept
#  output: $int       <- number of cuis closer to concept1 than concept2
sub findNumberOfCloserConcepts {

    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;
    
    my $length = $pathfinder->_findNumberOfCloserConcepts($concept1, $concept2);
    
    return $length;
}


#  method that finds the length of the shortest path
#  input : $concept1  <- the first concept
#          $concept2  <- the second concept
#  output: $int       <- the length of the shortest path between them
sub findShortestPathLength {

    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;
    
    my $length = $pathfinder->_findShortestPathLength($concept1, $concept2);
    
    return $length;
}

#  returns the shortest path between two concepts given the 
#  sources and relations specified in the configuration file
#  input : $concept1 <- string containing the first cui
#          $concept2 <- string containing the second
#  output: $array    <- reference to an array containing the shortest path(s)
sub findShortestPath {

    my $self     = shift;
    my $concept1 = shift;
    my $concept2 = shift;

    my $array = $pathfinder->_findShortestPath($concept1, $concept2);

    return $array;
}
   
#   returns the least common subsummer between two concepts given 
#   the sources and relations specified in the configuration file
#  input : $concept1 <- string containing the first cui
#          $concept2 <- string containing the second
#  output: $array    <- reference to an array containing the lcs(es)
sub findLeastCommonSubsumer {   

    my $self = shift;
    my $concept1 = shift;
    my $concept2 = shift;
    
    my $array = $pathfinder->_findLeastCommonSubsumer($concept1, $concept2);

    return $array;
}    

#####################################################################
#  methods located in ICFinder.pm
#####################################################################

#  sets the propagation counts 
#  input : $hash <- reference to hash containing parameters
#                   debug         -> turn debug option on 
#                   icpropagation -> file containing icpropagation counts
#                   icfrequency   -> file containing icfrequency counts
#                   smooth        -> whether you want to smooth the 
#                                    the frequency counts
sub setPropagationParameters {
    
    my $self       = shift;
    my $parameters = shift;
    
    $icfinder->_setPropagationParameters($parameters);
}

#  returns the information content of a given cui
#  input : $concept <- string containing a cui
#  output: $double  <- double containing its IC
sub getIC {
    my $self     = shift;
    my $concept  = shift;
    
    my $ic = $icfinder->_getIC($concept);

    return $ic;    
}

#  returns the probability of a given cui
#  input : $concept <- string containing a cui
#  output: $double  <- double containing its probability
sub getProbability {
    my $self     = shift;
    my $concept  = shift;
    
    my $prob = $icfinder->_getProbability($concept);

    return $prob;
}

#  returns the total number of CUIs (N)
#  input : 
#  output: $int  <- integer containing frequency
sub getN {
    my $self     = shift;
    
    my $n = $icfinder->_getN();

    return $n;
}

#  returns the propagation count (frequency) of a given cui
#  input : $concept <- string containing a cui
#  output: $double  <- double containing its frequency
sub getFrequency {
    my $self     = shift;
    my $concept  = shift;
    
    my $ic = $icfinder->_getFrequency($concept);

    return $ic;    
}

#  returns all of the cuis to be propagated given the sources
#  and relations specified by the user in the configuration file
#  input :
#  output: $hash <- reference to hash containing the cuis
sub getPropagationCuis
{
    my $self = shift;
    
    my $hash = $icfinder->_getPropagationCuis();

    return $hash;
    
}

#  check that the parameters in config file match
#  input : $string1 <- string containing parameter
#          $string2 <- string containing configuratation parameter
#  output: 0|1      <- true or false
sub checkParameters {
    my $self = shift;
    my $string1 = shift;
    my $string2 = shift;
    
    return $icfinder->_checkParameters($string1, $string2);
}

#  check that the parameters in config file match
#  input : $string <- string containing relation configuration parameter
#  output: 0|1      <- true or false
sub checkHierarchicalRelations {
    my $self   = shift;
    my $string = shift;
    
    return $icfinder->_checkHierarchicalRelations($string);
}

#  propagates the given frequency counts
#  input : $hash <- reference to the hash containing 
#                   the frequency counts
#  output: $hash <- containing the propagation counts of all
#                   the cuis given the sources and relations
#                   specified in the configuration file
sub propagateCounts
{

    my $self = shift;
    my $fhash = shift;
    
    my $hash = $icfinder->_propagateCounts($fhash);

    return $hash;
}

#####################################################################
#  methods located in STFinder.pm
#####################################################################
#  returns the minimum depth of a semantic type in the network
#  input : $st  <- string containing the semantic type
#  output: $int <- minimum depth of hte semantic type
#sub getMinStDepth {
#    my $self = shift;
#    my $st   = shift;
#    
#    my $depth = $stfinder->_getMinDepth($st);
#
#    return $depth;
#}

#  returns the maximum depth of a semantic type in the network
#  input : $st  <- string containing the semantic type
#  output: $int <- maximum depth of hte semantic type
#sub getMaxStDepth {
#    my $self = shift;
#    my $st   = shift;
#    
#    my $depth = $stfinder->_getMaxDepth($st);
#
#    return $depth;
#}

#  load the propagation hash
#  input : $hash  <- reference to a hash containin probability counts
#  output: 
sub loadStPropagationHash {
    my $self = shift;
    my $hash = shift;
    
    $stfinder->_loadStPropagationHash($hash);
}

#  returns the information content of a given semantic type
#  input : $concept <- string containing a semantic type
#  output: $double  <- double containing its IC
sub getStIC {
    my $self = shift;
    my $st   = shift;
    
    my $ic = $stfinder->_getStIC($st);

    return $ic;    
}

#  returns the probability of a given semantic type
#  input : $concept <- string containing a semantic type
#  output: $double  <- double containing its probability
sub getStProbability {
    my $self     = shift;
    my $st       = shift;
    
    my $prob = $stfinder->_getStProbability($st);

    return $prob;
}

#  propagates the given frequency counts of the semantic types
#  input : $hash <- reference to the hash containing 
#                   the frequency counts
#  output: $hash <- containing the propagation counts of all
#                   the semantic types
sub propagateStCounts
{

    my $self = shift;
    my $fhash = shift;
    
    my $hash = $stfinder->_propagateStCounts($fhash);

    return $hash;
}

#  returns the total number of semantic types (N)
#  input : 
#  output: $int  <- double containing frequency
sub getStN {
    my $self     = shift;
    
    my $n = $stfinder->_getStN();

    return $n;
}
#  method to set the smoothing parameter
#  input  
#  output: 
sub setStSmoothing
{
    my $self      = shift;
    
    $stfinder->_setStSmoothing();
    
}

#  method to find all the paths from a semantic type (tui) to 
#  the root node of the is-a taxonomy in the semantic network
#  input : $tui     <- string containing tui
#  output: $array   <- array reference containing the paths
sub stPathsToRoot
{
    my $self  = shift;
    my $tui   = shift;

    my $array = $stfinder->_pathsToRoot($tui);

    return $array;  
}


#  this function returns the shortest path between two semantic type TUIs
#  input : $st1   <- string containing the first tui
#          $st2   <- string containing the second tui
#  output: $array <- reference to an array containing paths
sub stFindShortestPath 
{
    my $self = shift;
    my $st1  = shift;
    my $st2  = shift;
    
    my $array = $stfinder->_findShortestPath($st1, $st2);
    
    return $array;
}

1;

__END__

=head1 NAME

UMLS::Interface - Perl interface to the Unified Medical Language System (UMLS)

=head1 SYNOPSIS

 use UMLS::Interface;

 $umls = UMLS::Interface->new(); 

 die "Unable to create UMLS::Interface object.\n" if(!$umls); 

 my $root = $umls->root();

 my $term1    = "skull";

 my $tList1   = $umls->getConceptList($term1);
 my $cui1     = pop @{$tList1};

 my $term2    = "hand";
 my $tList2   = $umls->getDefConceptList($term2);

 my $cui2     = shift @{$tList2};
 my $exists1  = $umls->exists($cui1);
 my $exists2  = $umls->exists($cui2);

 if($exists1) { print "The concept $term1 ($cui1) exists in your UMLS view.\n"; }
 else         { print "The concept $term1 ($cui1) does not exist in your UMLS view.\n"; }

 if($exists2) { print "The concept $term2 ($cui2) exists in your UMLS view.\n"; }
 else         { print "The concept $term2 ($cui2) does not exist in your UMLS view.\n"; }
 print "\n";

 my $cList1   = $umls->getTermList($cui1);
 my $cList2   = $umls->getDefTermList($cui2);

 print "The terms associated with $term1 ($cui1) using the SAB parameter:\n";
 foreach my $c1 (@{$cList1}) {
    print " => $c1\n";
 } print "\n";

 print "The terms associated with $term2 ($cui2) using the SABDEF parameter:\n";
 foreach my $c2 (@{$cList2}) {
    print " => $c2\n";
 } print "\n";

 my $lcs = $umls->findLeastCommonSubsumer($cui1, $cui2);
 print "The least common subsumer between $term1 ($cui1) and ";
 print "$term2 ($cui2) is @{$lcs}\n\n";

 my $shortestpath = $umls->findShortestPath($cui1, $cui2);
 print "The shortest path between $term1 ($cui1) and $term2 ($cui2):\n";
 print "  => @{$shortestpath}\n\n";

 my $pathstoroot   = $umls->pathsToRoot($cui1);
 print "The paths from $term1 ($cui1) and the root:\n";
 foreach  $path (@{$pathstoroot}) {
    print "  => $path\n";
 } print "\n";

 my $mindepth = $umls->findMinimumDepth($cui1);
 my $maxdepth = $umls->findMaximumDepth($cui1);
 print "The minimum depth of $term1 ($cui1) is $mindepth\n";
 print "The maximum depth of $term1 ($cui1) is $maxdepth\n\n";

 my $children = $umls->getChildren($cui2); 
 print "The child(ren) of $term2 ($cui2) are: @{$children}\n\n";

 my $parents = $umls->getParents($cui2);
 print "The parent(s) of $term2 ($cui2) are: @{$parents}\n\n";

 my $relations = $umls->getRelations($cui2);
 print "The relation(s) of $term2 ($cui2) are: @{$relations}\n\n";

 my $rels = $umls->getRelated($cui2, "PAR");
 print "The parents(s) of $term2 ($cui2) are: @{$rels}\n\n";

 my $definitions = $umls->getCuiDef($cui1);
 print "The definition(s) of $term1 ($cui1) are:\n";
 foreach $def (@{$definitions}) {
    print "  => $def\n"; $i++;
 } print "\n";

 my $sabs = $umls->getSab($cui1);

 print "The sources containing $term1 ($cui1) are: @{$sabs}\n\n";

 print "The semantic type(s) of $term1 ($cui1) and the semantic\n";

 print "definition are:\n";
 my $sts = $umls->getSt($cui1);
 foreach my $st (@{$sts}) {

    my $abr = $umls->getStAbr($st);
    my $string = $umls->getStString($abr);
    my $def    = $umls->getStDef($abr);
    print "  => $string ($abr) : @{$def}\n";

 } print "\n";

 my $cell = "T025";
 my $bpoc = "T023";

 my $paths = $umls->stPathsToRoot($cell);
 print "The paths between cell ($cell) and the root:\n"; 
 foreach my $path (@{$paths}) { 
    print " => $path\n";
 } print "\n\n";

 my $spaths = $umls->stFindShortestPath($cell, $bpoc);
 print "The paths between cell ($cell) and bpoc ($bpoc): \n";
 foreach my $path (@{$spaths}) { 
    print " => $path\n";
 }

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

=head1 DATABASE SETUP

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

=head1 INITIALIZING THE MODULE

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

=head1 PARAMETERS

You can also pass other parameters which controls the functionality 
of the Interface.pm module. 

    $umls = UMLS::Interface->new({"forcerun"      => "1",
				  "realtime"      => "1",
				  "cuilist"       => "file",  
				  "verbose"       => "1", 
                                  "debugpath"     => "file"});

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

  'debugpath'    -> This prints out the path information to a file during
                    any of the realtime runs


You can also reconfigure these options by calling the reConfig 
method. 

    $umls->reConfig({"forcerun"      => "1",
		     "realtime"      => "1",
		     "verbose"       => "1", 
                     "debugpath"     => "file"});


=head1 CONFIGURATION FILE

There exist a configuration files to specify which source and what 
relations are to be used. The default source is the Medical Subject 
Heading (MSH) vocabulary and the default relations are the PAR/CHD 
relation. 

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

RELA :: <include|exclude> <rela1, rela2, ... relaN> 

SABDEF :: <include|exclude> <source1, source2, ... sourceN>

RELDEF :: <include|exclude> <relation1, relation2, ... relationN>

The SAB, REL and RELA are for specifing what sources and relations 
should be used when traversing the UMLS. For example, if we 
wanted to use the MSH vocabulary with only the RB/RN relations 
that have been identified as 'isa' RELAs, then the configuration 
file would be:

SAB :: include MSH
REL :: include RB, RN
RELA :: include inverse_isa, isa

if we did not care what type of RELA the RB/RN relations were the 
configuration would be:

SAB :: include MSH
REL :: include RB, RN


if we wanted to use MSH and use any relation except for PAR/CHD, 
the configuration would be:

SAB :: include MSH
REL :: exclude PAR, CHD

The SABDEF and RELDEF are for obtaining a definition or extended 
definition of the CUI. SABDEF signifies which sources to extract 
the definition from. For example, 

SABDEF :: include SNOMEDCT

would only return definitions that exist in the SNOMEDCT source.
where as:

SABDEF :: exclude SNOMEDCT

would use the definitions from the entire UMLS except for SNOMEDCT.
The default, if you didn't specify SABDEF at all in the configuration 
file, would use the entire UMLS. 

The RELDEF is from the extended definition. It signifies which 
relations should be included when creating the extended definition 
of a given CUI. For example, 

RELDEF :: include TERM, CUI, PAR, CHD, RB, RN

This would include in the definition the terms associated with 
the CUI, the CUI's definition and the definitions of the concepts 
related to the CUI through either a PAR, CHD, RB or RN relation. 
Similarly, using the exclude as in:

RELDEF :: exclude TERM, CUI, PAR, CHD, RB, RN

would use all of the relations except for the one's specified. If 
RELDEF is not specified the default uses all of the relations which 
consist of: TERM, CUI, PAR, CHD, RB, RN, RO, SYN, and SIB.

I know that TERM and CUI are not 'relations' but we needed a way to
specify them and this seem to make the most sense at the time.

An example of the configuration file can be seen in the samples/ directory. 

=head1 REFERENCING

    If you write a paper that has used UMLS-Interface in some way, we'd 
    certainly be grateful if you sent us a copy and referenced UMLS-Interface. 
    We have a published paper that provides a suitable reference:

    @inproceedings{McInnesPP09,
       title={{UMLS-Interface and UMLS-Similarity : Open Source 
               Software for Measuring Paths and Semantic Similarity}}, 
       author={McInnes, B.T. and Pedersen, T. and Pakhomov, S.V.}, 
       booktitle={Proceedings of the American Medical Informatics 
                  Association (AMIA) Symposium},
       year={2009}, 
       month={November}, 
       address={San Fransico, CA}
    }

    This paper is also found in
    <http://www-users.cs.umn.edu/~bthomson/publications/pubs.html>
    or
    <http://www.d.umn.edu/~tpederse/Pubs/amia09.pdf>

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

 Ying Liu, University of Minnesota
 liux0935 at umn.edu

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
