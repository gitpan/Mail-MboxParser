# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# Version: $Id: Mail.pm,v 1.21 2001/08/17 07:51:53 parkerpine Exp $

package Mail::MboxParser::Mail;

require 5.004;

use Mail::MboxParser::SpamDetector;
use MIME::Parser;
use Carp;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT @ISA);
$VERSION    = "0.12";
@EXPORT     = qw();
@ISA		= qw(Mail::MboxParser::Base MIME::Entity);
$^W++;

my $Parser = new MIME::Parser; $Parser->output_to_core(1);

sub init (@) {
	my ($self, $args) = @_;
	my ($header, $body) = @{$args};
	
	$self->{HEADER}			= $header;
	$self->{HEADER_HASH}	= \&split_header;
	$self->{BODY}			= $body;
	$self->{TOP_ENTITY}		= 0;
	$self;
}

sub header() {
	my $self = shift;
	$self->reset_last;
	
	return $self->{HEADER_HASH}->($self->{HEADER});
}

sub body() { 
	my $self = shift;
	$self->reset_last;
	
	return $self->{BODY}; 
}

sub from() {
	my $self = shift;
	$self->reset_last;
	
	my $from = $self->header->{from};
	my ($name, $email) = split /\s\</, $from;
	$email =~ s/\>$//g unless not $email;
	if ($name && not $email) {
		$email = $name;
		$name  = "";
	}
	return {(name => $name, email => $email)};
}

sub to() {
	my $self = shift;
	$self->reset_last;
	
	my $to = $self->header->{to};
	my @tos = split /,/, $to;
	map { s/^\s+//; s/\s+$// } @tos; # remove leading or trailing whitespaces
	my @to_line;
	for my $pair (@tos) {
		my ($name, $email) = split /\s</, $pair;
		$email =~ s/\>$//g unless not $email;
		if ($name and not $email) {
			$email = $name;
			$name  = "";
		}
		push @to_line, {(name => $name, email => $email)};
	}
	return @to_line;
}

sub id() { shift->header->{'message-id'} =~ /\<(.*)\>/; $1 } 

# --------------------
# MIME-related methods
#---------------------

sub num_entities() { 
	my $self = shift;
	$self->reset_last;

	my @ents = $self->get_entities;
	return scalar @ents;
}

sub get_entities(;$) {
	my $self = shift;
	my $num  = shift;
	$self->reset_last;

	my @parts;
	if (ref $self->{TOP_ENTITY} ne 'MIME::Entity') {
		$self->{TOP_ENTITY} = 
			$Parser->parse_data($self->{HEADER}.$self->{BODY});
	}
	if ($num) {
		eval { push @parts, $self->{TOP_ENTITY}->parts($num); };
		$self->{LAST_LOG} = $@ if $@;
	}
	else {
		eval { push @parts, $self->{TOP_ENTITY}->parts; };
		$self->{LAST_LOG} = $@ if $@;
	}
	if (@parts == 1) 	{ return $parts[0] }
	else 				{ return @parts }
}

sub get_entity_body($) {
	my $self = shift;
	my $num  = shift;
	$self->reset_last;
	
	if ($num < $self->num_entities &&
		$self->get_entities($num)->bodyhandle) {
		return $self->get_entities($num)->bodyhandle->as_string;
	}
	else {
		$self->{LAST_ERR} = "$num: No such entity";
		return;
	}
}

sub store_entity_body($$) {
	my $self = shift;
	my ($num, $handle) = @_;		
	$self->reset_last;
	
	if (not $num || not $handle) {
		croak "Wrong number of arguments for store_entity_body";
	}

	my $b = $self->get_entity_body($num);

	print $handle $b; 
	return 1;
}

sub store_attachement($;$$@) {
	my $self = shift;
	my ($num, $path, $code, @args) = @_;
	$self->reset_last;
	
	$path = "." if not $path;
	$path =~ s/\/$//;

	if ($code && ref $code ne 'CODE') {
		carp <<EOW;	
Warning: Second argument for store_attachement must be
a coderef. Using filename from header instead
EOW
		undef $code; undef @args;
	}
	
	if ($num < $self->num_entities) {
		my $file;
		eval { $file = $self->get_entities($num)->head->recommended_filename; };
		$self->{LAST_LOG} = $@;
		
		if (not $file) {
			$self->{LAST_ERR} = "No attachement in entity $num";
			return;
		}
		
		if (-e $path && not -d $path) {
			$self->{LAST_ERR} = "$path is a file";
			return;
		}

		if (not -e $path) {
			if (not mkdir $path, 0755) {
				$self->{LAST_ERR} = "Could not create directory $path: $!";
				return;
			}
		}
		
		if ($code) { $file = $code->($self, $num, @args) }
		if (open ATT, ">$path/$file") {
			$self->store_entity_body($num, \*ATT);
			close ATT ;
			return $file;
		}
		else {
			$self->{LAST_ERR} = "Could not create $path/$file: $!";
			return;
		}
	}
	else {
		$self->{LAST_ERR} = "$num: No such entity";
		return;
	}
}

sub store_all_attachements(;$$@) {
	my $self = shift;
	my ($path, $code, @args) = @_;
	$self->reset_last;

	if ($code and ref $code ne 'CODE') {
		carp <<EOW; 	
Warning: Second argument for store_all_attachements must be a coderef. 
Using filename from header instead 
EOW
		undef $code; undef @args;
	}
	my @files;
	for (0 .. $self->num_entities - 1) {
		push @files, $self->store_attachement($_, $path, $code, @args);
	}
	$self->{LAST_ERR} = "Found no attachement at all" if @files == 0;
	return @files;
}

# --------------------
# spam-related methods
# --------------------

sub is_spam(;@) {
	my ($self, %args) = @_; 
	my $detector	= Mail::MboxParser::SpamDetector->new($self, %args);
	return $detector->classify;
}

# patch provided by Kenn Frankel
sub split_header {
	my $header = shift;
	my @headerlines = split /\n/, $header;
	my @header;
 	foreach my $bit (@headerlines) {
		if ($bit =~ /^\s/) 	{ $header[-1] .= $bit; }
		else 				{ push @header, $bit; }
	}
											   
	my ($key, $value);
	my %header;
	for (@header) {
		unless (/^Received:\s/ or not /: /) {
			$key   = substr $_, 0, index($_, ": ");
			$value = substr $_, index($_, ": ") + 2;
			$header{lc($key)} = $value;
		}
	}
	return {%header};
}

sub DESTROY {
	my $self = shift;
	undef $self;
}

1;

__END__

=head1 NAME

Mail::MboxParser::Mail - Provide mail-objects and methods upon

=head1 SYNOPSIS

See L<Mail::MboxParser> for examples on usage.

=head1 DESCRIPTION

Mail::MboxParser::Mail objects are usually not created directly though, in theory, they could be. A description of the provided methods can be found in L<Mail::MboxParser>.

Documentation will be added as soon as it becomes useful which probably happens when Mail::MboxParser can also write to mailboxes.

=head1 SEE ALSO

L<Mail::MboxParser>

=head1 AUTHOR AND COPYRIGHT

Tassilo von Parseval <Tassilo.Parseval@post.RWTH-Aachen.de>.

Copyright (c)  2001 Tassilo von Parseval.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
