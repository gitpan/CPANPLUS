# $File: //depot/cpanplus/dist/lib/CPANPLUS/Error.pm $
# $Revision: #3 $ $Change: 1963 $ $DateTime: 2002/11/04 16:32:10 $

###############################################
###              CPANPLUS/Error.pm          ###
### Error handling for the CPAN++ interface ###
###      Written 04-10-2001 by Jos Boumans  ###
###############################################

### Error.pm ###
package CPANPLUS::Error;

use strict;
use Carp;
use CPANPLUS::I18N;

BEGIN {
    use vars        qw( $VERSION );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

# Possible settings:
# < 1   errors are all stored in $ERROR and accessed as desired.
# 1     confess handles the errors (warn of errors)
# 2     croak handles the errors (die with errors)
# > 2   confess handles the errors (die with stacktrace)

### Constructor ###
sub new {
    # Expects a hash of arguments with keys relating to all fields with
    # 'required' status in the %_data structure.  All other fields without a
    # preceding _ may optionally have values supplied.
    my $class = shift;

    my %temp = @_;
    my %args = map { lc($_) => $temp{$_} } keys %temp;

    my $self = {
        ETRACK  => $args{error_track} || '0',   # track in what sub errors happened
        ITRACK  => $args{message_track} || '0', # track in what sub messags were sent
        ERROR   => '',                          # Error message
        STACK   => [],                          # Error stack
        MSG     => '',                          # Info message
        INFORM  => [],                          # Information stack
        ILEVEL  => $args{message_level} || '0', # Inform verbosity level
        ELEVEL  => defined $args{error_level}   # Error handling level
                        ? $args{error_level}
                        : 1,
        COUNTER => 0,
    };
    return bless $self, $class;
}

### Set the error, add it to the stack and handle it
sub trap {
    my $self = shift;
    my %args = @_;

    my $error = $args{'error'};
    $error .= loc(" in %1 at %2", $self->_who_was_it(), scalar localtime) if $self->{ETRACK};

    if ( length $args{error} ) {

        ### sets the current error ###
        $self->{ERROR} = $error;

        ### adds the error to the stack ###
        unshift @{$self->{STACK}}, [ $self->{ERROR}, ++$self->{COUNTER} ];

    } else {
        ### must be a confused call ###
        return 0;
    }

    unless ( $args{quiet} ) {
        # Very high level of debugging makes errors fatal & traceable.
        confess($self->{ERROR}) if ($self->{ELEVEL} > 2);

        # High level of debugging makes all errors fatal.
        croak($self->{ERROR}) if ($self->{ELEVEL} > 1);

        # Debug level of 1 reports all errors right away
        carp($self->{ERROR}) if ($self->{ELEVEL});
    }

    ### Return that the error was handled ###
    return 1;

}


### returns the entire stack in list context,
### or just the current error in scalar context.
### it does NOT change the STACK nor the ERROR
sub stack {
    my $self = shift;

    return wantarray
        ? @{[ map { $_->[0] } @{$self->{STACK}} ]}
        : $self->{ERROR}
}

### flushes the current ERROR and returns it in scalar context
### flushes the entire stack in list context
### understand that $self->{STACK}->[0] eq $self->{ERROR}
sub flush {
    my $self = shift;

    if (my $level = shift) {

        ### splice off the number of errors that are asked for ###
        my @list = map { $_->[0] } splice @{$self->{STACK}}, 0, $level;

        ### reset the error
        $self->{ERROR} = $self->{STACK}->[0]->[0];

        ### return a list of the errors spliced off
        return \@list;

    } else {
        ### save the current stack to return it
        my $list = [ map { $_->[0] } @{$self->{STACK}} ];

        ### delete everything from the stack
        $self->{ERROR} = '';
        $self->{STACK} = [];

        return $list;
    }
}


sub inform {
    my $self = shift;
    my %args = @_;

    ### called without an inform message
    return 0 unless length $args{msg};

    my $msg = $args{'msg'};
    $msg .= loc(" in %1 at %2", $self->_who_was_it(), scalar localtime) if $self->{ITRACK};

    if ( !$args{quiet} || $self->{ILEVEL} ) { print $msg,"\n" }

    unshift @{$self->{INFORM}}, [ $msg, ++$self->{COUNTER} ];

    $self->{MSG} = $msg;

    ### indicate the error was handled
    return 1;
}

sub list {
    my $self = shift;

    return wantarray
        ? @{[ map { $_->[0] } @{$self->{INFORM}} ]}
        : $self->{MSG}
}

sub forget {
    my $self = shift;

    if (my $level = shift) {

        ### splice off the number of errors that are asked for ###
        my @list = map { $_->[0] } splice @{$self->{INFORM}}, 0, $level;

        ### reset the error
        $self->{MSG} = $self->{INFORM}->[0]->[0];

        ### return a list of the errors spliced off
        return \@list;

    } else {
        ### save the current stack to return it
        my $list = [ map { $_->[0] } @{$self->{INFORM}} ] ;

        ### delete everything from the stack
        $self->{MSG} = '';
        $self->{INFORM} = [];

        return $list;
    }
}

sub summarize {
    my $self = shift;
    my %args = @_;

    my $stack = my $list = $args{all} if defined $args{all};

    $list   ||= defined $args{msg}
                    ?   $args{msg}
                    :   0;

    $stack  ||= defined $args{error}
                    ?   $args{error}
                    :   $list ? 0 : 1;

    my @list    = @{$self->{INFORM}}    if $list;
    my @stack   = @{$self->{STACK}}     if $stack;


    my @sorted =
        map     { $_->[0] }
        sort    { $a->[1] <=> $b->[1] }
        map     { $_ } ( @list, @stack );

    return \@sorted;
}

### set object variables, like DEBUG ###
sub set {
    my $self = shift;

    my %temp = @_;
    my %args = map { uc($_) => $temp{$_} } keys %temp;

    for my $key ( keys %$self ) {
        if ( length $args{$key} ) {
            $self->{$key} = $args{$key};
        }
    }
}

sub _who_was_it { return (caller 2)[3] }
1;

__END__

=pod

=head1 NAME

CPANPLUS::Error - Error handling for the CPAN++ interface

=head1 SYNOPSIS

    use CPANPLUS::Error;

    my $obj = new CPANPLUS::Error(
        error_track   => 1,
        error_level   => 2,
        message_track => 0,
        message_level => 1,
    );

    $obj->trap(  error => 'There was an error!');
    $obj->inform(msg   => 'I did something', quiet=>1);

    my @all_errors = $obj->stack();
    my $last_msg   = $obj->list();

    my $last_two_errors = $obj->flush(2);
    my $all_messages = $obj->forget();

    my $msg_and_err = summarize(all => 1);


=head1 DESCRIPTION

CPANPLUS::Error provides a standard method of handling errors for
components of the CPAN++ interface.

=head1 METHODS

=head2 new(error_track => bool, error_level => number, message_track => bool, message_level => bool)

The constructor expects a hash of arguments for the following
fields:

=over 4

=item error_level

The setting is a number from 0 to 3 which indicates what should
happen when an error is reported.  Regardless of the setting, error
messages will be saved for later access.  By default the error level
is 1.

      0  no action

      1  Carp ('warn')

      2  Croak ('die')

    > 2  Confess ('die with a stacktrace')

=item error_track

If enabled, the name of the subroutine in which the error occurred
will be appended to each error message.  By default it is false.

=item message_level

This field specifies the handling level for messages.  By default
the level is 0.  If true, messages will be printed when they are
reported.

=item message_track

If true, each message will track the subroutine in which the message
occurred.  By default it is false.

=back

=head2 trap(error => ERROR, quiet => bool )

This method puts the error message on the error stack.  The optional
'quiet' argument will override the error_level setting and prevent
error actions from being taken.  1 is returned for success in
handling the error; 0 is returned otherwise.

=head2 inform(msg => WARNING, quiet => bool)

This function behaves like trap() except that it manipulates
messages instead of errors.  It returns 1 if the message was
handled, and 0 if it was not.

=head2 stack()

If called in list context, stack() returns the contents of the
error stack.  If called in scalar context, it returns the most
recent error.

=head2 list()

In list context, this method returns the message stack.  In
scalar context it returns the most recent message.

=head2 flush([NUMBER])

Flush removes the specified number of errors from the error stack
and returns an array reference containing the removed errors.  If
no argument is specified, the entire stack is emptied.

=head2 forget([NUMBER])

This method is like flush() except that it operates on the
message stack.

=head2 summarize(ARG => BOOL)

This method allows errors and messages to be combined in the order in
which they were logged.  If no argument is specified, I<error> is
assumed.  It accepts the following keys:

=over 4

=item * I<all>

A true value returns both messages and errors.

=item * I<msg>

A true value returns just the message history.

=item * I<error>

A true value returns the error stack.  This is the default setting.

=back

An array reference containing the results is returned.

=head1 AUTHORS

Copyright (c) 2001, 2002 Jos Boumans E<lt>kane@cpan.orgE<gt>
and Ann Barcomb E<lt>kudra@cpan.orgE<gt>.
All rights reserved.

This documentation Copyright (c) 2002 Ann Barcomb
E<lt>kudra@cpan.orgE<gt>.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
