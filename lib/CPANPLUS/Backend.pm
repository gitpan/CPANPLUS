# $File: //member/autrijus/cpanplus/dist/lib/CPANPLUS/Backend.pm $
# $Revision: #7 $ $Change: 3548 $ $DateTime: 2002/03/26 09:09:27 $

#######################################################
###                 CPANPLUS/Backend.pm             ###
### Module to provide OO interface to the CPAN++    ###
###         Written 17-08-2001 by Jos Boumans       ###
#######################################################

package CPANPLUS::Backend;

use strict;

use Carp;
use CPANPLUS::Configure;
use CPANPLUS::Internals;
use CPANPLUS::Internals::Module;
use Data::Dumper;


BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( CPANPLUS::Internals Exporter );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}


sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    ### play games with passed args
    my $conf;
    if ($_[0] and ref $_[0]) { # must have passed a $config object
        $conf = shift;
    } else {
        $conf = CPANPLUS::Configure->new( @_ );
    }

    ### Will call the _init constructor in Internals.pm ###
    my $self = $class->SUPER::_init( conf => $conf );

    return $self;
}


sub search {
    my $self = shift;
    my %hash = @_;

    my $_data = {
        type    => { required =>1, default=>'' },
        list    => { required =>1, default=>[] },
        data    => { default=>{} },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    return 0 unless $self->_check_input( %$args );

    my $href;

    ### type can be 'author' or 'module' or any other 'module-obj' key
    ### _query_author_tree will find authors matching the paterns
    ### and then do a _query_mod_tree with the finds
    if( $args->{'type'} eq 'author' ) {
        $href = $self->_query_author_tree( %$args );
    } else {
        $href = $self->_query_mod_tree( %$args );
    }

    return $href;
}


sub install {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->{_error};

    my $_data = {
        modules         => { required => 1, default=>[] },
        force           => { default => 0 },
        makeflags       => { default => '' },
        make            => { default => '' },
        perl            => { default => '' },
        makemakerflags  => { default => '' },
        fetchdir        => { default => '' },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $force = $args->{'force'} || $self->{_conf}->get_conf('force');

    my $href;
    for my $mod ( @{$args->{"modules"}} ) {

        ### the user decided to go get a file.. .something like:
        ### /D/DC/DCONWAY/Acme-Bleach-0.12.tar.gz

        my ($modobj,$name);
        if ( $mod =~ m|/| ) {

            $name = $mod;

            my @parts = split '/', $mod;

            my $file = pop @parts;
            my $path = File::Spec::Unix->catdir( @parts );

            ### Every module get's stored as a module object ###
            $modobj = CPANPLUS::Internals::Module->new(
                    module      => $file,           # full module name
                    path        => $path,           # extended path on the cpan mirror, like /A/AB/ABIGAIL
                    author      => $parts[-1],      # module author
                    package     => $file,           # package name, like 'foo-bar-baz-1.03.tar.gz'
                    _error      => $self->{_error}, # error object
                    _conf       => $self->{_conf},  # configure object
            );

        ### the user asked us for a module, say Acme::Bleach
        } else {

            ### either we pass it a module object, OR just a name
            ### we have to accept objects to work properly with
            ### CPANPLUS::Internals::Module, cuz IT doesn't store a
            ### _modtree for $self.

            if ( ref $mod eq 'CPANPLUS::Internals::Module' ) {
                ### ok, it's an object
                $modobj = $mod;

            } else {
                $modobj = $self->{_modtree}->{$mod};
            }

            $name = $modobj->{module};

	    unless( $force == 1 ) {
    	        my $res =  $self->_check_install( module => $name );

                if ($res->{uptodate}) {
                    $err->inform( msg => "Module $name already up to date; won't install without force!" );
                    next;
                }
	    }
        }

        $args->{modules} = [ $modobj ];
        my $rv = $self->_install_module( %$args );

        unless ($rv) {
            $err->trap( error => "Installing $name failed!" );
            $href->{ $name } = 0;
        } else {
            $href->{ $name } = $rv;
        }

    }

    ### flush the install status of the modules we installed so far ###
    $self->flush('modules') if $self->get_conf('flush');

    return $href;
}


sub fetch {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->{_error};
    my $conf    = $self->{conf};

    my $_data = {
        modules     => { required => 1, default => [] },
        fetchdir   	=> { default => '.' },
        force       => { default => 0 },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $force = $args->{'force'} || $self->{_conf}->get_conf('force');

    ### perhaps we shouldn't do a "_check_install" if we just want to fetch?
#    my @list;
#    unless ( $force == 1 ) {
#        for my $el ( @{ $args->{'modules'} } ) {
#            my $mod = $self->{_modtree}->{$el};
#            $self->_check_install( module => $mod->{module}, version => $mod->{version} )
#            ? $err->inform( msg => qq[ $mod->{module}, version $mod->{version} already installed, won't fetch without force] )
#            : push (@list, $el);
#        }
#        $args->{'modules'} = \@list;
#    }


    my $href;

    for my $mod ( @{$args->{'modules'}} ) {

        my $rv;
        my $name;

        ### the user decided to go get a file.. .something like:
        ### /D/DC/DCONWAY/Acme-Bleach-0.12.tar.gz
        if ( $mod =~ m|/| ) {

            my ($path,$file) = $mod =~ m|(.+)/(.+)$|;

            $name = $file;

            my $dir = File::Spec::Unix->catfile(
                                    $self->{_conf}->_get_ftp('base'),
                                    $path,
                                );

            ### we might need windowsy dirs, etc
            my @dirs = split '/', $path;
            my $fetchdir = File::Spec->catfile(
                                    $self->{_conf}->_get_build(qw[base autdir]),
                                    @dirs
                                );

            $rv = $self->_fetch(
                                file        => $file,
                                dir         => $dir,
                                fetchdir    => $fetchdir,
                                force       => $force,
                            );

        ### the user asked us for a module, say Acme::Bleach
        } else {

            ### either we pass it a module object, OR just a name
            ### we have to accept objects to work properly with
            ### CPANPLUS::Internals::Module, cuz IT doesn't store a
            ### _modtree for $self.
            my $modobj;

            if ( ref $mod eq 'CPANPLUS::Internals::Module' ) {
                ### ok, it's an object
                $modobj = $mod;
            } else {
                $modobj = $self->{_modtree}->{$mod};
            }

            $name = $modobj->{'module'};

            ### will either return a filename, or '0' for now
            $rv = $self->_fetch(
                                #data        => $self->{_modtree}->{$mod},
                                #host        => $args->{'host'},
                                data        => $modobj,
                                fetchdir    => $args->{'fetchdir'},
                                force       => $force,
                            );
        }
        unless ($rv) {
            $err->trap( error => "fetching $name failed!" );
            $href->{ $name } = 0;
        } else {
            $href->{ $name } = $rv;
        }
    }

    return $href;
}


sub extract {
    my $self    = shift;
    my %hash    = @_;

    my $_data = {
        files       => { required => 1, default => [] },
        targetdir   => { default => '' },
        force       => { default => 0 },
    };


    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $href;
    for my $file ( @{$args->{'files'}} ) {
        $args->{'file'} = $file;

        ### will either return a filename, or '0' for now
        my $rv = $self->_extract( %$args );

        unless ($rv) {
            $self->{_error}->trap( error => "extracting $file failed!" );
            $href->{ $file } = 0;
        } else {
            $href->{ $file } = $rv;
        }
    }
    return $href;
}


sub make {
    my $self = shift;
    my %hash = @_;

    my $err = $self->{_error};

    ### input check ? ###

    my $_data = {
        dirs            => { required => 1, default => [] },
        force           => { default => 0 },
        makeflags       => { default => '' },
        make            => { default => '' },
        perl            => { default => '' },
        makemakerflags  => { default => {} },
    };


    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $href;
    for my $dir ( @{$args->{'dirs'}} ) {
        my $rv = $self->_make( dir => $dir, %$args );

        unless ( $rv ) {
            $err->trap( error => "make'ing for $dir failed!");
            $href->{ $dir } = 0;
        } else {
            $href->{ $dir } = $rv;
        }
    }

    return $href;
}


### return the module tree
sub module_tree { return shift->{_modtree} }


### return the author tree
sub author_tree { return shift->{_authortree} }


### return the error object
sub error_object { return shift->{_error} };


### return the configure object
sub configure_object { return shift->{_conf} };


### wrapper for CPANPLUS::Internals::_files ###
### returns the files that belong to a certain module
sub files {
    my $self    = shift;
    my %hash    = @_;

    my $err = $self->{_error};

    ### input check ? ###
    ### possible are: ``prog'', ``man'' or ``all'',
    my $_data = {
        modules => { required => 1, default => [] },
        type    => { default => 'all' },
    };


    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $href;
    for my $mod ( @{$args->{'modules'}} ) {
        my $rv = $self->_files( module => $mod, %$args );

        unless ( $rv ) {
            $err->trap( error => "Could not get files for $mod");
            $href->{ $mod } = 0;
        } else {
            $href->{ $mod } = $rv;
        }
    }

    return $href;
}

### wrapper for CPANPLUS::Internals::_uninstall ###
### uninstall's a particular module.
### CAVEAT: we parse the packlist to do it, so modules installed
### thru say, ppm, aren't found. also, we don't ALTER the .packlist
### after this, so you CAN uninstall it, but the .packlist will tell
### you the files are still there...
### problem is there's no portable way to do it yet =/
sub uninstall {
    my $self    = shift;
    my %hash    = @_;

    my $err = $self->{_error};

    ### input check ? ###
    ### possible are: ``prog'', ``man'' or ``all'',
    my $_data = {
        modules => { required => 1, default => [] },
        type    => { default => 'all' },
    };


    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $href;
    for my $mod ( @{$args->{'modules'}} ) {
        my $rv = $self->_uninstall( module => $mod, %$args );

        unless ( $rv ) {
            $err->trap( error => "Could not uninstall $mod");
            $href->{ $mod } = 0;
        } else {
            $href->{ $mod } = $rv;
        }
    }
    return $href;
}

### wrapper for CPANPLUS::Internals::_uninstall ###
### uninstall's a particular module.
### CAVEAT: we parse the packlist to do it, so modules installed
### thru say, ppm, aren't found. also, we don't ALTER the .packlist
### after this, so you CAN uninstall it, but the .packlist will tell
### you the files are still there...
### problem is there's no portable way to do it yet =/
sub uptodate {
    my $self    = shift;
    my %hash    = @_;

    my $err = $self->{_error};

    ### input check ? ###
    ### possible are: ``prog'', ``man'' or ``all'',
    my $_data = {
        modules => { required => 1, default => [] },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $href;
    for my $mod ( @{$args->{'modules'}} ) {

        $href->{$mod} = $self->_check_install(
                                    module  => $mod,
                                    version => $self->{_modtree}->{$mod}->{version},
                                );
    }
    return $href;
}


### wrapper for CPANPLUS::Internals::_flush ###
### right now it only knows how to flush all caches, though we could allow
### the user to selectively flush - is this a good idea?
### yes, patched -kane
sub flush {
    my $self    = shift;
    my $input   = shift;

    my $cache = {
        methods => [ qw( _methods ) ],
        modules => [ qw( _todo ) ],
        path    => [ qw( _inc ) ],
        extract => [ qw( _extract ) ],
        all     => [ qw( _methods _todo _inc _extract ) ],
    };

    my $list;
    return 0 unless $list = $cache->{ lc $input };

    if ( $self->_flush( list => $list ) ) {
        $self->{_error}->inform( msg => "All cached data has been flushed." );
        return 1;
    }

    ### should never get here ###
    return 0;
}

### wrapper for CPANPLUS::Configure::get_conf ###
sub get_conf {
    my $self = shift;
    my @list = @_;

    return 0 unless @list;

    my $href;
    for my $opt ( @list ) {
        $href->{$opt} = $self->{_conf}->get_conf($opt);
    }
    return $href;
}

### wrapper for CPANPLUS::Configure::set_conf ###
sub set_conf {
    my $self = shift;

    # is there a better way to check this without a warning?
    my %args = @_, if scalar(@_) % 2 == 0;
    return 0 unless %args;

    my $href;

    for my $key (keys %args) {
        if ( $self->{_conf}->set_conf( $key => $args{$key} ) ) {
            #$self->{_error}->inform( msg => "$key set to $args{$key}" );
            $href->{$key} = $args{$key};
        } else {
            $self->{_error}->inform( msg => "unknown key: $key" );
            $href->{$key} = 0;
        }
    }

    return $href;
}

sub details {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->{_error};

    my $_data = {
        modules => { required => 1, default => [] },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $dslip_def = $self->_dslip_defs();

    my $result;
    for my $mod ( @{$args->{'modules'}} ) {
        my $href;
        unless( $href = $self->{_modtree}->{$mod} ) {
            $result->{$mod} = 0;
            next;
        }

        my @dslip = split '', $href->{dslip};

        $result->{$mod} = {
            Package     => $href->{package},
            Description => $href->{description} || 'None given',
            Version     => $href->{version}     || 'None given',
        };

        for my $i (0..$#dslip) {
            $result->{$mod}->{ $dslip_def->[$i]->[0] } =
                $dslip_def->[$i]->[1]->{ $dslip[$i] } || 'Unknown';
        }
    }

    return $result;
}

### looks for all distributions by a given author ###
sub distributions {
    my $self = shift;

    my %hash    = @_;
    my $err     = $self->{_error};

    my $_data = {
        authors => { required => 1, default => [] },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my @authors = map { "(?i:$_)" } @{$args->{authors}};

    my $list = $self->_query_author_tree( list => \@authors, authors_only => 1 );

    my $href;
    for my $auth ( @$list ) {
        my $rv = $self->_distributions( author => $auth );

        unless ( $rv ) {
            $err->trap( error => "Could not find distributions for $auth");
            $href->{ $auth } = 0;
        } else {
            $href->{ $auth } = $rv;
        }
    }

    return $href;
}

### input checks ###
{
    ### scoped variables for the input check methods ###
    my ($data, $args);


    # Return 1 if the specified key is part of %_data; 0 otherwise
    sub _is_ok{
        my $self    = shift;
        $data       = shift;
        my $href    = shift;

        #print Dumper $data, $href;

        my $err = $self->{_error};
        my $verbose = $self->{_conf}->get_conf( 'verbose' );

        #%$args = map { my $k = lc $_; $k, $href->{$_} } keys %$href;
        # same thing, but no temp needed -jmb
        %$args = map { lc, $href->{$_} } keys %$href;

        ### check if the required keys have been entered ###
        my $flag;
        for my $key ( %$data ) {

            ### check if the key is required and whether or not it was supplied
            my $rv = $self->_hasreq( $key );

            unless ( $rv ) {
                $err->trap(
                    error => qq(Required option "$key" is not provided for ) . (caller(1))[3],
                );
                $flag = 1;
            }
        }

        ### if $flag is set, at least one required option wasn't passed, and we return 0
        return 0 if $flag;

        ### set defaults for all arguments ###
        my ($defs) = $self->_hashdefs();

        ### check if all keys are valid ###
        for my $key ( keys %$args ) {

            my $rv = $self->_iskey( $key );


            ### if the key exists, override the default with the provided value ###
            if ( $rv ) {

                ### this is NOT quite working... trying to check if both data types
                ### are of the same ref. but it's screwing up =/

                #print qq(ref $defs->{$key} eq ref $args->{$key});
                #if ( ref $defs->{$key} eq ref $args->{$key} ) {

                if(1){
                    $defs->{$key} = $args->{$key};
                } else {
                    $err->inform(
                        msg     => qq( "$key" is not of a valid type for ) .
                                    (caller(1))[3] . ", using default instead!",
                        quiet   => !$verbose,
                    );
                }

            ### no $rv, means $key isn't a valid option. we just inform for this
            } else {
                $err->inform(
                    msg     => qq("$key" is not a valid option for ) . (caller(1))[3],
                    quiet   => !$verbose,
                );
            }
        }

        ### return the 'updated' $args
        return $defs;
    }


    ### check if the key exists in $data ###
    sub _iskey {
        my ($self, $key) = @_;

        return 0 unless ($self->_okcaller());

        return 1 if $data->{$key};

        return 0;
    }


    ### check if the $key is required, and if so, whether it's in $args ###
    sub _hasreq {
        my ($self, $key) = @_;
        my $reqs = $self->_listreqs();
        my $err  = $self->{_error};


        return 0 unless ($self->_okcaller());

        if ( $reqs->{$key} ) {
            return defined $args->{$key} ? 1 : 0;
        } else {
            return 1;
        }
    }


    # Return a hash ref of $_data keys with required values
    sub _listreqs {
        my %hash = map { $_ => 1 } grep { $data->{$_}->{required} } keys %$data;
        return \%hash;
    }


    # Return a hash of $data keys with default values => defaults
    sub _hashdefs {
        my %hash = map {
            $_ => $data->{$_}->{default}
        } grep {
            $data->{$_}->{default}
        } keys %$data ;

        return \%hash;
    }


    sub _okcaller {
        my $self = shift;
        my $err  = $self->{_error};

        my $package = __PACKAGE__;
        my $caller = (caller(2))[3];

        # Couldn't get a caller
        unless ( $caller ) {
            $err->trap( error => "Unable to identify caller");
            return 0;
        }

        # Caller is part of current package
        return 1 if ($caller =~ /^$package/);

        # Caller is not part of current package
        $err->trap( error => "Direct access to private method ".
                (caller(1))[3]." is forbidden");

        return 0;
    }
}


### input check, mainly used by 'search' ###
sub _check_input {
    my $self = shift;
    my %args = @_;

    ### check if we're searching for some valid key ###
    for( keys %{$self->{_modtree}->{ (each %{$self->{_modtree}})[0] }} ) {
        if ( $_ eq $args{'type'} ) { return 1 }
    }

    return 0;
}


1;

__END__

=pod

=head1 NAME

CPANPLUS::Backend - Object-oriented interface for CPAN++

=head1 SYNOPSIS

    use CPANPLUS::Backend;

    my $cp = new CPANPLUS::Backend;


    ### Backend methods which return objects ###

    my $err  = $cp->error_object();
    my $conf = $cp->configure_object();

    my $all_modules = $cp->module_tree(); 
    my $all_authors = $cp->author_tree();


    ### Backend methods which return hash references ###

    my $mod_search = $cp->search(type => 'module',
                                 list => ['xml', '^dbix?']);

    my $auth_search = $cp->search(type => 'author',
                                  list => ['(?i:mi)'],
                                  data => $search);

    $cp->flush('modules');

    $extract = $cp->extract(files => [$fetch_result->{B::Tree},
                                      '/tmp/POE-0.17.tar.gz']);

    $make = $cp->make(dirs => ['/home/munchkin/Data-Denter-0.13']);


    ### Backend methods with corresponding Module methods ###

    my $fetch_result =
      $cp->fetch(modules  => ['/K/KA/KANE/Acme-POE-Knee-1.10.zip'],
                 fetchdir => '/tmp');              # Backend method
    $fetch_result = $all_modules{'Gtk'}->fetch();  # Module method

    my $install_result = 
      $cp->install(modules => ['GD', 'Gtk'], force => 1); # Backend 
    $install_result = $all_modules{'GD'}->install();      # Module

    my $info = $cp->details(modules => ['Math::Random']); # Backend
    $info    = $all_modules{'Math::Random'}->details();   # Module


    ### Additional Module and Author methods ###

    my $mods_by_same_auth = $all_modules{'LEGO::RCX'}->modules();
    $mods_by_same_auth    = $all_authors{'JQUILLAN'}->modules();

    my $dists_by_same_auth = $all_modules{'Acme::USIG'}->distributions();
    $dists_by_same_auth    = $all_authors{'RCLAMP'}->distributions();

    my $files_in_dist = $all_modules{'Mail::Box'}->files();

    my $version_is_cur = $all_modules{'ControlX10::CM11'}->uptodate();

=head1 DESCRIPTION

CPANPLUS::Backend is the OO interface to CPAN.
It is designed to be used by other programs, such as custom
install scripts or tailored shells.

See CPANPLUS::Shell::Default if you are looking for a ready-made interactive
interface.

=head1 METHODS

=head2 new(CONFIGURATION);

This creates and returns a backend object.

Arguments may be provided to override CPAN++ settings.  Settings
can also be modified with C<set_conf>.

Provide either a single CPANPLUS::Configure object:

    my $backend = new CPANPLUS::Backend($config);

or use the following syntax:

    my $backend = new CPANPLUS::Backend(conf => {debug => 0,
                                                 verbose => 1});

Refer to CPANPLUS::Configure for a list of available options.

=head2 error_object();

This function returns a CPANPLUS::Error object which maintains errors
and warnings for this backend session.

Be aware that you should flush the error and warning caches for long-running
programs.

See L<CPANPLUS::Error> for details on using the error object.

=head2 configure_object();

This function returns a CPANPLUS::Configure object for the current
invocation of Backend.

See L<CPANPLUS::Configure> for available methods and note that you
modify this object at your own risk.

=head2 module_tree();

This method will return a hash reference where each key in the
hash is a module name and the values are module objects.

Module objects belong to CPANPLUS::Internals::Module but
should not be created manually.  Instead, use the objects
returned by Backend methods.

The following methods may be called with a module object:

=over 4

=item * C<$module_object-E<gt>details()>

This method returns a hash reference with more details about
the module.

It strongly resembles the CPANPLUS::Backend method C<details>.
The Backend method returns a hash reference of module names where
each value is another hash reference--the same hash reference 
returned by this method.

Refer to the CPANPLUS::Backend method C<details> for a description
of module details.

=item * C<$module_object-E<gt>distributions()>

This provides a list of all distributions by the author of the
module (object).  It returns a hash reference where each key is
the name of a distribution and each value is a hash reference
containing additional information: the last modified time, the
CPAN short name, md5 and the distribution size in kilobytes.

For example, the CPAN author id 'KANE' might return the following:

    {
        'Acme-POE-Knee-1.10.zip' => {
            'mtime'     => '2001-08-23',
            'shortname' => 'acmep110.zip',
            'md5'       => '6314eb799a0f2d7b22595bc7ad3df369',
            'size'      => '6625'
                                    },
        'Acme-POE-Knee-1.00.zip' => {
            'mtime'     => '2001-08-13',
            'shortname' => 'acmep100.zip',
            'md5'       => '07a781b498bd403fb12e52e5146ac6f4',
            'size'      => '12230'
                                    },
    }

=item * C<$module_object-E<gt>modules()>

This returns other modules by the author of this module (object)
in the form of a hash reference where each key is the name of a module
and each value is a module object.

=item * C<$module_object-E<gt>files()>

This function lists all files belonging to a module if the module is
installed.  It returns 0 if it is not installed.  Otherwise, it returns
an array references of files like the one in the following example:

    [
        'C:\\Perl\\site\\lib\\Acme\\POE\\demo_race.pl',
        'C:\\Perl\\site\\lib\\Acme\\POE\\Knee.pm',
        'C:\\Perl\\site\\lib\\Acme\\POE\\demo_simple.pl'
    ];


=item * C<$module_object-E<gt>fetch()>

This method will attempt to fetch the module.  It returns 0 in
the event of failure, or the path of the file for success.  An
example return value:

    '.\\Acme-POE-Knee-1.10.zip'

This method is similar to the CPANPLUS::Backend method C<fetch>.

=item * C<$module_object-E<gt>install()>

This method will try to install the module.  It returns 1 for
success and 0 for failure.

A similar result can be achieved through the CPANPLUS::Backend method
C<install>.

=item * C<$module_object-E<gt>uptodate()>

This method will check if the currently installed version of the
module is the most recent distribution.  It returns 1 if it is
and 0 if it is not.

=back

All these methods can take the same arguments as the corresponding
Backend methods.  For example, the following is valid:

    $module_object->install(force=>1);

=head2 author_tree();

This function returns a hash reference with all authors.  Each key
corresponds to a CPAN identification.  The values are author
objects.

Author objects belong to CPANPLUS::Internals::Author
but should not be created manually.  Instead, use the objects
returned by Backend methods.

The following methods may be called with an author object:

=over 4

=item * C<$author_object-E<gt>distributions()>

This method will list all distributions by an author.  It returns
a hash reference where each key is the name of a distribution and
each value is a hash reference with additional information.  

Refer to the module object method C<distributions> for an example
return.

=item * C<$author_object-E<gt>modules()>

This method will return a a hash reference where each key is the name
of a module and each value is a module object.

Refer to the documentation for module_tree() for more information on
module objects.

=back

All these methods can take the same arguments as the corresponding
Backend methods. 

=head2 details(modules => [LIST]);

Given a list of strings of module names, this function will
return a hash reference containing detailed information about
the modules in the list.

Keys correspond to the modules specified in the call, while
values are hash references which contain the following keys:

=over 4

=item * C<Description>

The description of the module.  If one was not provided, the
description will be I<None given>.

=item * C<Development Stage>

The stage of development the module is in.
This detail is expanded from dslip information.

=item * C<Interface Style>

The interface style of the module.
This detail is expanded from dslip information.

=item * C<Language Used>

The language used in the module.
This detail is expanded from dslip information.

=item * C<Package>

The package that the module is a part of.

=item * C<Support Level>

The level at which support is offered for the module.
This detail is expanded from dslip information.

=item * C<Version>

The version of the module.  If the version information is
not available, the version will be I<None given>.

=back

For example, the module details for Apache::Leak look like this:

    Development Stage => 'Beta testing'
    Description       => 'Memory leak tracking routines'
    Version           => '1.00'
    Package           => 'mod_perl-1.26.tar.gz'
    Language Used     => 'C and perl, a C compiler will be needed'
    Interface Style   => 'plain Functions, no references used'
    Support Level     => 'Mailing-list'

=head2 install(modules => [LIST], make => PROGRAM, makeflags => FLAGS,
makemakerflags => HASHREF_OF_FLAGS, perl => PERL, force => BOOL
fetchdir => DIRECTORY, extractdir => DIRECTORY);

Install is a shortcut for performing C<fetch>, C<extract> and C<make>
on the specified modules.   See the documentation on these methods
for more information.

Optional arguments can be used to override configuration information.

=over 4

=item * C<make>

Identify the program to use for C<make>.

=item * C<makeflags>

Flags to use with make.  An example is C<--quiet>.

=item * C<makemakerflags>

Flags for MakeMaker.  An example argument for MakeMaker is
C<INST_LIB =E<gt> '/home/ann/perl/lib/'>.  See ExtUtils::MakeMaker
for a complete list of possible arguments.

Note that individual modules may provide their own additional
flags.

=item * C<perl>

The path to Perl to use.

=item * C<force>

Force downloads even if files of the same name exist and
force installation even if tests fail by setting force to
a true value.

=item * C<fetchdir>

The directory fetched files should be stored in.

=item * C<extractdir>

The directory files will be extracted into.  For example, if you
provide C</tmp> as an argument and the file being extracted is
C<POE-0.17.tar.gz>, the extracted files will be in C</tmp/POE-0.17>.

=back

Install returns a hash reference.  The keys are the modules
specified and the values are either 1 for success or 0 for
failure.

Note that a failure does not identify the source of the problem,
which could be caused by a dependency rather than the named module.
It also does not indicate in what stage of the installation procedure
the failure occurred.  For more detailed information it is
necessary to examine the error object.

=head2 fetch(modules => [LIST], force => BOOL, fetchdir => DIRECTORY);

This function will retrieve the modules specified with the C<modules>
argument.  Modules can be specified by name or by a fully qualified
file name relative to the /authors/id directory on a CPAN mirror.
Names which contain a I</> will be treated as files.

The first example is a module by name, and the second is a fully
qualified file name beginning with a I</>.

=over 4

=item * C<Acme::POE::Knee>

=item * C</K/KA/KANE/Acme-POE-Knee-1.10.zip>

=back

The remaining arguments are optional.  A true value for force means
that pre-existing files will be overwritten.  Fetchdir behaves like
the C<install> argument of the same name.

The method will return a hash reference where keys are the names of
the modules in the list.  The value will either be the fully qualified
path plus the file name of the saved module, or--in the case of a
failure--0.

=head2 extract(files => [FILES], extractdir => DIRECTORY);

Given the full local path and file name of a module, this function
will extract it.

A hash reference will be returned.  Keys are the files specified.
If successful, the value is the directory the file was extracted
to.  Failure results in a value of 0.

Extractdir is optional and behaves like the C<install> argument
of the same name.

=head2 make(dirs => [DIRECTORIES], force => BOOL, makeflags => FLAGS,
makemakerflags => FLAGS, perl => PERL);

This function will attempt to install the module in the specified
directory with C<perl Makefile.PL>, C<make>, C<make test>, and
C<make install>.

Optional arguments are described fully in C<install>.

The method returns a hash reference.  Directory names are keys and
values are boolean indications of status.

=head2 flush(CACHE_NAME);

This method allows flushing of caches.
There are three which can be flushed:

=over 4

=item * C<methods>

The return status of methods which have been attempted, such as
different ways of fetching files.  It is recommended that automatic
flushing be used instead.

=item * C<modules>

Information about modules such as prerequisites and whether
installation succeeded, failed, or was not attempted.

=item * C<path>

The location of modules on the local system.

=item * C<extract>

List of archives extracted.

=item * C<all>

Flush all three of the aforementioned caches.

=back

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

L<CPANPLUS::Shell::Default>, L<CPANPLUS::Configure>, L<CPANPLUS::Error>,
L<ExtUtils::MakeMaker>, L<CPANPLUS::Internals::Module>

=cut
