# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# Version: $Id: Mail.pm,v 1.32 2001/09/08 08:34:47 parkerpine Exp $

package Mail::MboxParser::Mail;

require 5.004;

use Mail::MboxParser::Mail::Body;
use Mail::MboxParser::Mail::Convertable;
use MIME::Parser;
use Carp;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT @ISA $AUTOLOAD);
$VERSION    = "0.17";
@EXPORT     = qw();
@ISA		= qw(Mail::MboxParser::Base);
$^W++;

my $Parser = new MIME::Parser; $Parser->output_to_core(1);

use overload '""' => \&as_string, fallback => 1;

sub init (@) {
	my ($self, @args) = @_;
	my ($header, $body, $conf) = @args;
	
	$self->{HEADER}			= $header;
	$self->{HEADER_HASH}	= \&split_header;
	$self->{BODY}			= $body;
	$self->{TOP_ENTITY}		= 0;
	$self->{ARGS}			= $conf;
	$self;
}

sub header() {
	my $self = shift;
	$self->reset_last;
	
	return $self->{HEADER_HASH}->($self->{HEADER});
}

sub body(;$) { 
	my ($self, $num) = @_;
	$self->reset_last;

	if (defined $num && $num >= $self->num_entities) {
		$self->{LAST_ERR} = "No such body";
		return;
	}

	# body needs the "Content-type: ... boundary=" stuff
	# in order to decide which lines are part of signature and
	# which lines are not (ie denote a MIME-part)
	my $bound; 
	
	# particular entity desired?
	# we need to read the header of this entity then :-(
	if (defined $num) {		
		my $ent = $self->get_entities($num);
		if ($bound = $ent->head->get('content-type')) {
			$bound =~ /boundary="(.*)"/; $bound = $1;
		}
		return Mail::MboxParser::Mail::Body->new(	$ent, 
													$bound, 
													$self->{ARGS});
	}
	
	# else
	if ($bound = $self->header->{'content-type'}) { 
		$bound =~ /boundary="(.*)"/; $bound = $1;
	}	
	return ref $self->{TOP_ENTITY} eq 'MIME::Entity' 
		?	Mail::MboxParser::Mail::Body->new(	$self->{TOP_ENTITY}, 
												$bound,
												$self->{ARGS})
		:	Mail::MboxParser::Mail::Body->new(	$self->get_entities(0), 
												$bound,
												$self->{ARGS});
}

sub find_body() {
	my $self = shift;
	$self->{LAST_ERR} = "Could not find a suitable body at all";
	my $num = -1;
	for my $part ($self->parts_DFS) {
		$num++;
		if ($part->effective_type eq 'text/plain') {
			$self->reset_last; last;
		}
	}
	return $num;
}

sub make_convertable(@) {
	my $self = shift;
	return ref $self->{TOP_ENTITY} eq 'MIME::Entity'
		? Mail::MboxParser::Mail::Convertable->new($self->{TOP_ENTITY})
		: Mail::MboxParser::Mail::Convertable->new($self->get_entities(0));
}

sub from() {
	my $self = shift;
	$self->reset_last;
	my $decode = $self->{ARGS}->{decode} || 'NEVER';
	
	my $from = $self->header->{from};
	my ($name, $email) = split /\s\</, $from;
	$email =~ s/\>$//g unless not $email;
	if ($name && not $email) {
		$email = $name;
		$name  = "";
	}
	
	if ($decode eq 'HEADER' || $decode eq 'ALL') { 
		use MIME::Words qw(:all);
		$name = decode_mimewords($name);
	}

	return {(name => $name, email => $email)};
}

sub to() { shift->_recipients("to") }

sub cc() { shift->_recipients("cc") }

sub id() { 
	my $self = shift;
	$self->reset_last;
	$self->header->{'message-id'} =~ /\<(.*)\>/; 
	$1; 
} 

# --------------------
# MIME-related methods
#---------------------

sub num_entities() { 
	my $self = shift;
	$self->reset_last;
	# force list contest becaus of wantarray in get_entities
	$self->{NUM_ENT} = () = $self->get_entities unless defined $self->{NUM_ENT};
	return $self->{NUM_ENT};
}

sub get_entities(@) {
	my ($self, $num) = @_;
	$self->reset_last;
	
	if (defined $num && $num >= $self->num_entities) {
		$self->{LAST_ERR} = "No such entity"; 
		return;
	}
	
	if (ref $self->{TOP_ENTITY} ne 'MIME::Entity') {
		$self->{TOP_ENTITY} = 
			$Parser->parse_data($self->{HEADER}.$self->{BODY});
	}
	
	my @parts = eval { $self->{TOP_ENTITY}->parts_DFS; };
	$self->{LAST_LOG} = $@ if $@;
	return wantarray ? @parts : $parts[$num];
}

# just overriding MIME::Entity::parts() 
# to work around its strange behaviour
sub parts(@) { shift->get_entities(@_) }

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

sub store_entity_body($@) {
	my $self = shift;
	my ($num, %args) = @_;		
	$self->reset_last;
	
	if (not $num || (not exists $args{handle} && 
                     ref $args{handle} ne 'GLOB')) {
		croak <<EOC;
Wrong number or type of arguments for store_entity_body. Second argument must
have the form handle => \*FILEHANDLE.
EOC
	}
    my $handle = $args{handle};

	my $b = $self->get_entity_body($num);

	print $handle $b if defined $b; 
	return 1;
}

sub store_attachement($@) {
	my $self = shift;
	my ($num, %args) = @_;
	$self->reset_last;
	
	my $path = $args{path} || ".";
	$path =~ s/\/$//;

	if (defined $args{code} && ref $args{code} ne 'CODE') {
		carp <<EOW;	
Warning: Second argument for store_attachement must be
a coderef. Using filename from header instead
EOW
		delete @args{ qw(code args) };
	}

	if ($num < $self->num_entities) {
		my $file = eval { 
			$self->get_entities($num)->head->recommended_filename; };
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
		
		if (defined $args{code}) { $file = $args{code}->($self, 
                                                        $num, 
                                                        @{$args{args}}) }
		if (open ATT, ">$path/$file") {
			$self->store_entity_body($num, handle => \*ATT);
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

sub store_all_attachements(@) {
	my $self = shift;
    my %args = @_;
	$self->reset_last;
    
	if (defined $args{code} and ref $args{code} ne 'CODE') {
		carp <<EOW; 	
Warning: Second argument for store_all_attachements must be a coderef. 
Using filename from header instead 
EOW
		delete @args{ qw(code args) };
	}
	my @files;
	for (0 .. $self->num_entities - 1) {
		push @files, $self->store_attachement(  $_, 
                                                path => $args{path} || ".",
                                                code => $args{code},
                                                args => $args{args});
                                               
                                               
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

sub as_string {
	my $self = shift;
	return $self->{HEADER}.$self->{BODY};
}

sub _recipients($) {
	my ($self, $field) = @_;
	$self->reset_last;
	my $decode = $self->{ARGS}->{decode} || 'NEVER';
	
	my $rec = $self->header->{$field};
	if (not $rec) {
		$self->{LAST_ERR} = "'$field' not in header";
		return;
	}
	
	my @recs = split /,/, $rec;
	map { s/^\s+//; s/\s+$// } @recs; # remove leading or trailing whitespaces
	my @rec_line;
	for my $pair (@recs) {
		my ($name, $email) = split /\s</, $pair;
		$email =~ s/\>$//g unless not $email;
		if ($name and not $email) {
			$email = $name;
			$name  = "";
		}
		push @rec_line, {(name => $name, email => $email)};
	}
	
	if ($decode eq 'HEADER' || $decode eq 'ALL') {
		use MIME::Words qw(:all);
		map { $_->{name} = decode_mimewords($_->{name}) } @rec_line;
	}
	
	return @rec_line;
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
	return { %header };
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	(my $call = $AUTOLOAD) =~ s/.*\:\://;
	
	# create some dummy objects to use with can() unless we have some
	my @dummies;
	if (ref $self->{TOP_ENTITY} eq 'MIME::Entity') {
		push @dummies, $self->{TOP_ENTITY}; 
	}
	else  {
		push @dummies, MIME::Entity->new;
	}
	
	# test some potential classes that might implement $call
	for my $class (@dummies) {
		# we found a Class that implements $call
		if ($class->can($call)) {
			if (ref $class eq 'MIME::Entity') {
				no strict "refs";
				$self->{TOP_ENTITY} = 
					$Parser->parse_data($self->{HEADER}.$self->{BODY})
						if ref $self->{TOP_ENTITY} ne 'MIME::Entity';
				return $self->{TOP_ENTITY}->$call(@args);
			}

			if (ref $class eq 'Mail::Internet') {
				no strict "refs";
				return Mail::Internet->new(
					[ split /\n/, $self->{HEADER}.$self->{BODY} ] 
					);
			}
		}
	}	
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

However, go on reading if you want to use methods from MIME::Entity and learn about overloading.

=head1 EXTERNAL METHODS

Mail::MboxParser::Mail implements an autoloader that will do the appropriate type-casts for you if you invoke methods from external modules. This, however, currently only works with MIME::Entity. Support for other modules will follow.
Example:

	my $mb = Mail::MboxParser->new("/home/user/Mail/received");
	for my $msg ($mb->get_messages) {
		print $msg->effective_type, "\n";
	}

effective_type() is not implemented by Mail::MboxParser::Mail and thus the corresponding method of MIME::Entity is automatically called.

To learn about what methods might be useful for you, you should read the "Access"-part of the section "PUBLIC INTERFACE" in the MIME::Entity manpage.
It may become handy if you have mails with a lot of MIME-parts and you not just want to handle binary-attachements but any kind of MIME-data.

=head1 OVERLOADING

Mail::MboxParser::Mail overloads the " " operator. Overloading operators is a fancy feature of Perl and some other languages (C++ for instance) which will change the behaviour of an object when one of those overloaded operators is applied onto it. Here you get the stringified mail when you write "$mail" while otherwise you'd get the stringified reference: Mail::MboxParser::Mail=HASH(...).

=head1 AUTHOR AND COPYRIGHT

Tassilo von Parseval <Tassilo.Parseval@post.RWTH-Aachen.de>.

Copyright (c)  2001 Tassilo von Parseval.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Mail::MboxParser> for a description of methods

=cut
