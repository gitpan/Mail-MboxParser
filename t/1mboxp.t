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
my $msg = $a[1];
ok(defined $mb);
ok(scalar @a == 7);
ok($msg->from->{name}  eq 'Perl Authors Upload Server');
ok($msg->from->{email} eq 'upload@p11.speed-link.de');
