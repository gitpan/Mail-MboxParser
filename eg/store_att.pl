#! /usr/bin/perl
# $Id$

use strict;
#use lib "../../";
use Mail::MboxParser;

my $Dir = shift;
opendir DIR, $Dir or die "Error: Could not open $Dir: $!";
my @Mboxes = readdir DIR ;

my $Mb = new Mail::MboxParser;

for my $m (@Mboxes) {
	$Mb->open("$Dir/$m");
	$_->store_all_attachements('/tmp') for ($Mb->get_messages);
}
		
	
