use ExtUtils::MakeMaker;

eval { require Mail::Mbox::MessageParser };

if ($@) {
    warn <<EOWARN;
*******************
You don't have Mail::Mbox::MessageParser installed. If you want to get
significantly faster parsing, you should install this module from the CPAN.

If you do so, you are advised to do it before issuing 'make test' on this
module because otherwise the new parsing routines can't be tested on your
platform.
*******************
EOWARN
}

WriteMakefile(
    AUTHOR       => 'Tassilo v. Parseval <tassilo.parseval@post.rwth-aachen.de',
    NAME         => 'Mail::MboxParser',
    PMLIBDIRS    => ['MboxParser'],
    VERSION_FROM => 'MboxParser.pm', # finds $VERSION
    PREREQ_PM    => { MIME::Tools               => 5.0,
                      MIME::QuotedPrint         => 0, 
                    },
    DISTNAME     => 'Mail-MboxParser',
);
