# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# Version: $Id: Mail.pm,v 1.34 2001/09/20 11:26:46 parkerpine Exp $

package Mail::MboxParser::Mail;

require 5.004;

use Mail::MboxParser::Mail::Body;
use Mail::MboxParser::Mail::Convertable;
use MIME::Parser;
use Carp;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT @ISA $AUTOLOAD);
$VERSION    = "0.19";
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
    my $decode = $self->{ARGS}->{decode} || 'NEVER';
	$self->reset_last;
	
	return $self->{HEADER_HASH}->($self->{HEADER}, $decode);
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

sub get_field($) {    
    my ($self, $fieldname) = @_;
    $self->reset_last;

    my @headerlines = split /\n/, $self->{HEADER};
    my ($ret, $inretfield);
    foreach my $bit (@headerlines) {
        if ($bit =~ /^\s/) { if ($inretfield) { $ret .= $bit."\n"; } }
        elsif ($bit =~ /^$fieldname/i) { ++$inretfield; $ret .= $bit."\n"; }
        else { $inretfield = 0; }
    }
    $self->{LAST_ERR} = "No such field" if not $ret;
    return $ret;
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

sub as_string {
	my $self = shift;
	return $self->{HEADER}.$self->{BODY};
}

sub _recipients($) {
	my ($self, $field) = @_;
	$self->reset_last;
	
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
	
	return @rec_line;
}

# patch provided by Kenn Frankel
sub split_header {
	my ($header, $decode) = @_;
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
            if ($decode eq 'ALL' || $decode eq 'HEADER') {
                use MIME::Words qw(:all);
                $value = decode_mimewords($value); 
            }
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

=head1 METHODS

=over 4

=item B<new(header, body)>

This is usually not called directly but instead by get_messages(). You could however create a mail-object manually providing the header and body both as one string.

=item B<header>

Returns the mail-header as a hash-ref with header-fields as keys. All keys are turned to lower-case, so $header{Subject} has to be written as $header{subject}.

=item B<body>

=item B<body(n)>

Returns a Mail::MboxParser::Mail::Body object. For methods upon that see further below. When called with the argument n, the n-th body of the message is retrieved. That is, the body of the n-th entity.

Sets $message->error if something went wrong.

=item B<find_body>

This will return an index number that represents what Mail::MboxParser considers to be the actual (main)-body of an email. This is useful if you don't know about the structure of a message but want to retrieve the message's signature for instance:

	$signature = $msg->body($msg->find_body)->signature;

Changes are good that find_body does what it is supposed to do.

=item B<get_field(headerfield)>

Returns the specified raw field from the message header, that is: no transformation or decoding is done. Returns multiple lines as needed if the field is "Received" or another multi-line field.  Not case sensitive.
Sets $mail->error() if the field was not found in which case get_field() returns undef.

=item B<from>

Returns a hash-ref with the two fields 'name' and 'email'. Returns undef if empty. The name-field does not necessarily contain a value either. Example:
	
	print $mail->from->{email};

=item B<to>

Returns an array of hash-references of all to-fields in the mail-header. Fields are the same as those of $mail->from. Example:

	for my $recipient ($mail->to) {
		print $recipient->{name} || "<no name>", "\n";
		print $recipient->{email};
	}

=item B<cc>

Identical with to() but returning the hash-refed "Cc: "-line.

=item B<id>

Returns the message-id of a message cutting off the leading and trailing '<' and '>' respectively.

=item B<num_entitities>

Returns the number of MIME-entities. That is, the number of sub-entitities actually. If 0 is returned and you think this is wrong, check $mail->log.

=item B<get_entities>

=item B<get_entities(n)>

Either returns an array of all MIME::Entity objects or one particular if called with a number. If no entity whatsoever could be found, an empty list is returned.

$mail->log instantly called after get_entities will give you some information of what internally may have failed. If set, this will be an error raised by MIME::Entity but you don't need to worry about it at all. It's just for the record.

=item B<get_entity_body(n)>

Returns the body of the n-th MIME::Entity as a single string, undef otherwise in which case you could check $mail->error.

=item B<store_entity_body(n, handle =E<gt> FILEHANDLE)>

Stores the stringified body of n-th entity to the specified filehandle. That's basically the same as:

 my $body = $mail->get_entity_body(0);
 print FILEHANDLE $body;

and could be shortened to this:

 $mail->store_entity_body(0, handle => \*FILEHANDLE);

It returns a true value on success and undef on failure. In this case, examine the value of $mail->error since the entity you specified with 'n' might not exist.

=item B<store_attachement(n)>  [sic!]

=item B<store_attachement(n, options)>  [sic!]

It is really just a call to store_entity_body but it will take care that the n-th entity really is a saveable attachement. That is, it wont save anything with a MIME-type of, say, text/html or so. 

Unless further 'options' have been given, an attachement (if found) is stored into the current directory under the recommended filename given in the MIME-header. 'options' are specified in key/value pairs:

    key:      | value:       | description:
    ==========|==============|===============================
    path      | relative or  | directory to store attachement
    (".")     | absolute     |
              | path         |
    ==========|==============|===============================
    code      | an anonym    | first argument will be the 
              | subroutine   | $msg-object, second one the 
              |              | index-number of the current
              |              | MIME-part
              |              | should return a filename for
              |              | the attachement
    ==========|==============|===============================
    args      | additional   | this array-ref will be passed  
              | arguments as | on to the 'code' subroutine
              | array-ref    | as a dereferenced array

Example:

 	$msg->store_attachement(1, 
                            path => "/home/ethan/", 
                            code => sub {
                                        my ($msg, $n, @args) = @_;
                                        return $msg->id."+$n";
                                        },
                            args => [ "Foo", "Bar" ]);

This will save the attachement found in the second entity under the name that consists of the message-ID and the appendix "+1" since the above code works on the second entity (that is, with index = 1). 'args' isn't used in this example but should demonstrate how to pass additional arguments. Inside the 'code' sub, @args equals ("Foo", "Bar").

If 'path' does not exist, it will try to create the directory for you.

Returns the filename under which the attachement has been saved. undef is returned in case the entity did not contain a saveable attachement, there was no such entity at all or there was something wrong with the 'path' you specified. Check $mail->error to find out which of these possibilities appliy.

=item B<store_all_attachements>  [sic!]

=item B<store_all_attachements(options)>  [sic!]

Walks through an entire mail and stores all apparent attachements. 'options' are exactly the same as in store_attachement() with the same behaviour if no options are given. 

Returns a list of files that has been succesfully saved and an empty list if no attachement could be extracted.

$mail->error will tell you possible failures and a possible explanation for that.

=item B<make_convertable>

Returns a Mail::MboxParser::Mail::Convertable object. For details on what you can do with it, read L<Mail::MboxParser::Mail::Convertable>.

=back

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

=cut
