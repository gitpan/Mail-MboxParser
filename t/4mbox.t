#! /usr/bin/perl -w

use Test;
use File::Spec;
use strict;

use lib '../..';
use Mail::MboxParser;

my $src = File::Spec->catfile('t', 'testbox');

BEGIN { plan tests => 3 };

my $mb  = Mail::MboxParser->new($src);
my @a   = $mb->get_messages;
my $msg = $a[3];

ok(defined $mb);
ok($msg->effective_type eq 'text/plain');
ok($msg->parts == 0);

