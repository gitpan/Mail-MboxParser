# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# $Id: SpamDetector.pm,v 1.2 2001/08/13 16:14:34 parkerpine Exp $

package Mail::MboxParser::SpamDetector;

require 5.004;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT);
$VERSION    = "0.11";
@EXPORT     = qw();
$^W++;

sub wordlist();
sub pattern_body();

sub new {
	my $call 	= shift;
	my $class 	= ref($call) || $call;
	my $self	= {};
	
	my $msg  = shift;
	my %args = @_;
	$self->{MSG} = $msg;
	
	bless ($self, $class);

	$self->configure(%args);
	
	return $self;
}

sub configure {
	my ($self, %args) = @_;

	# apply defaults
	$self->{CONFIG}{WORDS} 			= join "|", wordlist;
	$self->{CONFIG}{IN_HEADER}		= [ keys %{$self->{MSG}->header} ];
	$self->{CONFIG}{PATTERN_BODY}	= join "|", pattern_body;

	if (exists $args{add_words}) {
		my @words = wordlist;
		push @words, @{$args{add_words}};
		$self->{CONFIG}{WORDS} = join "|", @words;
	}

	if (exists $args{override_words}) {
		my @words = @{$args{override_words}};
		$self->{CONFIG}{WORDS} = join "|", @words;
	}

	if (exists $args{search_in_header}) {
		$self->{CONFIG}{IN_HEADER} = $args{search_in_header};
	}

	if (exists $args{add_pattern_body}) {
		my @pattern = pattern_body;
		push @pattern, @{$args{add_pattern_body}};
		$self->{CONFIG}{PATTERN_BODY} = join "|", @pattern;
	}

	if (exists $args{override_pattern_body}) {
		my @pattern = @{$args{override_pattern_body}};
		$self->{CONFIG}{PATTERN_BODY} = join "|", @pattern;
	}
}

sub classify() {
	my $self = shift;
	
	my @detected_in_header;
	my @detected_in_body;
	my $percentage;
	my @all_words_body = split /\s/, $self->{MSG}->{BODY};
	
	my $words  = $self->{CONFIG}{WORDS};
	my $bd_pat = $self->{CONFIG}{PATTERN_BODY};
	
	@detected_in_header = grep $self->{MSG}->header->{$_} =~ /$words/i, 
								@{$self->{CONFIG}{IN_HEADER}};
	@detected_in_body = grep /$bd_pat|$words/i, @all_words_body;
	eval { $percentage = sprintf "%2.2f",
						 scalar @detected_in_body / @all_words_body * 100 };
	$percentage = 0 if $@;

	return (scalar @detected_in_header, scalar @detected_in_body, 
			\@detected_in_header, \@detected_in_body,
			$percentage);
}
			
sub pattern_body() {
	# first pattern: detect possible price-indications
	return qw( ^\$$|^\$\d+\.?\d*$|^\d+\.?\d*\$ );
}

sub wordlist() {
	return qw/	pics video porn .*porno.* .*sex.* fuck.*
				blowjob suck  /;
}

1;
	
