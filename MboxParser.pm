# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or 
# modify it under the same terms as Perl itself.

# Version: $Id: MboxParser.pm,v 1.34 2001/09/08 08:34:47 parkerpine Exp $

package Mail::MboxParser;

require 5.004;

use base 'Mail::MboxParser::Base';

use Mail::MboxParser::Mail;
use IO::File;
use strict;
use Carp;

use base qw(Exporter);
use vars qw($VERSION @EXPORT @ISA);
$VERSION	= "0.20";
@EXPORT		= qw();
@ISA		= qw(Mail::MboxParser::Base); 
$^W++;

sub init (@) {
	my ($self, @args) = @_;

    if (@args == 0) {
		croak <<EOC;
Error: open needs either a filename, a filehande (as glob-ref) or a 
(scalar/array)-referece variable as first argument.
EOC
	}
		
	# we need odd number of arguments
	if ((@args % 2) == 0) { 
		croak <<EOC;
Error: open() can never have an even number of arguments. 
See 'perldoc Mail::MboxParser' on how to call it.
EOC
	}
	$self->open(@args); 
	$self;
}

sub open (@) {
	my ($self, @args) = @_;

	my $source 	= shift @args;
	$self->{CONFIG} = { @args };	
	
	# supposedly a filename
	if (not ref $source) {	
		if (! -e $source) {
			croak <<EOC;
Error: The filename you passed to open() does not refer to an existing file
EOC
		}
		open MBOX, "<$source" or
			croak "Error: Could not open $source for reading: $!";
		$self->{READER} = \*MBOX;
		return;
	}
	
	# a filehandle
	elsif (ref $source eq 'GLOB' && $source != \*STDIN) { 
		$self->{READER} = $source;
		return;
	}

	# else
	my $fh = IO::File->new_tmpfile or croak <<EOC;
Error: Could not create temporary file. This is very weird.
EOC
	if 		(ref $source eq 'SCALAR') 	{ print $fh ${$source} }
	elsif 	(ref $source eq 'ARRAY')  	{ print $fh @{$source} }
	elsif   ($source == \*STDIN) 	  	{ print $fh <STDIN> }
	$self->{READER} = $fh;
    return;
}

sub get_messages() {
	my $self = shift;
	
	my ($in_header, $in_body) = (0, 0);
	my ($header, $body);
	my (@header, @body);
	my $h = $self->{READER};

	my $got_header;
	my $from_date  = qr(^From (.*)\d{4}\n$);
	my $empty_line = qr(^\n$);

	my @messages;

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
			my $m = Mail::MboxParser::Mail->new($header, 
												$body, 
												$self->{CONFIG});
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
	};
	
	if (exists $self->{CONFIG}->{decode}) {
		$Mail::MboxParser::Mail::Config->{decode} = $self->{CONFIG}->{decode};
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
	close $self->{READER} if defined $self->{READER};
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

B<IMPORTANT CHANGES:> 

If you had been using a previous release of Mail::MboxParser, pay special attention to the changes in the interface. It now should be 'future-proof' since named parameters have been introduced. This makes Mail::MboxParser easily extensible without breaking any scripts depending on this module.

More to that, the rather unlucky SpamDetector class has been wiped out and so the call to is_spam(). There has lately been a release of Mail::SpamAssassin to CPAN. It acts as a plug-in to Mail::Audit and can't yet be used for Mail::MboxParser. This is something for the Convertable-class and on my to-do list.

Mail::MboxParser::Mail::Convertable has been newly introduced. As for yet, it offers only a rudimentary functionality. See the perldocs of this module for details.

=head1 METHODS

See also the section ERROR-HANDLING much further below.

----

The below methods refer to Mail::MboxParser-objects.

=over 4

=item B<new(mailbox, options)>

=item B<new(scalar-ref, options)>

=item B<new(array-ref, options)>

=item B<new(filehandle, options)>

This creates a new MboxParser-object opening the specified 'mailbox' with either absolute or relative path. 

new() can also take a reference to a variable containing the mailbox either as one string (reference to a scalar) or linewise (reference to an array), or a filehandle from which to read the mailbox.

The following option(s) may be useful. The value in brackets below the key is default if none given.

	key:      | value:     | description:
	==========|============|===============================
	decode    | 'NEVER'    | never decode transfer-encoded
	(NEVER)   |            | data
	          |------------|-------------------------------
	          | 'BODY'     | will decode body into a human-
	          |            | readable format
	          |------------|-------------------------------
	          | 'HEADER'   | will decode header fields if
	          |            | any is encoded
	          |------------|-------------------------------
	          | 'ALL'      | decode any data

When passing either a scalar-, array-ref or \*STDIN as first-argument, an anonymous tmp-file is created to hold the data. This procedure is hidden away from the user so there is no need to worry about it. Since a tmp-file acts just like an ordinary mailbox-file you don't need to be concerned about loss of data or so once you have been walking through the mailbox-data. No data will be lost and it'll all be fine and smooth.

=item B<open(source, options)>

Takes exactly the same arguments as new() does just that it can be used to change the characteristics of a mailbox on the fly.

=item B<get_messages>

Returns an array containing all messages in the mailbox respresented as Mail::MboxParser::Mail objects.

=item B<nmsgs>

Returns the number of messages in a mailbox. You could naturally also call get_messages in an array context, but this one wont create new objects. It just counts them and thus it is much quicker and wont eat a lot of memory.

=back

----

The below methods refer to Mail::MboxParser::Mail-objects returned by get_messages.

=over 4

=item B<new(header, body)>

This is usually not called directly but instead by $mb->get_messages. You could however create a mail-object manually providing the header and body both as one string.

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

=item B<store_attachement(n)>

=item B<store_attachement(n, options)>

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

=item B<store_all_attachements>

=item B<store_all_attachements(options)>

Walks through an entire mail and stores all apparent attachements. 'options' are exactly the same as in store_attachement() with the same behaviour if no options are given. 

Returns a list of files that has been succesfully saved and an empty list if no attachement could be extracted.

$mail->error will tell you possible failures and a possible explanation for that.

=item B<make_convertable>

Returns a Mail::MboxParser::Mail::Convertable object. For details on what you can do with it, read L<Mail::MboxParser::Mail::Convertable>.

=back

----

Methods that apply to Mail::MboxParser::Mail-objects come here:

=over 4

=item B<as_string>

Returns the textual representation of the body as one string. Decoding takes place when the mailbox has been opened using the decode => 'HEADER' | 'ALL' option.

=item B<as_lines>

Sames as as_string() just that you get an array of lines.

=item B<signature>

Returns the signature of a message as an array of lines. Trailing newlines are already removed.

=item B<extract_urls>

=item B<extract_urls (unique =E<gt> 1)>

Returns an array of hash-refs. Each hash-ref has two fields: 'url' and 'context' where context is the line in which the 'url' appeared.

When calling it like $mail->extract_urls(unique => 1), duplicate URLs will be filtered out regardless of the 'context'. That's useful if you just want a list of all URLs that can be found in your mails.

=item B<quotes>

Returns a hash-ref of array-refs where the hash-keys are the several levels of quotation. Each array-element contains the paragraphs of this quotation-level as one string. Example:

	my $quotes = $msg->body($msg->find_body)->quotes;
	print $quotes->{1}->[0], "\n";
	print $quotes->{0}->[0], "\n";

This should print the first paragraph of the mail-body that has been quoted once and below that the paragraph that supposedly is the reply to this paragraph. Perhaps thus:

	> I had been trying to work with the CGI module 
	> but I didn't yet fully understand it.

	Ah, it is tricky. Have you read the CGI-FAQ that 
	comes with the module?

Mark that empty lines will not be ignored and are part of the lines contained in the array of $quotes->{0}.

So below is a little code-snippet that should, in most cases, restore the first 5 paragraphs (containing quote-level 0 and 1) of an email:

	for (0 .. 5) {
		print $quotes->{0}->[$_];
		print $quotes->{1}->[$_];
	}

Since quotes() considers an empty line between two quotes paragraphs as a paragraph in $quotes->{0}, the paragraphs with one quote and those with zero are balanced. That means: 

scalar @{$quotes->{0}} - DIFF == scalar @{$quotes->{1}} where DIFF is element of {-1, 0, 1}.

Unfortunately, quotes() can up to now only deal with '>' as quotation-marks.

=back

----

Common methods for both mailbox- and mail-objects come below. These are about error-handling so you should read the section ERROR-HANDLING as well.

=over 4

=item B<error>

Call this immediately after one of the methods above that mention a possible error-message. 

=item B<log>

Sort of internal weirdnesses are recorded here. Again only the last event is saved.

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

=head1 TODO

Apart from new bugs that almost certainly have been introduced with this release, following things still need to be done:

=over 4

=item PODS

I need to split them up and put the relevant parts into the respective modules. In its current way it's getting hard to maintain.

=item Transfer-Encoding

Decoding of header-fields and bodies looks dubious to me. It happens intransparently and, more to that, will only deal with quoted-printable encoding. This, however, does not apply to binary attachements as handled with store_attachement and the lot.

=item Error-handling

Yet hardly implemented for the Body- and Convertable-class. 

=item Convertable-class

Much more needs to be done here. Body cannot be modified yet, furthermore interfaces to other classes needs to be provided (Mail::Box, perhaps Mail::Folder).

=item Tests

Clean-up of the test-scripts is desperately needed. Now they represent rather an arbitrary selection of tested functions. Some are tested several times while others don't show up at all in the suits.

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

L<Mail::MboxParser::Mail::Convertable>

=cut
