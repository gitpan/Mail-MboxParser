#! /usr/bin/perl -w

use Test;
use File::Spec;
use strict;

use lib '../..';
use Mail::MboxParser;

my $src = File::Spec->catfile('t', 'testbox');

BEGIN { plan tests => 5 };

my $mb  = Mail::MboxParser->new($src);
my @a   = $mb->get_messages;
my $msg = $a[7];

ok(defined $mb);
ok($msg->body($msg->find_body)->signature == 6);
ok(@{$msg->body($msg->find_body)->quotes->{0}} == 8);
ok(@{$msg->body($msg->find_body)->quotes->{1}} == 7);
ok(not exists $msg->body($msg->find_body)->quotes->{2});

