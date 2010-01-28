#!/usr/bin/perl 

=head1 NAME

findDFS.pl - This program runs a dfs over a specified set of sources
and relations in the UMLS.

=head1 SYNOPSIS

This is a utility runs a dfs over a specified set of sources
and relations in the UMLS returning the depth, number of paths 
to the root, branching factor, leaf and node count.

=head1 USAGE

Usage: findDFS.pl CONFIGFILE [OPTIONS]

=head1 INPUT

=head2 Required Arguments: 

=head3 CONFIGFILE

Configuration file containing the set of sources and 
relations to use. The default uses MSH and the PAR/CHD 
relations.

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

=head3 --verbose FILE

Stores the path information for each of the concepts 
in FILE during the DFS


=head3 --depth NUMBER

Searches up to the specified depth. The default is to 
search the complete hierarchy

=head3 --root CUI

Starts the search at a specified CUI. The default starts 
the search at the UMLS root node

=head3 --help

Displays the quick summary of program options.

=head3 --version

Displays the version information.

=head1 OUTPUT

The program returns the following: 

    1. the maximum depth
    2. paths to root
    3. sources
    4. maximum branching factor
    5. average branching factor
    6. number of leaf nodes
    7. number of nodes
    8. root

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

GetOptions( "version", "help", "username=s", "password=s", "hostname=s", "database=s", "socket=s", "depth=s", "root=s", "verbose=s", "debug");



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
    print STDERR "The config file was not specified on the command line\n";
    &minimalUsageNotes();
    exit;
}


my $config = shift;

my $database = "umls";
if(defined $opt_database) { $database = $opt_database; }
my $hostname = "localhost";
if(defined $opt_hostname) { $hostname = $opt_hostname; }
my $socket   = "/tmp/mysql.sock";
if(defined $opt_socket)   { $socket   = $opt_socket;   }

my $umls = "";

my %option_hash = ();

$option_hash{"config"} = $config;

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
($errCode, $errString) = $umls->getError();
die "$errString\n" if($errCode);

&errorCheck($umls);

#  set the root
my $root = "C0085567";
if(defined $opt_root) {
    $root = $opt_root;
}

#  set paths to root counter;
my $paths_to_root = 0;

#  set branching variables
my $max_branch     = 0;
my $avg_branch     = 0;
my $branch_counter = 0;
my %branch_hash = ();

#  set leaf node counter
my %leafs = ();
my %nodes = ();

#  set max depth variable
my $max_depth = 0;

#  set the sources
my $sources = "";
open(CONFIG, $config) || die "Could not open config file: $config\n";
while(<CONFIG>) {
    if($_=~/SAB\s+\:\:\s+(include|exclude)\s+(.*)/) {
	$sources = $2;
    }
}

#  if the verbose option is turned on open up the table file
if($opt_verbose) {
    
    open(TABLEFILE, ">$opt_verbose") || die "Could not open $opt_verbose";
}

#  get the first set of children and start the 
my @children= $umls->_getChildrenForDFS($root); 
&errorCheck($umls);

#  update the branching variables
$max_branch = $#children + 1;
$branch_hash{$root} = $max_branch;

foreach my $child (@children) {
    my @array = (); 
    push @array, $root;
    my $path  = \@array;
    &_depthFirstSearch($child, $d, $path,*TABLEFILE);
}

#  set the node count for the root
if($#children >= 0) { 
    $nodes{$root}++;
}
else {
    $leafs{$root}++;
}

#  close the file and set the permissions
if($opt_verbose) {
    close TABLEFILE;
    my $temp = chmod 0777, $tableFile;
}

#  calculate the max and average number of branches
foreach my $cui (sort keys %branch_hash) {
    if($branch_hash{$cui} > $max_branch) { $max_branch = $branch_hash{$cui}; }
    $avg_branch += $branch_hash{$cui};
    $branch_counter++;
}
$avg_branch = $avg_branch / $branch_counter;

#  set the node and leaf counts
my $leaf_count = keys %leafs;
my $node_count = keys %nodes;



#  print out the information
print "max_depth : $max_depth\n";
print "paths_to_root : $paths_to_root\n";
print "sources : $sources\n";
print "max_branch : $max_branch\n";
print "avg_branch : $avg_branch\n";
print "leaf_count : $leaf_count\n";
print "node_count : $node_count\n";
print "root : $root\n";


#foreach my $b (sort {$a<=>$b} keys %branch_hash) {
#    print "$b: $branch_hash{$b}\n";
#}

######################################################################### 
#  Depth First Search (DFS) 
######################################################################### 
sub _depthFirstSearch
{
    my $concept = shift;
    my $d       = shift;
    my $array   = shift;
    local(*F)   = shift;

    #  increment the depth
    $d++;

    #  if the depth option has been set and the depth 
    #  is now greater than the set depth just return 
    if(defined $opt_depth) {
	if($d > $opt_depth) { return; }
    }
    
    #  set the max depth
    if($d > $max_depth) { $max_depth = $d; }

    #  if concept is one of the following just return
    #C1274012|Ambiguous concept (inactive concept)
    if($concept=~/C1274012/) { return; }
    #C1274013|Duplicate concept (inactive concept)
    if($concept=~/C1274013/) { return; }
    #C1276325|Reason not stated concept (inactive concept)
    if($concept=~/C1276325/) { return; }
    #C1274014|Outdated concept (inactive concept)
    if($concept=~/C1274014/) { return; }
    #C1274015|Erroneous concept (inactive concept)
    if($concept=~/C1274015/) { return; }
    #C1274021|Moved elsewhere (inactive concept)
    if($concept=~/C1274021/) { return; }

    #  set the new path
    my @path = @{$array};
    push @path, $concept;
    
    my $series = join " ", @path;
    
    #  print information into the file if verbose option is set
    if($opt_verbose) { print F "$concept\t$d\t$series\n"; }
    
    #  increment the number of paths
    $paths_to_root++;

    #  get all the children
    my @children = $umls->_getChildrenForDFS($concept);

    
    my $branches = 0;
    #  search through the children
    foreach my $child (@children) {
	
	#  check if child cui has already in the path
	my $flag = 0;
	foreach my $cui (@path) {
	    if($cui eq $child) { 
		$flag = 1; 
	    }
	}

	#  if it isn't continue on with the depth first search
	if($flag == 0) {
	    &_depthFirstSearch($child, $d, \@path, *F);
	    $branches++;
	}
    }
 
    #  update the branching variables
    if($branches > 0) {
	$branch_hash{$concept} = $branches;
    }
    
    #  set the leaf count
    if($branches == 0) { $leafs{$concept}++; }
    else               { $nodes{$concept}++; }
}

##############################################################################
#  error check
##############################################################################
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
    
    print "Usage: findDFS.pl CONFIGFILE [OPTIONS]\n";
    &askHelp();
    exit;
}

##############################################################################
#  function to output help messages for this program
##############################################################################
sub showHelp() {

        
    print "This is a utility runs a dfs over a specified set of sources\n";
    print "and relations in the UMLS returning the depth, number of paths\n";
    print "to the root, branching factor, leaf and node count.\n\n";
  
    print "Usage: findDFS.pl CONFIGFILE [OPTIONS]\n\n";

    print "Options:\n\n";

    print "--debug                  Sets the debug flag for testing\n\n";

    print "--username STRING        Username required to access mysql\n\n";

    print "--password STRING        Password required to access mysql\n\n";

    print "--hostname STRING        Hostname for mysql (DEFAULT: localhost)\n\n";

    print "--database STRING        Database contain UMLS (DEFAULT: umls)\n\n";
    
    print "--socket STRING          Socket used by mysql (DEFAULT: /tmp.mysql.sock)\n\n";

    print "--verbose FILE           Stores path information in FILE\n\n";
    
    print "--depth NUMBER           Searches up to the specified depth\n";
    print "                         Default searches the complete taxonomy\n\n";
    
    print "--root CUI               Starts the search at a specified CUI\n";
    print "                         Default is the UMLS root\n\n";
    
    print "--version                Prints the version number\n\n";
 
    print "--help                   Prints this help message.\n\n";
}

##############################################################################
#  function to output the version number
##############################################################################
sub showVersion {
    print '$Id: findDFS.pl,v 1.2 2010/01/20 16:28:31 btmcinnes Exp $';
    print "\nCopyright (c) 2008, Ted Pedersen & Bridget McInnes\n";
}

##############################################################################
#  function to output "ask for help" message when user's goofed
##############################################################################
sub askHelp {
    print STDERR "Type findDFS.pl --help for help.\n";
}
    
