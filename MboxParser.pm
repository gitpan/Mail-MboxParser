# Mail::MboxParser - object-oriented access to UNIX-mailboxes
#
# Copyright (C) 2001  Tassilo v. Parseval
# This program is free software; you can redistribute it and/or 
# modify it under the same terms as Perl itself.

# Version: $Id: MboxParser.pm,v 1.46 2001/12/13 13:26:26 parkerpine Exp $

package Mail::MboxParser;

require 5.004;

use base 'Mail::MboxParser::Base';

# ----------------------------------------------------------------

=head1 NAME

Mail::MboxParser - read-only access to UNIX-mailboxes

=head1 SYNOPSIS

    use Mail::MboxParser;

    my $mb = Mail::MboxParser->new('some_mailbox', decode => 'ALL');

    # -----------
    
    # slurping
	for my $msg ($mb->get_messages) {
		print $msg->header->{subject}, "\n";
		$msg->store_all_attachments('/tmp');
	}

    # iterating
    while (my $msg = $mb->next_message) {
        print $msg->header->{subject}, "\n";
        # ...
    }

    # we forgot to do something with the messages
    $mb->rewind;
    while (my $msg = $mb->next_message) {
        # iterate again
        # ...
    }

=head1 DESCRIPTION

This module attempts to provide a simplified access to standard UNIX-mailboxes. It offers only a subset of methods to get 'straight to the point'. More sophisticated things can still be done by invoking any method from MIME::Tools on the appropriate return values.

Mail::MboxParser has not been derived from Mail::Box and thus isn't acquainted with it in any way. It, however, incorporates some invaluable hints by the author of Mail::Box, Mark Overmeer.

=head1 METHODS

See also the section ERROR-HANDLING much further below.

More to that, see the relevant manpages of Mail::MboxParser::Mail, Mail::MboxParser::Mail::Body and Mail::MboxParser::Mail::Convertable for a description of the methods for these objects.

=cut

use strict;
use Mail::MboxParser::Mail;
use IO::File;
use Carp;

use base qw(Exporter);
use vars qw($VERSION @EXPORT @ISA $OS);
$VERSION	= "0.30_4";
@EXPORT		= qw();
@ISA		= qw(Mail::MboxParser::Base); 


my $from_date   = qr/^From (.*)\d{4}\015?$/;
my $empty_line  = qr/^\015?$/;

# ----------------------------------------------------------------

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

=back

=cut

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
    binmode $self->{READER} if $^O =~ /Win/;
	$self;
}

# ----------------------------------------------------------------

=over 4

=item B<open(source, options)>

Takes exactly the same arguments as new() does just that it can be used to change the characteristics of a mailbox on the fly.

=back

=cut

sub open (@) {
	my ($self, @args) = @_;

	my $source 	= shift @args;
	$self->{CONFIG} = { @args };	
    $self->{CURR_POS} = 0;
	
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
    seek $self->{READER}, 0, 0;
    return;
}

# ----------------------------------------------------------------

=over 4

=item B<get_messages>

Returns an array containing all messages in the mailbox respresented as Mail::MboxParser::Mail objects. This method is _minimally_ quicker than iterating over the mailbox using C<next_message> but eats much more memory. Memory-usage will grow linearly for each new message detected since this method creates a huge array containing all messages. After creating this array, it will be returned.

=back

=cut

sub get_messages() {
	my $self = shift;
	
	my ($in_header, $in_body) = (0, 0);
	my ($header, $body);
	my (@header, @body);
	my $h = $self->{READER};

	my $got_header;

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
            #$header = join '', @header;
			$body 	= join '', @body;
			my $m = Mail::MboxParser::Mail->new([ @header ], 
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

# ----------------------------------------------------------------

=over 4

=item B<get_message(n)>

Returns the n-th message (first message has index 0) in a mailbox. Examine C<$mb-E<gt>error> which contains an error-string if the message does not exist. In this case, C<get_message> returns undef.

=back

=cut

sub get_message($) {
    my ($self, $num) = @_;
    
    $self->reset_last;
    $self->make_index if ! exists $self->{MSG_IDX};

    my $tmp_idx = $self->current_pos;
    my $pos     = $self->get_pos($num);
    
    if (my $err = $self->error) {
        $self->set_pos($tmp_idx); 
        $self->{LAST_ERR} = $err;
        return;
    }

    $self->set_pos($pos);
    my $msg = $self->next_message;
    $self->set_pos($tmp_idx);
    return $msg;
}

# ----------------------------------------------------------------

=over 4

=item B<next_message>

This lets you iterate over a mailbox one mail after another. The great advantage over C<get_messages> is the very low memory-comsumption. It will be at a constant level throughout the execution of your script. Secondly, it almost instantly begins spitting out Mail::MboxParser::Mail-objects since it doesn't have to slurp in all mails before returing them.

=back

=cut

sub next_message() {
    my $self = shift;
    $self->reset_last;
    my $h    = $self->{READER};

	my ($in_header, $in_body) = (0, 0);
	my ($header, $body);
	my (@header, @body);

	my $got_header = 0;
    
    seek $h, $self->{CURR_POS}, 0;
    
    while (<$h>) { 
        
        if (/$from_date/ || eof $h) {
            if (! $got_header) {
                ($in_header, $in_body) = (1, 0);
            }
            else {
                $self->{CURR_POS} = tell($h) - length;
                return Mail::MboxParser::Mail->new([@header],
                                                   join ('', @body),
                                                   $self->{CONFIG});
            }
        }
        
        $got_header = 1 if /$empty_line/ && $in_header;
        
        if (/$empty_line/ && $got_header) {
            ($in_header, $in_body) = (0, 1); 
            $got_header = 1;
        }
        
        push @header, $_ if $in_header;
        push @body,   $_ if $in_body; 
        
    }
}

# ----------------------------------------------------------------

=over 4

=item B<set_pos(n)>

=item B<rewind>

=item B<current_pos>

These three methods deal with the position of the internal filehandle backening the mailbox. Once you have iterated over the whole mailbox using C<next_message> MboxParser has reached the end of the mailbox and you have to do repositioning if you want to iterate again. You could do this with either C<set_pos> or C<rewind>.

    $mb->rewind;  # equivalent to
    $mb->set_pos(0);

C<current_pos> reveals the current position in the mailbox and can be used to later return to this position if you want to do tricky things. Mark that C<current_pos> does *not* return the current line but rather the current character as returned by Perl's tell() function.
    
    my $last_pos;
    while (my $msg = $mb->next_message) {
        # ...
        if ($msg->header->{subject} eq 'I had been looking for this') {
            $last_pos = $mb->current_pos;
            last; # bail out here and do something else
        }
    }
    
    # ...
    # ...
    
    # now continue where we stopped:
    $mb->set_pos($last_pos)
    while (my $msg = $mb->next_message) {
        # ...
    }

=back

=cut
    
sub set_pos($) { 
    my ($self, $pos) = @_;
    $self->reset_last;
    $self->{CURR_POS} = $pos;
}

# ----------------------------------------------------------------

sub rewind() { 
    my $self = shift;
    $self->reset_last;
    $self->set_pos(0); 
}

# ----------------------------------------------------------------

sub current_pos() { 
    my $self = shift;
    $self->reset_last;
    return $self->{CURR_POS};
}

# ----------------------------------------------------------------

=over 4

=item B<make_index>

You can force the creation of a message-index with this method. The message-index is a mapping between the index-number of a message (0 .. $mb->nmsgs - 1) and the byte-position of the filehandle. This is usually done automatically for you once you call C<get_message> hence the first call for a particular message will be a little slower since the message-index first has to be built. This is, however, done rather quickly. 

You can have a peek at the index if you are interested. The following produces a nicely padded table (suitable for mailboxes up to 9.9999...GB ;-).
    
    $mb->make_index;
    for (0 .. $mb->nmsgs - 1) {
        printf "%5.5d => %10.10d\n", 
                $_, $mb->get_pos($_);
    }   

=back

=cut

sub make_index() {
    my $self = shift;
    $self->reset_last;
    my $h    = $self->{READER};
    
    seek $h, 0, 0;
    
    my $c = 0;
    while (<$h>) {
        $self->{MSG_IDX}->{$c} = tell($h) - length, $c++ 
            if /$from_date/;
    }
    seek $h, 0, 0;
} 

# ----------------------------------------------------------------

=over 4

=item B<get_pos(n)>

This method takes the index-number of a certain message within the mailbox and returns the corresponding position of the filehandle that represents that start of the file.

It is mainly used by C<get_message()> and you wouldn't really have to bother using it yourself except for statistical purpose as demonstrated above along with B<make_index>.

=back

=cut

sub get_pos($) {
    my ($self, $num) = @_;
    $self->reset_last;
    if (exists $self->{MSG_IDX}) { 
        if (! exists $self->{MSG_IDX}{$num}) {
            $self->{LAST_ERR} = "$num: No such message";
        }
        return $self->{MSG_IDX}{$num} }
    else { return }
}

# ----------------------------------------------------------------

=over 4

=item B<nmsgs>

Returns the number of messages in a mailbox. You could naturally also call get_messages in scalar-context, but this one wont create new objects. It just counts them and thus it is much quicker and wont eat a lot of memory.

=back

=cut

sub nmsgs() {
	my $self = shift;
	if (not $self->{READER}) { return "No mbox opened" }
	if (not $self->{NMSGS}) {
		my $h = $self->{READER};
        seek $h, 0, 0;
		while (<$h>) {
			$self->{NMSGS}++ if /$from_date/;
		}
	}
	return $self->{NMSGS} || "0";	
}	

# ----------------------------------------------------------------

sub DESTROY {
	my $self = shift;
	$self->{NMSGS} = undef;
	close $self->{READER} if defined $self->{READER};
}

# ----------------------------------------------------------------

1;		

__END__

=head2 METHODS SHARED BY ALL OBJECTS

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

Well, they exist. When you handle MIME-stuff a lot such as attachments etc., Mail::MboxParser internally calls a lot of methods provided by the MIME::Tools package. These work splendidly in most cases, but the MIME::Tools may fail to produce something sensible if you have a very queer or even screwed up mailbox.

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

Mail::Box by Mark Overmeer is closer to Mail::MboxParser with mailboxes that contain binary-attachments, I don't know why. More to that, it only eats about 50% the memory that Mail::MboxParser needs while still providing more features (at the same time being a little bit more complex in usage).

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

=back 

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
