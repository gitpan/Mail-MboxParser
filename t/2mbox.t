#! /usr/bin/perl -w

use Test;
use File::Spec;
use strict;

use lib '../..';
use Mail::MboxParser;

my $src = File::Spec->catfile('t', 'testbox');

BEGIN { plan tests => 10 };

my $mb  = Mail::MboxParser->new($src);
my @a   = $mb->get_messages;
my $msg = $a[1];
ok(defined $mb);
ok(scalar @a == 8);
ok($msg->header->{subject}  eq 'Welcome new user VPARSEVAL');
ok($msg->id eq '200107050338.FAA01533@pause.perl.org');
ok($msg->num_entities == 1);

$msg = $a[7];
ok($msg->header->{subject} eq 'Re: Mail::MboxParser');
ok($msg->id eq '20010706164307.B12625@atcmpg.ATComputing.nl');
ok($msg->from->{name} eq 'Mark Overmeer');
ok($msg->from->{email} eq 'markov@ATComputing.nl');
ok($msg->num_entities == 3);
