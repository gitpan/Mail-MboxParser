#! /usr/bin/perl -w

use Test;
use File::Spec;
use strict;

use lib '../..';
use Mail::MboxParser;

my $src = File::Spec->catfile('t', 'testbox');

BEGIN { plan tests => 7 };

my $mb    = Mail::MboxParser->new($src);
my @mails = $mb->get_messages;

# 1
print "Testing num of messages...\n";
ok(scalar @mails, $mb->nmsgs);

# 2 - 7
print "Testing from- and received-lines...\n";
chop (my $from_line = $mails[0]->from_line);
ok($from_line, 
    "From friedrich\@pythonpros.com  Thu Feb 26 17:23:40 1998");
ok(scalar $mails[0]->trace, 2);

ok($mails[1]->from_line,
    'From nobody@p11.speed-link.de Thu Jul 05 08:03:22 2001');
ok(scalar $mails[1]->trace, 6);

ok($mails[2]->from_line,
    'From nobody@p11.speed-link.de Thu Jul 05 08:03:22 2001');
ok(scalar $mails[2]->trace, 6);
