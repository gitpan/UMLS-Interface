#!/usr/bin/perl 

=head1 NAME

getRelated.pl - This programs returns all CUIs of a given relation.

=head1 SYNOPSIS

This program takes in a CUI or a term and returns all of its relation
given a specified set of sources.

=head1 USAGE

Usage: getRelated.pl [OPTIONS] [CUI|TERM] REL

=head1 INPUT

=head2 Required Arguments:

=head3 [CUI|TERM]

A concept or a term from the Unified Medical Language System

=head3 REL

The relation of the given CUI or term.

=head2 Optional Arguments:

=head3 --config FILE

This is the configuration file. The format of the configuration 
file is as follows:

SAB :: <include|exclude> <source1, source2, ... sourceN>

REL :: <include|exclude> <relation1, relation2, ... relationN>

RELA :: <include|exclude> <rela1, rela2, ... relaN> (optional)

For example, if we wanted to use the MSH vocabulary with only 
the RB/RN relations, the configuration file would be:

SAB :: include MSH
REL :: include RB, RN
RELA :: include inverse_isa, isa

or 

SAB :: include MSH
REL :: exclude PAR, CHD

If you go to the configuration file directory, there will 
be example configuration files for the different runs that 
you have performed.

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

=head4 --help

Displays the quick summary of program options.

=head4 --version

Displays the version information.

=head1 OUTPUT

List of related CUIs

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

eval(GetOptions( "version", "help", "debug", "username=s", "password=s", "hostname=s", "database=s", "socket=s", "config=s")) or die ("Please check the above mentioned option(s).\n");


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
if(scalar(@ARGV) <= 1) {
    print STDERR "A term and relation must be specified\n";
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

if(defined $opt_config) {
    $option_hash{"config"} = $opt_config;
}
if(defined $opt_verbose) {
    $option_hash{"verbose"} = $opt_verbose;
}
if(defined $opt_debug) {
    $option_hash{"debug"} = $opt_debug;
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

$umls = UMLS::Interface->new(\%option_hash); 
die "Unable to create UMLS::Interface object.\n" if(!$umls);

my $input  = shift;
my $rel    = shift;
my $term   = $input;

my @c = ();
if($input=~/C[0-9]+/) {
    push @c, $input;
    ($term) = $umls->getTermList($input);
}
else {
    @c = $umls->getConceptList($input);
}

my $printFlag = 0;

foreach my $cui (@c) {

    #  make certain cui exists in this view
    if($umls->exists($cui) == 0) { next; }	
    
    my @cuis = $umls->getRelated($cui, $rel); 
    
    if($#cuis < 0) {
	print "No CUIs are associated with $term ($cui) given the relation ($rel).\n";
    }
    else {
	print "The related ($rel) CUIs to $term ($cui):\n";
	foreach my $related_cui (@cuis) {
	    my ($t) = $umls->getTermList($related_cui);
	    print "  $t ($related_cui)\n";
	}
    }
    $printFlag = 1;
}

if(! ($printFlag) ) {
    print "No CUIs are associated with $input given the relation ($rel).\n";
}



##############################################################################
#  function to output minimal usage notes
##############################################################################
sub minimalUsageNotes {
    
    print "Usage: getRelated.pl [OPTIONS] [CUI|TERM] REL\n";
    &askHelp();
    exit;
}

##############################################################################
#  function to output help messages for this program
##############################################################################
sub showHelp() {

        
    print "This is a utility that takes as input a CUI (or a \n";
    print "term) and a relation and returns all the related CUIs \n";
    print "a specified set of sources\n\n";
  
    print "Usage: getRelated.pl [OPTIONS] [CUI|TERM] REL\n\n";

    print "Options:\n\n";

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
    print '$Id: getRelated.pl,v 1.11 2010/05/24 17:57:16 btmcinnes Exp $';
    print "\nCopyright (c) 2008, Ted Pedersen & Bridget McInnes\n";
}

##############################################################################
#  function to output "ask for help" message when user's goofed
##############################################################################
sub askHelp {
    print STDERR "Type getRelated.pl --help for help.\n";
}
    
