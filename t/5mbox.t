#! /usr/bin/perl -w

use Test;
use File::Spec;
use strict;

use lib '../..';
use Mail::MboxParser;

my $src = File::Spec->catfile('t', 'testbox');

BEGIN { plan tests => 4 };

my $mb  = Mail::MboxParser->new($src);
my @a   = $mb->get_messages;
my $msg = $a[7];

ok(defined $mb);
ok($msg->body($msg->find_body)->signature == 6);
ok(($msg->body($msg->find_body)->extract_urls)[1]->{url} eq 
	'http://Mark.Overmeer.net');
ok($msg->num_entities == 3);

