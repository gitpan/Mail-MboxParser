# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or 
# modify it under the same terms as Perl itself.

# Version: $Id: MboxParser.pm,v 1.38 2001/11/26 11:34:42 parkerpine Exp $

package Mail::MboxParser;

require 5.004;

use base 'Mail::MboxParser::Base';

use Mail::MboxParser::Mail;
use IO::File;
use strict;
use Carp;

use base qw(Exporter);
use vars qw($VERSION @EXPORT @ISA);
$VERSION	= "0.23";
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
        if (!$in_body && /$from_date/) {
			($in_header, $in_body) = (1, 0);
			$got_header = 0;
		}
		# entering body
        if ($in_header && /$empty_line/) { 
			($in_header, $in_body) = (0, 1);
			$got_header = 1; 
		}
		
		# just before entering next mail-header or running
		# out of data, store message in Mail-object
        if ((/$from_date/ || eof) && $got_header) {
            push @body, $_ if eof; # don't forget last line!!
			$header = join '', @header;
			$body 	= join '', @body;
			my $m = Mail::MboxParser::Mail->new($header, 
												$body, 
												$self->{CONFIG});
			push @messages, $m;
			($in_header, $in_body) = (1, 0);
			($header, $body) = (undef, undef);
			(@header, @body) = ();
			$got_header = 0;
		}
		if ($_) {
            push @header, $_ if $in_header && !$got_header; 
            push @body, $_   if $in_body   &&  $got_header;
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

More to that, see the relevant manpages of Mail::MboxParser::Mail, Mail::MboxParser::Mail::Body and Mail::MboxParser::Mail::Convertable for a description of the methods for these objects.

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

Common methods for all objects come below:

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

=item Transfer-Encoding

Still, only quoted-printable encoding is correctly handled.

=item Error-handling

Yet not done for the Convertable-class. 

=item Convertable-class

Much more needs to be done here. Body cannot be modified yet, furthermore interfaces to other classes needs to be provided (Mail::Box, perhaps Mail::Folder).

=item Tests

Clean-up of the test-scripts is desperately needed. Now they represent rather an arbitrary selection of tested functions. Some are tested several times while others don't show up at all in the suits.

=item Misspellings

I've been told that - confusingly for any native English-speaker - I misspelled 'attachment'. This is annoying in method-names and a source of confusion and mistakes. Will soon be fixed as I find the time to do the necessary changes inside the modules, docs and test-scripts.

=head1 THANKS

Thanks to a number of people who gave me invaluable hints that helped me with Mail::Box, notably Mark Overmeer for his hints on more object-orientedness.

Kenn Frankel (kenn@kenn.cc) kindly patched the broken split-header routine and added get_field().

=head1 AUTHOR AND COPYRIGHT

Tassilo von Parseval <Tassilo.Parseval@post.RWTH-Aachen.de>.

Copyright (c)  2001 Tassilo von Parseval. 
This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<MIME::Entity>

L<Mail::MboxParser::Mail>, L<Mail::MboxParser::Mail::Body>, L<Mail::MboxParser::Mail::Convertable>

=cut
