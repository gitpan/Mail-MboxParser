# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# Version: $Id: Mail.pm,v 1.11 2001/07/23 16:11:52 parkerpine Exp $

package Mail::MboxParser::Mail;

require 5.004;

use MIME::Parser;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT);
$VERSION    = "0.03";
@EXPORT     = qw();
$^W++;

sub new {
	my $call = shift;
	my $class = ref($call) || $call;
	my $self = {};

	my ($header, $body) = @_;
	my %header = _split_header($header);
	my $p = new MIME::Parser;
	$p->output_to_core(1);	

	$self->{RAW}			= $header.$body;
	$self->{HEADER} 		= $header;
	$self->{HEADER_HASH}	= {%header};
	$self->{BODY}			= $body;
	$self->{ENTITY}			= $p->parse_data($self->{RAW});

	bless ($self, $class);
	return $self;
}

sub header {
	my $self = shift;
	return $self->{HEADER_HASH};
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
	return (my $n = $self->{ENTITY}->parts);
}

sub get_entities {
	my $self = shift;
	my $num  = shift;
	return $self->{ENTITY}->parts($num);
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

sub _split_header {
	my $header = shift;
	my @header = split /\n/, $header;
	my ($key, $value, @r);
	my %header;
	for (@header) {
		unless (/^Received:\s/ or not /: /) {
			$key   = substr $_, 0, index($_, ": ");
			$value = substr $_, index($_, ": ") + 2;
			$header{lc($key)} = $value;
		}
	}
	return %header;
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
