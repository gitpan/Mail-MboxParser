# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# Version: $Id: Mail.pm,v 1.16 2001/08/01 08:01:11 parkerpine Exp $

package Mail::MboxParser::Mail;

require 5.004;

use MIME::Parser;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT);
$VERSION    = "0.08";
@EXPORT     = qw();
$^W++;

sub new {
	my $call  	= shift;
	my $class 	= ref($call) || $call;
	my $self  	= {};

	my ($header, $body) = @_;
	$self->{HEADER} 		= $header;
	$self->{HEADER_HASH}	= \&split_header;
	$self->{BODY}			= $body;
	$self->{TOP_ENTITY}		= 0;
	$self->{ENTITY}			= 
		sub { 
			my $p = new MIME::Parser;
			$p->output_to_core(1);
			$self->{TOP_ENTITY} =
				$p->parse_data($self->{HEADER}.$self->{BODY});
		};

	bless ($self, $class);
	return $self;
}

sub header {
	my $self = shift;
	return $self->{HEADER_HASH}->(\$self->{HEADER});
}

sub body {
	my $self = shift;
	return $self->{BODY};
}

sub from {
	my $self = shift;
	my %from;
	my %h = %{$self->header};
	my $from = $h{from};
	my ($name, $email) = split /\s</, $from;
	$email =~ s/>$//g unless not $email;
	if ($name and not $email) {
		$email = $name;
		$name = "";
	}
	return {(name => $name, email => $email)};
}

sub id {
	my $self = shift;
	my %h = %{$self->header};
	my $id = $h{'message-id'};
	$id =~ s/^<|>$//g;
	return $id;
}

sub num_entities {
	my $self = shift;
	# closure $self->{ENTITY} only defined
	# if not yet called
	if ($self->{ENTITY}) {	
		$self->{ENTITY}->();
		undef $self->{ENTITY};
	}	
	return scalar $self->{TOP_ENTITY}->parts;
		
}

sub get_entities {
	my $self = shift;
	my $num  = shift;
	if ($self->{ENTITY}) {
		$self->{ENTITY}->();
		undef $self->{ENTITY};
	}					
	return $self->{TOP_ENTITY}->parts($num);
}

sub get_entity_body {
	my $self = shift;
	my $num  = shift;

	if (not $num >= $self->num_entities and 
		$self->get_entities($num)->bodyhandle) {
		return $self->get_entities($num)->bodyhandle->as_string;
	}
	else { return undef }
}

sub store_entity_body {
	my $self = shift;
	my ($num, $handle) = @_;		

	my $b = $self->get_entity_body($num);
	unless (not defined $handle or not $b) { print $handle $b }
}

sub store_attachement {
	my $self = shift;
	my ($num, $path) = @_;
	
	$path = "." if not $path;
	$path =~ s/\/$//;
	
	if ($num < $self->num_entities) {
		my $file = $self->get_entities($num)->head->recommended_filename;
		return if not $file; 
		open ATT, ">$path/$file";
		$self->store_entity_body($num, \*ATT);
		close ATT ;
	}
}

sub store_all_attachements {
	my $self = shift;
	my $path = shift;
	for (0 .. $self->num_entities - 1) {
		$self->store_attachement($_, $path);
	}
}

sub split_header {
	my $header = shift;
	my @header = split /\n/, $$header;
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
	undef (my $self = shift);
}

1;

__END__

=head1 NAME

Mail::MboxParser::Mail - Provide a mail-objects and methods upon

=head1 SYNOPSIS

See L<Mail::MboxParser> for examples on usage.

=head1 DESCRIPTION

Mail::MboxParser::Mail objects are usually not created directly though, in theory, they could be.

Documentation will be added as soon as it becomes useful which probably happens when Mail::MboxParser can also write to mailboxes.

=head1 COPYRIGHT

Tassilo von Parseval <Tassilo.Parseval@post.RWTH-Aachen.de>.

Copyright (c)  2001 Tassilo von Parseval.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::MboxParser>

=cut
