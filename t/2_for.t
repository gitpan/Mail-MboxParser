#! /usr/bin/perl -w

use Test;
use File::Spec;
use strict;

use lib '../..';
use Mail::MboxParser;

my $src = File::Spec->catfile('t', 'testbox');

BEGIN { plan tests => 28 };

my $mb    = Mail::MboxParser->new($src);
my @mails = $mb->get_messages;

# 1
print "Testing num of messages...\n";
ok(scalar @mails, $mb->nmsgs);

# 2 - 9
print "Testing subjects...\n";
ok($mails[1]->header->{subject}, 'Welcome new user VPARSEVAL');
ok($mails[2]->header->{subject}, 'Welcome new user VPARSEVAL');
ok($mails[3]->header->{subject}, 'Password Update');
ok($mails[4]->header->{subject}, 'Notification from PAUSE');
ok($mails[5]->header->{subject}, 
    'CPAN Upload: V/VP/VPARSEVAL/Mail-MboxParser-0.01.tar.gz');
ok($mails[6]->header->{subject}, 'Module submission Mail::MboxParser');
ok($mails[7]->header->{subject}, 'Module submission Mail::MboxParser');
ok($mails[8]->header->{subject}, 'Re: Mail::MboxParser');

# 10-25
print "Testing attachments...there should be none\n";
for my $msg (@mails[0..7]) {
    ok($msg->num_entities, 1);
    ok($msg->get_attachments, undef);
}

# 25-28
print "Testing attachments on multipart...\n";
ok($mails[8]->num_entities, 3);
ok($mails[8]->get_attachments);
ok($mails[8]->get_attachments('Plans'), 2);
