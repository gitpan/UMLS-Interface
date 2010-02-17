 #!/usr/bin/perl

 use UMLS::Interface;

 $umls = UMLS::Interface->new(); 

 die "Unable to create UMLS::Interface object.\n" if(!$umls);

 ($errCode, $errString) = $umls->getError();

 die "$errString\n" if($errCode);

 my $root = $umls->root();

 my $term1    = "blood";

 my @tList1   = $umls->getConceptList($term1);

 my $cui1     = pop @tList1;

 if($umls->checkConceptExists($cui1) == 0) { 
    print "This concept ($cui1) doesn't exist\n";
 } else { print "This concept ($cui1) does exist\n"; }

 my $term2    = "cell";

 my @tList2   = $umls->getConceptList($term2);

 my $cui2     = pop @tList2;

 my $exists1  = $umls->checkConceptExists($cui1);

 my $exists2  = $umls->checkConceptExists($cui2);

 if($exists1) { print "$term1($cui1) exists in your UMLS view.\n"; }

 else         { print "$term1($cui1) does not exist in your UMLS view.\n"; }
 
 if($exists2) { print "$term2($cui2) exists in your UMLS view.\n"; }

 else         { print "$term2($cui2) does not exist in your UMLS view.\n"; }

 print "\n";

 my @cList1   = $umls->getTermList($cui1);

 my @cList2   = $umls->getTermList($cui2);

 print "The terms associated with $term1 ($cui1):\n";

 foreach my $c1 (@cList1) {

    print " => $c1\n";

 } print "\n";

 print "The terms associated with $term2 ($cui2):\n";

 foreach my $c2 (@cList2) {

    print " => $c2\n";

 } print "\n";

 my $lcs = $umls->findLeastCommonSubsumer($cui1, $cui2);

 print "The least common subsumer between $term1 ($cui1) and \n";

 print "$term2 ($cui2) is $lcs\n\n";

 my @shortestpath = $umls->findShortestPath($cui1, $cui2);

 print "The shortest path between $term1 ($cui1) and $term2 ($cui2):\n";

 print "  => @shortestpath\n\n";

 my $pathstoroot   = $umls->pathsToRoot($cui1);

 print "The paths from $term1 ($cui1) and the root:\n";

 foreach  $path (@{$pathstoroot}) {

    print "  => $path\n";

 } print "\n";

 my $mindepth = $umls->findMinimumDepth($cui1);

 my $maxdepth = $umls->findMaximumDepth($cui1);

 print "The minimum depth of $term1 ($cui1) is $mindepth\n";

 print "The maximum depth of $term1 ($cui1) is $maxdepth\n\n";

 my @children = $umls->getChildren($cui2); 

 print "The child(ren) of $term2 ($cui2) are: @children\n\n";

 my @parents = $umls->getParents($cui2);

 print "The parent(s) of $term2 ($cui2) are: @parents\n\n";

 my @relations = $umls->getRelations($cui2);

 print "The relation(s) of $term2 ($cui2) are: @relations\n\n";

 my @rel_sab = $umls->getRelationsBetweenCuis($cui1, "C1524024");
 
 print "The relation (source) between $cui1 and $cui2: @rel_sab\n";
   
 my @siblings = $umls->getRelated($cui2, "SIB");

 print "The sibling(s) of $term2 ($cui2) are: @siblings\n\n";

 my @definitions = $umls->getCuiDef($cui1);

 print "The definition(s) of $term1 ($cui1) are:\n";

 foreach $def (@definitions) {

    print "  => $def\n"; $i++;

 } print "\n";

 my @sabs = $umls->getSab($cui1);

 print "The sources containing $term1 ($cui1) are: @sabs\n";

 print "The semantic type(s) of $term1 ($cui1) and the semantic\n";

 print "definition are:\n";

 my @sts = $umls->getSt($cui1);

 foreach my $st (@sts) {

    my $abr = $umls->getStAbr($st);

    my $string = $umls->getStString($abr);
    
    my $def    = $umls->getStDef($abr);

    print "  => $string ($abr) : $def\n";
    
 } print "\n";

 $umls->removeConfigFiles();

 $umls->dropConfigTable();
