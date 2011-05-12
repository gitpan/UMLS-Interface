#!/usr/bin/perl 

=head1 NAME

reConfigTest.pl - 

    This program returns the shortest path length between two 
    CUIs (or terms) using different sources in order to test 
    the reConfig method in the Interface.pm module

=head1 SYNOPSIS

This program takes in a term and returns all of its associated CUIs
from two different sources

=head1 USAGE

Usage: reConfigTest.pl [OPTIONS} [CUI1|TERM1] [CUI2|TERM2]

=head1 INPUT

=head2 Required Arguments:


=head3 [CUI1|TERM1] [CUI2|TERM2]

A TERM or CUI (or some combination) from the Unified 
Medical Language System

=head2 Optional Arguments:

=head3 --debug

Sets the debug flag for testing

=head3 --username STRING

Username is required to access the umls database on MySql
unless it was specified in the my.cnf file at installation

=head3 --password STRING

Password is required to access the umls database on MySql
unless it was specified in the my.cnf file at installation

=head3 --hostname STRING

Hostname where mysql is located. DEFAULT: localhost

=head3 --socket STRING

The socket your mysql is using. DEFAULT: /tmp/mysql.sock

=head3 --database STRING        

Database contain UMLS DEFAULT: umls

=head3 --realtime

This option will not create a database of the path information
for all of concepts in the specified set of sources and relations 
in the config file but obtain the information for just the 
input concept

=head3 --forcerun

This option will bypass any command prompts such as asking 
if you would like to continue with the index creation. 

=head3 --verbose

This option will print out the table information to the 
config directory that you specified.

=head3 --help

Displays the quick summary of program options.

=head3 --version

Displays the version information.

=head1 OUTPUT

The path(s) between the two given CUIs or terms

=head1 SYSTEM REQUIREMENTS

=over

=item * Perl (version 5.8.5 or better) - http://www.perl.org

=back

=head1 AUTHOR

 Bridget T. McInnes, University of Minnesota

=head1 COPYRIGHT

Copyright (c) 2007-2009,

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
this program; if not, write to:

 The Free Software Foundation, Inc.,
 59 Temple Place - Suite 330,
 Boston, MA  02111-1307, USA.

=cut

###############################################################################

#                               THE CODE STARTS HERE
###############################################################################

#                           ================================
#                            COMMAND LINE OPTIONS AND USAGE
#                           ================================

use UMLS::Interface;
use Getopt::Long;

eval(GetOptions( "version", "help", "debug", "username=s", "password=s", "hostname=s", "database=s", "socket=s")) or die ("Please check the above mentioned option(s).\n");


#  if help is defined, print out help
if( defined $opt_help ) {
    $opt_help = 1;
    &showHelp();
    exit;
}

#  if version is requested, show version
if( defined $opt_version ) {
    $opt_version = 1;
    &showVersion();
    exit;
}

# At least 1 term should be given on the command line.
if(scalar(@ARGV) < 2) {
    print STDERR "Two terms and/or CUIs are required\n";
    &minimalUsageNotes(); 
    exit;
}

my $database = "umls";
if(defined $opt_database) { $database = $opt_database; }
my $hostname = "localhost";
if(defined $opt_hostname) { $hostname = $opt_hostname; }
my $socket   = "/tmp/mysql.sock";
if(defined $opt_socket)   { $socket   = $opt_socket;   }

my $umls = "";
my %option_hash = ();

if(defined $opt_debug) {
    $option_hash{"debug"} = $opt_debug;
}
if(defined $opt_verbose) {
    $option_hash{"verbose"} = $opt_verbose;
}
if(defined $opt_username) {
    $option_hash{"username"} = $opt_username;
}
if(defined $opt_driver) {
    $option_hash{"driver"}   = "mysql";
}
if(defined $opt_database) {
    $option_hash{"database"} = $database;
}
if(defined $opt_password) {
    $option_hash{"password"} = $opt_password;
}
if(defined $opt_hostname) {
    $option_hash{"hostname"} = $hostname;
}
if(defined $opt_socket) {
    $option_hash{"socket"}   = $socket;
}

#  set the configuration files
open(CONFIG1, ">config1") || die "Could not open config file (config1)\n";
open(CONFIG2, ">config2") || die "Could not open config file (config2)\n";
open(CONFIG3, ">config3") || die "Could not open config file (config3)\n";

print CONFIG1 "SAB :: include MSH\n";
print CONFIG1 "REL :: include PAR, CHD\n";

print CONFIG2 "SAB :: include SNOMEDCT\n";
print CONFIG2 "REL :: include PAR, CHD\n";

print CONFIG3 "SABDEF :: include UMLS_ALL\n";
print CONFIG3 "RELDEF :: include CUI\n";

close CONFIG1;
close CONFIG3;
close CONFIG3;

#  use the first config file
$option_hash{"config"} = "config1";

print "Processing config file:\n";
#system "cat config1";
$umls = UMLS::Interface->new(\%option_hash); 
die "Unable to create UMLS::Interface object.\n" if(!$umls);

my $i1 = shift;
my $i2 = shift;

&getLength($i1, $i2);

print "Processing config file:\n";
#system "cat config2";
$option_hash{"config"} = "config2";
$umls->reConfig(\%option_hash);

&getLength($i1, $i2);


print "Processing config file:\n";
#system "cat config3";
$option_hash{"config"} = "config3";
$umls->reConfig(\%option_hash);

&getDef($i1);
print "\n\n";
&getDef($i2);


sub getDef {

    my $input = shift;
    my $term  = $input;
    
    my @c = ();
    if($input=~/C[0-9]+/) {
	push @c, $input;
	($term) = $umls->getDefTermList($input);
    }
    else {
    @c = $umls->getConceptList($input);
    }
    
    my $printFlag = 0;
    
    foreach my $cui (@c) {
	
	my $rdef = $umls->getExtendedDefinition($cui); 
	my @defs = @{$rdef}; 
	
	if($#defs >= 0) {
	    print "The definition(s) of $term ($cui):\n";
	    my $i = 1;
	    foreach $def (@defs) {
		print "  $i. $def\n"; $i++;
	    }
	}
	else {
	    print "There are no definitions for $term ($cui)\n";
	}
    }	
}



sub getLength
{
    my $input1 = shift;
    my $input2 = shift;
    
    my $flag1 = "cui";
    my $flag2 = "cui";

    my @c1 = ();
    my @c2 = ();

    #  check if the input are CUIs or terms
    if( ($input1=~/C[0-9]+/)) {
	push @c1, $input1;
    }
    else {
	@c1 = $umls->getConceptList($input1); 
	$flag1 = "term";
    }
    if( ($input2=~/C[0-9]+/)) {
	push @c2, $input2; 
    }
    else {
	@c2 = $umls->getConceptList($input2); 
	$flag2 = "term";
    }
    
    
    my $printFlag = 0;
    my $precision = 4;      
    my $floatformat = join '', '%', '.', $precision, 'f';    
    foreach $cui1 (@c1) {
	foreach $cui2 (@c2) {
	   
	    if(! ($umls->exists($cui1)) ) { next; }
	    if(! ($umls->exists($cui2)) ) { next; }
		    
	    my $t1 = $input1;
	    my $t2 = $input2;
	    
	    if($flag1 eq "cui") { ($t1) = $umls->getTermList($cui1); }
	    if($flag2 eq "cui") { ($t2) = $umls->getTermList($cui2); }

	    my $length = -1;
	    if($cui1 eq $cui2) { 
		$length = 1;
	    }
	    else {
		$length = $umls->findShortestPathLength($cui1, $cui2);
	    }
	    
	    print "\nThe length of the shortest path between $t1 ($cui1) and $t2 ($cui2) is $length\n";
	}
    }
}

##############################################################################
#  function to output minimal usage notes
##############################################################################
sub minimalUsageNotes {
    
    print "Usage: reConfigTest.pl [OPTIONS] TERM \n";
    &askHelp();
    exit;
}

##############################################################################
#  function to output help messages for this program
##############################################################################
sub showHelp() {

        
    print "This is a utility that takes as input a term\n";
    print "and returns all of its possible CUIs.\n\n";
  
    print "Usage: reConfigTest.pl [OPTIONS] TERM\n\n";

    print "Options:\n\n";
    
    print "--sab                    Prints out the source of the CUI\n\n";

    print "--debug                  Sets the debug flag for testing\n\n";

    print "--username STRING        Username required to access mysql\n\n";

    print "--password STRING        Password required to access mysql\n\n";

    print "--hostname STRING        Hostname for mysql (DEFAULT: localhost)\n\n";

    print "--database STRING        Database contain UMLS (DEFAULT: umls)\n\n";
    
    print "--socket STRING          Socket used by mysql (DEFAULT: /tmp.mysql.sock)\n\n";

    print "--config FILE            Configuration file\n\n";

    print "--version                Prints the version number\n\n";
 
    print "--help                   Prints this help message.\n\n";
}

##############################################################################
#  function to output the version number
##############################################################################
sub showVersion {
    print '$Id: reConfigTest.pl,v 1.1 2011/01/21 19:49:57 btmcinnes Exp $';
    print "\nCopyright (c) 2008, Ted Pedersen & Bridget McInnes\n";
}

##############################################################################
#  function to output "ask for help" message when user's goofed
##############################################################################
sub askHelp {
    print STDERR "Type reConfigTest.pl --help for help.\n";
}
    
