# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or 
# modify it under the same terms as Perl itself.

# Version: $Id: MboxParser.pm,v 1.18 2001/08/04 12:09:14 parkerpine Exp $

package Mail::MboxParser;

require 5.004;

use Mail::MboxParser::Mail;

use strict;
use base qw(Exporter);
use vars qw($VERSION @EXPORT);
$VERSION	= "0.09";
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
}

sub get_messages {
	my $self = shift;
	my ($in_header, $in_body) = (0, 0);
	my ($header, $body);
	my (@header, @body);
	my @messages;
	my $h = $self->{READER};
	
	my $got_header;
	my $from_date  = qr(^From (.*)\d{4}\n$);
	my $empty_line = qr(^\n$);

	seek $h, 0, 0;
	while (<$h>) {
		# entering header
		if (not $in_body and /$from_date/) {
			($in_header, $in_body) = (1, 0);
			$got_header = 0;
		}
		# entering body
		if ($in_header and /$empty_line/) { 
			($in_header, $in_body) = (0, 1);
			$got_header = 1; 
		}
		
		# just before entering next mail-header or running
		# out of data, store message in Mail-object
		if ((/$from_date/ or eof) and $got_header) {
			$header = join '', @header;
			$body 	= join '', @body;
			my $m = Mail::MboxParser::Mail->new($header, $body);
			push @messages, $m;
			($in_header, $in_body) = (1, 0);
			($header, $body) = (undef, undef);
			undef @header; undef @body;
			$got_header = 0;
		}
		if ($_) {
			push @header, $_ if $in_header and not $got_header; 
			push @body, $_ if $in_body and $got_header;
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
		my $from_date = qr(^From (.*)\d{4}\n$);
		while (<$h>) {
			$self->{NMSGS}++ if /$from_date/;
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
		print $msg->from->{name}, "\n";
		print $msg->from->{email}, "\n";
		print $msg->header->{subject}, "\n";
		print $msg->header->{'reply-to'}, "\n";
		$msg->store_all_attachements('/tmp');
	}

=head1 DESCRIPTION

This module attempts to provide a simplified access to standard UNIX-mailboxes. It offers only a subset of methods to get 'straight to the point'. More sophisticated things can still be done by invoking any method from MIME::Tools on the appropriate return values.

=head1 METHODS

The below methods refer to Mail::MboxParser-objects.

=over 4

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

=back

The below methods refer to Mail::MboxParser::Mail-objects returned by get_messages.

=over 4

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

=back

=head1 FIELDS

Mail::MboxParser basically is a hash-ref:

=over 4

=item $mb->{READER}

This is the filehandle from which is read internally. As to yet, it is read-only so you can't use it for writing. This may be changed later.

=item $mb->{NMSGS}

Having called nmsgs once this field contains the number of messages in the mailbox. Thus there is no need for calling the method twice which speeds up matters a little.

Mail::MboxParser::Mail consists of the following fields:

=item $mail->{RAW}

This field no longer exists in order to save memory. Instead, do something like

 $entire_message = $mail->{HEADER}.$mail->{BODY};

=item $mail->{HEADER}

Well, just the header of the message as a string.

=item $mail->{BODY}

You guess it.

=item $mail->{TOP_ENTITY}

The top-level MIME::Entity of a message. You can call any suitable methods from the MIME::tools upon this object to give you more specific access to MIME-parts.

This field is undefined until one of the MIME-methods (num_entities, get_entities etc.) is called for the sake of efficiency.

=back

=head1 CAVEATS

I have been working hard on making Mail::MboxParser eat less memory and as quick as possible. Due to that, two time and memory consuming matters are now called on demand. That is, parsing out the MIME-parts and turning the raw header into a hash have become closures.

The drawback of that is that it may get inefficient if you often call 

 $mail->header->{field}
 
In this case you should probably save the return value of $mail->header (a hashref) into a variable since each time you call it the raw header is parsed.

On the other hand, if you have a mailbox of, say, 25MB, and hold each header of each message in memory, you'll quickly run out of that. So, you can now choose between more performance and more memory.

This all does not happen if you just parse a mailbox to extract one header-field (eg. subject), work with that and exit. In this case it will need both less memory and is still considerably quicker. :-)

Below you see two tables produced by the Benchmark module. I compared my module (0.06) with Mail::Box, Mail::Folder and Mail::Folder::FastReader (grepmail), while the second table shows the same with 0.07 of Mail::MboxParser. I only let the modules iterate over the mailbox and count the number of messages by extracting them. There is no single header-field extracted. So keep that in mind. Mail::MboxParser is slower than 330/s when you call $mail->header.

=end

                   Rate Mail::Folder Mail::Box Mail::MboxParser grepmail
Mail::Folder     23.2/s           --      -76%             -89%     -99%
Mail::Box        97.1/s         318%        --             -53%     -95%
MboxParser        206/s         786%      112%               --     -89%
grepmail         1852/s        7878%     1807%             800%       --

                   Rate Mail::Folder Mail::Box Mail::MboxParser grepmail
Mail::Folder     23.2/s           --      -76%             -93%     -99%
Mail::Box        97.2/s         318%        --             -71%     -95%
Mail::MboxParser  330/s        1320%      240%               --     -82%
grepmail         1852/s        7867%     1806%             461%       --

grepmail is obviously the fastest of all (it is written in C using Inline). Mail::Folder performs worst, but that's because it uses temporary files and will probably need only a little memory. 

Mail::Box by Mark Overmeer is closer to Mail::MboxParser with mailboxes that contain binary-attachements, I don't know why. More to that, it only eats about 50% the memory that Mail::MboxParser needs while still providing more features (at the same time being a little bit more complex in usage).

=head1 BUGS

Don't know yet of any. However, since I only have a limited number of mailboxes on which I could test the module, there might be circumstances under which Mail::MboxParser fails to work correctly. It might fail on mal-formated mails produced by some cheap CGI-webmailers. 

The way of counting the messages and detecting them now complies to RFC 822. This is, however, no guarentee that it all works seamlessly. There are just so many mailboxes that get screwed up by mal-formated mails.

=head1 THANKS

Thanks to a number of people who gave me invaluable hints that helped me with Mail::Box, notably Kenn Frankel and Mark Overmeer.

=head1 AUTHOR AND COPYRIGHT

Tassilo von Parseval <Tassilo.Parseval@post.RWTH-Aachen.de>.

Copyright (c)  2001 Tassilo von Parseval. 
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

