#! /usr/bin/perl
# $Id$

use strict;
#use lib "../../";
use Mail::MboxParser;

my @Mboxes;
my $Dir = shift;
if (-d $Dir) {
	opendir DIR, $Dir or die "Error: Could not open $Dir: $!";
	my @Mboxes = readdir DIR ;
}
else {
	push @Mboxes, $Dir;
}

my $Mb = new Mail::MboxParser;

for my $m (@Mboxes) {
	my $mbox;
	if (-e $m) 	{ $mbox = $m }
	else 		{ $mbox = "$Dir/$m" }
	$Mb->open($mbox);
	$_->store_all_attachements('/tmp') for ($Mb->get_messages);
}
		
	
