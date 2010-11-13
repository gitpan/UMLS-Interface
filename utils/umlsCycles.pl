#!/usr/bin/perl

=head1 NAME

umlsCycles.pl - This program marks problematic relations defined by the user.

=head1 SYNOPSIS

This is a utility that takes as input a list of problematic
relations in the MRREL file. The relations cause cycles in 
structure. This programs marks the problematic relations in
the MRREL file by inserting a '1' into the CVF column. It 
does not physicall remove a relation from the table only tags
it. The bad-relations.txt file is found in the default_options
directory. This file is used as the default unless one is 
specified on the command line.
   	
Documentation on how the badrelation files was compiled, please 
refer to:

	  Bodenreider O. An object-oriented model for representing 
	  semantic locality in the UMLS. Medinfo 2001;10(Pt 1):161-5.
	  http://mor.nlm.nih.gov/pubs/pdf/2001-medinfo-ob.pdf 


=head1 USAGE

Usage: umlsCycles.pl --username STRING --password STRING [OPTIONS]

=head1 INPUT

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

=head3 --file

File containing the bad relations. The assumption is that you are 
running umlsCycles from the utils directory.

DEFAULT: ../default_options/2008AA-badpairs

=head3 --unmark

It removes the marks of the the problematic relations in
the MRREL file by inserting a NULL into the CVF column.

=head4 --help

Displays the quick summary of program options.

=head4 --version

Displays the version information.

=head1 OUTPUT

disambiguate.pl creates two directories. One containing the arff files
and the other containing the weka files. In the weka directory, the 
overall averages are stored in the OverallAverage file.

=head1 SYSTEM REQUIREMENTS

=over

=item * Perl (version 5.8.5 or better) - http://www.perl.org

=back

=head1 AUTHOR

 Bridget T. McInnes, University of Minnesota

=head1 COPYRIGHT

Copyright (c) 200 - 2009

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

use DBI;
use Getopt::Long;

eval(GetOptions( "version", "help", "username=s", "password=s", "hostname=s", "database=s", "socket=s", "file=s", "unmark")) or die ("Please check the above mentioned option(s).\n"); 

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


my $database = "umls";
if(defined $opt_database) { $database = $opt_database; }
my $hostname = "localhost";
if(defined $opt_hostname) { $hostname = $opt_hostname; }
my $socket   = "/tmp/mysql.sock";
if(defined $opt_socket)   { $socket   = $opt_socket;   }

my $db = "";

print "Connecting to the UMLS\n";

if(defined $opt_username and defined $opt_password) {    
    print "  => Connecting with username and password\n\n";
    $db = DBI->connect("DBI:mysql:database=$database;mysql_socket=$socket;host=$hostname",$opt_username, $opt_password, {RaiseError => 1});
}
else {
    print "  => Connecting using the my.cnf file\n\n";
    my $dsn = "DBI:mysql:umls;mysql_read_default_group=client;";
    $db = DBI->connect($dsn);
}

 
if(!$db || $db->err()) {
    print STDERR "Error! Unable to open database: ".($db->errstr());
    exit;
}


if(!$db || $db->err()) { 
    print STDERR "Error Unable to open database: umls\n\n";
    exit;
}

# Check if the tables exist...
$sth = $db->prepare("show tables");
$sth->execute();
if($sth->err()) {
    print STDERR "Error! Unable run query: ".($sth->errstr());
    exit;
}

my %tables = ();
while(($tableName) = $sth->fetchrow()) {
    $tables{$tableName} = 1;
}
$sth->finish();

if(!defined $tables{"MRREL"}) {
    print STDERR "Table MRREL not found in database.";
    exit;
}

#  if the unmark option is defined we need to unmark 
#  the problematic relations in the MRREL file 
if(defined $opt_unmark) {

    print "Unmarking the relations in the file\n";
    my $ar = $db->do("update MRREL set CVF=NULL where CVF=1");
    my $drop  = $db->do("drop index CVFINDEX on MRREL");
    my $drop  = $db->do("drop index RELINDEX on MRREL");

}
elsif (defined $opt_file) {
    print "Creating Index CVFINDEX in MRREL on CUI1 CUI2 and REL\n";
    print "Otherwise this takes forever to run!\n";

    print "Create CVFINDEX\n";
    my $index = $db->do("create index CVFINDEX on MRREL (CUI1, CUI2, REL)");
    print "Create RELINDEX\n";
    my $index = $db->do("create index RELINDEX on MRREL (REL)");
    print "Both indexes are created\n\n";

    print "Marking the relations in the file\n";
    open(FILE, $opt_file) || die "Could not open file: $opt_file\n";
    
    #  Mark the bad relations found in the badpairs config file.
    #  This sets the CVF column of the MRREL to one resulting in 
    #  the relation not being considered. This removes the cycles 
    #  from the UMLS which is necessary in order to obtain the 
    #  depth and propogate the frequency of concepts up the taxonomy

    print "Marking relations from the file....\n";

    my $ar = $db->do("update MRREL  set CVF=1 where CUI1=CUI2");
    
    while(<FILE>) {
	chomp;
	
	my ($cui1, $cui2, $rel, $rela) = split/\|/;
	
	my $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='$rel'");
	
	if($rel eq "PAR") {
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='RB'");
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui2' and CUI2='$cui1' and REL='CHD'");
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui2' and CUI2='$cui1' and REL='RN'");
	}
	if($rel eq "RB") {
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='PAR'");
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui2' and CUI2='$cui1' and REL='CHD'");
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui2' and CUI2='$cui1' and REL='RN'");
	}
	if($rel eq "CHD") {
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='RN'");
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui2' and CUI2='$cui1' and REL='PAR'");
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui2' and CUI2='$cui1' and REL='RB'");
	}
	if($rel eq "RN") {
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui1' and CUI2='$cui2' and REL='CHD'");
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui2' and CUI2='$cui1' and REL='PAR'");
	    $ar1 = $db->do("update MRREL  set CVF=1 where CUI1='$cui2' and CUI2='$cui1' and REL='RB'");
	}
    }
}
else {



}
print "Finished.\n";

##############################################################################
#  function to output minimal usage notes
##############################################################################
sub minimalUsageNotes {
    
    print "Usage: umlsCycles.pl --username STRING --password STRING [OPTIONS]\n\n";
    &askHelp();
    exit;
}

##############################################################################
#  function to output help messages for this program
##############################################################################
sub showHelp() {

    print "Usage: umlsCycles.pl --username STRING --password STRING [OPTIONS]\n\n";
    
    print  "This is a utility that takes as input a list of problematic\n";
    print  "relations in the MRREL file. The relations cause cycles in \n";
    print  "structure. This programs marks the problematic relations in\n";
    print  "the MRREL file by inserting a '1' into the CVF column. It \n";
    print  "does not physicall remove a relation from the table only tags\n";
    print  "it. The bad-relations.txt file is found in the default_options\n";
    print  "directory. This file is used as the default unless one is \n";
    print  "specified on the command line.\n\n";

    print "Options:\n\n";

    print "--username STRING        Username required to access mysql\n\n";

    print "--password STRING        Password required to access mysql\n\n";

    print "--hostname STRING        Hostname for mysql (DEFAULT: localhost)\n\n";

    print "--database STRING        Database contain UMLS (DEFAULT: umls)\n\n";

    print "--unmark                 Unmark the problematic relations\n\n";

    print "--file FILE              File containing bad relations\n\n";
  
    print "--version                Prints the version number\n\n";
 
    print "--help                   Prints this help message.\n\n";
}

##############################################################################
#  function to output the version number
##############################################################################
sub showVersion {
    print '$Id: umlsCycles.pl,v 1.1.1.1 2009/10/14 15:38:57 btmcinnes Exp $';
    print "\nCopyright (c) 2007, Ted Pedersen & Bridget McInnes\n";
}

##############################################################################
#  function to output "ask for help" message when user's goofed
##############################################################################
sub askHelp {
    print STDERR "Type umlsCycles.pl --help for help.\n";
}
    
