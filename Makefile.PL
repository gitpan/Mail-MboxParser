# $Id: Makefile.PL,v 1.1 2001/07/01 07:58:31 parkerpine Exp $

use ExtUtils::MakeMaker;

WriteMakefile(
    AUTHOR       => 'Tassilo v. Parseval <tassilo.parseval@post.rwth-aachen.de',
    NAME         => 'Mail::MboxParser',
    PMLIBDIRS    => ['MboxParser'],
    VERSION_FROM => 'MboxParser.pm', # finds $VERSION
    PREREQ_PM    => { MIME::Tools       => 5.0,
                      MIME::QuotedPrint => 0, },
    DISTNAME     => 'Mail-MboxParser',
);
