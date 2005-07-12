use Test;
use File::Spec;
use strict;

use Mail::MboxParser;
my $src = File::Spec->catfile('t', 'qpname');

BEGIN { plan tests => 1 };

my $mb = Mail::MboxParser->new($src);
my ($msg) = $mb->get_messages;

if (&Mail::MboxParser::Mail::HAVE_MIMEWORDS) {
    my $att = $msg->get_attachments;
    ok(defined $msg->get_attachments("test þðüýçö characters.txt"));
} else {
    skip("Mime::Words not installed");
}



