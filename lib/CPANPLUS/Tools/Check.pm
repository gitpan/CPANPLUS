package CPANPLUS::Tools::Check;
use strict;
use Carp qw[carp];
use CPANPLUS::I18N;

BEGIN {
    use Exporter    ();
    use vars        qw[ @ISA $VERSION @EXPORT_OK $VERBOSE $ALLOW_UNKNOWN 
                        $STRICT_TYPE $STRIP_LEADING_DASHES];

    @ISA        =   qw[ Exporter ];
    $VERSION    =   0.01;
    $VERBOSE    =   1;

    @EXPORT_OK  =   qw[check];
}

sub check {
    my $tmpl    = shift;
    my $href    = shift;
    my $verbose = shift || $VERBOSE || 0;

    ### lowercase all args, and handle both hashes and hashrefs ###
    my $args = {};
    if (ref($href) eq 'HASH') {
        %$args = map { _canon_key($_), $href->{$_} } keys %$href;
    } elsif (ref($href) eq 'ARRAY') {
        if ($#$href == 1 && ref($href->[0]) eq 'HASH') {
            %$args = map { _canon_key($_), $href->[0]->{$_}}
                keys %{ $href->[0] };
        } else {
            if ($#$href % 2) {
                carp qq[Uneven number of arguments passed to ] . _who_was_it()
                    if $verbose;
                return undef;
            }
            my %realargs = @$href;
            %$args = map { _canon_key($_), $realargs{$_} } keys %realargs;
        }
    }


    ### flag to set if something went wrong ###
    my $flag;

    for my $key ( keys %$tmpl ) {

        ### check if the required keys have been entered ###
        my $rv = _hasreq( $key, $tmpl, $args );

        unless( $rv ) {
            carp loc("Required option '%1' is not provided for %2 by %3",
                        $key, _who_was_it(), _who_was_it(1),
                    ) if $verbose;
            $flag++;
        }
    }
    return undef if $flag;

    ### set defaults for all arguments ###
    my $defs = _hashdefs($tmpl);

    ### check if all keys are valid ###
    for my $key ( keys %$args ) {

        unless( _iskey( $key, $tmpl ) ) {
            if( $ALLOW_UNKNOWN ) {
                $defs->{$key} = $args->{$key} if exists $args->{$key};
            } else {
                carp loc("Key '%1' is not a valid key for %2 provided by %3",
                        $key, _who_was_it(), _who_was_it(1)
                    ) if $verbose;
                next;
            }

        } elsif ( $tmpl->{$key}->{no_override} ) {
            carp loc( qq[You are not allowed to override key '%1' for %2 from %3],
                        $key, _who_was_it(), _who_was_it(1)
                    ) if $verbose;
            next;
        } else {

            ### flag to set if the value was of a wrong type ###
            my $wrong;

            if( exists $tmpl->{$key}->{allow} ) {

                my $what = $tmpl->{$key}->{allow};

                ### it's a string it must equal ###
                ### this breaks for digits =/
                unless ( ref $what ) {
                    $wrong++ unless _safe_eq( $args->{$key}, $what );

                } elsif ( ref $what eq 'Regexp' ) {
                    $wrong++ unless $args->{$key} =~ /$what/;

                } elsif ( ref $what eq 'ARRAY' ) {
                    $wrong++ unless grep { ref $_ eq 'Regexp'
                                                ? $args->{$key} =~ /$_/
                                                : _safe_eq($args->{$key}, $_)
                                         } @$what;

                } elsif ( ref $what eq 'CODE' ) {
                    $wrong++ unless $what->( $key => $args->{$key} );

                } else {
                    carp loc(qq[Can not do allow checking based on a %1 for %2],
                                ref $what, _who_was_it()
                            );
                }
            }

            if( $STRICT_TYPE || $tmpl->{$key}->{strict_type} ) {
                $wrong++ unless ref $args->{$key} eq ref $tmpl->{$key}->{default};
            }

            ### somehow it's the wrong type.. warn for this! ###
            if( $wrong ) {
                carp loc( qq[Key '%1' is of invalid type for %2 provided by %3],
                            $key, _who_was_it(), _who_was_it(1)
                        ) if $verbose;
                ++$flag && next;

            } else {

                ### if we got here, it's apparently an ok value for $key,
                ### so we'll set it in the default to return it in a bit
                $defs->{$key} = $args->{$key};
            }

        }
    }

    return $flag ? undef : $defs;
}

### Like check_array, but tmpl is an array and arguments can be given
### in a positional way; the tmpl order is the argument order.
sub check_positional {
    my $atmpl   = shift;
    my $aref    = shift;
    my $verbose = shift || $VERBOSE || 0;

    my %args;
    {
        local $STRIP_LEADING_DASHES = 1;
        my ($tmpl, $pos, $syn) = _atmpl_to_tmpl_pos_syn($atmpl);
        
        if ($#$aref == 1 && ref($aref->[0]) eq 'HASH') {
        
            ### Single hashref argument containing actual args.
            my ($key, $item);
            while (($key, $item) = each %{ $aref->[0] }) {
                $key = _canon_key($key);
                if ($syn->{$key}) {
                    # XXX Make this nonfatal ?
                    carp loc( qq[Synonym used in call to %1], _who_was_it() )
                        if $verbose;
                    $key = $syn->{$key};
                }
                $args{$key} = $item;
            }
        
        } elsif (!($#$aref % 2) && ref($aref->[0]) eq 'SCALAR' &&
                     $aref->[0] =~ /^-/) {
            
            ### List of -KEY => value pairs.
            while (my $key = (shift @$aref)) {
                $key = _canon_key($key);
                if ($syn->{$key}) {
                    # XXX Make this nonfatal ?
                    carp loc( qq[Synonym used in call to %1], _who_was_it() )
                        if $verbose;
                    $key = $syn->{$key};
                }
                $args{lc $key} = shift @$aref;
            }
        } else {
            ### Positional arguments, yay!
            while (@$aref) {
                my $item = shift @$aref;
                my $key = shift @$pos;
                if (!$key) {
                    carp loc( qq[Too many positional arguments for %1] ,
                            _who_was_it() ) if $verbose;
                    
                    ### We ran out of positional arguments, no sense in
                    ### continuing on.
                    last;
                }
                $args{$key} = $item;
            }
        }
        return check($tmpl, \%args, $verbose);
    }
}

### Return a hashref of $tmpl keys with required values
sub _listreqs {
    my $tmpl = shift;

    my %hash = map { $_ => 1 } grep { $tmpl->{$_}->{required} } keys %$tmpl;
    return \%hash;
}

### Convert template arrayref (keyword, hashref pairs) into straight ###
### hashref and an (array) mapping of position => keyname ###
sub _atmpl_to_tmpl_and_pos {
    my @atmpl = @{ shift @_ };

    my (%tmpl, @positions, %synonyms);
    while (@atmpl) {
        
        my $key = shift @atmpl;
        my $href = shift @atmpl;
        
        push @positions, $key;
        $tmpl{lc $key} = $href;
        
        for ( @{ $href->{synonyms} || [] } ) {
            $synonyms{lc $_} = $key;
        };
        
        undef $href->{synonyms};
    };
    return (\%tmpl, \@positions, \%synonyms);
}

### Canonicalise key (lowercase, and strip leading dashes if desired) ###
sub _canon_key {
    my $key = lc shift;
    $key =~ s/^-// if $STRIP_LEADING_DASHES;
    return $key;
}


### check if the $key is required, and if so, whether it's in $args ###
sub _hasreq {
    my ($key, $tmpl, $args ) = @_;
    my $reqs = _listreqs($tmpl);

    return $reqs->{$key}
            ? exists $args->{$key}
                ? 1
                : undef
            : 1;
}

### Return a hash of $tmpl keys with default values => defaults
### make sure to even include undefined ones, so that 'exists' will dwym
sub _hashdefs {
    my $tmpl = shift;

    my %hash =  map {
                    $_ => defined $tmpl->{$_}->{default}
                                ? $tmpl->{$_}->{default}
                                : undef
                } keys %$tmpl;

    return \%hash;
}

### check if the key exists in $data ###
sub _iskey {
    my ($key, $tmpl) = @_;
    return $tmpl->{$key} ? 1 : undef;
}

sub _who_was_it {
    my $level = shift || 0;

    return (caller(2 + $level))[3] || 'ANON'
}

sub _safe_eq {
    my($a, $b) = @_;

    if ( defined($a) && defined($b) ) {
        return $a eq $b;
    }
    else {
        return defined($a) eq defined($b);
    }
}

1;

__END__

=pod

=head1 NAME

CPANPLUS::Tools::Check;

=head1 SYNOPSIS

    use CPANPLUS::Tools::Check qw[check];

    sub fill_personal_info {
        my %hash = @_;

        my $tmpl = {
            firstname   => { required   => 1, },
            lastname    => { required   => 1, },
            gender      => { required   => 1,
                             allow      => [qr/M/i, qr/F/i],
                           },
            married     => { allow      => [0,1] },
            age         => { default    => 21,
                             allow      => qr/^\d+$/,
                           },
            id_list     => { default    => [],
                             strict_type => 1
                           },
            phone       => { allow      => sub {
                                                my %args = @_;
                                                return 1 if
                                                    &valid_phone(
                                                        $args{phone}
                                                    );
                                            }
                            },
            }
        };

        my $parsed_args = check( $tmpl, \%hash, $VERBOSE )
                            or die [Could not parse arguments!];

=head1 DESCRIPTION

CPANPLUS::Tools::Check is a generic input parsing/checking mechanism.

It allows you to validate input via a template. The only requirement
is that the arguments must be named.

CPANPLUS::Tools::Check will do the following things for you:

=over 4

=item *

Convert all keys to lowercase

=item *

Check if all required arguments have been provided

=item *

Set arguments that have not been provided to the default

=item *

Weed out arguments that are not supported and warn about them to the
user

=item *

Validate the arguments given by the user based on strings, regexes,
lists or even subroutines

=item *

Enforce type integrity if required

=back

Most of CPANPLUS::Tools::Check's power comes from it's template, which we'll
discuss below:



=head1 Template

As you can see in the synopsis, based on your template, the arguments
provided will be validated.

The template can take a different set of rules per key that is used.

The following rules are available:

=over 4

=item default

This is the default value if none was provided by the user.
This is also the type C<strict_type> will look at when checking type
integrity (see below).

=item required

A boolean flag that indicates if this argument was a required
argument. If marked as required and not provided, check() will fail.

=item strict_type

This does a C<ref()> check on the argument provided. The C<ref> of the
argument must be the same as the C<ref> of the default value for this
check to pass.

This is very usefull if you insist on taking an array reference as
argument for example.

=item allow

A set of criteria used to validate a perticular piece of data if it
has to adhere to particular rules.
You can use the following types of values for allow:

=over 4

=item string

The provided argument MUST be equal to the string for the validation
to pass.

=item array ref

The provided argument MUST equal (or match in case of a regular
expression) one of the elements of the array ref for the validation to
pass.

=item regexp

The provided argument MUST match the regular expression for the
validation to pass.

=item subroutine

The provided subroutine MUST return true in order for the validation
to pass and the argument accepted.

(This is particularly usefull for more complicated data).

=back

=back

=head1 Functions

=head2 check

CPANPLUS::Tools::Check only has one function, which is called C<check>.

This function is not exported by default, so you'll have to ask for it
via:

    use CPANPLUS::Tools::Check qw[check];

or use it's fully qualified name instead.

C<check> takes a list of arguments, as follows:

=over 4

=item Template

This is a hashreference which contains a template as explained in the
synopsis.

=item Arguments

This is a reference to a hash of named arguments which need checking.

=item Verbose

A boolean to indicate whether C<check> should be verbose and warn
about whant went wrong in a check or not.

=back

C<check> will return undef when it fails, or a hashref with lowercase
keys of parsed arguments when it succeeds.

So a typical call to check would look like this:

    my $parsed = check( \%template, \%arguments, $VERBOSE )
                    or warn q[Arguments could not be parsed!];


=head1 Global Variables

The behaviour of CPANPLUS::Tools::Check can be altered by changing the
following global variables:

=head2 $CPANPLUS::Tools::Check::VERBOSE

This controls whether CPANPLUS::Check::Module will issue warnings and
explenations as to why certain things may have failed. If you set it
to 0, CPANPLUS::Tools::Check will not output any warnings.
The default is 1;

=head2 $CPANPLUS::Tools::Check::STRICT_TYPE

This works like the C<strict_type> option you can pass to C<check>,
which will turn on C<strict_type> globally for all calls to C<check>.
The default is 0;

=head2 $CPANPLUS::Tools::Check::ALLOW_UNKNOWN

If you set this flag, unknown options will still be present in the
return value, rather than filtered out. This is usefull if your
subroutine is only interested in a few arguments, and wants to pass
the rest on blindly to perhaps another subroutine.
The default is 0;


=head1 AUTHOR

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt>.

=head1 Acknowledgements

Thanks to Ann Barcomb for her suggestions.

=head1 COPYRIGHT

This module is
copyright (c) 2002 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

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
         
