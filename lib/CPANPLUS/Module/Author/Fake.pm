package CPANPLUS::Module::Author::Fake;

use CPANPLUS::inc;
use CPANPLUS::Module::Author;
@ISA = qw[CPANPLUS::Module::Author];

use strict;
use vars            qw[@ISA];
use Params::Check   qw[check];

$Params::Check::VERBOSE = 1;

=pod

=head1 NAME

CPANPLUS::Module::Author::Fake

=head1 SYNOPSIS

    my $auth = CPANPLUS::Module::Author::Fake->new(
                    name    => 'Foo Bar',
                    email   => 'luser@foo.com',
                    cpanid  => 'FOO',
                    _id     => $cpan->id,
                );

=head1 DESCRIPTION

A class for creating fake author objects, for shortcut use internally
by CPANPLUS.

Inherits from C<CPANPLUS::Module::Author>.

=head1 METHODS

=head2 new( _id => DIGIT )

Creates a dummy author object. It can take the same options as
C<< CPANPLUS::Module::Author->new >>, but will fill in default ones
if none are provided. Only the _id key is required.

=cut

sub new {
    my $class = shift;
    my %hash  = @_;

    my $tmpl = {
        author  => { default    => 'CPANPLUS Internals' },
        email   => { default    => 'cpanplus-info@lists.sf.net' },
        cpanid  => { default    => 'CPANPLUS' },
        _id     => { required   => 1 },
    };

    my $args = check( $tmpl, \%hash ) or return;

    my $obj = CPANPLUS::Module::Author->new( %$args ) or return;

    ### rebless object ###
    return bless $obj, $class;
}

1;


# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
