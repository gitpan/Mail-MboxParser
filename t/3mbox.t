#! /usr/bin/perl -w

use Test;
use File::Spec;
use strict;

use lib '../..';
use Mail::MboxParser;

my $src = File::Spec->catfile('t', 'testbox');

BEGIN { plan tests => 6 };

my $mb  = Mail::MboxParser->new($src);
my @a   = $mb->get_messages;
my $msg = $a[3];
ok(defined $mb);
ok(scalar @a == 8);
ok(($msg->to)[0]->{name}  eq 'Tassilo von Parseval');
ok(($msg->to)[0]->{email} eq 'tassilo.parseval@post.rwth-aachen.de');
ok(($msg->to)[1]->{name}  eq '');
ok(($msg->to)[1]->{email} eq 'andreas.koenig@anima.de');

