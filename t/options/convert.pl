#!/usr/bin/perl

while(<>) {
    chomp;
    my($freq, $cui, $str) = split/\|/;
    print "$cui<>$freq\n";
}
