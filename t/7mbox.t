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
my $msg  = $a[0];
my $conv = $msg->make_convertable;

ok(defined $mb);
ok(defined $conv);

$conv->delete_from_header(qw(recieved message-id frim date sender to));
$conv->replace_in_header('from', 'test@mail.mboxparser.com');
$conv->replace_in_header('sender', 'test@mail.mboxparser.com');
$conv->add_to_header([ 'to', 'john.doe@foobar.com' ]);

ok($conv->{TOP_ENTITY}->head->get('from') eq "test\@mail.mboxparser.com\n");
ok($conv->{TOP_ENTITY}->head->get('sender') eq "test\@mail.mboxparser.com\n");


