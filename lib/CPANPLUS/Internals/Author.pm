# $File: //member/autrijus/cpanplus/dist/lib/CPANPLUS/Internals/Author.pm $
# $Revision: #8 $ $Change: 3564 $ $DateTime: 2002/03/27 05:03:47 $

#######################################################
###            CPANPLUS/Internals/Author.pm         ###
###   Subclass to make author objects for cpanplus  ###
###         Written 13-03-2002 by Jos Boumans       ###
#######################################################

### Author.pm ###

package CPANPLUS::Internals::Author;

use strict;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use CPANPLUS::Backend;
use CPANPLUS::Internals;
use Data::Dumper;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter CPANPLUS::Backend);
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

my $Class = "CPANPLUS::Backend";

### it's currently set to only allow creation, not modification
### of course you could poke into the object, but you really shouldn't. -kane
sub new {
    my $class   = shift;
    my %hash    = @_;

    ### allowed data ###
    my $_data = {
        name        => { required => 1 },   # full name of the author
        cpanid      => { required => 1 },   # cpan id
        email       => { default => '' },   # email address of the author
        _id         => { required => 1 },   # id of the Internals object that spawned us
    };


    ### we're unable to use this check now because it requires a working backend object ###
    #my $args = $Class->_is_ok( $_data, \%hash );
    #return 0 unless keys %$args;

    #my $object;
    ### put this in a loop so we can easily add stuff later if desired -kane
    #for my $key ( keys %$args ) {
    #    $object->{$key} = $args->{$key};
    #}

    my $object;
    ### so for now, this is the alternative ###
    for my $key ( keys %$_data ) {

        if ( $_data->{$key}->{required} && !$hash{$key} ) {
            #warn "Missing key $key\n";
            return 0;
        }

        if( defined $hash{$key} ) {
            if( $hash{$key} ) {
                $object->{$key} = $hash{$key};
            }
        } else {
            $object->{$key} = $_data->{$key}->{default};
        }
    }

    return bless $object, $class;
}

### this will need a reference to the author_tree in the module object
### or internals will be unhappy. unfortunately, that's a catch22
### since these objects are the things that make UP the authortree... -kane
### so we solved it by storing an ID for the internals object and linking
### all the objects we need to that. We store THAT id in $self->{_id} and that
### way we can just retrieve the info we need. -kane


### will list all distributions by an author.
### invoked as $author_object->distributions.
### the return value would look something like this:
#$VAR1 = {
#          'Acme-POE-Knee-1.10.zip' => {
#                                        'mtime' => '2001-08-23',
#                                        'shortname' => 'acmep110.zip',
#                                        'md5' => '6314eb799a0f2d7b22595bc7ad3df369',
#                                        'size' => '6625'
#                                      },
#          'Acme-POE-Knee-1.00.zip' => {
#                                        'mtime' => '2001-08-13',
#                                        'shortname' => 'acmep100.zip',
#                                        'md5' => '07a781b498bd403fb12e52e5146ac6f4',
#                                        'size' => '12230'
#                                      }
#        };.
sub distributions {
    my $self = shift;

    my $obj = $self->_make_object();

    my $href = $obj->distributions( @_, authors => ['^'.$self->{cpanid}.'$'] );

    return $href->{$self->{cpanid}};
}


### similar to distributions, this will list all modules by an author.
### invoked as $author_object->modules.
### the return value would look something like this:
#$VAR1 = {
#          'Acme::POE::Knee' => bless( {
#                                        'path' => 'K/KA/KANE',
#                                        'description' => '',
#                                        'dslip' => '    ',
#                                        'status' => '',
#                                        'prereqs' => {},
#                                        'module' => 'Acme::POE::Knee',
#                                        'comment' => '',
#                                        'author' => 'KANE',
#                                        '_id' => 6,
#                                        'version' => '1.10',
#                                        'package' => 'Acme-POE-Knee-1.10.zip'
#                                      }, 'CPANPLUS::Internals::Module' )
#        };
sub modules {
    my $self = shift;

    my $obj = $self->_make_object();

    my $href = $obj->search( @_, type => 'author', list => ['^'.$self->{cpanid}.'$'] );

    my $rv;

    for my $key (keys %$href ) {
        $rv->{$key} = $obj->{_modtree}->{$key};
    }

    return $rv;
}

sub _make_object {
    my $self = shift;

    my $obj = CPANPLUS::Internals->_retrieve_id( $self->{_id} );

    return bless $obj, $Class;
}

1;

=pod

=head1 NAME

CPANPLUS::Internals::Author - Author tree for CPAN++

=head1 DESCRIPTION

Author.pm is a module used internally to store information about
CPAN authors.

=head1 METHODS

Due to the fact that this module is only used in conjunction with
CPANPLUS::Backend, all methods have been documented in that module. 

=head1 OBJECT

Here is a sample dump of the author object for KANE:

    'KANE' => bless( {
        'cpanid' => 'KANE',
        '_id' => 6,
        'email' => 'boumans@frg.eur.nl',
        'name' => 'Jos Boumans'
    }, 'CPANPLUS::Internals::Author' );

The author object contains the following information:

=head2 cpanid

The CPAN identification for the module author.

=head2 email

The author's email address.

=head2 name

The author's full name.

=head2 _id

An internal identification number.

=head1 AUTHORS

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt>.

This pod text by Ann Barcomb E<lt>kudra@cpan.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001, 2002 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same 
terms as Perl itself.

=head1 SEE ALSO 

L<CPANPLUS::Backend>

=cut
