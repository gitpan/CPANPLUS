# $File$
# $Revision$ $Change$ $DateTime$

#######################################################
###            CPANPLUS/Internals/Module.pm         ###
###   Subclass to make module objects for cpanplus  ###
###         Written 12-03-2002 by Jos Boumans       ###
#######################################################

### Module.pm ###

package CPANPLUS::Internals::Module;

use strict;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use CPANPLUS::Backend;
use Data::Dumper;

BEGIN {
    use Exporter    ();
    use Data::Dumper;
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
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
        module      => { default => '', required => 1 },    # full module name
        version     => { default => '0.0' },                # version number
        path        => { default => '', required => 1 },    # extended path on the cpan mirror, like /author/id/A/AB/ABIGAIL
        comment     => { default => ''},                    # comment on the module
        author      => { default => '', required => 1 },    # module author
        package     => { default => '', required => 1 },    # package name, like 'foo-bar-baz-1.03.tar.gz'
        description => { default => '' },                   # description of the module
        dslip       => { default => '    ' },               # dslip information
        prereqs     => { default => {} },                   # any prerequisites known for this module
        status      => { default => '' },                   # some status we can assign to a module
        _id         => { required => 1 },                   # id of the Internals object that spawned us
    };


    ### we're unable to use this check now because it requires a working backend object ###
#    my $cb = $class->_make_object();
#
#    my $args = $cb->_is_ok( $_data, \%hash );
#    return 0 unless keys %$args;
#
#    my $object;
#    ### put this in a loop so we can easily add stuff later if desired -kane
#    for my $key ( keys %$args ) {
#        $object->{$key} = $args->{$key};
#    }

    my $object;
    ### so for now, this is the alternative ###
    for my $key ( keys %$_data ) {

        if ( $_data->{$key}->{required} && !$hash{$key} ) {
            warn "Missing key $key\n";
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

### I prefer to have these autoloaded, but since they have the same name as in Backend.pm
### AND this module ISA Backend.pm, there'd be confusion, since ISA gets checked before
### AUTOLOAD. Tried some dynamic inheritance foo, but that broke perl (tying ISA is not supported)
### coderefs in ISA are also not supported. Lathos had some evil Devil::Pointer hack,
### but that's not core until 5.7, so we can't use it.
### other than that, there is no pure perl solution, so we're stuck writing this stuff out,
### or defining all these in a 'for' loop. -kane


### will give the details for a module just like backend would.
### invoked as $mod_object->details;
### the return value would look something like this:
#$VAR1 = {
#          'Development Stage' => 'Released',
#          'Description' => 'Libwww-perl',
#          'Version' => '5.64',
#          'Package' => 'libwww-perl-5.64.tar.gz',
#          'Language Used' => 'Perl-only, no compiler needed, should be platform independent',
#          'Interface Style' => 'Object oriented using blessed references and/or inheritance',
#          'Support Level' => 'Mailing-list'
#        };
sub details {
    my $self = shift;

    my $obj = $self->_make_object();

    my $href = $obj->details( @_, modules => [$self->{module}] );

    return $href->{$self->{module}};
}

### this will need a reference to the author_tree in the module object
### or internals will be unhappy. unfortunately, that's a catch22
### since these objects are the things that make UP the authortree... -kane
### so we solved it by storing an ID for the internals object and linking
### all the objects we need to that. We store THAT id in $self->{_id} and that
### way we can just retrieve the info we need. -kane
###
### will list all distributions by an author.
### invoked as $mod_object->distributions.
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

    my $href = $obj->distributions( @_, authors => [$self->{author}] );

    return $href->{$self->{author}};
}

### will fetch the module.
### invoked as $module_object->fetch.
### the return value would look something like this:
### 0 on failure, or the path to the file on success;
### $VAR1 = '.\\Acme-POE-Knee-1.10.zip';
sub fetch {
    my $self = shift;

    my $obj = $self->_make_object();

    my $href = $obj->fetch( @_, modules => [$self] );

    return $href->{$self->{module}};
}

### will list all the files belonging to a module
### invoked as $mod_object->files()
### return value is 0 if the module is not installed, or
### something like:
#$VAR1 = [
#          'C:\\Perl\\site\\lib\\Acme\\POE\\demo_race.pl',
#          'C:\\Perl\\site\\lib\\Acme\\POE\\Knee.pm',
#          'C:\\Perl\\site\\lib\\Acme\\POE\\demo_simple.pl'
#        ];
sub files {
    my $self = shift;

    my $obj = $self->_make_object();

    my $href = $obj->files( @_, modules => [$self->{module}] );

    return $href->{$self->{module}};
}

### this will install this modules
### invoked as $mod_object->install
### return value is 1 for success, 0 for fail.
sub install {
    my $self = shift;

    my $obj = $self->_make_object();

    my $href = $obj->install( @_, modules => [$self] );

    return $href->{$self->{module}};
}


### similar to distributions, this will list all modules by an author.
### invoked as $mod_object->modules.
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

    my $href = $obj->search( @_, type => 'author', list => ['^'.$self->{author}.'$'] );

    my $rv;

    for my $key (keys %$href ) {
        $rv->{$key} = $obj->{_modtree}->{$key};
    }

    return $rv;
}

### this will uninstall this modules
### invoked as $mod_object->uninstall
### return value is 1 for success, 0 for fail.
sub uninstall {
    my $self = shift;

    my $obj = $self->_make_object();

    my $href = $obj->uninstall( @_, modules => [$self->{module}] );

    return $href->{$self->{module}};
}

### will check if a given module is uptodate
### invoked as $mod_object->uptodate
### returns 1 if it is uptodate, 0 if not
sub uptodate {
    my $self = shift;

    my $obj = $self->_make_object();

    my $href = $obj->uptodate( @_, modules => [$self->{module}] );

    return $href->{$self->{module}}->{uptodate};
}

sub _make_object {
    my $self = shift;

    my $obj = CPANPLUS::Internals->_retrieve_id( $self->{_id} );

    return bless $obj, $Class;
}

1;

=pod

=head1 NAME

Module.pm - Module tree for CPAN++

=head1 DESCRIPTION

Module.pm is a module used internally to store information about
CPAN modules.

=head1 METHODS

Because the only Module objects that should be used are returned
by Backend methods, Module methods are documented in CPANPLUS::Backend
under the function C<module_tree>.

=head1 OBJECT

Here is a sample dump of the module object for Acme::Buffy:

    'Acme::Buffy' => bless( {
        'path' => 'L/LB/LBROCARD',
        'description' => 'An encoding scheme for Buffy fans',
        'dslip' => 'Rdph',
        'status' => '',
        'prereqs' => {},
        'module' => 'Acme::Buffy',
        'comment' => '',
        'author' => 'LBROCARD',
        '_id' => 6,
        'package' => 'Acme-Buffy-1.2.tar.gz',
        'version' => 'undef'
      }, 'CPANPLUS::Internals::Module' )

The module object contains the following information:

=head2 author

The CPAN identification for the module author.

=head2 comment

This is any comment which appears in the source files; it
is largely unused.

=head2 description

The description of the module.

=head2 dslip

Information on development stage, support level, language used,
interface style and public license.

The dslip consists of single-letter codes which can be expanded with
the C<details> method from either Backend or Modules, both of which
are documented in CPANPLUS::Backend.

=head2 module

The name of the module.

=head2 package

The file name of the module on CPAN.

=head2 path

The path of the module on CPAN, starting
from the CPAN author id directory.  For example, if a module
was found in
C</pub/mirror/CPAN/authors/id/I/IR/IROBERTS/Crypt-OpenSSL-RSA-0.12.tar.gz>
the value for path would be just
C<I/IR/IROBERTS>.

=head2 prereqs

Currently not in use.

=head2 status

Currently not in use.

=head2 version
The version of the module.

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
