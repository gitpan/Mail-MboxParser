# Mail::MboxParser - object-oriented access to UNIX-mailboxes
# Body.pm		   - the (textual) body of an email
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# Version: $Id: Body.pm,v 1.7 2001/09/01 06:40:13 parkerpine Exp $

package Mail::MboxParser::Mail::Body;

require 5.004;

use Carp;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT @ISA $AUTOLOAD $_HAVE_NOT_URI_FIND);
$VERSION 	= "0.03";
@EXPORT  	= qw();
@ISA	 	= qw(Mail::MboxParser::Base Mail::MboxParser::Mail);
$^W++;


BEGIN { 
	eval { require URI::Find; };
	if ($@) 	{ $_HAVE_NOT_URI_FIND = 1 }
}

sub init(@) {
	my ($self, $args) 	= @_;
	$self->{CONTENT}	= ${$args}[0]->body; # isa MIME::Body
	$self->{BOUNDARY}	= ${$args}[1];	     # the one in Content-type
	$self;
}

sub signature() {
	my $self = shift;
	$self->reset_last;
	my $bound = $self->{BOUNDARY};
	
	my @signature;
	my $seperator = 0;
	for (@{$self->{CONTENT}}) {
	
		# we are still outside the signature
		if (! /^--\040?[\r\n]?$/ && not $seperator) {
			next;
		}
		
		# we hit the signature delimiter (--)
		elsif (not $seperator) { $seperator = 1; next }

		# we are inside signature: is line perhaps MIME-boundary?
		last if $bound && /^--\Q$bound\E/ && $seperator;

		# none of the above => signature line
		push @signature, $_; 
	}
	
	$self->{LAST_ERR} = "No signature found" if @signature == 0;
	map { chomp } @signature;
	return @signature if $seperator;
	return ();
}

sub extract_urls(@_) {
	my ($self, %args) = @_;
	$self->reset_last;
	
	$args{unique} = 0 if not exists $args{unique};

	if ($_HAVE_NOT_URI_FIND) {
		carp <<EOW;
You need the URI::Find module in order to use extract_urls.
EOW
		return;
	}
else { 
	my @uris; my %seen;
	
	for my $line (@{$self->{CONTENT}}) {
		chomp $line;
		URI::Find::find_uris($line, sub {
							my (undef, $url) = @_;
							$line =~ s/^\s+|\s+$//;
							if (not $seen{$url}) {
								push @uris, { 	url => $url, 
												context => $line }
							}
							$seen{$url}++ if $args{unique};
						}
			);
	}
	$self->{LAST_ERR} = "No URLs found" if @uris == 0;
	
	return @uris;
	}
}

sub quotes() {
	my $self = shift;
	$self->reset_last;
	
	my %ret;
	my $q 		= 0; # num of '>'
	my $in 		= 0; # being inside a quote
	my $last 	= 0; # num of quotes in last line
	
	for (@{$self->{CONTENT}}) {
	
		# count quotation signs
		$q = 0;
		my $t = "a" x length;
		for my $c (unpack $t, $_) {
			if ($c eq '>') 				{ $q++ }
			if ($c ne '>' && $c ne ' ') { last }
		}
		
		# first: create a hash-element for level $q
		if (! exists $ret{$q}) {
			$ret{$q}= [];
		}
		
		# if last line had the same level as current one:
		# attach the line to the last one
		if ($last == $q) {
			
			if (@{$ret{$q}} == 0) { $ret{$q}->[$q] .= $_ }
			else { $ret{$q}->[-1] .= $_ }
			
		}
		
		# if not:
		# create a new array-element in the appropriate hash-element
		else { push @{$ret{$q}}, $_ }
		
		$last = $q;
		
	}
	return \%ret;
}


1;

__END__

=head1 NAME

Mail::MboxParser::Mail::Body - rudimentary mail-body object

=head1 SYNOPSIS

See L<Mail::MboxParser> for examples on usage and description of the provided methods.

=head1 DESCRIPTION

This class represents the body of an email-message. 
Since emails can have multiple MIME-parts and each of these parts has a body it is not always easy to say which part actually holds the text of the message (if there is any at all). Mail::MboxParser::Mail::find_body will help and suggest a part.

=head1 AUTHOR AND COPYRIGHT

Tassilo von Parseval <Tassilo.Parseval@post.RWTH-Aachen.de>.

Copyright (c)  2001 Tassilo von Parseval.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::MboxParser::Mail> to learn how to use MIME::Entity-stuff easily

