#!/usr/bin/perl 

=head1 NAME

findCuiDepth.pl - This program returns the minimum and maximum depth 
of a given CUI or term.

=head1 SYNOPSIS

This program takes in a CUI or a term and returns its minimum and 
maximum depth.

=head1 USAGE

Usage: findCuiDepth.pl [OPTIONS] [TERM|CUI]

=head1 INPUT

=head2 Required Arguments:

=head3 [TERM|CUI]

Concept Unique Identifier (CUI) or a term from the Unified 
Medical Language System (UMLS)

=head2 Optional Arguments:
=head3 --debug

This sets the debug flag for testing

=head3 --minimum

Finds just the minimum CUI depth

=head3 --maximum

Finds just the maximum CUI depth

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
config file that you specified.

=head3 --cuilist FILE

This option takes in a file containing a list of CUIs (one CUI 
per line) and stores only the path information for those CUIs 
rather than for all of the CUIs given the specified set of 
sources and relations

=head3 --help

Displays the quick summary of program options.

=head3 --version

Displays the version information.

=head1 OUTPUT

The minimum depth of a given CUI or term

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

GetOptions( "version", "help", "username=s", "password=s", "hostname=s", "database=s", "socket=s", "config=s", "forcerun", "debug", "verbose", "cuilist=s", "realtime", "minimum", "maximum");


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

# At least 1 CUI should be given on the command line.
if(scalar(@ARGV) < 1) {
    print STDERR "No term was specified on the command line\n";
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

if(defined $opt_realtime) {
    $option_hash{"realtime"} = $opt_realtime;
}
if(defined $opt_config) {
    $option_hash{"config"} = $opt_config;
}
if(defined $opt_forcerun) {
    $option_hash{"forcerun"} = $opt_forcerun;
}
if(defined $opt_debug) {
    $option_hash{"debug"} = $opt_debug;
}
if(defined $opt_verbose) {
    $option_hash{"verbose"} = $opt_verbose;
}
if(defined $opt_cuilist) {
    $option_hash{"cuilist"} = $opt_cuilist;
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
($errCode, $errString) = $umls->getError();
die "$errString\n" if($errCode);


&errorCheck($umls);

my $input = shift;
my $term  = $input;

my @c = ();
if($input=~/C[0-9]+/) {
    push @c, $input;
    ($term) = $umls->getTermList($input);
}
else {
    @c = $umls->getConceptList($input);
}

&errorCheck($umls);

my $printFlag = 0;

foreach my $cui (@c) {
    #  check that the cui is valid
    if($umls->validCui($cui)) {
	print STDERR "ERROR: The concept ($cui) is not valid.\n";
	exit;
    }

    #  make certain cui exists in this view
    if($umls->checkConceptExists($cui) == 0) { next; }
    
    
    #  get the minimum depth
    if(defined $opt_minimum) {
	my $min = $umls->findMinimumDepth($cui);
	&errorCheck($umls);
	print "The minimum depth of $term ($cui) is $min\n";
    }
    #  get the maximum depth
    elsif(defined $opt_maximum) {
	my $max = $umls->findMaximumDepth($cui);
	&errorCheck($umls);
	print "The maximum depth of $term ($cui) is $max\n";
    }
    else {
	my $min = $umls->findMinimumDepth($cui);
	&errorCheck($umls);
	print "The minimum depth of $term ($cui) is $min\n";
	
	my $max = $umls->findMaximumDepth($cui);
	&errorCheck($umls);
	print "The maximum depth of $term ($cui) is $max\n";
    }
    
    $printFlag = 1;
}

if(! ($printFlag) ) {
    print "$input does not exist in this view of the UMLS.\n";
}

sub errorCheck
{
    my $obj = shift;
    ($errCode, $errString) = $obj->getError();
    print STDERR "$errString\n" if($errCode);
    exit if($errCode > 1);
}


##############################################################################
#  function to output minimal usage notes
##############################################################################
sub minimalUsageNotes {
    
    print "Usage: findCuiDepth.pl [OPTIONS] [TERM|CUI] \n";
    &askHelp();
    exit;
}

##############################################################################
#  function to output help messages for this program
##############################################################################
sub showHelp() {

        
    print "This is a utility that takes as input a CUI or a TERM\n";
    print "and returns its minimum depth.\n\n";
  
    print "Usage: findCuiDepth.pl [OPTIONS] [TERM|CUI]\n\n";

    print "Options:\n\n";

    print "--minimum                Returns the minimum depth (DEFAULT)\n\n";
    
    print "--maximum                Returns the maximum depth\n\n";

    print "--username STRING        Username required to access mysql\n\n";

    print "--password STRING        Password required to access mysql\n\n";

    print "--hostname STRING        Hostname for mysql (DEFAULT: localhost)\n\n";

    print "--database STRING        Database contain UMLS (DEFAULT: umls)\n\n";
    
    print "--socket STRING          Socket used by mysql (DEFAULT: /tmp.mysql.sock)\n\n";

    print "--config FILE            Configuration file\n\n";
   
    print "--realtime               This option will not create a database of the\n";
    print "                         path information for all of concepts but just\n"; 
    print "                         obtain the information for the input concept\n\n";

    print "--debug                  Sets the debug flag for testing.\n\n";

    print "--forcerun               This option will bypass any command \n";
    print "                         prompts such as asking if you would \n";
    print "                         like to continue with the index \n";
    print "                         creation. \n\n";

    print "--verbose                This option prints out the path information\n";
    print "                         to a file in your config directory.\n\n";    
    print "--cuilist FILE           This option takes in a file containing a \n";
    print "                         list of CUIs (one CUI per line) and stores\n";
    print "                         only the path information for those CUIs\n"; 
    print "                         rather than for all of the CUIs\n\n";

    print "--version                Prints the version number\n\n";
 
    print "--help                   Prints this help message.\n\n";
}

##############################################################################
#  function to output the version number
##############################################################################
sub showVersion {
    print '$Id: findCuiDepth.pl,v 1.2 2010/01/20 16:28:31 btmcinnes Exp $';
    print "\nCopyright (c) 2008, Ted Pedersen & Bridget McInnes\n";
}

##############################################################################
#  function to output "ask for help" message when user's goofed
##############################################################################
sub askHelp {
    print STDERR "Type findCuiDepth.pl --help for help.\n";
}
    