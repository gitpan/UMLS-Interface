#!/usr/bin/perl 

=head1 NAME

findShortestPath.pl - This program finds the shoretest path between two 
concepts.

=head1 SYNOPSIS

This program takes two terms or CUIs and returns the shortest 
path between them.

=head1 USAGE

Usage: findShortestPath.pl [OPTIONS] [CUI1|TERM1] [CUI2|TERM2]

=head1 INPUT

=head2 Required Arguments:

=head3 [CUI1|TERM1] [CUI2|TERM2]

A TERM or CUI (or some combination) from the Unified 
Medical Language System

=head2 Optional Arguments:

=head4 --infile FILE

   A file containing pairs of concepts or terms in the following format:

    term1<>term2 
    
    or 

    cui1<>cui2
 
    or 
    
    cui1<>term2

    or 

    term1<>cui2


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

GetOptions( "version", "help", "username=s", "password=s", "hostname=s", "database=s", "socket=s", "config=s", "cui", "infile=s" );


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

my @fileArray = ();
if(defined $opt_infile) {
    open(FILE, $opt_infile) || die "Could not open infile: $opt_infile\n";
    while(<FILE>) {
	chomp;
	if($_=~/^\s*$/) { next; }
	push @fileArray, $_;
    }
    close FILE;
}
else {
    
    # At least 2 terms and/or cuis should be given on the command line.
    if(scalar(@ARGV) < 2) {
	print STDERR "Two terms and/or CUIs are required\n";
	&minimalUsageNotes();
	exit;
    }
    

    my $i1 = shift;
    my $i2 = shift;

    my $string = "$i1<>$i2";
    push @fileArray, $string;
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


foreach my $element (@fileArray) {
    
    my ($input1, $input2) = split/<>/, $element;
    
    my $flag1 = "cui";
    my $flag2 = "cui";

    #  check if the input are CUIs or terms
    if( ($input1=~/C[0-9]+/)) {
	push @c1, $input1;
    }
    else {
	@c1 = $umls->getConceptList($input1); 
	&errorCheck($umls);
	$flag1 = "term";
    }
    if( ($input2=~/C[0-9]+/)) {
	push @c2, $input2; 
    }
    else {
	@c2 = $umls->getConceptList($input2); 
	&errorCheck($umls);
	$flag2 = "term";
    }
    
    
    my $printFlag = 0;
    
    foreach $cui1 (@c1) {
	foreach $cui2 (@c2) {
	    
	    if($umls->validCui($cui1)) {
		print STDERR "ERROR: The concept ($cui1) is not valid.\n";
		exit;
	    }
	    
	    if($umls->validCui($cui2)) {
		print STDERR "ERROR: The concept ($cui2) is not valid.\n";
		exit;
	    }
	    if(! ($umls->checkConceptExists($cui1)) ) {
		next; 
	    }
	    if(! ($umls->checkConceptExists($cui2)) ) {
		next; 
	    }
		    
	    my @shortestpath = $umls->findShortestPath($cui1, $cui2);
	    
	    &errorCheck($umls);
	    
	    if($#shortestpath < 0) { next; }

	    my $t1 = $input1;
	    my $t2 = $input2;
	    
	    if($flag1 eq "cui") {
		($t1) = $umls->getTermList($cui1); 
	    }
	    
	    if($flag2 eq "cui") {
		($t2) = $umls->getTermList($cui2); 
	    }
	    
	    print "\nThe shortest path between $t1 ($cui1) and $t2 ($cui2):\n";
	    print "  => ";
	    foreach my $concept (@shortestpath) {
		my ($t) = $umls->getTermList($concept); 
		print "$concept ($t) "; 
	    }
	    print "\n";

	    $printFlag = 1;
	    
	}
    }
    
    if( !($printFlag) ) {
	print "\n";
	print "There is not a path between $input1 and $input2\n";
	print "given the current view of the UMLS.\n\n";
    }
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
    
    print "Usage: findShortestPath.pl [OPTIONS] [CUI1|TERM1] [CUI2|TERM2]\n";
    &askHelp();
    exit;
}

##############################################################################
#  function to output help messages for this program
##############################################################################
sub showHelp() {

        
    print "This is a utility that takes as input two Terms or\n";
    print "CUIs and returns the shortest path between them.\n\n";
  
    print "Usage: findShortestPath.pl [OPTIONS] [CUI1|TERM1] [CUI2|TERM2]\n\n";

    print "Options:\n\n";

    print "--infile FILE            File containing TERM or CUI pairs\n\n";

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
    print '$Id: findShortestPath.pl,v 1.15 2009/02/18 18:20:26 btmcinnes Exp $';
    print "\nCopyright (c) 2008, Ted Pedersen & Bridget McInnes\n";
}

##############################################################################
#  function to output "ask for help" message when user's goofed
##############################################################################
sub askHelp {
    print STDERR "Type findShortestPath.pl --help for help.\n";
}
    
