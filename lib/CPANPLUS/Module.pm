package CPANPLUS::Module;

use strict;
use vars qw[@ISA];

use CPANPLUS::inc;
use CPANPLUS::Dist;
use CPANPLUS::Error;
use CPANPLUS::Module::Signature;
use CPANPLUS::Module::Checksums;
use CPANPLUS::Internals::Constants;

use FileHandle;

use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';
use IPC::Cmd                    qw[can_run run];
use File::Find                  qw[find];
use Params::Check               qw[check];
use Module::Load::Conditional   qw[can_load check_install];

$Params::Check::VERBOSE = 1;

@ISA = qw[ CPANPLUS::Module::Signature CPANPLUS::Module::Checksums];

=pod

=head1 NAME

CPANPLUS::Module

=head1 SYNOPSIS

    ### get a module object from the CPANPLUS::Backend object
    my $mod = $cb->module_tree('Some::Module');

    ### accessors
    $mod->version;
    $mod->package;

    ### methods
    $mod->fetch;
    $mod->extract;
    $mod->install;


=head1 DESCRIPTION

C<CPANPLUS::Module> creates objects from the information in the
source files. These can then be used to query and perform actions
on, like fetching or installing.

These objects should only be created internally. For C<fake> objects,
there's the C<CPANPLUS::Module::Fake> class. To obtain a module object
consult the C<CPANPLUS::Backend> documentation.

=cut

my $tmpl = {
    module      => { default => '', required => 1 },    # full module name
    version     => { default => '0.0' },                # version number
    path        => { default => '', required => 1 },    # extended path on the
                                                        # cpan mirror, like
                                                        # /author/id/K/KA/KANE
    comment     => { default => ''},                    # comment on module
    package     => { default => '', required => 1 },    # package name, like
                                                        # 'bar-baz-1.03.tgz'
    description => { default => '' },                   # description of the
                                                        # module
    dslip       => { default => '    ' },               # dslip information
    _id         => { required => 1 },                   # id of the Internals
                                                        # parent object
    status      => { no_override => 1 },                # stores status object
    author      => { default => '', required => 1,
                     allow => IS_AUTHOBJ },             # module author
};

### autogenerate accessors ###
for my $key ( keys %$tmpl ) {
    no strict 'refs';
    *{__PACKAGE__."::$key"} = sub {
        $_[0]->{$key} = $_[1] if @_ > 1;
        return $_[0]->{$key};
    }
}

=pod

=head1 CLASS METHODS

=head2 accessors ()

Returns a list of all accessor methods to the object

=cut

sub accessors { return keys %$tmpl };

=head1 ACCESSORS

An objects of this class has the following accessors:

=over 4

=item module

Name of the module.

=item version

Version of the module. Defaults to '0.0' if none was provided.

=item path

Extended path on the mirror.

=item comment

Any comment about the module -- largely unused.

=item package

The name of the package.

=item description

Description of the module -- only registered modules have this.

=item dslip

The five character dslip string, that represents meta-data of the
module -- again, only registered modules have this.

=item status

The C<CPANPLUS::Module::Status> object associated with this object.
(see below).

=item author

The C<CPANPLUS::Module::Author> object associated with this object.

=item parent

The C<CPANPLUS::Internals> object that spawned this module object.

=back

=cut

sub parent {
    my $self = shift;
    my $obj  = CPANPLUS::Internals->_retrieve_id( $self->_id );

    return $obj;
}

=head1 STATUS ACCESSORS

C<CPANPLUS> caches a lot of results from method calls and saves data
it collected along the road for later reuse.

C<CPANPLUS> uses this internally, but it is also available for the end
user. You can get a status object by calling:

    $modobj->status

You can then query the object as follows:

=over 4

=item installer_type

The installer type used for this distribution. Will be one of
'makemaker' or 'build'. This determines whether C<CPANPLUS::Dist::MM>
or C<CPANPLUS::Dist::Build> will be used to build this distribution.

=item dist_cpan

The dist object used to do the CPAN-side of the installation. Either
a C<CPANPLUS::Dist::MM> or C<CPANPLUS::Dist::Build> object.

=item dist

The custom dist object used to do the operating specific side of the
installation, if you've chosen to use this. For example, if you've
chosen to install using the C<ports> format, this may be a
C<CPANPLUS::Dist::Ports> object.

Undefined if you didn't specify a separate format to install through.

=item prereqs

A hashref of prereqs this distribution was found to have. Will look
something like this:

    { Carp  => 0.01, strict => 0 }

Might be undefined if the distribution didn't have any prerequisites.

=item signature

Flag indicating, if a signature check was done, whether it was OK or
not.

=item extract

The directory this distribution was extracted to.

=item fetch

The location this distribution was fetched to.

=item readme

The text of this distributions README file.

=item uninstall

Flag indicating if an uninstall call was done successfully.

=item created

Flag indicating if the C<create> call to your dist object was done
successfully.

=item installed

Flag indicating if the C<install> call to your dist object was done
successfully.

=item checksums

The location of this distributions CHECKSUMS file.

=item checksum_ok

Flag indicating if the checksums check was done successfully.

=item checksum_value

The checksum value this distribution is expected to have

=back

=head1 METHODS

=head2 new( OPTIONS )

This method returns a C<CPANPLUS::Module> object. Normal users
should never call this method directly, but instead use the
C<CPANPLUS::Backend> to obtain module objects.

This example illustrates a C<new()> call with all required arguments:

        CPANPLUS::Module->new(
            module  => 'Foo',
            path    => 'authors/id/A/AA/AAA',
            package => 'Foo-1.0.tgz',
            author  => $author_object,
            _id     => INTERNALS_OBJECT_ID,
        );

Every accessor is also a valid option to pass to C<new>.

Returns a module object on success and false on failure.

=cut


sub new {
    my($class, %hash) = @_;

    ### don't check the template for sanity
    ### -- we know it's good and saves a lot of performance
    local $Params::Check::SANITY_CHECK_TEMPLATE = 0;

    my $object  = check( $tmpl, \%hash ) or return;

    bless $object, $class;

    my $acc = Object::Accessor->new;
    $acc->mk_accessors( qw[ installer_type dist_cpan dist prereqs
                            signature extract fetch readme uninstall
                            created installed checksums checksum_ok
                            checksum_value ] );

    $object->status( $acc );

    return $object;
}


### flush the cache of this object ###
sub _flush {
    my $self = shift;
    $self->status->mk_flush;
    return 1;
}

=head2 $mod->package_name

Returns the name of the package a module is in. For C<Acme::Bleach>
that might be C<Acme-Bleach>.

=head2 $mod->package_version

Returns the version of the package a module is in. For a module
in the package C<Acme-Bleach-1.1.tar.gz> this would be C<1.1>.

=head2 $mod->package_extension

Returns the suffix added by the compression method of a package a
certain module is in. For a module in C<Acme-Bleach-1.1.tar.gz>, this
would be C<tar.gz>.

=head2 $mod->package_is_perl_core

Returns a boolean indicating of the package a particular module is in,
is actually a core perl distribution.

=head2 $mod->module_is_supplied_with_perl_core

Returns a boolean indicating whether C<ANY VERSION> of this module
was supplied with the current running perl's core package.

=head2 $mod->is_bundle

Returns a boolean indicating if the module you are looking at, is
actually a bundle. Bundles are identified as modules whose name starts
with C<Bundle::>.

=cut

{
    my $regex = qr/^(.+)-(.+)\.((?:tar\.gz|zip|tgz))/i;

    ### fetches the test reports for a certain module ###
    sub package_name {
        return $1 if shift->package() =~ $regex;
    }

    sub package_version {
        return $2 if shift->package() =~ $regex;
    }

    sub package_extension {
        return $3 if shift->package() =~ $regex;
    }

    sub package_is_perl_core {
        my $self = shift;

        ### check if the package looks like a perl core package
        return 1 if $self->package_name eq PERL_CORE;

        my $core = $self->module_is_supplied_with_perl_core;
        ### ok, so it's found in the core, BUT it could be dual-lifed
        if ($core) {
            ### if the package is newer than installed, then it's dual-lifed
            return if $self->version > $self->installed_version;

            ### if the package is newer than corelist, then it's dual-lifed
            return if $self->version > $core;

            ### otherwise, it's older than corelist, thus unsuitable.
            return 1;
        }

        ### not in corelist, not a perl core package.
        return;
    }

    sub module_is_supplied_with_perl_core {
        my $self = shift;

        ### check Module::CoreList to see if it's a core package
        require Module::CoreList;
        my $core = $Module::CoreList::version{ $] }->{ $self->module };

        return $core;
    }
}

{
    sub is_bundle {
        return shift->module =~ /^bundle::/i ? 1 : 0;
    }
}

=pod

=head2 clone

Clones the current module object for tinkering with.
It will have a clean C<CPANPLUS::Module::Status> object, as well as
a fake C<CPANPLUS::Module::Author> object.

=cut

sub clone {
    my $self = shift;

    ### clone the object ###
    my %data;
    for my $acc ( grep !/status/, __PACKAGE__->accessors() ) {
        $data{$acc} = $self->$acc();
    }

    my $obj = CPANPLUS::Module::Fake->new( %data );

    return $obj;
}

=pod

=head2 fetch

Fetches the module from a CPAN mirror.
Look at L<CPANPLUS::Internals::Fetch::_fetch()> for details on the
options you can pass.

=cut

sub fetch {
    my $self = shift;
    my $cb   = $self->parent;

    my $where = $cb->_fetch( @_, module => $self ) or return;

    ### do an md5 check ###
    if( $cb->configure_object->get_conf('md5') and
        $self->package ne CHECKSUMS
    ) {
        unless( $self->_validate_checksum ) {
            error( loc( "Checksum error for '%1' -- will not trust package",
                        $self->package) );
            return;
        }
    }

    return $where;
}

=pod

=head2 extract

Extracts the fetched module.
Look at L<CPANPLUS::Internals::Extract::_extract()> for details on
the options you can pass.

=cut

sub extract {
    my $self = shift;
    my $cb   = $self->parent;

    unless( $self->status->fetch ) {
        error( loc( "You have not fetched '%1' yet -- cannot extract",
                    $self->module) );
        return;
    }

    return $cb->_extract( @_, module => $self );
}

=head2 get_installer_type([prefer_makefile => BOOL])

Gets the installer type for this module. This may either be C<build> or
C<makemaker>. If C<Module::Build> is unavailable or no installer type
is available, it will fall back to C<makemaker>. If both are available,
it will pick the one indicated by your config, or by the
C<prefer_makefile> option you can pass to this function.

Returns the installer type on success, and false on error.

=cut

sub get_installer_type {
    my $self = shift;
    my $cb   = $self->parent;
    my $conf = $cb->configure_object;
    my %hash = @_;

    my $prefer_makefile;
    my $tmpl = {
        prefer_makefile => { default => $conf->get_conf('prefer_makefile'),
                             store => \$prefer_makefile, allow => BOOLEANS },
    };

    check( $tmpl, \%hash ) or return;

    my $extract = $self->status->extract();
    unless( $extract ) {
        error(loc("Cannot determine installer type of unextracted module '%1'",
                  $self->module));
        return;
    }


    ### check if it's a makemaker or a module::build type dist ###
    my $found_build     = -e BUILD_PL->( $extract );
    my $found_makefile  = -e MAKEFILE_PL->( $extract );

    my $type;
    $type = INSTALLER_BUILD if !$prefer_makefile &&  $found_build;
    $type = INSTALLER_BUILD if  $found_build     && !$found_makefile;
    $type = INSTALLER_MM    if  $prefer_makefile &&  $found_makefile;
    $type = INSTALLER_MM    if  $found_makefile  && !$found_build;

    ### ok, so it's a 'build' installer, but you don't /have/ module build
    unless( check_install( module => 'Module::Build' ) ) {
        error( loc( "This module requires '%1' to be installed, ".
                    "but you don't have it! Will fall back to ".
                    "'%2', but might not be able to install!",
                     'Module::Build', INSTALLER_MM ) );
        $type = INSTALLER_MM;

    ### ok, actually we found neither ###
    } elsif ( !$type ) {
        error( loc( "Unable to find '%1' or '%2' for '%3'; ".
                    "Will default to '%4' but might be unable ".
                    "to install!", BUILD_PL->(), MAKEFILE_PL->(),
                    $self->module, INSTALLER_MM ) );
        $type = INSTALLER_MM;
    }

    return $self->status->installer_type( $type ) if $type;
    return;
}

=pod

=head2 dist([format => DISTRIBUTION_TYPE, args => {key => val}]);

Create a distribution object, ready to be installed.
Distribution type defaults to your config settings

The optional C<args> hashref is passed on to the specific distribution
types' C<create> method after being dereferenced.

Returns a distribution object on success, false on failure.

See C<CPANPLUS::Dist> for details.

=cut

sub dist {
    my $self = shift;
    my $cb   = $self->parent;
    my $conf = $cb->configure_object;
    my %hash = @_;

    my $type; my $args;
    my $tmpl = {
        format  => { default => $conf->get_conf('dist_type') ||
                                $self->status->installer_type,
                     store   => \$type },
        args    => { default => {}, store => \$args },
    };

    check( $tmpl, \%hash ) or return;

    my $dist = CPANPLUS::Dist->new( format => $type,
                                    module => $self
                            ) or return;

    $dist->create( %$args ) or return;

    $self->status->created(1);

    #$self->status->dist( $dist );

    return $dist;
}

=pod

=head2 $mod->test( )

Convenience wrapper around C<install()> that tests a module, without
installing it.
It's the equivalent to invoking C<install()> with C<target> set to
C<create> and C<skiptest> set to C<0>.

Returns true on success, false on failure.

=cut

sub test {
    my $self = shift;
    return $self->install( @_, target => 'create', skiptest => 0 );
}

=pod

=head2 install([ target => 'create|install', format => FORMAT_TYPE, extractdir => DIRECTORY, fetchdir => DIRECTORY, prefer_bin => BOOL, force => BOOL, verbose => BOOL, ..... ]);

Installs the current module. This includes fetching it and extracting
it, if this hasn't been done yet, as well as creating a distribution
object for it.

This means you can pass it more arguments than described above, which
will be passed on to the relevant methods as they are called.

See C<CPANPLUS::Internals::Fetch>, C<CPANPLUS::Internals::Extract> and
C<CPANPLUS::Dist> for details.

Returns true on success, false on failure.

=cut

sub install {
    my $self = shift;
    my $cb   = $self->parent;
    my $conf = $cb->configure_object;
    my %hash = @_;

    my $args; my $target; my $format;
    {   ### so we can use the rest of the args to the create calls etc ###
        local $Params::Check::NO_DUPLICATES = 1;
        local $Params::Check::ALLOW_UNKNOWN = 1;

        ### targets 'dist' and 'test' are now completely ignored ###
        my $tmpl = {
                        ### match this allow list with Dist->_resolve_prereqs
            target     => { default => 'install', store => \$target,
                                allow => [qw|create install|] },
            force      => { default => $conf->get_conf('force'), },
            verbose    => { default => $conf->get_conf('verbose'), },
            format     => { default => $conf->get_conf('dist_type'),
                                store => \$format },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    ### if this target is 'create' then so is the target of every prereq
    $args->{'prereq_target'} ||= 'create' if $target eq 'create';

    ### check if it's already upto date ###
    if( $target eq 'install' and !$args->{'force'} and
        !$self->package_is_perl_core() and         # seperate rules apply
        ( $self->status->installed() or $self->is_uptodate ) and
        !INSTALL_VIA_PACKAGE_MANAGER->($format)
    ) {
        msg(loc("Module '%1' already up to date, won't install without force",
                $self->module), $args->{'verbose'} );
        return $self->status->installed(1);
    }

    # if it's a non-installable core package, abort the install.
    if( $self->package_is_perl_core() ) {
        # if the installed is newer, say so.
        if( $self->installed_version > $self->version ) {
            error(loc("The core Perl %1 module '%2' (%3) is more ".
                      "recent than the latest release on CPAN (%4). ".
                      "Aborting install.",
                      $], $self->module, $self->installed_version,
                      $self->version ) );
        # if the installed matches, say so.
        } elsif( $self->installed_version == $self->version ) {
            error(loc("The core Perl %1 module '%2' (%3) can only ".
                      "be installed by Perl itself. ".
                      "Aborting install.",
                      $], $self->module, $self->installed_version ) );
        # otherwise, the installed is older; say so.
        } else {
            error(loc("The core Perl %1 module '%2' can only be ".
                      "upgraded from %3 to %4 by Perl itself (%5). ".
                      "Aborting install.",
                      $], $self->module, $self->installed_version,
                      $self->version, $self->package ) );
        }
        return;
    }

    ### fetch it if need be ###
    unless( $self->status->fetch ) {
        my $params;
        for (qw[prefer_bin fetchdir]) {
            $params->{$_} = $args->{$_} if exists $args->{$_};
        }
        for (qw[force verbose]) {
            $params->{$_} = $args->{$_} if defined $args->{$_};
        }
        $self->fetch( %$params ) or return;
    }

    ### extract it if need be ###
    unless( $self->status->extract ) {
        my $params;
        for (qw[prefer_bin extractdir]) {
            $params->{$_} = $args->{$_} if exists $args->{$_};
        }
        for (qw[force verbose]) {
            $params->{$_} = $args->{$_} if defined $args->{$_};
        }
        $self->extract( %$params ) or return;
    }

    $format ||= $self->status->installer_type;

    unless( $format ) {
        error( loc( "Don't know what installer to use; " .
                    "Couldn't find either '%1' or '%2' in the extraction " .
                    "directory '%3' -- will be unable to install",
                    BUILD_PL->(), MAKEFILE_PL->(), $self->status->extract ) );

        $self->status->installed(0);
        return;
    }


    ### do SIGNATURE checks? ###
    if( $conf->get_conf('signature') ) {
        unless( $self->check_signature( verbose => $args->{verbose} ) ) {
            error( loc( "Signature check failed for module '%1' ".
                        "-- Not trusting this module, aborting install",
                        $self->module ) );
            $self->status->signature(0);
            return;

        } else {
            ### signature OK ###
            $self->status->signature(1);
        }
    }

    ### a target of 'create' basically means not to run make test ###
    ### eh, no it /doesn't/.. skiptest => 1 means skiptest => 1.
    #$args->{'skiptest'} = 1 if $target eq 'create';

    ### bundle rules apply ###
    if( $self->is_bundle ) {
        ### check what we need to install ###
        my @prereqs = $self->bundle_modules();
        unless( @prereqs ) {
            error( loc( "Bundle '%1' does not specify any modules to install",
                        $self->module ) );

            ### XXX mark an error here? ###
        }
    }

    my $dist = $self->dist( format => $format, args => $args );
    unless( $dist ) {
        error( loc( "Unable to create a new distribution object for '%1' " .
                    "-- cannot continue", $self->module ) );
        return;
    }

    return 1 if $target ne 'install';

    my $ok = $dist->install() ? 1 : 0;

    $self->status->installed($ok);

    return 1 if $ok;
    return;
}

=pod bundle_modules()

Returns a list of module objects the Bundle specifies.

This requires you to have extracted the bundle already, using the
C<extract()> method.

Returns false on error.

=cut

sub bundle_modules {
    my $self = shift;
    my $cb   = $self->parent;

    unless( $self->is_bundle ) {
        error( loc("'%1' is not a bundle", $self->module ) );
        return;
    }

    my $dir;
    unless( $dir = $self->status->extract ) {
        error( loc("Don't know where '%1' was extracted to", $self->module ) );
        return;
    }

    my @files;
    find( {
        wanted      => sub { push @files, File::Spec->rel2abs($_) if /\.pm/i; },
        no_chdir    => 1,
    }, $dir );

    my $prereqs = {}; my @list; my $seen = {};
    for my $file ( @files ) {
        my $fh = FileHandle->new($file)
                    or( error(loc("Could not open '%1' for reading: %2",
                        $file,$!)), next );

        my $flag;
        while(<$fh>) {
            ### quick hack to read past the header of the file ###
            last if $flag && m|^=head|i;

            ### from perldoc cpan:
            ### =head1 CONTENTS
            ### In this pod section each line obeys the format
            ### Module_Name [Version_String] [- optional text]
            $flag = 1 if m|^=head1 CONTENTS|i;

            if ($flag && /^(?!=)(\S+)\s*(\S+)?/) {
                my $module  = $1;
                my $version = $2 || '0';

                my $obj = $cb->module_tree($module);

                unless( $obj ) {
                    error(loc("Cannot find bundled module '%1'", $module),
                          loc("-- it does not seem to exist") );
                    next;
                }

                ### make sure we list no duplicates ###
                unless( $seen->{ $obj->module }++ ) {
                    push @list, $obj;
                    $prereqs->{ $module } =
                        $cb->_version_to_number( version => $version );
                }
            }
        }
    }

    ### store the prereqs we just found ###
    $self->status->prereqs( $prereqs );

    return @list;
}

=pod

=head2 readme

Fetches the readme belonging to this module and stores it under
C<< $obj->status->readme >>. Returns the readme as a string on
success and returns false on failure.

=cut

sub readme {
    my $self = shift;

    ### did we already dl the readme once? ###
    return $self->status->readme() if $self->status->readme();

    ### this should be core ###
    return unless can_load( modules     => { FileHandle => '0.0' },
                            verbose     => 1,
                        );

    ### get a clone of the current object, with a fresh status ###
    my $obj  = $self->clone or return;

    ### munge the package name
    my $pkg = README->( $obj );
    $obj->package($pkg);

    my $file = $obj->fetch or return;

    ### read the file into a scalar, to store in the original object ###
    my $fh = new FileHandle;
    unless( $fh->open($file) ) {
        error( loc( "Could not open file '%1': %2", $file, $! ) );
        return;
    }

    my $in;
    { local $/; $in = <$fh> };
    $fh->close;

    return $self->status->readme( $in );
}

=pod

=head2 installed_version()

Returns the currently installed version of this module, if any.

=head2 installed_file()

Returns the location of the currently installed file of this module,
if any.

=head2 is_uptodate([version => VERSION_NUMBER])

Returns a boolean indicating if this module is uptodate or not.

=cut

### uptodate/installed functions
{   my $map = {             # hashkey,      alternate rv
        installed_version   => ['version',  0 ],
        installed_file      => ['file',     ''],
        is_uptodate         => ['uptodate', 0 ],
    };

    while( my($method, $aref) = each %$map ) {
        my($key,$alt_rv) = @$aref;

        no strict 'refs';
        *$method = sub {
            ### never use the @INC hooks to find installed versions of
            ### modules -- they're just there in case they're not on the
            ### perl install, but the user shouldn't trust them for *other*
            ### modules!
            local @INC = CPANPLUS::inc->original_inc;

            my $self = shift;
            my $href = check_install(
                            module  => $self->module,
                            version => $self->version,
                            @_,
                        );

            return $href->{$key} || $alt_rv;
        }
    }
}



=pod

=head2 details()

Returns a hashref with key/value pairs offering more information about
a particular module. For example, for C<Time::HiRes> it might look like
this:

    Author                  Jarkko Hietaniemi (jhi@iki.fi)
    Description             High resolution time, sleep, and alarm
    Development Stage       Released
    Interface Style         plain Functions, no references used
    Language Used           C and perl, a C compiler will be needed
    Package                 Time-HiRes-1.65.tar.gz
    Support Level           Developer
    Version Installed       1.52
    Version on CPAN         1.65

=cut

sub details {
    my $self = shift;
    my $conf = $self->parent->configure_object();
    my $cb   = $self->parent;
    my %hash = @_;

    my $res = {
        Author              => loc("%1 (%2)",   $self->author->author(),
                                                $self->author->email() ),
        Package             => $self->package,
        Description         => $self->description     || loc('None given'),
        'Version on CPAN'   => $self->version,
    };

    ### check if we have the module installed
    ### if so, add version have and version on cpan
    $res->{'Version Installed'} = $self->installed_version
                                    if $self->installed_version;

    my $i = 0;
    for my $item( split '', $self->dslip ) {
        $res->{ $cb->_dslip_defs->[$i]->[0] } =
                $cb->_dslip_defs->[$i]->[1]->{$item} || loc('Unknown');
        $i++;
    }

    return $res;
}

=pod

=head2 fetch_report()

This function queries the CPAN testers database at
I<http://testers.cpan.org/> for test results of specified module
objects, module names or distributions.

Look at L<CPANPLUS::Internals::Report::_query_report()> for details on
the options you can pass.


=cut

sub fetch_report {
    my $self    = shift;
    my $cb      = $self->parent;

    return $cb->_query_report( @_, module => $self );
}

=pod

=head2 uninstall([type => [all|man|prog])

This function uninstalls the specified module object.

You can install 2 types of files, either C<man> pages or C<prog>ram
files. Alternately you can specify C<all> to uninstall both (which
is the default).

Returns true on success and false on failure.

Do note that this does an uninstall via the so-called C<.packlist>,
so if you used a module installer like say, C<ports> or C<apt>, you
should not use this, but use your package manager instead.

=cut

sub uninstall {
    my $self = shift;
    my $conf = $self->parent->configure_object();
    my %hash = @_;

    my ($type,$verbose);
    my $tmpl = {
        type    => { default => 'all', allow => [qw|man prog all|],
                        store => \$type },
        verbose => { default => $conf->get_conf('verbose'),
                        store => \$verbose },
        force   => { default => $conf->get_conf('force') },
    };

    ### XXX add a warning here if your default install dist isn't
    ### makefile or build -- that means you are using a package manager
    ### and this will not do what you think!

    my $args = check( $tmpl, \%hash ) or return;

    if( $conf->get_conf('dist_type') and (
        ($conf->get_conf('dist_type') ne INSTALLER_BUILD) or
        ($conf->get_conf('dist_type') ne INSTALLER_MM))
    ) {
        msg(loc("You have a default installer type set (%1) ".
                "-- you should probably use that package manager to " .
                "uninstall modules", $conf->get_conf('dist_type')), $verbose);
    }

    ### check if we even have the module installed -- no point in continuing
    ### otherwise
    unless( $self->installed_version ) {
        error( loc( "Module '%1' is not installed, so cannot uninstall",
                    $self->module ) );
        return;
    }

                                                ### nothing to uninstall ###
    my $files   = $self->files( type => $type )             or return;
    my $dirs    = $self->directory_tree( type => $type )    or return;
    my $sudo    = $conf->get_program('sudo');

    ### just in case there's no file; M::B doensn't provide .packlists yet ###
    my $pack    = $self->packlist;
    $pack       = $pack->[0]->packlist_file() if $pack;

    ### first remove the files, then the dirs if they are empty ###
    my $flag = 0;
    for my $file( @$files, $pack ) {
        next unless defined $file && -f $file;

        msg(loc("Unlinking '%1'", $file), $verbose);

        my $buffer;
        unless ( run(   command => [$sudo, $^X, "-eunlink+q[$file]"],
                        verbose => $verbose,
                        buffer  => \$buffer )
        ) {
            error(loc("Failed to unlink '%1': '%2'",$file, $buffer));
            $flag++;
        }
    }

    for my $dir ( sort @$dirs ) {
        local *DIR;
        open DIR, $dir or next;
        my @count = readdir(DIR);
        close DIR;

        next unless @count == 2;    # . and ..

        msg(loc("Removing '%1'", $dir), $verbose);

        ### this fails on my win2k machines.. it indeed leaves the
        ### dir, but it's not a critical error, since the files have
        ### been removed. --kane
        #unless( rmdir $dir ) {
        #    error( loc( "Could not remove '%1': %2", $dir, $! ) )
        #        unless $^O eq 'MSWin32';
        #}
        my $buffer;
        unless ( run(   command => [$sudo, $^X, "-ermdir+q[$dir]"],
                        verbose => $verbose,
                        buffer  => \$buffer )
        ) {
            error(loc("Failed to rmdir '%1': %2",$dir,$buffer));
            $flag++;
        }
    }

    $self->status->uninstall(!$flag);
    $self->status->installed( $flag ? 1 : undef);

    return !$flag;
}

=pod

=head2 distributions()

Returns a list of module objects representing all releases for this
module on success, false on failure.

=cut

sub distributions {
    my $self = shift;
    my %hash = @_;

    my @list = $self->author->distributions( %hash, module => $self ) or return;

    ### it's another release then by the same author ###
    return grep { $_->package_name eq $self->package_name } @list;
}

=pod

=head2 files ()

Returns a list of files used by this module, if it is installed.

=cut

sub files {
    return shift->_extutils_installed( @_, method => 'files' );
}

=pod

=head2 directory_tree ()

Returns a list of directories used by this module.

=cut

sub directory_tree {
    return shift->_extutils_installed( @_, method => 'directory_tree' );
}

=pod

=head2 packlist ()

Returns the C<ExtUtils::Packlist> object for this module.

=cut

sub packlist {
    return shift->_extutils_installed( @_, method => 'packlist' );
}

=pod

=head2 validate ()

Returns a list of files that are missing for this modules, but
are present in the .packlist file.

=cut

sub validate {
    return shift->_extutils_installed( method => 'validate' );
}

### generic method to call an ExtUtils::Installed method ###
sub _extutils_installed {
    my $self = shift;
    my $conf = $self->parent->configure_object();
    my %hash = @_;

    my ($verbose,$type,$method);
    my $tmpl = {
        verbose => {    default     => $conf->get_conf('verbose'),
                        store       => \$verbose, },
        type    => {    default     => 'all',
                        allow       => [qw|prog man all|],
                        store       => \$type, },
        method  => {    required    => 1,
                        store       => \$method,
                        allow       => [qw|files directory_tree packlist
                                        validate|],
                    },
    };

    my $args = check( $tmpl, \%hash ) or return;

    ### old versions of cygwin + perl < 5.8 are buggy here. bail out if we
    ### find we're being used by them
    {   my $err = ON_OLD_CYGWIN;
        if($err) { error($err); return };
    }

    return unless can_load(
                        modules     => { 'ExtUtils::Installed' => '0.0' },
                        verbose     => $verbose,
                    );

    my $inst;
    unless( $inst = ExtUtils::Installed->new() ) {
        error( loc("Could not create an '%1' object", 'ExtUtils::Installed' ) );

        ### in case it's being used directly... ###
        return;
    }


    {   ### EU::Installed can die =/
        my @files;
        eval { @files = $inst->$method( $self->module, $type ) };

        if( $@ ) {
            chomp $@;
            error( loc("Could not get '%1' for '%2': %3",
                        $method, $self->module, $@ ) );
            return;
        }

        return wantarray ? @files : \@files;
    }
}



# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:

1;

__END__

todo:
reports();
