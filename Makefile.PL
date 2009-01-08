# This -*- perl -*- script writes the Makefile for UMLS::Interface
# (Last Updated 08/09/2004 -- Sid)
#
# Generates the Makefile for the UMLS::Interface Perl modules. 
#
# ----------------------------------------------------------------------

use 5.005;
use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

my $author1 = 'Siddharth Patwardhan <sidd@cs.utah.edu>';
my $author2 = 'Serguei Pakhomov <pakhomov.serguei@mayo.edu>';
my $author3 = 'Ted Pedersen <tpederse@d.umn.edu>';
my $author4 = 'Bridget McInnes <bthomson@cs.umn.edu>';

WriteMakefile(
              'NAME'		  => 'UMLS::Interface',
              'VERSION_FROM'	  => 'lib/UMLS/Interface.pm',
              'EXE_FILES'         => [("utils/umlsCycles.pl", "utils/queryTerm.pl", "utils/queryCui.pl")],
              'dist'              => {'COMPRESS' => 'gzip -9f', 'SUFFIX' => 'gz'},
              ($] >= 5.005 ?
               ('ABSTRACT_FROM'   => 'lib/UMLS/Interface.pm', # retrieve abstract from module
                'AUTHOR'          => "$author1, $author2, $author3, $author4") : ()));

