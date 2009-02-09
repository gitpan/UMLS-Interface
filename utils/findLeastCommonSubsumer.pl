#!/usr/bin/perl 

=head1 NAME

findLeastCommonSubsumer.pl - program finds the least common subsumer 
between two concepts

=head1 SYNOPSIS

This program takes two terms or CUIs and returns the least common
subsumer between them.

=head1 USAGE

Usage: findLeastCommonSubsumer.pl [OPTIONS] [CUI1|TERM1] [CUI2|TERM2]

=head1 INPUT

=head2 Required Arguments:

=head3 [CUI1|TERM1] [CUI2|TERM2]

A TERM or CUI (or some combination) from the Unified 
Medical Language System

=head2 Optional Arguments:

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

# At least 2 terms and/or cuis should be given on the command line.
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
    $flag2 = "term";
}
else {
    @c2 = $umls->getConceptList($input2); 
    &errorCheck($umls);
    $flag = "term";
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
	
	my $lcs = $umls->findLeastCommonSubsumer($cui1, $cui2);
	
	&errorCheck($umls);

	my $t1 = $input1;
	my $t2 = $input2;
	
	if($flag1 eq "term") {
	    ($t1) = $umls->getTermList($cui1); 
	}

	if($flag2 eq "term") {
	    ($t2) = $umls->getTermList($cui2); 
	}
	

	my ($t) = $umls->getTermList($lcs);
	
	print "\nThe least common subsumer between $t1 ($cui1) and $t2 ($cui2) is $t ($lcs)\n";
	
	$printFlag = 1;
    }
}

if( !($printFlag) ) {
    print "\n";
    print "There is not a least common subsumer between $input1 \n";
    print "and $input2 given the current view of the UMLS.\n\n";
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
    
    print "Usage: findLeastCommonSubsumer.pl [OPTIONS] [CUI1|TERM1] [CUI2|TERM2]\n";
    &askHelp();
    exit;
}

##############################################################################
#  function to output help messages for this program
##############################################################################
sub showHelp() {

        
    print "This is a utility that takes as input two Terms or CUIs\n";
    print "and returns the Least Common Subsumer between the two.\n\n";
  
    print "Usage: findLeastCommonSubsumer.pl [OPTIONS] [CUI1|TERM1] [CUI2|TERM2]\n\n";

    print "Options:\n\n";

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
    print '$Id: findLeastCommonSubsumer.pl,v 1.10 2009/02/09 18:16:09 btmcinnes Exp $';
    print "\nCopyright (c) 2008, Ted Pedersen & Bridget McInnes\n";
}

##############################################################################
#  function to output "ask for help" message when user's goofed
##############################################################################
sub askHelp {
    print STDERR "Type findLeastCommonSubsumer.pl --help for help.\n";
}
    
