# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or 
# modify it under the same terms as Perl itself.

# Version: $Id: MboxParser.pm,v 1.28 2001/08/27 06:33:22 parkerpine Exp $

package Mail::MboxParser;

require 5.004;

use base 'Mail::MboxParser::Base';

use Mail::MboxParser::Mail;
use strict;
use Carp;

use base qw(Exporter);
use vars qw($VERSION @EXPORT @ISA);
$VERSION	= "0.15";
@EXPORT		= qw();
@ISA		= qw(Mail::MboxParser::Base); 
$^W++;

sub init (;$) {
	my ($self, $file) = @_;
	
	if ($file) { $self->open($$file[0]) }

	$self;
}

sub open ($) {
	my ($self, $file) = @_;
	open MBOX, "<$file"
		or croak "Error: Could not open $file for reading: $!";
	$self->{READER} = \*MBOX;
}

sub get_messages() {
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
		
sub nmsgs() {
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
		print $msg->from->{name} || "none", "\n";
		print $msg->from->{email}, "\n";
		print $msg->header->{subject}, "\n";
		print $msg->header->{'reply-to'}, "\n";
		$msg->store_all_attachements('/tmp');
	}

=head1 DESCRIPTION

This module attempts to provide a simplified access to standard UNIX-mailboxes. It offers only a subset of methods to get 'straight to the point'. More sophisticated things can still be done by invoking any method from MIME::Tools on the appropriate return values.

Mail::MboxParser has not been derived from Mail::Box and thus isn't acquainted with it in any way. It, however, incorporates some invaluable hints by the author of Mail::Box, Mark Overmeer.

=head1 METHODS

See also the section ERROR-HANDLING much further below.

The below methods refer to Mail::MboxParser-objects.

=over 4

=item B<new>

=item B<new(mailbox)>

This creates a new MboxParser-object opening the specified MAILBOX with either absolute or relative path. It does not necessarily need a parameter in which case you need to pass the mailbox to the object using the method 'open'.
Returns nothing.

=item B<open(mailbox)>

Can be used to either pass a mailbox to the MboxParser-object either the first time or for changing the mailbox. 
Returns nothing.

=item B<get_messages>

Returns an array containing all messages in the mailbox respresented as Mail::MboxParser::Mail objects.

=item B<nmsgs>

Returns the number of messages in a mailbox. You could naturally also call get_messages in an array context, but this one wont create new objects. It just counts them and thus it is much quicker and wont eat a lot of memory.

=back

The below methods refer to Mail::MboxParser::Mail-objects returned by get_messages.

=over 4

=item B<new(header, body)>

This is usually not called directly but instead by $mb->get_messages. You could however create a mail-object manually providing the header and body both as one string.

=item B<header>

Returns the mail-header as a hash-ref with header-fields as keys. All keys are turned to lower-case, so $header{Subject} has to be written as $header{subject}.

=item B<body[(n)]>

Returns a Mail::MboxParser::Mail::Body object. For methods upon that see further below. When called with the argument n, the n-th body of the message is retrieved. That is, the body of the n-th entity.

Sets $message->error if something went wrong.

=item B<find_body>

This will return an index number that represents what Mail::MboxParser considers to be the actual (main)-body of an email. This is useful if you don't know about the structure of a message but want to retrieve the message's signature for instance:

	$signature = $msg->body($msg->find_body)->signature;

Changes are good that find_body does what it is supposed to do.
	
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

=item B<get_entitities([n])>

Either returns an array of all MIME::Entity objects or one particular if called with a number. If no entity whatsoever could be found, an empty list is returned.

$mail->log instantly called after get_entities will give you some information of what internally may have failed. If set, this will be an error raised by MIME::Entity but you don't need to worry about it at all. It's just for the record.

=item B<get_entity_body(n)>

Returns the body of the n-th MIME::Entity as a single string, undef otherwise in which case you could check $mail->error.

=item B<store_entity_body(n, FILEHANDLE)>

Stores the stringified body of n-th entity to the specified filehandle. That's basically the same as:

 my $body = $mail->get_entity_body(0);
 print FILEHANDLE $body;

and could be shortened to this:

 $mail->store_entity_body(0, \*FILEHANDLE);

It returns a true value on success and undef on failure. In this case, examine the value of $mail->error since the entity you specified with 'n' might not exist.

=item B<store_attachement(n, path, [coderef [,args]])>

It is really just a call to store_entity_body but it will take care that the n-th entity really is a saveable attachement. That is, it wont save anything with a MIME-type of, say, text/html or so. 

It uses the recommended-filename found in the MIME-header unless a 'coderef' has been given. The coderef is a reference to a subroutine whose first argument will always be the Mail::MboxParser::Mail object and  whose second argument is the index of the current MIME-entity that is processed. The return value is used as the filename under which the attachement is to be saved. Any additional arguments that you want to pass to the coderef can be added as list behind 'coderef'. 'path' is the place where the new file will go to. Example:

	my $coderef = 
		sub {
 			my ($msg, $n, @args) = @_;
			return $msg->id."_$n";
		};
	my @additional = qw(Foo Bar);
 	$msg->store_attachement(1,       "/home/ethan/", 
	                        $coderef, @additional);

This will save the attachement found in the second entity under the name that consists of the message-ID and the appendix "_1" since the above code works on the second entity (that is, with index = 1). @additional isn't used in this example but should demonstrate how to pass additional arguments.

If 'path' does not exist, it will try to create the directory for you.

Returns the filename under which the attachement has been saved. undef is returned in case the entity did not contain a saveable attachement, there was no such entity at all or there was something wrong with the 'path' you specified. Check $mail->error to find out which of these possibilities appliy.

=item B<store_all_attachements(path, [coderef [,args]])>

Walks through an entire mail and stores all apparent attachements to 'path'. See the supplied store_att.pl script in the eg-directory of the package to see a useful example.

As for 'coderef', read store_attachement.

Returns a list of files that has been succesfully saved and an empty list if no attachement could be extracted.

$mail->error will tell you poassible failures and a possible explanation for that.

=item B<is_spam>

Sorry, no documentation on that yet before this is properly implemented. You can, however, try to find out yourself. ;-)

=back

Methods that apply to Mail::MboxParser::Mail-objects come here:

=over 4

=item B<signature>

Returns the signature of a message as an array of lines. Trailing newlines are already removed.

=item B<extract_urls [(unique => 0|1)]>

Returns an array of hash-refs. Each hash-ref has two fields: 'url' and 'context' where context is the line in which the 'url' appeared.

When calling it like $mail->extract_urls(unique => 1), duplicate URLs will be filtered out regardless of the 'context'. That's useful if you just want a list of all URLs that can be found in your mails.

=cut

Common methods for both mailbox- and mail-objects come below. These are about error-handling so you should read the section ERROR-HANDLING as well.

=over 4

=item B<error>

Call this immediately after one of the methods above that mention a possible error-message. 

=item B<log>

Sort of internal weirdnesses are recorded here. Again only the last event is saved.

=back 

=head1 FIELDS

Mail::MboxParser basically is a hash-ref:

=over 4

=item B<$mb->{READER}>

This is the filehandle from which is read internally. As to yet, it is read-only so you can't use it for writing. This may be changed later.

=item B<$mb->{NMSGS}>

Having called nmsgs once this field contains the number of messages in the mailbox. Thus there is no need for calling the method twice which speeds up matters a little.

Mail::MboxParser::Mail consists of the following fields:

=item B<$mail->{RAW}>

This field no longer exists in order to save memory. Instead, do something like

	$entire_message = $mail->{HEADER}.$mail->{BODY};

=item B<$mail->{HEADER}>

Well, just the header of the message as a string.

=item B<$mail->{BODY}>

You guess it.

=item B<$mail->{TOP_ENTITY}>

The top-level MIME::Entity of a message. Technically speaking, the message itself from the perspective of MIME::Entity.

This field is undefined until one of the MIME-methods (num_entities, get_entities etc.) is called for the sake of efficiency.

=back

=head1 ERROR-HANDLING

Mail::MboxParser provides a mechanism for you to figure out why some methods did not function as you expected. There are four classes of unexpected behavior:

=over 4

=item B<(1) bad arguments >

In this case you called a method with arguments that did not make sense, hence you confused Mail::MboxParser. Example:

  $mail->store_entity_body;           # wrong, needs two arguments
  $mail->store_entity_body(0);        # wrong, still needs one more

In any of the above two cases, you'll get an error message and your script will exit. The message will, however, tell you in which line of your script this error occured.

=item B<(2) correct arguments but...>

Consider this line:

  $mail->store_entity_body(50, \*FH); # could be wrong

Obviously you did call store_entity_body with the correct number of arguments. That's good because now your script wont just exit. Unfortunately, your program can't know in advance whether the particular mail ($mail) has a 51st entity.

So, what to do?

Just be brave: Write the above line and do the error-checking afterwards by calling $mail->error immediately after store_entity_body:

	$mail->store_entity_body(50, *\FH);
	if ($mail->error) {
		print "Oups, something wrong:", $mail->error;
	}

In the description of the available methods above, you always find a remark when you could use $mail->error. It always returns a string that you can print out and investigate any further.

=item B<(3) errors, that never get visible>

Well, they exist. When you handle MIME-stuff a lot such as attachements etc., Mail::MboxParser internally calls a lot of methods provided by the MIME::Tools package. These work splendidly in most cases, but the MIME::Tools may fail to produce something sensible if you have a very queer or even screwed up mailbox.

If this happens you might find information on that when calling $mail->log. This will give you the more or less unfiltered error-messages produced by MIME::Tools.

My advice: Ignore them! If there really is something in $mail->log it is either because you're mails are totally weird (there is nothing you can do about that then) or these errors are smoothly catched inside Mail::MboxParser in which case all should be fine for you.

=item B<(4) the apocalyps>

If nothing seems to work the way it should and $mail->error is empty, then the worst case has set in: Mail::MboxParser has a bug.

Needless to say that there is any way to get around of this. In this case you should contact and I'll examine that.

=back

=head1 CAVEATS

I have been working hard on making Mail::MboxParser eat less memory and as quick as possible. Due to that, two time and memory consuming matters are now called on demand. That is, parsing out the MIME-parts and turning the raw header into a hash have become closures.

The drawback of that is that it may get inefficient if you often call 

 $mail->header->{field}
 
In this case you should probably save the return value of $mail->header (a hashref) into a variable since each time you call it the raw header is parsed.

On the other hand, if you have a mailbox of, say, 25MB, and hold each header of each message in memory, you'll quickly run out of that. So, you can now choose between more performance and more memory.

This all does not happen if you just parse a mailbox to extract one header-field (eg. subject), work with that and exit. In this case it will need both less memory and is still considerably quicker. :-)

Below you see two tables produced by the Benchmark module. I compared my module (0.06) with Mail::Box, Mail::Folder and Mail::Folder::FastReader (grepmail), while the second table shows the same with 0.07 of Mail::MboxParser. I only let the modules iterate over the mailbox and count the number of messages by extracting them. There is no single header-field extracted. So keep that in mind. Mail::MboxParser is slower than 330/s when you call $mail->header.

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

Some mailers have a fancy idea of how a "To: "- or "Cc: "-line should look. I have seen things like:

	To: "\"John Doe"\" <john.doe@foo.com>

The splitting into name and email, however, does still work here, but you have to remove these silly double-quotes and backslashes yourself.

The way of counting the messages and detecting them now complies to RFC 822. This is, however, no guarentee that it all works seamlessly. There are just so many mailboxes that get screwed up by mal-formated mails.

=head1 THANKS

Thanks to a number of people who gave me invaluable hints that helped me with Mail::Box, notably Kenn Frankel and Mark Overmeer for his hints on more object-orientedness.

=head1 AUTHOR AND COPYRIGHT

Tassilo von Parseval <Tassilo.Parseval@post.RWTH-Aachen.de>.

Copyright (c)  2001 Tassilo von Parseval. 
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<MIME::Entity>

L<Mail::MboxParser::Mail> to learn how to use MIME::Entity-stuff easily

=cut
