# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or 
# modify it under the same terms as Perl itself.

# Version: $Id: MboxParser.pm,v 1.10 2001/07/06 06:13:07 parkerpine Exp $

package Mail::MboxParser;

require 5.004;

use Mail::MboxParser::Mail;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT);
$VERSION	= "0.02";
@EXPORT		= qw();
$^W++;

sub new {
	my $call = shift;
	my $class = ref($call) || $call;
	my $self = {};
	
	$self->{READER} = undef;
	$self->{NMSGS}	= undef;
	
	my $file;
	
	if (($file = shift)) { 
		open MBOX, "<$file" 
			or die "Error: Could not open $file for reading: $!";			
		$self->{READER} 	= \*MBOX; 
	}
	bless ($self, $class);
	return $self;
}

sub open {
	my $self = shift;
	die "Error: Mail::MboxParser::open requires an argument\n" if @_ == 0;
	my $file = shift;
	open MBOX, "<$file"
		or die "Error: Could not open $file for reading: $!";
	$self->{READER} = \*MBOX;
	return $self;
}

sub get_messages {
	my $self = shift;
	my ($in_header, $in_body) = (0, 0);
	my ($header, $body);
	my @messages;
	my $h = $self->{READER};
	
	my $got_header;
	while (<$h>) {
		# entering header
		if (/^From (.*)\d{4}\n$/ and not $in_body) {
			($in_header, $in_body) = (1, 0);
			$got_header = 0;
		}
		# entering body
		if ($in_header and /^\n$/) { 
			($in_header, $in_body) = (0, 1);
			$got_header = 1; 
		}
		
		# just before entering next mail-header or running
		# out of data, store message in Mail-object
		if ((/^From (.*)\d{4}\n$/ or eof) and $got_header) {
			my $m = Mail::MboxParser::Mail->new($header, $body);
			push @messages, $m;
			($in_header, $in_body) = (1, 0);
			($header, $body) = (undef, undef);
			$got_header = 0;
		}
		if ($_) {
			$header	.= $_ if $in_header and not $got_header; 
			$body 	.= $_ if $in_body and $got_header;
		}

			
	}
	return @messages;
}
		
sub nmsgs {
	my $self = shift;
	my $h;
	if (not $self->{READER}) { return "No mbox opened" }
	if (not $self->{NMSGS}) {
		$h = $self->{READER};
		while (<$h>) {
			$self->{NMSGS}++ if /^Lines: \d+\n$/;
		}
	}
	return $self->{NMSGS} || "0";	
}	

sub DESTROY {
	my $self = shift;
	$self->{NMSGS} = undef;
	close $self->{READER};
}

1;		

__END__

=head1 NAME

Mail::MboxParser - read-only access to UNIX-mailboxes

=head1 SYNOPSIS

	use Mail::MboxParser;

	my $mb = Mail::MboxParser->new('some_mailbox');

	for my $msg ($mb->get_messages) {
		my %header = %{$msg->header};
		print $msg->from->{name}, "\n";
		print $msg->from->{email}, "\n";
		print $header{subject}, "\n";
		print $header{'reply-to'}, "\n";
		$msg->store_all_attachements('/tmp');
	}

=head1 DESCRIPTION

This module attempts to provide a simplified access to standard UNIX-mailboxes. It offers only a subset of methods to get 'straight to the point'. More sophisticated things can still be done by invoking any method from MIME::Tools on the appropriate return values.

=head2 METHODS

The below methods refer to Mail::MboxParser-objects.

=item new

=item new(MAILBOX)

This creates a new MboxParser-object opening the specified MAILBOX with either absolute or relative path. It does not necessarily need a parameter in which case you need to pass the mailbox to the object using the method 'open'.
Returns nothing.

=item open(mailbox)

Can be used to either pass a mailbox to the MboxParser-object either the first time or for changing the mailbox. 
Returns nothing.

=item get_messages

Returns an array containing all messages in the mailbox respresented as Mail::MboxParser::Mail objects.

=item nmsgs

Returns the number of messages in a mailbox. You could naturally also call get_messages in an array context, but this one wont create new objects. It just counts them and thus it is much quicker and wont eat a lot of memory.

The below methods refer to Mail::MboxParser::Mail-objects returned by get_messages.

=item new(header, body)

This is usually not called directly but instead by $mb->get_messages. You could however create a mail-object manually providing the header and body both as one string.

=item header

Returns the mail-header as a hash-ref with header-fields as keys. All keys are turned to lower-case, so $header{Subject} has to be written as $header{subject}.

=item body

Returns the body as a single string.

=item from

Returns a hash-ref with the two fields 'name' and 'email'. Returns undef if empty.

=item id

Returns the message-id of a message cutting off the leading and trailing '<' and '>' respectively.

=item num_entitities

Returns the number of MIME-entities. That is, the number of sub-entitities actually. 

=item get_entitities([n])

Either returns an array of all MIME::Entity objects or one particular if called with a number.

=item get_entity_body(n)

Returns the body of the n-th MIME::Entity as a single string.

=item store_entity_body(n, FILEHANDLE)

Stores the stringified body of n-th entity to the specified filehandle. That's basically the same as:

	my $body = $mail->get_entity_body(0);
	print FILEHANDLE $body;

and could be shortened to this:

	$mail->store_entity_body(0, \*FILEHANDLE);

=item store_attachement(n, path)

It is really just a call to store_entity_body but it will take care that the n-th entity really is a saveable attachement. That is, it wont save anything with a MIME-type of, say, text/html or so. 
It uses the recommended-filename found in the MIME-header. 'path' is the place where the new file will go to.

=item store_all_attachements(path)

Walks through an entire mail and stores all apparent attachements to 'path'. See the supplied store_att.pl script in the eg-directory of the package to see a useful example.

=head2 FIELDS

Mail::MboxParser is basically a pseudo-hash containing two fields.

=item $mb->{READER}

This is the filehandle from which is read internally. As to yet, it is read-only so you can't use it for writing. This may be changed later.

=item $mb->{NMSGS}

Having called nmsgs once this field contains the number of messages in the mailbox. Thus there is no need for calling the method twice which speeds up matters a little.

Mail::MboxParser::Mail is a pseudo-hash with four fields.

=item $mail->{RAW}

Contains the whole message (that is, header plus body) in one string.

=item $mail->{HEADER}

Well, just the header of the message as a string.

=item $mail->{BODY}

You guess it.

=item $mail->{ENTITY}

The top-level MIME::Entity of a message. You can call any suitable methods from the MIME::tools upon this object to give you more specific access to MIME-parts.

=head1 BUGS

Don't know yet of any. However, since I only have a limited number of mailboxes on which I could test the module, there might be circumstances under which Mail::MboxParser fails to work correctly. It will probably fail on mal-formated mails produced by some cheap CGI-webmailers. 

The way of counting the number of mails in a mailbox is a little suspect. Internally this looks like '$self->{NMSGS}++ if /^Lines: \d+\n$/;'. In case nmsgs really produces bogus then you could try calling get_messages in scalar context: '$mb->{NMSGS} = $mb->get_messages'. Once having done so, a call to nmsgs will produce this number since it only parses once and will only return the previously cached results on later calls.

=head1 AUTHOR AND COPYRIGHT

Tassilo von Parseval <Tassilo.Parseval@post.RWTH-Aachen.de>.

Copyright (c)  2001 Tassilo von Parseval. 
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

