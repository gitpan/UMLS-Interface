# UMLS::Interface::ICFinder
# (Last Updated $Id: ICFinder.pm,v 1.8 2010/06/08 15:35:11 btmcinnes Exp $)
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

package UMLS::Interface::ICFinder;

use Fcntl;
use strict;
use warnings;
use DBI;
use bytes;

use UMLS::Interface::CuiFinder;
use UMLS::Interface::ErrorHandler;

my $pkg = "UMLS::Interface::ICFinder";

my $root = "";

my $debug = 0;

my %propagationFreq  = ();
my %propagationHash  = ();

my $propagationFile  = "";
my $frequencyFile    = "";

my %frequencyHash = ();

my $option_icpropagation = 0;
my $option_icfrequency   = 0;
my $option_t           = 0;

my $smooth             = 0;

my $errorhandler = "";
my $cuifinder    = "";

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

    # initialize the object.
    $self->_initialize($params);

    return $self;
}

# Method to initialize the UMLS::Interface::ICFinder object.
sub _initialize
{
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

    #  load the propagation hash if the option is specified
    if($option_icpropagation) { 
	$self->_loadPropagationHash();
    }

    #  load hte frequency hash if hte option is specified
    if($option_icfrequency) { 
	$self->_loadFrequencyHash();
    }
}


#  print out the function name to standard error
#  input : $function <- string containing function name
#  output: 
sub _debug {
    my $function = shift;
    if($debug) { print STDERR "In UMLS::Interface::ICFinder::$function\n"; }
}

#  method to set the global parameter options
#  input : $params <- reference to a hash
#  output: 
sub _setOptions 
{
    my $self = shift;
    my $params = shift;
 
    my $function = "_setOptions";
    
    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }
 
    #  get all the parameters
    my $debugoption   = $params->{'debug'};
    my $t             = $params->{'t'};
    my $icpropagation = $params->{'icpropagation'};
    my $icfrequency   = $params->{'icfrequency'};
    my $icsmooth      = $params->{'smooth'};
  
    my $output = "";

    #  check if options have been defined
    if(defined $icpropagation || defined $icfrequency || 
       defined $debugoption   || defined $icsmooth) { 
	$output .= "\nICFinder User Options:\n";
    }

    #  check if the debug option has been been defined
    if(defined $debugoption) {
	$debug = 1; 
	$output .= "   --debug option set\n";
    }
    
    if(defined $icsmooth) {
	$smooth = $icsmooth;
	$output .= "  --smooth\n";
    }

    #  check if the propagation option has been identified
    if(defined $icpropagation) {
	$option_icpropagation = 1;
	$propagationFile    = $icpropagation;
	$output .= "  --icpropagation $icpropagation\n";
    }

    #  check if the frequency option has been identified
    if(defined $icfrequency) { 
	$option_icfrequency = 1;
	$frequencyFile    = $icfrequency;
	$output .= "  --icfrequency $icfrequency\n";
    }

    &_debug($function);
      
    if(defined $t) {
	$option_t = 1;
    }
    else {
	print STDERR "$output\n";
    }    
}

 
#  returns the information content (IC) of a cui
#  input : $concept <- string containing a cui
#  output: $double  <- double containing its IC
sub _getIC
{
    my $self     = shift;
    my $concept  = shift;

    my $function = "_getIC";
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
       
    #  if option frequency then the propagation hash 
    #  hash has not been loaded and we should determine
    #  the information content of the concept using the
    #  frequency information in the file in realtime
    if($option_icfrequency) { 
	
  	#  initialize the propagation hash
	$self->_initializePropagationHash();
	
	#  load the propagation frequency hash
	$self->_loadPropagationFreq(\%frequencyHash);
	
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
sub _loadFrequencyHash {

    my $self = shift;
    
    my $function = "_loadFrequencyHash";

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  open the frequency file
    open(FILE, $frequencyFile) || die "Could not open file $frequencyFile\n";

    #  the source  associated with the frequencyfile
    my $sab = <FILE>; chomp $sab;

    #  get the source in the config file (or the default)
    my $configsab = $cuifinder->_getSabString();

    #  check the source information is correct
    if($sab ne $configsab)  {
	my $str = "SAB information ($sab) does not match the config file ($configsab).";
	$errorhandler->_error($pkg, $function, $str, 5);
    }
        
    #  obtain the frequency counts storing them in the frequency hash table
    while(<FILE>) { 
	chomp;
	
	#  if blank line more on
	if($_=~/^\s*$/) { next; }

	#  get the cui and its frequency count
	my($cui, $freq) = split/<>/;
	
	#  make certain that it is a cui and a frequency
	#  and if it is load it into the frequency hash
	if( ($cui=~/C[0-9]/) && ($freq=~/[0-9]+/) ) { 
	    if(exists $frequencyHash{$cui}) { 
		$frequencyHash{$cui} += $freq;
	    }
	    else {
		$frequencyHash{$cui} = $freq;
	    }
	}
    }
    
    close(FILE);
}

#  this method obtains the CUIs in the sources which 
#  are going to be propagated
#  input :
#  output: $hash <- reference to hash containing the cuis
sub _getPropagationCuis {

    my $self = shift;
    
    my $function = "_getPropagationCuis";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  return the reference to a hash
    return $cuifinder->_getCuiList();
}

#  initialize the propgation hash
#  input :
#  output:
sub _initializePropagationHash {

    my $self = shift;

    my $function = "_initializePropagationHash";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }
    
    #  clear out the hash just in case
    my $hash = $self->_getPropagationCuis();
       
    #  add the cuis to the propagation hash
    foreach my $cui (sort keys %{$hash}) { 
	$propagationHash{$cui} = "";
	$propagationFreq{$cui} = $smooth;
    }
}

#  load the propagation frequency has with the frequency counts
#  input : $hash <- reference to hash containing frequency counts
#  output:
sub _loadPropagationFreq {

    my $self = shift;
    my $fhash = shift;
    
    my $function = "_loadPropagationFreq";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

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
	$propagationFreq{$cui} = ($propagationFreq{$cui}) / $N;
    }
}

#  load the propagation hash
#  input :
#  output: 
sub _loadPropagationHash {

    my $self = shift;
        
    my $function = "_loadPropagationHash";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  open the propagation file
    open(FILE, $propagationFile) || die "Could not open file $propagationFile\n";
    #  check if smoothing was set
    my $psmooth = <FILE>;
    
    #  the source and relations associated with the propagation file
    my $sab = <FILE>; chomp $sab;
    my $rel = <FILE>; chomp $rel;

    #  get the source and relations from config file or the defaults
    my $configsab = $cuifinder->_getSabString();
    my $configrel = $cuifinder->_getRelString();

    #  check the source information is correct
    if($sab ne $configsab )  {
	my $str = "SAB information ($sab) does not match the config file ($configsab).";
	$errorhandler->_error($pkg, $function, $str, 5);
    }
    
    #  check that that the relation information is correct
    if($rel ne $configrel)  {
	my $str = "REL information ($rel) does not match the config file ($configrel).";
	$errorhandler->_error($pkg, $function, $str, 5);
    }

    while(<FILE>) {
	chomp;

	#  if blank line move on
	if($_=~/^\s*$/) { next; }

	#  check if rela information was used
	if($_=~/RELA/) {
	    if($_ ne $cuifinder->_getRelaString()) {
		my $str = "RELA information does not match the config file ($_).";
		$errorhandler->_error($pkg, $function, $str, 5);
	    }
	}
	
	#  get the cui and its frequency count
	my ($cui, $freq) = split/<>/;

	#  load it into the propagation hash
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
sub _getPropagationCount {

    my $self = shift;
    my $concept = shift;

    my $function = "_getPropagationCount";
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

    #  propagate teh counts
    $self->_propagateCounts();

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
sub _propagateCounts {

    my $self = shift;    
    my $fhash = shift;
    
    my $function = "_propagateCounts";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

    #  check the parameters
    if(!defined $fhash) { 
	$errorhandler->_error($pkg, $function, "Input variable \%fhash  not defined.", 4);
    }

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
    
    #  return the propagation counts
    return \%propagationHash;
}

#  method that tallys up the probability counts of the
#  cui and its decendants and then calculates the ic
#  input :
#  output: 
sub _tallyCounts {

    my $self = shift;
    
    my $function = "_tallyCounts";
    &_debug($function);

    #  check self
    if(!defined $self || !ref $self) {
	$errorhandler->_error($pkg, $function, "", 2);
    }

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
sub _propagation {

    my $self    = shift;
    my $concept = shift;
    my $array   = shift;

    my $function = "_propagation";

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
    my @children = $cuifinder->_getChildren($concept);
    
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

#  removes duplicates in an array
#  input : $array <- reference to an array
#  output: 
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

UMLS::Interface::ICFinder  - provides the information content 
of the CUIs in the UMLS for the modules in the 
UMLS::Interface package.

=head1 DESCRIPTION

This package provides the information content of the CUIs in the 
UMLS for the modules in the UMLS::Interface package.

For more information please see the UMLS::Interface.pm 
documentation. 

=head1 SYNOPSIS

 #!/usr/bin/perl

 use UMLS::Interface::CuiFinder;

 use UMLS::Interface::ICFinder;

 %params = ();

 $cuifinder = UMLS::Interface::CuiFinder->new(\%params); 

 die "Unable to create UMLS::Interface::CuiFinder object.\n" if(!$cuifinder);

 $icfinder = UMLS::Interface::ICFinder->new(\%params, $cuifinder); 

 die "Unable to create UMLS::Interface::ICFinder object.\n" if(!$icfinder);

  $concept = "C0037303";

 $ic = $icfinder->_getIC($concept);

 $hash = $icfinder->_getPropagationCuis();

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

=head2 PROPAGATION

The Information Content (IC) is  defined as the negative log 
of the probability of a concept. The probability of a concept, 
c, is determine by summing the probability of the concept 
(P(c)) ocurring in some text plus the probability its decendants 
(P(d)) occuring in some text:

P(c*) = P(c) + \sum_{d\exists decendant(c)} P(d)

The initial probability of a concept (P(c)) and its decendants 
(P(d)) is obtained by dividing the number of times a concept is 
seen in the corpus (freq(d)) by the total number of concepts (N):

P(d) = freq(d) / N

Not all of the concepts in the taxonomy will be seen in the corpus. 
We have the option to use Laplace smoothing, where the frequency 
count of each of the concepts in the taxonomy is incremented by one. 
The advantage of doing this is that it avoides having a concept that 
has a probability of zero. The disadvantage is that it can shift the 
overall probability mass of the concepts from what is actually seen 
in the corpus. 

=head2 PROPAGATION IN REALTIME

The algorithm to determine the information content of a CUI in real 
time is as follows:

        1. get all of its decendants using the DFS

        2. looping through the frequency file computing the 
           probability of the decendants and storing this 
           information

        3. sum the probability of the decedants and the CUI 

        4. calculate the IC which is defined as the negative log of 
           the probabilty of the concept (which is the sum from
           step 3)


In order to run the propagation in real time, we require the frequency 
counts of a list of CUIs to be given to us. 

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

