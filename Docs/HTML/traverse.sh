#!/bin/csh

# This script is called by create_doc.sh
# This script traverses the given directory recursively searching for .pl files and creating .html documentation for 
# each file. The .html files are written out in the directory structure as that of the .pl files.
 
if($#argv != 1) then
	echo "Usage: traverse.sh DESTINATION_PATH";
	exit;
endif

# traverse through current dir and puts html files 
# in the specified path

set dest=$1
set dirs=`ls`

echo $dirs
foreach dir ($dirs)
	if(-d $dir) then
		cd $dir
		if(! -e "$dest/$dir") then
			mkdir $dest/$dir
		endif
		traverse.sh $dest/$dir
		cd ..
	else
		if(`echo $dir | grep "\.pl"` == $dir) then
			set program = `echo $dir | sed 's/\.pl//'`
			pod2html --title $dir $dir > $dest/$program.html
			/utils/rm pod2ht*
		endif
	endif
end
