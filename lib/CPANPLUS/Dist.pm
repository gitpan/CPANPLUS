package CPANPLUS::Dist;

use strict;

use CPANPLUS::inc;
use CPANPLUS::Error;
use CPANPLUS::Internals::Constants;

use Params::Check               qw[check];
use Module::Load::Conditional   qw[can_load check_install];
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';
use Object::Accessor;

local $Params::Check::VERBOSE = 1;

my @methods = qw[status parent];
for my $key ( @methods ) {
    no strict 'refs';
    *{__PACKAGE__."::$key"} = sub {
        my $self = shift;
        $self->{$key} = $_[0] if @_;
        return $self->{$key};
    }
}

=pod

=head1 NAME

CPANPLUS::Dist

=head1 SYNOPSIS

    my $dist = CPANPLUS::Dist->new(
                                format  => 'build',
                                module  => $modobj,
                            );

=head1 DESCRIPTION

C<CPANPLUS::Dist> is a base class for any type of C<CPANPLUS::Dist::>
modules.

=head1 ACCESSORS

=over 4

=item parent()

Returns the C<CPANPLUS::Module> object that parented this object.

=item status()

Returns the C<Object::Accessor> object that keeps the status for
this module.

=back

=head1 STATUS ACCESSORS

All accessors can be accessed as follows:
    $deb->status->ACCESSOR

=over 4

=item created()

Boolean indicating whether the dist was created successfully.
Explicitly set to C<0> when failed, so a value of C<undef> may be
interpreted as C<not yet attempted>.

=item installed()

Boolean indicating whether the dist was installed successfully.
Explicitly set to C<0> when failed, so a value of C<undef> may be
interpreted as C<not yet attempted>.

=item uninstalled()

Boolean indicating whether the dist was uninstalled successfully.
Explicitly set to C<0> when failed, so a value of C<undef> may be
interpreted as C<not yet attempted>.

=item dist()

The location of the final distribution. This may be a file or
directory, depending on how your distribution plug in of choice
works. This will be set upon a successful create.

=cut

=head2 $dist = CPANPLUS::Dist->new( module => MODOBJ, [format => DIST_TYPE] );

Create a new C<CPANPLUS::Dist> object based on the provided C<MODOBJ>.
The optional argument C<format> is used to indicate what type of dist
you would like to create (like C<makemaker> for a C<CPANPLUS::Dist::MM>
object, C<build> for a C<CPANPLUS::Dist::Build> object, and so on ).
If not provided, will default to the setting as specified by your
config C<dist_type>.

Returns a C<CPANPLUS::Dist> object on success and false on failure.

=cut

sub new {
    my $self = shift;
    my %hash = @_;

    local $Params::Check::ALLOW_UNKNOWN = 1;

    ### first verify we got a module object ###
    my $mod;
    my $tmpl = {
        module  => { required => 1, allow => IS_MODOBJ, store => \$mod },
    };
    check( $tmpl, \%hash ) or return;

    ### get the conf object ###
    my $conf = $mod->parent->configure_object();

    ### figure out what type of dist object to create ###
    my $format;
    my $tmpl2 = {
        format  => {    default => $conf->get_conf('dist_type'),
                        allow   => [ __PACKAGE__->dist_types ],
                        store   => \$format  },
    };
    check( $tmpl2, \%hash ) or return;


    unless( can_load( modules => { $format => '0.0' }, verbose => 1 ) ) {
        error(loc("'%1' not found -- you need '%2' version '%3' or higher ".
                    "to detect plugins", $format, 'Module::Pluggable','2.4'));
        return;
    }

    ### bless the object in the child class ###
    my $obj = bless { parent => $mod }, $format;

    ### check if the format is available in this environment ###
    if( $conf->_get_build('sanity_check') and not $obj->format_available ) {
        error( loc( "Format '%1' is not available",$format) );
        return;
    }

    ### create a status object ###
    {   my $acc = Object::Accessor->new;
        $obj->status($acc);

        ### add minimum supported accessors
        $acc->mk_accessors( qw[created installed uninstalled dist] );
    }

    ### now initialize it or admit failure
    unless( $obj->init ) {
        error(loc("Dist initialization of '%1' failed for '%2'",
                    $format, $mod->module));
        return;
    }

    ### return the object
    return $obj;
}

=head2 @dists = CPANPLUS::Dist->dist_types;

Returns a list of the CPANPLUS::Dist::* classes available

=cut

### returns a list of dist_types we support
### will get overridden by Module::Pluggable if loaded
### XXX add support for 'plugin' dir in config as well
{   my $Loaded;
    my @Dists = (INSTALLER_BUILD, INSTALLER_MM);

    ### backdoor method to add more dist types
    sub _add_dist_types { my $self = shift; push @Dists, @_ };

    ### locally add the plugins dir to @INC, so we can find extra plugins
    #local @INC = @INC, File::Spec->catdir(
    #                        $conf->get_conf('base'),
    #                        $conf->_get_build('plugins') );

    ### load any possible plugins
    sub dist_types {

        if ( !$Loaded++ and check_install(  module  => 'Module::Pluggable',
                                            version => '2.4')
        ) {
            require Module::Pluggable;

            my $only_re = __PACKAGE__ . '::\w+$';

            ### XXX M::P 2.4 can do regexes -- find out how
            Module::Pluggable->import(
                            sub_name    => '_dist_types',
                            search_path => __PACKAGE__,
                            only        => qr/$only_re/,
                            except      => [ INSTALLER_MM, INSTALLER_SAMPLE,
                                             INSTALLER_BUILD ],
                        );
            push @Dists, grep { $_ !~ /CPANPLUS::Dist::Constants/ }
                            __PACKAGE__->_dist_types;
        }

        return @Dists;
    }
}


=head2 _resolve_prereqs

Makes sure prerequisites are resolved

XXX Need docs, internal use only

=cut

sub _resolve_prereqs {
    my $dist = shift;
    my $self = $dist->parent;
    my $cb   = $self->parent;
    my $conf = $cb->configure_object;
    my %hash = @_;

    my ($prereqs, $format, $verbose, $target, $force);
    my $tmpl = {
        ### XXX perhaps this should not be required, since it may not be
        ### packaged, just installed...
        ### Let it be empty as well -- that means the $modobj->install
        ### routine will figure it out, which is fine if we didn't have any
        ### very specific wishes (it will even detect the favourite
        ### dist_type).
        format  => { required => 1, store => \$format,
                        allow => ['',__PACKAGE__->dist_types], },
        prereqs => { required => 1, default => { },
                        strict_type => 1, store => \$prereqs },
        verbose => { default => $conf->get_conf('verbose'),
                        store => \$verbose },
        force   => { default => $conf->get_conf('force'),
                        store => \$force },
                    ### make sure allow matches with $mod->install's list
        target  => { default => '', allow => ['',qw[create ignore install]],
                        store => \$target },
    };

    check( $tmpl, \%hash ) or return;

    ### so there are no prereqs? then don't even bother
    return 1 unless keys %$prereqs;

    ### so you didn't provide an explicit target.
    ### maybe your config can tell us what to do.
    $target ||= {
        PREREQ_ASK,     'install',   # we'll bail out if the user says no
        PREREQ_BUILD,   'create',
        PREREQ_IGNORE,  'ignore',
        PREREQ_INSTALL, 'install',
    }->{ $conf->get_conf('prereqs') } || '';


    ### first, transfer this key/value pairing into a
    ### list of module objects + desired versions
    my @install_me;
    for my $mod ( sort keys %$prereqs ) {
        my $version = $prereqs->{$mod};
        my $modobj  = $cb->module_tree($mod);

        #### XXX we ignore the version, and just assume that the latest
        #### version from cpan will meet your requirements... dodgy =/
        unless( $modobj ) {
            error( loc( "No such module '%1' found on CPAN", $mod ) );
            next;
        }

        ### it's not uptodate, we need to install it
        if( !$modobj->is_uptodate(version => $version) ) {
            msg(loc("Module '%1' requires '%2' version '%3' to be installed ",
                    $self->module, $modobj->module, $version), $verbose );

            push @install_me, [$modobj, $version];

        ### it's not an MM or Build format, that means it's a package
        ### manager... we'll need to install it as well, via the PM
        } elsif ( INSTALL_VIA_PACKAGE_MANAGER->($format) and
                    !$modobj->package_is_perl_core and
                    ($target ne 'ignore')
        ) {
            msg(loc("Module '%1' depends on '%2', creating a '%3' package ".
                    "for it as well", $self->module, $modobj->module,
                    $format));
            push @install_me, [$modobj, $version];
        }
    }



    ### so you just want to ignore prereqs? ###
    if( $target eq 'ignore' ) {

        ### but you have modules you need to install
        if( @install_me ) {
            msg(loc("Ignoring prereqs, this may mean your install will fail"),
                $verbose);
            msg(loc("'%1' listed the following dependencies:", $self->module),
                $verbose);

            for my $aref (@install_me) {
                my ($mod,$version) = @$aref;

                my $str = sprintf "\t%-35s %8s\n", $mod->module, $version;
                msg($str,$verbose);
            }

            return;

        ### ok, no problem, you have all needed prereqs anyway
        } else {
            return 1;
        }
    }

    my $flag;
    for my $aref (@install_me) {
        my($modobj,$version) = @$aref;

        ### either we're told to ignore the prereq,
        ### or the user wants us to ask him
        if( ( $conf->get_conf('prereqs') == PREREQ_ASK and not
              $cb->_callbacks->install_prerequisite->($self, $modobj)
            )
        ) {
            msg(loc("Will not install prerequisite '%1' -- Note " .
                    "that the overall install may fail due to this",
                    $modobj->module), $verbose);
            next;
        }

        ### value set and false -- means failure ###
        if( defined $modobj->status->installed
            && !$modobj->status->installed
        ) {
            error( loc( "Prerequisite '%1' failed to install before in " .
                        "this session", $modobj->module ) );
            $flag++;
            last;
        }

        if( $modobj->package_is_perl_core ) {
            error(loc("Prerequisite '%1' is perl-core (%2) -- not ".
                      "installing that. Aborting install",
                      $modobj->module, $modobj->package ) );
            $flag++;
            last;
        }

        ### circular dependency code ###
        my $pending = $cb->_status->pending_prereqs || {};

        ### recursive dependency ###
        if ( $pending->{ $modobj->module } ) {
            error( loc( "Recursive dependency detected (%1) -- skipping",
                        $modobj->module ) );
            next;
        }

        ### register this dependency as pending ###
        $pending->{ $modobj->module } = $modobj;
        $cb->_status->pending_prereqs( $pending );


        ### call $modobj->install rather than doing
        ### CPANPLUS::Dist->new and the like ourselves,
        ### since ->install will take care of fetch &&
        ### extract as well
        my $ca = $dist->status->_create_args    || {};
        my $ia = $dist->status->_install_args   || {};

        unless( $modobj->install(   %$ca, %$ia,
                                    force   => $force,
                                    verbose => $verbose,
                                    format  => $format,
                                    target  => $target )
        ) {
            error(loc("Failed to install '%1' as prerequisite " .
                      "for '%2'", $modobj->module, $self->module ) );
            $flag++;
        }

        ### unregister the pending dependency ###
        $pending->{ $modobj->module } = 0;
        $cb->_status->pending_prereqs( $pending );

        last if $flag;

        ### don't want us to install? ###
        if( $target ne 'install' ) {
            my $dir = $modobj->status->extract
                        or error(loc("No extraction dir for '%1' found ".
                                     "-- weird", $modobj->module));

            $cb->_add_to_includepath(
                    directories => [
                        File::Spec->catdir(BLIB->($dir), LIB),
                        File::Spec->catdir(BLIB->($dir), ARCH),
                    ]
            );
            next;
        }
    }

    ### reset the $prereqs iterator, in case we bailed out early ###
    keys %$prereqs;

    return 1 unless $flag;
    return;
}

1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
