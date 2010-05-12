# UMLS::Interface 
# (Last Updated $Id: ICFinder.pm,v 1.4 2010/05/11 20:29:07 btmcinnes Exp $)
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

package UMLS::ICFinder;

use Fcntl;
use strict;
use warnings;
use DBI;
use bytes;

use UMLS::CuiFinder;

my $root = "";

my $debug = 0;

my %propagationFreq  = ();
my %propagationHash  = ();

my $propagationFile  = "";
my $frequencyFile    = "";

my $option_propagation = 0;
my $option_frequency   = 0;
my $option_t           = 0;

my $smooth             = 1;

# UMLS-specific stuff ends ----------

# -------------------- Class methods start here --------------------

#  method to create a new UMLS::PathFinder object
sub new {
    my $self = {};
    my $className = shift;
    my $paramHash = shift;
    my $cuifinder = shift;
    
    # Initialize Error String and Error Code.
    $self->{'errorString'} = "";
    $self->{'errorCode'} = 0;

    # Bless the object.
    bless($self, $className);

    # Initialize the object.
    $self->_initialize($paramHash, $cuifinder);

    return $self;
}

# Method to initialize the UMLS::Interface object.
sub _initialize
{
    my $self      = shift;
    my $params    = shift;
    my $cuifinder = shift;

    return undef if(!defined $self || !ref $self);
    
    $params = {} if(!defined $params);

    #  set function name
    my $function = "_initialize";

    #  check the cuifinder
    if(!$cuifinder) { 
	return($self->_error($function, "No UMLS::CuiFinder")); 
    } $self->{'cuifinder'} = $cuifinder;
    
    #  get the umlsinterfaceindex database from CuiFinder
    my $sdb = $cuifinder->getIndexDB();
    if(!$sdb) { 
	return($self->_error($function, "No db sent from UMLS::CuiFinder")); 
    } $self->{'sdb'} = $sdb;

    #  get the root
    $root = $cuifinder->root();

    #  set up the options
    $self->_setOptions($params);
    if($self->checkError($function)) { return (); }	

    #  load the propagation hash if the option is specified
    if($option_propagation) { 
	$self->_loadPropagationHash();
    }

}


#  print out the function name to standard error
#  input : $function <- string containing function name
#  output: 
sub _debug {
    my $function = shift;
    if($debug) { print STDERR "In UMLS::ICFinder::$function\n"; }
}

#  method to set the global parameter options
#  input : $params <- reference to a hash
#  output: 
sub _setOptions 
{
    my $self = shift;
    my $params = shift;
    
    return undef if(!defined $self || !ref $self);

    my $function = "_setOptions";

    #  get all the parameters
    my $debugoption  = $params->{'debug'};
    my $t            = $params->{'t'};
    my $propagation  = $params->{'icpropagation'};
    my $frequency    = $params->{'icfrequency'};

    my $output = "";

    #  check if options have been defined
    if(defined $propagation || defined $frequency || 
       defined $debugoption) { 
	$output .= "\nICFinder User Options:\n";
    }

    #  check if the debug option has been been defined
    if(defined $debugoption) {
	$debug = 1; 
	$output .= "   --debug option set\n";
    }
    
    #  check if the propagation option has been identified
    if(defined $propagation) {
	$option_propagation = 1;
	$propagationFile    = $propagation;
	$output .= "  --propagation $propagation\n";
    }

    #  check if the frequency option has been identified
    if(defined $frequency) { 
	$option_frequency = 1;
	$frequencyFile    = $frequency;
	$output .= "  --frequency $frequency\n";
    }

    &_debug($function);
      
    if(defined $t) {
	$option_t = 1;
    }
    else {
	print STDERR "$output\n";
    }    
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
        
    $self->{'errorString'} .= "\nError (UMLS::PathFinder->$function()) - ";
    $self->{'errorString'} .= $string;
    $self->{'errorCode'} = 2;

}

#  check error function to determine if an error happened within a function
#  input : $function <- string containing name of function
#  output: 0|1 indicating if an error has been thrown 
sub checkError {
    my $self     = shift;
    my $function = shift;
   
    my $code = $self->{'errorCode'}; 
    
    my $sdb = $self->{'sdb'};
    if($sdb->err()) { 
	$self->_error($function, 
		      "Error executing database query: ($sdb->errstr())");
	return 1;
    }
    
    if($code == 2) { return 1; }
    else           { return 0; }
}

#  method that returns the error string and error code from the 
#  last method call on the object.
#  input : 
#  output: $returnCode, $returnString <- strings containing 
#                                        error information
sub getError {
    my $self      = shift;

    my $returnCode = $self->{'errorCode'};
    my $returnString = $self->{'errorString'};

    $returnString =~ s/^\n+//;

    return ($returnCode, $returnString);
}

#  method sets the error - this is for when we call
#  something in another pm module we can propagate
#  that erro back through the program
#  input : $handler
#  output: 
sub setError {
    my $self = shift;
    my $handler = shift;

    my $function = "setError";
    &_debug($function);
    
    #  set the cuifinder 
    
    my ($returnCode, $returnString) = $handler->getError();
    
    $self->{'returnCode'}   = $returnCode;
    $self->{'returnString'} = $returnString;
}

 
#  returns the information content (IC) of a cui
#  input : $concept <- string containing a cui
#  output: $double  <- double containing its IC
sub getIC
{
    my $self     = shift;
    my $concept  = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "getIC";
    &_debug($function);

    #  check concept was obtained
    if(!$concept) { 
	return($self->_error($function, "Undefined input values.")); 
    }
    
    #  set the cuifinder 
    my $cuifinder = $self->{'cuifinder'};
    if(!$cuifinder) { 
	return($self->_error($function, "UMLS::CuiFinder not defined.")); 
    }
    
    #  check valid concept
    if($cuifinder->validCui($concept)) { 
	return($self->_error($function, "Incorrect input value ($concept).")); 
    }
    
       
    #  if option frequency then the propagation hash 
    #  hash has not been loaded and we should determine
    #  the information content of the concept using the
    #  frequency information in the file in realtime
    if($option_frequency) { 
	
	#  initialize the propagation hash
	$self->_initializePropagationHash();
	
	#  load the propagation frequency hash
	$self->_loadPropagationFreq();
	
	#  propogate the counts
	&_debug("_propagation");
	my @array = ();
	$self->_propagation($concept, \@array);
	
	#  tally up the propagation counts
	$self->_tallyCounts();
    }
    
    my $prob = $propagationHash{$concept};
    
    if(!defined $prob) { return 0; }

    return ($prob > 0 and $prob < 1) ? -log($prob) : 0;
}

#  this method obtains the CUIs in the sources which 
#  are going to be propagated
#  input :
#  output: $hash <- reference to hash containing the cuis
sub getPropagationCuis
{
    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "getPropagationCuis";
    &_debug($function);
    
    #  set the cuifinder 
    my $cuifinder = $self->{'cuifinder'};
    if(!$cuifinder) { 
	return($self->_error($function, "UMLS::CuiFinder not defined.")); 
    }
    
    #  get the hash
    my $hash = $cuifinder->getCuiList();

    #  make certain there weren't any problems
    if($self->checkError($cuifinder)) { 
	$self->setError($cuifinder);
	return; 
    }
    
    return $hash;
}

#  initialize the propgation hash
#  input :
#  output:
sub _initializePropagationHash
{
    my $self = shift;

    return undef if(!defined $self || !ref $self);
    
    my $function = "_initializePropagationHash";
    &_debug($function);
    
    #  clear out the hash just in case
    my $hash = $self->getPropagationCuis();
        
    if($debug) { print STDERR "SMOOTH: $smooth\n"; }

    #  add the cuis to the propagation hash
    foreach my $cui (sort keys %{$hash}) { 
	$propagationHash{$cui} = "";
	$propagationFreq{$cui} = $smooth;
    }
}

#  load the propagation frequency has with the frequency counts
#  input : $hash <- reference to hash containing frequency counts
#  output:
sub _loadPropagationFreq
{
    my $self = shift;
    my $fhash = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_loadPropagationFreq";
    &_debug($function);

    #  loop through and set the frequency count
    my $N = 0;    
    foreach my $cui (sort keys %{$fhash}) {
	my $freq = ${$fhash}{$cui};
	if(exists $propagationFreq{$cui}) {
	    $propagationFreq{$cui} += $freq;
	}
	$N+= $freq;
    }
    

    #  check if something has been set
    if($smooth == 1) { 
	my $pkeys = keys %propagationFreq;
	$N += $pkeys;
    }
    
    #  loop through again and set the probability
    foreach my $cui (sort keys %propagationFreq) { 
	$propagationFreq{$cui} = $propagationFreq{$cui} / $N;
    }
}

#  load the propagation hash
#  input :
#  output: 
sub _loadPropagationHash
{
    my $self = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "_loadPropagationHash";
    &_debug($function);

    open(FILE, $propagationFile) || die "Could not open file $propagationFile\n";
    while(<FILE>) {
	chomp;
	my ($cui, $freq) = split/<>/;
	if(! (exists $propagationHash{$cui})) { 
	    $propagationHash{$cui} = 0;
	}

	$propagationHash{$cui} += $freq;
    }
}

#  get the propagation count for a given cui
#  input : $concept   <- string containing the cui
#  output: $double|-1 <- the propagation count otherwise
#                        a -1 if none existed for that cui
sub getPropagationCount
{
    my $self = shift;
    my $concept = shift;

    my $function = "getPropagationCount";
    &_debug($function);

    $self->_propagateCounts();

    #  check concept was obtained
    if(!$concept) { 
	return($self->_error($function, "Undefined input values.")); 
    }
    
    #  set the cuifinder 
    my $cuifinder = $self->{'cuifinder'};
    if(!$cuifinder) { 
	return($self->_error($function, "UMLS::CuiFinder not defined.")); 
    }
    
    #  check valid concept
    if($cuifinder->validCui($concept)) { 
	return($self->_error($function, "Incorrect input value ($concept).")); 
    }

    #  if the concept exists in the propagation hash 
    #  return the probability otherwise return a -1
    if(exists $propagationHash{$concept}) {
	return $propagationHash{$concept};
    }
    else {
	return -1;
    }

}

#  method which actually propagates the counts
#  input : $hash <- reference to the hash containing 
#                   the frequency counts
#  output: 
sub propagateCounts
{

    my $self = shift;    
    my $fhash = shift;
    
    return undef if(!defined $self || !ref $self);
    
    my $function = "propagateCounts";
    &_debug($function);
    
    #  initialize the propagation hash
    $self->_initializePropagationHash();
    
    #  load the propagation frequency hash
    $self->_loadPropagationFreq($fhash);
    
    #  propagate the counts
    my @array = ();
    $self->_propagation($root, \@array);
    
    #  tally up the propagation counts
    $self->_tallyCounts();

    my $k = keys %propagationHash;
    print STDERR "key: $k\n";
    
    #  return the propagation counts
    return \%propagationHash;
}

#  method that tallys up the probability counts of the
#  cui and its decendants and then calculates the ic
#  input :
#  output: 
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

#  recursive method that acuatlly performs the propagation
#  input : $concept <- string containing the cui
#          $array   <- reference to the array containing
#                      the cui's decendants
#  output: $concept <- string containing the cui
#          $array   <- reference to the array containing
#                      the cui's decendants
sub _propagation
{
    my $self    = shift;
    my $concept = shift;
    my $array   = shift;

    my $function = "_propagation";
    
   #  check concept was obtained
    if(!$concept) { 
	return($self->_error($function, "Undefined input values.")); 
    }
    
    #  set the cuifinder 
    my $cuifinder = $self->{'cuifinder'};
    if(!$cuifinder) { 
	return($self->_error($function, "UMLS::CuiFinder not defined.")); 
    }
    
    #  check valid concept
    if($cuifinder->validCui($concept)) { 
	return($self->_error($function, "Incorrect input value ($concept).")); 
    }
 
    #  if the concept is inactive
    if($cuifinder->_forbiddenConcept($concept)) { return; }
       
    #  set up the new path
    my @intermediate = @{$array};
    push @intermediate, $concept;
    my $series = join " ", @intermediate;

    #  initialize the set
    my $set = $propagationHash{$concept};

    #  if the propagation hash already contains a list of CUIs it
    #  is from its decendants so it has been here before so all we 
    #  have to do is return the list of ancestors with it added
    if(defined $set) { 
	if(! ($set=~/^\s*$/)) { 
	    $set .= " $concept";
	    return $set; 
	}
    }

    #  get all the children
    my @children = $cuifinder->getChildren($concept);
    if($cuifinder->checkError("UMLS::CuiFinder::getChildren")) { return (); }
    
    #  search through the children   
    foreach my $child (@children) {

	my $flag = 0;
	
	#  check that the concept is not one of the forbidden concepts
	if($cuifinder->_forbiddenConcept($child)) { $flag = 1; }
	
	#  check if child cui has already in the path
	foreach my $cui (@intermediate) {
	    if($cui eq $child) { $flag = 1; }
	}
	
	#  if it isn't continue on with the depth first search
	if($flag == 0) {  
	    $set .= " ";
	    $set .= $self->_propagation($child, \@intermediate);    
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


1;

__END__

=head1 NAME

UMLS::CuiFinder - Perl interface to support the UMLS::Interface.pm which 
is an interface to the Unified Medical Language System (UMLS). 

=head1 SYNOPSIS

see UMLS::Interface.pm

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

