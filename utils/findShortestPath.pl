#! /usr/local/bin/perl 
#!/usr/bin/perl 

=head1 NAME

findShortestPath.pl - program finds the shoretst path between two concepts

=head1 SYNOPSIS

This program takes two terms or CUIs and returns the shortest 
path between them.

=head1 USAGE

Usage: findShortestPath.pl [OPTIONS] TERM1 TERM2

=head1 INPUT

=head2 Required Arguments:

=head3 TERM1 and TERM2

A term in the Unified Medical Language System

=head2 Optional Arguments:

=head3 --cui 

This flag indicates that TERM1 and TERM2 are actual CUIs 
in the UMLS rather than associated terms

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

List of CUIs that are associated with the input term

=head1 SYSTEM REQUIREMENTS

=over

=item * Perl (version 5.8.5 or better) - http://www.perl.org

=back

=head1 AUTHOR

 Bridget T. McInnes, University of Minnesota

=head1 COPYRIGHT

Copyright (c) 2007-2008,

 Bridget T. McInnes, University of Minnesota
 bthomson at cs.umn.edu
    
 Ted Pedersen, University of Minnesota Duluth
 tpederse at d.umn.edu

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

GetOptions( "version", "help", "username=s", "password=s", "hostname=s", "database=s", "socket=s", "config=s", "cui" );


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
if(scalar(@ARGV) < 1) {
    print STDERR "No term was specified on the command line";
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

if(defined $opt_username and defined $opt_password and defined $opt_config) {
    $umls = UMLS::Interface->new({"driver" => "mysql", 
				  "database" => "$database", 
				  "username" => "$opt_username",  
				  "password" => "$opt_password", 
				  "hostname" => "$hostname", 
				  "socket"   => "$socket",
			          "config"   => "$opt_config"}); 
    die "Unable to create UMLS::Interface object.\n" if(!$umls);
    ($errCode, $errString) = $umls->getError();
    die "$errString\n" if($errCode);
}
elsif(defined $opt_username and defined $opt_password) {
    $umls = UMLS::Interface->new({"driver" => "mysql", 
				  "database" => "$database", 
				  "username" => "$opt_username",  
				  "password" => "$opt_password", 
				  "hostname" => "$hostname", 
				  "socket"   => "$socket"}); 
    die "Unable to create UMLS::Interface object.\n" if(!$umls);
    ($errCode, $errString) = $umls->getError();
    die "$errString\n" if($errCode);
}
elsif(defined $opt_config) {
    $umls = UMLS::Interface->new({"config" => "$opt_config"});
    die "Unable to create UMLS::Interface object.\n" if(!$umls);
    ($errCode, $errString) = $umls->getError();
    die "$errString\n" if($errCode);
}
else {
    $umls = UMLS::Interface->new(); 
    die "Unable to create UMLS::Interface object.\n" if(!$umls);
    ($errCode, $errString) = $umls->getError();
    die "$errString\n" if($errCode);
}

&errorCheck($umls);


my $input1 = shift;
my $input2 = shift;

my $flag = "cui";

#  check if the input are CUIs or terms
if(defined $opt_cui) {
    push @c1, $input1;
    push @c2, $input2;
}
elsif( ($input1=~/C[0-9]+/) || ($input1=~/C[0-9]+/) ) {
    
    print "The input appear to be CUIs. Is this true (y/n)?\n";
    my $answer = <STDIN>; chomp $answer;
    if($answer=~/y/) {
	print "Please specify the --cui option next time.\n";
	push @c1, $input1;
	push @c2, $input2;
    }
    else {
	@c1 = $umls->getConceptList($input1); 
	&errorCheck($umls);
	@c2 = $umls->getConceptList($input2); 
	&errorCheck($umls);
	$flag = "term";
    }
}
else {
    @c1 = $umls->getConceptList($input1); 
    &errorCheck($umls);
    @c2 = $umls->getConceptList($input2); 
    &errorCheck($umls);
    $flag = "term";
}

my $printFlag = 0;

foreach $cui1 (@c1)
{
    foreach $cui2 (@c2)
    {

	if($umls->validCui($cui1)) {
	    print STDERR "ERROR: The concept ($cui1) is not valid.\n";
	    exit;
	}

	if($umls->validCui($cui2)) {
	    print STDERR "ERROR: The concept ($cui2) is not valid.\n";
	    exit;
	}
	
	my @shortestpath = $umls->findShortestPath($cui1, $cui2);
	
	&errorCheck($umls);
	
	if($flag eq "term") {
	    print "\nThe shortest path between $cui1 ($input1) and $cui2 ($input2):\n";
	}
	else {
	    print "\nThe shortest path between $cui1 and $cui2:\n";
	}
	print "  => @shortestpath\n\n";

	$printFlag = 1;
    }
}

if( !($printFlag) ) {
    print "\n";
    print "There is not a path between $input1 and $input2\n";
    print "given the current view of the UMLS.\n\n";
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
    
    print "Usage: findShortestPath.pl [OPTIONS] TERM1 TERM2\n\n";
    &askHelp();
    exit;
}

##############################################################################
#  function to output help messages for this program
##############################################################################
sub showHelp() {

        
    print "This is a utility that takes as input two Terms or\n";
    print "CUIs and returns the shortest path between them.\n\n";
  
    print "Usage: findShortestPath.pl [OPTIONS] TERM1 TERM2\n\n";

    print "Options:\n\n";

    print "--cui                    Indicates that the input TERM1 and TERM2\n";
    print "                         are Concept Unique Identifiers (CUIs).\n\n";

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
    print '$Id: findShortestPath.pl,v 1.6 2009/01/13 22:20:18 btmcinnes Exp $';
    print "\nCopyright (c) 2008, Ted Pedersen & Bridget McInnes\n";
}

##############################################################################
#  function to output "ask for help" message when user's goofed
##############################################################################
sub askHelp {
    print STDERR "Type findShortestPath.pl --help for help.\n";
}
    
