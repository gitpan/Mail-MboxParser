# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or
# modify it under the same terms as Perl itself.

# Version: $Id: Mail.pm,v 1.52 2002/03/01 10:09:32 parkerpine Exp $

package Mail::MboxParser::Mail;

require 5.004;

use base qw(Exporter Mail::MboxParser::Base);

# ----------------------------------------------------------------

=head1 NAME

Mail::MboxParser::Mail - Provide mail-objects and methods upon

=head1 SYNOPSIS

See L<Mail::MboxParser> for examples on usage.

=head1 DESCRIPTION

Mail::MboxParser::Mail objects are usually not created directly though, in theory, they could be. A description of the provided methods can be found in L<Mail::MboxParser>.

However, go on reading if you want to use methods from MIME::Entity and learn about overloading.

=head1 METHODS

=cut

use Mail::MboxParser::Mail::Body;
use Mail::MboxParser::Mail::Convertable;
use Carp;

use strict;
use vars qw($VERSION @EXPORT $AUTOLOAD $NL);
$VERSION    = "0.33";
@EXPORT     = qw();

# we'll use it to store the MIME::Parser 
my $Parser;

use overload '""' => \&as_string, fallback => 1;

# ----------------------------------------------------------------

=over 4

=item B<new(header, body)>

This is usually not called directly but instead by get_messages(). You could however create a mail-object manually providing the header and body each as either one string or as an array-ref representing the lines.

=back

=cut

sub init (@) {
	my ($self, @args) = @_;
	my ($header, $body, $conf) = @args;
	
	$self->{HEADER}			= ref $header ? $header : [ split /$NL/, $header ];
	$self->{HEADER_HASH}	= \&split_header;
	$self->{BODY}			= ref $body ? $body : [ split /$NL/, $body ];
	$self->{TOP_ENTITY}		= 0;
	$self->{ARGS}			= $conf;
	$self;
}

# ----------------------------------------------------------------

=over 4

=item B<header>

Returns the mail-header as a hash-ref with header-fields as keys. All keys are turned to lower-case, so $header{Subject} has to be written as $header{subject}.

If a header-field occurs more than once in the header, the value of the key is an array_ref. Example:

    my $field = $msg->header->{field};
    print $field->[0]; # first occurance of 'field'
    print $field->[1]; # second one
    ...

=back

=cut 

sub header() {
	my $self = shift;
    my $decode = $self->{ARGS}->{decode} || 'NEVER';
	$self->reset_last;
	
	return $self->{HEADER_HASH}->($self, $self->{HEADER}, $decode);
}

# ----------------------------------------------------------------

=over 4

=item B<from_line>

Returns the "From "-line of the message.

=back

=cut

sub from_line() { 
    my $self = shift;
    $self->reset_last;
    
    $self->{HEADER_HASH}->($self, $self->{HEADER}, 'NEVER') 
        if !exists $self->{FROM};
        
    if (! exists $self->{FROM}) {
        $self->{LAST_ERR} = "Message did not contain a From-line";
        return;
    }
    $self->{FROM};
}

# ----------------------------------------------------------------

=over 4

=item B<trace>

This method returns the "Received: "-lines of the message as a list.

=back

=cut

sub trace () {
    my $self = shift;
    $self->reset_last;

    $self->{HEADER_HASH}->($self, $self->{HEADER}, 'NEVER') 
        if ! exists $self->{TRACE};

    if (! exists $self->{TRACE}) {
        $self->{LAST_ERR} = "Message did not contain any Received-lines";
        return;
    }

    @{ $self->{TRACE} };
}

# ----------------------------------------------------------------

=over 4

=item B<body>

=item B<body(n)>

Returns a Mail::MboxParser::Mail::Body object. For methods upon that see further below. When called with the argument n, the n-th body of the message is retrieved. That is, the body of the n-th entity.

Sets $message->error if something went wrong.

=back

=cut

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
		return Mail::MboxParser::Mail::Body->new($ent, $bound, $self->{ARGS});
	}
	
	# else
	if ($bound = $self->header->{'content-type'}) { 
		$bound =~ /boundary="(.*)"/; $bound = $1;
	}	
	return ref $self->{TOP_ENTITY} eq 'MIME::Entity' 
		?	Mail::MboxParser::Mail::Body->new(	$self->{TOP_ENTITY}, 
												$bound,
												$self->{ARGS})
		:	Mail::MboxParser::Mail::Body->new(	scalar $self->get_entities(0), 
												$bound,
												$self->{ARGS});
}

# ----------------------------------------------------------------

=over 4

=item B<find_body>

This will return an index number that represents what Mail::MboxParser considers to be the actual (main)-body of an email. This is useful if you don't know about the structure of a message but want to retrieve the message's signature for instance:

	$signature = $msg->body($msg->find_body)->signature;

Changes are good that find_body does what it is supposed to do.

=back

=cut

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

# ----------------------------------------------------------------

=over 4

=item B<make_convertable>

Returns a Mail::MboxParser::Mail::Convertable object. For details on what you can do with it, read L<Mail::MboxParser::Mail::Convertable>.

=back

=cut

sub make_convertable(@) {
	my $self = shift;
	return ref $self->{TOP_ENTITY} eq 'MIME::Entity'
		? Mail::MboxParser::Mail::Convertable->new($self->{TOP_ENTITY})
		: Mail::MboxParser::Mail::Convertable->new($self->get_entities(0));
}

# ----------------------------------------------------------------

=over 4

=item B<get_field(headerfield)>

Returns the specified raw field from the message header, that is: the fieldname is not stripped off nor is any decoding done. Returns multiple lines as needed if the field is "Received" or another multi-line field.  Not case sensitive.

C<get_field> always returns one string regardless of how many times the field occured in the header. Multiple occurances are separated by a newline and multiple whitespaces squeezed to one. That means you can process each occurance of the field thusly:

    for my $field ( split /\n/, $msg->get_field('received') ) {
        # do something with $field
    }

Sets $mail->error() if the field was not found in which case get_field() returns undef.

=back

=cut

sub get_field($) {    
    my ($self, $fieldname) = @_;
    $self->reset_last;

    my @headerlines = ref $self->{HEADER} 
                            ? @{$self->{HEADER}}
                            : split /$NL/, $self->{HEADER};
    chomp @headerlines;

    my ($ret, $inretfield);
    foreach my $bit (@headerlines) {
        if ($bit =~ /^\s/) { 
            if ($inretfield) { 
                $bit =~ s/\s+/ /g;
                $ret .= $bit; 
            } 
        }
        elsif ($bit =~ /^$fieldname/i) {
            $bit =~ s/\s+/ /g;
            if (++$inretfield > 1) { $ret .= "\n" . $bit }
            else                   { $ret .= $bit }
        }
        else { $inretfield = 0; }
    }
    
    $self->{LAST_ERR} = "No such field" if not $ret;
    return $ret;
}
        
# ----------------------------------------------------------------

=over 4

=item B<from>

Returns a hash-ref with the two fields 'name' and 'email'. Returns undef if empty. The name-field does not necessarily contain a value either. Example:
	
	print $mail->from->{email};

=back

=cut

sub from() {
	my $self = shift;
	$self->reset_last;
	
	my $from = $self->header->{from};
	my ($name, $email) = split /\s\</, $from;
	$email =~ s/\>$//g unless not $email;
	if ($name && ! $email) {
		$email = $name;
		$name  = "";
	}
	return {(name => $name, email => $email)};
}

# ----------------------------------------------------------------

=over 4

=item B<to>

Returns an array of hash-references of all to-fields in the mail-header. Fields are the same as those of $mail->from. Example:

	for my $recipient ($mail->to) {
		print $recipient->{name} || "<no name>", "\n";
		print $recipient->{email};
	}

=back

=cut

sub to() { shift->_recipients("to") }

# ----------------------------------------------------------------

=over 4

=item B<cc>

Identical with to() but returning the hash-refed "Cc: "-line.

=back

=cut

sub cc() { shift->_recipients("cc") }

# ----------------------------------------------------------------

=over 4

=item B<id>

Returns the message-id of a message cutting off the leading and trailing '<' and '>' respectively.

=back

=cut

sub id() { 
	my $self = shift;
	$self->reset_last;
	$self->header->{'message-id'} =~ /\<(.*)\>/; 
	$1; 
} 

# ----------------------------------------------------------------

# --------------------
# MIME-related methods
#---------------------

# ----------------------------------------------------------------

=over 4

=item B<num_entities>

Returns the number of MIME-entities. That is, the number of sub-entitities actually. If 0 is returned and you think this is wrong, check $mail->log.

=back

=cut

sub num_entities() { 
	my $self = shift;
	$self->reset_last;
	# force list contest becaus of wantarray in get_entities
	$self->{NUM_ENT} = () = $self->get_entities unless defined $self->{NUM_ENT};
	return $self->{NUM_ENT};
}

# ----------------------------------------------------------------

=over 4

=item B<get_entities>

=item B<get_entities(n)>

Either returns an array of all MIME::Entity objects or one particular if called with a number. If no entity whatsoever could be found, an empty list is returned.

$mail->log instantly called after get_entities will give you some information of what internally may have failed. If set, this will be an error raised by MIME::Entity but you don't need to worry about it at all. It's just for the record.

=back

=cut

sub get_entities(@) {
	my ($self, $num) = @_;
	$self->reset_last;
	
	if (defined $num && $num >= $self->num_entities) {
		$self->{LAST_ERR} = "No such entity"; 
		return;
	}
	
	if (ref $self->{TOP_ENTITY} ne 'MIME::Entity') {
        
        if (! defined $Parser) {
            eval { require MIME::Parser; };
            $Parser = new MIME::Parser; $Parser->output_to_core(1);
        }

        my $data = join "", @{ $self->{HEADER} }, @{ $self->{BODY} };
		$self->{TOP_ENTITY} = $Parser->parse_data($data);
	}
	
	my @parts = eval { $self->{TOP_ENTITY}->parts_DFS; };
	$self->{LAST_LOG} = $@ if $@;
	return wantarray ? @parts : $parts[$num];
}

# ----------------------------------------------------------------

# just overriding MIME::Entity::parts() 
# to work around its strange behaviour
 
sub parts(@) { shift->get_entities(@_) }

# ----------------------------------------------------------------

=over 4

=item B<get_entity_body(n)>

Returns the body of the n-th MIME::Entity as a single string, undef otherwise in which case you could check $mail->error.

=back

=cut

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

# ----------------------------------------------------------------

=over 4

=item B<store_entity_body(n, handle =E<gt> FILEHANDLE)>

Stores the stringified body of n-th entity to the specified filehandle. That's basically the same as:

 my $body = $mail->get_entity_body(0);
 print FILEHANDLE $body;

and could be shortened to this:

 $mail->store_entity_body(0, handle => \*FILEHANDLE);

It returns a true value on success and undef on failure. In this case, examine the value of $mail->error since the entity you specified with 'n' might not exist.

=back

=cut

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
    
    binmode $args{handle};
	my $b = $self->get_entity_body($num);
	print { $args{handle} } $b if defined $b; 
	return 1;
}

# ----------------------------------------------------------------

=over 4

=item B<store_attachment(n)>  

=item B<store_attachment(n, options)>  

It is really just a call to store_entity_body but it will take care that the n-th entity really is a saveable attachment. That is, it wont save anything with a MIME-type of, say, text/html or so. 

Unless further 'options' have been given, an attachment (if found) is stored into the current directory under the recommended filename given in the MIME-header. 'options' are specified in key/value pairs:

    key:       | value:        | description:
    ===========|===============|===============================
    path       | relative or   | directory to store attachment
    (".")      | absolute      |
               | path          |
    -----------|---------------|-------------------------------
    store_only | a compiled    | store only files whose file
               | regex-pattern | names match this pattern
    -----------|---------------|-------------------------------
    code       | an anonym     | first argument will be the 
               | subroutine    | $msg-object, second one the 
               |               | index-number of the current
               |               | MIME-part
               |               | should return a filename for
               |               | the attachment
    -----------|---------------|-------------------------------
    args       | additional    | this array-ref will be passed  
               | arguments as  | on to the 'code' subroutine
               | array-ref     | as a dereferenced array

Example:

 	$msg->store_attachment(1, 
                            path => "/home/ethan/", 
                            code => sub {
                                        my ($msg, $n, @args) = @_;
                                        return $msg->id."+$n";
                                        },
                            args => [ "Foo", "Bar" ]);

This will save the attachment found in the second entity under the name that consists of the message-ID and the appendix "+1" since the above code works on the second entity (that is, with index = 1). 'args' isn't used in this example but should demonstrate how to pass additional arguments. Inside the 'code' sub, @args equals ("Foo", "Bar").

If 'path' does not exist, it will try to create the directory for you.

You can specify to save only files matching a certain pattern. To do that, use the store-only switch:

    $msg->store_attachment(1, path       => "/home/ethan/", 
                              store_only => qr/\.jpg$/i);

The above will only save files that end on '.jpg', not case-sensitive. You could also use a non-compiled pattern if you want, but that would make for instance case-insensitive matching a little cumbersome:

    store_only => '(?i)\.jpg$'
    
Returns the filename under which the attachment has been saved. undef is returned in case the entity did not contain a saveable attachement, there was no such entity at all or there was something wrong with the 'path' you specified. Check $mail->error to find out which of these possibilities appliy.

=back

=cut

sub store_attachment($@) {
	my $self = shift;
	my ($num, %args) = @_;
	$self->reset_last;
	
	my $path = $args{path} || ".";
	$path =~ s/\/$//;

	if (defined $args{code} && ref $args{code} ne 'CODE') {
		carp <<EOW;	
Warning: Second argument for store_attachment must be
a coderef. Using filename from header instead
EOW
		delete @args{ qw(code args) };
	}
    
	if ($num < $self->num_entities) {
		my $file = eval { 
			$self->get_entities($num)->head->recommended_filename; };
		$self->{LAST_LOG} = $@;
		if (not $file) {
            # test for Content-Disposition
            if (! $self->get_entities($num)->head->get('content-disposition')) {
                $self->{LAST_ERR} = "No attachment in entity $num";
			    return;
            }
            else {
                my ($type, $filename) = split /;\s*/, 
                    $self->get_entities($num)->head->get('content-disposition');
                if ($type ne 'attachment') {
                    $self->{LAST_ERR} = "No attachment in entity $num";
                    return;
                }
                else {
                    $filename =~ /filename\*?=(.*?''?)?(.*)$/;
                    ($file = $2) =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
                    if (! $file) {
                        $self->{LAST_ERR} = "No attachment in entity $num";
                        return;
                    }
                }
            }
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
                                                        
        if ($file =~ /^=\?/) { # decode qp if possible
            eval { require MIME::Words; };
            $file = MIME::Words::decode_mimewords($file) if ! $@;
        }
    
        return if defined $args{store_only} and 
                  $file !~ /$args{store_only}/;
        
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

# ----------------------------------------------------------------

=over 4

=item B<store_all_attachments>  

=item B<store_all_attachments(options)>  

Walks through an entire mail and stores all apparent attachments. 'options' are exactly the same as in store_attachement() with the same behaviour if no options are given. 

Returns a list of files that has been succesfully saved and an empty list if no attachment could be extracted.

$mail->error will tell you possible failures and a possible explanation for that.

=back

=cut

sub store_all_attachments(@) {
	my $self = shift;
    my %args = @_;
	$self->reset_last;
    
	if (defined $args{code} and ref $args{code} ne 'CODE') {
		carp <<EOW; 	
Warning: Second argument for store_all_attachments must be a coderef. 
Using filename from header instead 
EOW
		delete @args{ qw(code args) };
	}
	my @files;

    if (! exists $args{path} || $args{path} eq '') {
        $args{path} = '.';
    }
    
	for (0 .. $self->num_entities - 1) {
		push @files, $self->store_attachment($_, %args);
	}

	$self->{LAST_ERR} = "Found no attachment at all" if ! @files; 
	return @files;
}

# ----------------------------------------------------------------

=over 4

=item B<get_attachments>

=item B<get_attachments(file)>

This method returns a mapping from attachment-names (if those are savable) to index-numbers of the MIME-part that represents this attachment. It returns a hash-reference, the file-names being the key and the index the value:

    my $mapping = $msg->get_attachments;
    for my $filename (keys %$mapping) {
        print "$filename => $mapping->{$filename}\n";
    }

If called with a string as argument, it tries to look up this filename. If it can't be found, undef is returned. In this case you also should have an error-message patiently awaiting you in the return value of $msg->error().

Even though it looks tempting, don't do the following:

    # BAD!

    for my $file (qw/file1.ext file2.ext file3.ext file4.ext/) {
        print "$file is in message ", $msg->id, "\n"  
            if defined $msg->get_attachments($file);
    }

The reason is that B<get_attachments> is currently *not* optimized to cache the filename mapping. So, each time you call it on (even the same) message, it will scan it from beginning to end. Better would be:

    # GOOD!

    my $mapping = $msg->get_attachments;
    for my $file (qw/file1.ext file2.ext file3.ext file4.ext/) {
        print "$file is in message ", $msg->id, "\n" 
            if exists $mapping->{$file};
    }

=back

=cut

sub get_attachments(;$) {
	my ($self, $name) = @_;
	$self->reset_last;
    my %mapping;
    
    for my $num (0 .. $self->num_entities - 1) {
		my $file = eval { 
			$self->get_entities($num)->head->recommended_filename; 
        };
		$self->{LAST_LOG} = $@;
		if (! $file) {
            # test for Content-Disposition
            if (! $self->get_entities($num)->head->get('content-disposition')) {
                next;
            }
            else {
                my ($type, $filename) = split /;\s*/, 
                    $self->get_entities($num)->head->get('content-disposition');
                if ($type eq 'attachment') {
                    $filename =~ /filename\*?=(.*?''?)?(.*)$/;
                    ($file = $2) =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/eg;
                }
            }
		}
        
        next if ! $file;
        
        if ($file =~ /^=\?/) { # decode qp if possible
            eval { require MIME::Words; };
            $file = MIME::Words::decode_mimewords($file) if ! $@;
        }
        
        $mapping{$file} = $num;
        
	}
    
    if ($name) {
        if (! exists $mapping{$name}) {
            $self->{LAST_ERR} = "$name: No such attachment";
            return;
        }
        else { return $mapping{$name} }
    }
    
    if (keys %mapping == 0) {
        $self->{LAST_ERR} = "No attachments at all";
        return;
    }
    
    return \%mapping;
}
    
sub as_string {
	my $self = shift;
    
	return join "", @{ $self->{HEADER} }, @{ $self->{BODY} };
}

sub _recipients($) {
	my ($self, $field) = @_;
	$self->reset_last;
	
	my $rec = $self->header->{$field};
	if (! $rec) {
		$self->{LAST_ERR} = "'$field' not in header";
		return;
	}
	
	my @recs = split /,/, $rec;
	map { s/^\s+//; s/\s+$// } @recs; # remove leading or trailing whitespaces
	my @rec_line;
	for my $pair (@recs) {
		my ($name, $email) = split /\s</, $pair;
		$email =~ s/\>$//g if $email;
		if ($name && ! $email) {
			$email = $name;
			$name  = "";
		}
		push @rec_line, {(name => $name, email => $email)};
	}
	
	return @rec_line;
}

# patch provided            by Kenn Frankel
# additional corrections    by Nathan Uno
sub split_header {
    local $/ = $NL;
	my ($self, $header, $decode) = @_;
	my @headerlines = @{ $header };

	my @header;
    chomp @headerlines if ref $header;
 	foreach my $bit (@headerlines) {
        $bit =~ s/\s+$//;       # discard trailing whitespace
		if ($bit =~ s/^\s+/ /)  { $header[-1] .= $bit }
		else 				    { push @header, $bit }
	}
											   
	my ($key, $value);
	my %header;
	for (@header) {
        
        if    (/^Received:\s/) { push @{$self->{TRACE}}, substr($_, 10) }
        elsif (/^From /)       { $self->{FROM} = $_ }
        else {
            my $idx = index $_, ": ";
			$key   = substr $_, 0, $idx;
			$value = $idx != -1 ? substr $_, $idx + 2 : "";
            if ($decode eq 'ALL' || $decode eq 'HEADER') {
                use MIME::Words qw(:all);
                $value = decode_mimewords($value); 
            }

            # if such a field is already there => make array-ref
            if (exists $header{lc($key)}) {
                my $elem = $header{lc($key)};
                my @data = ref $elem ? @$elem : $elem;
                push @data, $value;
                $header{lc($key)} = [ @data ];
            }
            else {
                $header{lc($key)} = $value;
            }
		}
	}
	return  \%header;
}

sub AUTOLOAD {
	my ($self, @args) = @_;
	(my $call = $AUTOLOAD) =~ s/.*:://;

    # for backward-compatibility
    if ($call eq 'store_attachement') { 
        return $self->store_attachment(@args);
    }
    if ($call eq 'store_all_attachements') {
        return $self->store_all_attachments(@args);
    }
    
	# test some potential classes that might implement $call
    { 
        no strict 'refs';
    
        for my $class (qw/MIME::Entity Mail::Internet/) {
            eval "require $class";
            # we found a Class that implements $call
            if ($class->can($call)) {
                
                # MIME::Entity needed
                if ($class eq 'MIME::Entity') {
                    
                    if (! defined $Parser) {
                        eval { require MIME::Parser };
                        $Parser = new MIME::Parser; 
                        $Parser->output_to_core(1);
                    }
                    $self->{TOP_ENTITY} = 
                        $Parser->parse_data(join "", @{$self->{HEADER}},
                                                     @{$self->{BODY}})
                            if ref $self->{TOP_ENTITY} ne 'MIME::Entity';
                    return $self->{TOP_ENTITY}->$call(@args);
                }

                # Mail::Internet needed
                if ($class eq 'Mail::Internet') {
                    return Mail::Internet->new(
                        [ split /\n/, join "", ref $self->{HEADER}
                                                ? @{$self->{HEADER}}
                                                : $self->{HEADER}
                                            .$self->{BODY} ] 
                        );
                }
                
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

=head1 EXTERNAL METHODS

Mail::MboxParser::Mail implements an autoloader that will do the appropriate type-casts for you if you invoke methods from external modules. This, however, currently only works with MIME::Entity. Support for other modules will follow.
Example:

	my $mb = Mail::MboxParser->new("/home/user/Mail/received");
	for my $msg ($mb->get_messages) {
		print $msg->effective_type, "\n";
	}

effective_type() is not implemented by Mail::MboxParser::Mail and thus the corresponding method of MIME::Entity is automatically called.

To learn about what methods might be useful for you, you should read the "Access"-part of the section "PUBLIC INTERFACE" in the MIME::Entity manpage.
It may become handy if you have mails with a lot of MIME-parts and you not just want to handle binary-attachments but any kind of MIME-data.

=head1 OVERLOADING

Mail::MboxParser::Mail overloads the " " operator. Overloading operators is a fancy feature of Perl and some other languages (C++ for instance) which will change the behaviour of an object when one of those overloaded operators is applied onto it. Here you get the stringified mail when you write "$mail" while otherwise you'd get the stringified reference: Mail::MboxParser::Mail=HASH(...).

=head1 VERSION

This is version 0.36.

=head1 AUTHOR AND COPYRIGHT

Tassilo von Parseval <tassilo.parseval@post.rwth-aachen.de>

Copyright (c)  2001-2002 Tassilo von Parseval.
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<MIME::Entity>

L<Mail::MboxParser>, L<Mail::MboxParser::Mail::Body>, L<Mail::MboxParser::Mail::Convertable>

=cut
