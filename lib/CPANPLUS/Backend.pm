# $File: //member/autrijus/cpanplus/dist/lib/CPANPLUS/Backend.pm $
# $Revision: #20 $ $Change: 4042 $ $DateTime: 2002/04/30 10:59:09 $

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
        type            => { required => 1, default => '' },
        list            => { required => 1, default => [] },
        authors_only    => { default => 0 },
        data            => { default => {} },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    return 0 unless $self->_check_input( %$args );

    my $href;

    ### type can be 'author' or 'module' or any other 'module-obj' key
    ### _query_author_tree will find authors matching the patterns
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
        modules         => { required => 1, default=> [] },
        force           => { default => undef },
        makeflags       => { default => undef }, # hashref
        make            => { default => undef },
        perl            => { default => undef },
        makemakerflags  => { default => undef }, # hashref
        fetchdir        => { default => undef },
        target          => { default => 'install' },
        prereq_target   => { default => 'install' },
        type            => { default => 'MakeMaker', }
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $force = $args->{'force'};
    $force = $self->{_conf}->get_conf('force') unless defined $force;

    my $href;
    for my $mod ( @{$args->{"modules"}} ) {
        my $mods = $self->parse_module(modules => [$mod]) or next;

        my ($name, $modobj) = each %$mods;

        unless ( $name =~ m|/| or $name =~ /^Bundle::/ or $force ) {
            my $res =  $self->_check_install( module => $name );

            if ($res->{uptodate}) {
                my $do_install = ($args->{target} =~ /^(?:install|skiptest)$/);
                $err->inform(
                    msg => "Module $name already up to date; ".
                           ($do_install ? "won't install without force!"
                                        : "continuing anyway.")
		);
                next if $do_install;
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
        fetchdir    => { default => '' },
        force       => { default => undef },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $force = $args->{'force'};
    $force = $self->{_conf}->get_conf('force') unless defined $force;

    ### perhaps we shouldn't do a "_check_install" if we just want to fetch?
#    my @list;
#    unless ( $force == 1 ) {
#        for my $el ( @{ $args->{'modules'} } ) {
#            my $mod = $self->module_tree->{$el};
#            $self->_check_install( module => $mod->{module}, version => $mod->{version} )
#            ? $err->inform( msg => qq[ $mod->{module}, version $mod->{version} already installed, won't fetch without force] )
#            : push (@list, $el);
#        }
#        $args->{'modules'} = \@list;
#    }


    my $href;

    for my $mod ( @{$args->{'modules'}} ) {
        my $mods = $self->parse_module(modules => [$mod]) or next;

        my ($name, $modobj) = each %$mods;

        my $rv = $self->_fetch(
            data        => $modobj,
            fetchdir    => $args->{'fetchdir'},
            force       => $force,
        );

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
        force       => { default => undef },
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
        force           => { default => undef },
        makeflags       => { default => undef }, # hashref
        make            => { default => undef },
        perl            => { default => undef },
        makemakerflags  => { default => undef }, # hashref
        target          => { default => 'install' },
        prereq_target   => { default => 'install' },
        type            => { default => 'MakeMaker' },
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
sub module_tree { return shift->_module_tree }

### return the author tree
sub author_tree { return shift->_author_tree }

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
        my $mods = $self->parse_module(modules => [$mod]) or next;

        my ($name, $modobj) = each %$mods;

        my $rv = $self->_files( module => $modobj->{module}, %$args );

        unless ( $rv ) {
            $err->trap( error => "Could not get files for $name");
            $href->{ $name } = 0;
        } else {
            $href->{ $name } = $rv;
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
        my $mods = $self->parse_module(modules => [$mod]) or next;

        my ($name, $modobj) = each %$mods;

        my $rv = $self->_uninstall( module => $modobj->{module}, %$args );

        unless ( $rv ) {
            $err->trap( error => "Could not uninstall $name");
            $href->{ $name } = 0;
        } else {
            $href->{ $name } = $rv;
        }
    }
    return $href;
}

### wrapper for CPANPLUS::Internals::_check_install ###
### check if something's up to date against the newest CPAN version
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
        my $mods = $self->parse_module(modules => [$mod]) or next;

        my ($name, $modobj) = each %$mods;

        $href->{$name} = $self->_check_install(
            module  => $modobj->{module},
            version => $modobj->{version},
        );
    }

    return $href;
}

sub installed { shift->_installed() }

### validates if all files for a module are actually there, as per .packlist ###
sub validate {
    my $self    = shift;
    my %hash    = @_;

    my $err = $self->{_error};

    ### input check ? ###
    my $_data = {
        modules => { required => 1, default => [] },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $href;
    for my $mod ( @{$args->{'modules'}} ) {
        my $mods = $self->parse_module(modules => [$mod]) or next;

        my ($name, $modobj) = each %$mods;

        my $rv = $self->_validate_module( module  => $modobj->{module} );

        $href->{$name} = (UNIVERSAL::isa($rv, 'ARRAY') and scalar @$rv) ? $rv : 0;
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
    my $conf    = $self->configure_object();

    my $cache = {
        methods => [ qw( _methods ) ],
        uris    => [ qw( _uris ) ],
        modules => [ qw( _todo ) ],
        path    => [ qw( _inc ) ],
        extract => [ qw( _extract ) ],
        all     => [ qw( _uris _methods _todo _inc _extract ) ],
    };

    my $list;
    return 0 unless $list = $cache->{ lc $input };

    if ( $self->_flush( list => $list ) ) {
        $self->{_error}->inform(
                            msg     => "All cached data has been flushed",
                            quiet   => !$conf->get_conf('verbose'),
                        );
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
    my $modtree   = $self->module_tree();
    my $authtree  = $self->author_tree();
    my @modules   = @{$args->{modules}};

    my $result;

    for my $mod ( @modules ) {
        my $mods = $self->parse_module(modules => [$mod]) or next;

        my ($name, $modobj) = each %$mods;

        my @dslip = split '', $modobj->{dslip};
        my $author = $authtree->{$modobj->{'author'}}
            or ($result->{$name} = 0, next);

        #### fill the result; distributions don't have a 'version'.
        $result->{$name} = {
            Author      => "$author->{name} ($author->{email})",
            Package     => $modobj->{package},
            Description => $modobj->{description} || 'None given',
        (!ref($name) and $name =~ /[^\w:]/) ? () : (
            Version     => $modobj->{version}     || 'None given',
        ) };

        for my $i (0 .. $#dslip) {
            $result->{$name}->{ $dslip_def->[$i]->[0] } =
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
    for my $auth ( keys %$list ) {
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

### looks up all the modules by a given author ###
sub modules {
    my $self = shift;

    my %hash    = @_;
    my $err     = $self->{_error};

    my $_data = {
        authors => { required => 1, default => [] },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $rv;
    for my $auth ( @{$args->{authors}} ) {

        my $href = $self->search(
            type         => 'author',
            list         => ['^'.$auth.'$'],
            authors_only => $args->{authors_only},
            data         => $args->{data},
        );

        for my $key (keys %$href ) {
            $rv->{$auth}->{$key} = $self->module_tree()->{$key};
        }
    }

    return $rv;
}


### fetches the readme file ###
sub readme {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->{_error};
    my $conf    = $self->{conf};

    my $_data = {
        modules     => { required => 1, default => [] },
        force       => { default => undef },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $force = $args->{'force'};
    $force = $self->{_conf}->get_conf('force') unless defined $force;

    my $href;

    for my $mod ( @{$args->{'modules'}} ) {
        my $mods = $self->parse_module(modules => [$mod]) or next;

        my ($name, $modobj) = each %$mods;

        ### will either return a filename, or '0' for now
        my $rv = $self->_readme(
            module => $modobj,
            force  => $force,
        );

        unless ($rv) {
            $err->trap( error => "fetching readme for $name failed!" );
            $href->{ $name } = 0;
        } else {
            $href->{ $name } = $rv;
        }
    }

    return $href;
}

### displays the CPAN test result of given distributions; a wrapper for Report.pm
sub reports {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->{_error};
    my $conf    = $self->{conf};

    my $_data = {
        modules      => { required => 1, default => [] },
        all_versions => { default => 0 },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $href;
    foreach my $mod (@{$args->{modules}}) {
        my ($name, $modobj) = $self->_parse_module(mod => $mod) or next;

        if (my $dist = $modobj->{package}) {
            $href->{$name} = $self->_query_report(
                package      => $dist,
                all_versions => $args->{all_versions},
            ) or next;

        }
        else {
            $err->trap( error => "Cannot find distribution for $mod, skipping" );
        }
    }

    return $href;
}

### method to reload and optionally refetch the index files ###
sub reload_indices {
    my $self = shift;
    my %hash = @_;

    my $err     = $self->{_error};
    my $conf    = $self->{conf};

    my $_data = {
        update_source   => { required => 1, default => 0 },
        force           => { default => undef },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    ### this forcibly refetches the source files if 'update_source' is true
    ### if false, it checks whether they are still up to date (as compared to
    ### the TTL in Config.pm -kane
    $self->_check_trees(update_source => $args->{update_source} );

    {   ### uptodate => 0 means they'll have to be rebuilt ###
        my $rv = $self->_build_trees( uptodate => 0 );

        unless ($rv) {
            $err->trap( error => qq[Error rebuilding trees!] );
            return 0;
        }
    }

    return 1;
}

### canonizes a modobj, modname or distname into its pathname.
sub pathname {
    my $self = shift;
    my $err = $self->{_error};
    my %hash = @_;

    my $_data = {
        to   => { required => 1, default => '' },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    ### only takes one argument, so only pick the first if it's an arrayref
    my $to = $args->{to};
    if (ref($to) eq 'ARRAY') {
        $err->trap( error => "Array reference passed, but 'to' only takes one argument." );
        return 0;
    }

    my $mods = $self->parse_module(modules => [$to]) or return 0;

    my ($name, $modobj) = each %$mods;

    return File::Spec::Unix->catdir('', $modobj->{path}, $modobj->{package});
}

sub parse_module {
    my $self = shift;
    my $err = $self->{_error};
    my %hash = @_;

    my $_data = {
        modules => { required => 1, default => [] },
    };

    ### Input Check ###
    my $args = $self->_is_ok( $_data, \%hash );
    return 0 unless $args;

    my $rv;
    for my $mod ( @{$args->{modules}} ) {

        my ($name, $modobj) = $self->_parse_module( mod => $mod );

        if ($name) {
            $rv->{$name} = $modobj;
        }
    }

    return $rv;
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
            return exists $args->{$key} ? 1 : 0;
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
    for( keys %{$self->module_tree->{ (each %{$self->module_tree})[0] }} ) {
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


    ##### Methods which return objects #####

    my $err  = $cp->error_object();
    my $conf = $cp->configure_object();

    my $module_obj  = $cp->module_tree()->{'Dir::Purge'};
    my $all_authors = $cp->author_tree();


    ##### Methods which return hash references #####

    my $mod_search = $cp->search(type => 'module',
                                 list => ['xml', '^dbix?']);

    my $auth_search = $cp->search(type         => 'author',
                                  list         => ['(?i:mi)'],
                                  data         => $search,
                                  authors_only => 1);

    $cp->flush('modules');

    my $extract = $cp->extract(files => [$fetch_result->{B::Tree},
                                         '/tmp/POE-0.17.tar.gz']);

    my $make = $cp->make(dirs   => ['/home/munchkin/Data-Denter-0.13']
                         target => 'skiptest');


    my $installed = $cp->installed();

    my $validated = $cp->validate(modules => ['Rcs', $module_obj]);


    ### Backend methods with corresponding Module methods

    # The same result, first with a Backend then a Module method
    my $fetch_result = $cp->fetch(modules  => ['Dir::Purge']);
    $fetch_result = $module_obj->fetch();

    # Backend method
    my $txt = $cp->readme(modules => ['Mail::Box',
                              '/K/KA/KANE/Acme-POE-Knee-1.10.zip']);

    # Module method
    my $install_result = $module_obj->install(fetchdir => '/tmp');

    # Backend method
    my $info = $cp->details(modules => ['Math::Random', 'NexTrieve']);

    # Backend method
    my $test_report = $cp->reports(modules => ['Festival::Client']);

    # Backend method
    my $uninstalled = $cp->uninstall(modules => ['Acme::POE::Knee'],
                                     type    => 'prog');

    # Backend method
    my $version_is_cur = $cp->uptodate(modules => ['ControlX10::CM11']);

    # Backend method
    my $files_in_dist = $cp->files(modules => ['LEGO::RCX']);


    ### Backend methods with corresponding Module and Author methods

    # The same result via Backend, Module and Author methods
    my $mods_by_same_auth = $cp->modules(authors => ['JV']);
    $mods_by_same_auth    = $module_obj->modules();
    $mods_by_same_auth    = $all_authors->{'JV'}->modules();

    # Backend method
    my $dists_by_same_auth = $cp->distributions(authors => 'Acme::USIG');


    ##### Methods with other return values #####

    ### Backend and Module methods

    # Backend method
    my $path = $cp->pathname(to => 'C::Scan');


    ### Backend methods

    my $reload = $cp->reload_indices(update_source => 1);

=head1 DESCRIPTION

CPANPLUS::Backend is the OO interface to CPAN.
It is designed to be used by other programs, such as custom
install scripts or tailored shells.

See CPANPLUS::Shell::Default if you are looking for a ready-made interactive
interface.

=head1 METHODS

=head2 GENERAL NOTES

Unless otherwise noted, all functions which accept the I<modules> argument
accept module array elements in the form of strings or module objects.
Strings containing characters other than letters, digits, underscores
and colons will be treated as distribution files.

So, for example, the following are all valid values for I<modules>:

=over 4

=item * C<['/K/KA/KANE/Acme-POE-Knee-1.10.zip']>

=item * C<[$module_object, 'XML::Twig']>

=back

In general these methods return hash references
where the keys correspond to the names of listed modules, or, in
the case of distributions, the name of the distribution from the
CPAN author id directory, as returned by the C<pathname> method.

=head2 new(CONFIGURATION);

This creates and returns a backend object.

Arguments may be provided to override CPAN++ settings.  Settings
can also be modified with C<set_conf>.

Provide either a single CPANPLUS::Configure object:

    my $backend = new CPANPLUS::Backend($config);

or use the following syntax:

    my $backend = new CPANPLUS::Backend(conf => {debug => 0,
                                                 verbose => 1});

Refer to L<CPANPLUS::Configure> for a list of available options.

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

Refer to L<"MODULE OBJECTS"> for more information on using
module objects.

=head2 author_tree();

This function returns a hash reference with all authors.  Each key
corresponds to a CPAN identification.  The values are author
objects.

Refer to L<"AUTHOR OBJECTS"> for more information on using
author objects.

=head2 search(type => TYPE, list => [LIST], [data => PREVIOUS_RESULT], [authors_only => BOOL]);

The search function accepts the following arguments:

=over 4

=item * C<type>

This indicates what type of search should be performed.  Any
module object key may be provided as a type.  The most common
types are I<author> and I<module>.  For a complete list, refer
to L<"MODULE OBJECTS">.

=item * C<list>

This argument indicates what should be searched for.  Multiple strings
are joined in an 'or' search--modules which match any of the patterns
are returned.  An 'and' search can be performed with multiple searches
by the use of the I<data> argument.

Search strings should be specified as regular expressions.
If your version of perl supports it, you can use introduce
flags with the (?f:) syntax.  Refer to L<perlre> for more information.

=item * C<data>

In order to perform a search which matches more than pattern (and),
as opposed to matching any pattern supplied (or) as the list argument
does, first search on one pattern, then perform the second search
with the results of the first search input via the optional argument
I<data>.

=item * C<authors_only>

With this flag, searches of type I<author> can be made to return
a hash reference of author objects instead of module objects.  By
default, its value is false.  The results of an author_only search
can not be used as I<data> for subsequent searches.

=back

It returns a hash reference of module objects which matched any
of the list criteria.

=head2 details(modules => [LIST]);

See L<"GENERAL NOTES"> for more information about methods with
I<modules> arguments.

Values of the returned hash reference are 0 for unavailable modules,
or hash references containing the following keys:

=over 4

=item * C<Author>

The CPAN identification of the module author.

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

This field is only available for modules, not distributions.

=back

For example, the module details for Apache::Leak look like this:

    Author            => 'DOUGM',
    Development Stage => 'Beta testing',
    Description       => 'Memory leak tracking routines',
    Version           => '1.00',
    Package           => 'mod_perl-1.26.tar.gz',
    Language Used     => 'C and perl, a C compiler will be needed',
    Interface Style   => 'plain Functions, no references used',
    Support Level     => 'Mailing-list'

=head2 readme(modules => [LIST]);

See L<"GENERAL NOTES"> for more information about methods with
I<modules> arguments.

The values this method returns are the contents of the readme
files, or 0 for errors.

=head2 install(modules => [LIST], make => PROGRAM, makeflags => FLAGS, makemakerflags => FLAGS, perl => PERL, force => BOOL, fetchdir => DIRECTORY, extractdir => DIRECTORY, target => STRING, prereq_target => STRING);

See L<"GENERAL NOTES"> for more information about methods with
I<modules> arguments.

Install is a shortcut for performing C<fetch>, C<extract> and C<make>
on the specified modules.

Optional arguments can be used to override configuration information.

=over 4

=item * C<make>

Identify the program to use for C<make>.

=item * C<makeflags>

Flags to use with make; may be a string, a hash reference, or an
array reference.  In other words, all three forms below are equivalent:

    makeflags => '--quiet UNINST=1'
    makeflags => [ '--quiet', 'UNINST=1' ]
    makeflags => { '--quiet' => undef, 'UNINST' => 1 }

=item * C<makemakerflags>

Flags for MakeMaker may be a string, an array reference, or a hash
reference, just like C<makeflags>.  An example argument for MakeMaker is
C<{ INST_LIB =E<gt> '/home/ann/perl/lib/' }>.  See ExtUtils::MakeMaker
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

The directory fetched files should be stored in.  By default
it will store to the directory you started from.

=item * C<extractdir>

The directory files will be extracted into.  For example, if you
provide C</tmp> as an argument and the file being extracted is
C<POE-0.17.tar.gz>, the extracted files will be in C</tmp/POE-0.17>.

=item * C<target>

The objective of this attempt.  It can be one of C<makefile>, C<make>,
C<test>, C<install> (the default) or C<skiptest>.  Each target except
C<skiptest> implies all preceding ones.

The special C<skiptest> target has the same meaning as C<install>, but
will skip the C<test> step.

=item * C<prereq_target>

This argument is the objective when making prerequisite modules.
It takes the same range of values as C<target> and also defaults
to C<install>.  Usually C<install> is the correct value, or the
parent module won't make properly, but you may want to set it to
C<skiptest> if some of the prerequisites are known to fail.

=back

The values of the returned hash reference are 1 for success or
0 for failure.

Note that a failure does not identify the source of the problem,
which could be caused by a dependency rather than the named module.
It also does not indicate in what stage of the installation procedure
the failure occurred.  For more detailed information it is
necessary to examine the error object.

=head2 fetch(modules => [LIST], force => BOOL, fetchdir => DIRECTORY);

This function will retrieve the distributions that contains the modules
specified with the C<modules> argument.
Refer to L<"GENERAL NOTES"> for more information about methods with
I<modules> arguments.

The remaining arguments are optional.  A true value for force means
that pre-existing files will be overwritten.  Fetchdir behaves like
the C<install> argument of the same name.

The method will return a hash reference; values are either the
fully qualified path plus the file name of the saved module,
or--in the case of a failure--0.

Here is an example of a successful return value:

    '.\\Acme-POE-Knee-1.10.zip'

=head2 extract(files => [FILES], extractdir => DIRECTORY);

Given the full local path and file name of a module, this function
will extract it.

A hash reference will be returned.  Keys are the files specified.
If successful, the value is the directory the file was extracted
to.  Failure results in a value of 0.

Extractdir is optional and behaves like the C<install> argument
of the same name.

=head2 make(dirs => [DIRECTORIES], force => BOOL, makeflags => FLAGS, makemakerflags => FLAGS, perl => PERL, target => string, prereq_target => STRING);

This function will attempt to install the module in the specified
directory with C<perl Makefile.PL>, C<make>, C<make test>, and
C<make install>.

Optional arguments are described fully in C<install>.

The method returns a hash reference.  Directory names are keys and
values are boolean indications of status.

=head2 uninstall(modules => [LIST], type => TYPE)

This function uninstalls the modules specified.  There are
three possible arguments for type: I<prog>, I<man> and I<all>
which specify what files should be uninstalled: program files,
man pages, or both.  The default type is I<all>.

It returns a hash reference where the value is 1 for success
or 0 for failure.

See L<"GENERAL NOTES"> for more information about this method.

=head2 files(modules => [LIST]);

This function lists all files belonging to a module if the module is
installed.  See L<"GENERAL NOTES"> for more information about this
method.

It returns a hash reference.
The value will be 0 if the module is not installed.
Otherwise, it returns an array reference of files as
shown below.


    [
        'C:\\Perl\\site\\lib\\Acme\\POE\\demo_race.pl',
        'C:\\Perl\\site\\lib\\Acme\\POE\\Knee.pm',
        'C:\\Perl\\site\\lib\\Acme\\POE\\demo_simple.pl'
    ];

=head2 distributions(authors => [CPAN_ID [CPAN_ID]]);

This provides a list of all distributions by the author of the
module (given in the form of the CPAN author identification).
This information is provided by the CHECKSUMS file in the authors
directory.

It returns a hash reference where each key is
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

=head2 modules(authors => [CPAN_ID [CPAN_ID]]);

Given a CPAN author identification, this function returns the modules
by the author specified.  Multiple authors may be specified.

It returns a hash reference where each key is a module name and
each value is a module object.

=head2 reports(modules => [LIST], all_versions => BOOL);

This function queries the CPAN tester database at
I<http://testers.cpan.org/> for test results of specified module objects,
module names or distributions.

The optional argument C<all_versions> controls whether all versions of
a given distribution should be grabbed.  It defaults to false.

The function returns a hash reference.
See L<"GENERAL NOTES"> for more information about this method.

The values are themselves array references, the keys to which are the
distribution name and version.

The values are hash references, the keys to which are the
operating system name, operating system version and
the architecture name.

The values are the status of the test, which can be
one of the following: UNKNOWN, PASS, FAIL or NA.

For example,

    $cp->reports(modules => [ 'CPANPLUS' ], all_versions => 1);

might return the following data structure:

    { 'CPANPLUS' => [
        {
            'grade'    => 'PASS',
            'dist'     => 'CPANPLUS-0.031',
            'platform' => 'freebsd 4.5-release i386-freebsd'
        },
        {
            'grade'    => 'FAIL',
            'dist'     => 'CPANPLUS-0.03',
            'platform' => 'freebsd 4.2-stable i386-freebsd',
            'details'  => 'http://testers.cpan.org/search?request=dist&dist=CPANPLUS#0.03+freebsd+4.2-stable+i386-freebsd'
        },
        {
            'grade'    => 'PASS',
            'dist'     => 'CPANPLUS-0.01',
            'platform' => 'linux 2.4.8-11mdkenter i386-linux'
        },
        {
            'grade'    => 'PASS',
            'dist'     => 'CPANPLUS-0.01',
            'platform' => 'MSWin32 4.0 MSWin32-x86-multi-thread',
            'details'  => 'http://testers.cpan.org/search?request=dist&dist=CPANPLUS#0.01+MSWin32+4.0+MSWin32-x86-multi-thread'
        },
    ] }

=head2 uptodate(modules => [LIST]);

See L<"GENERAL NOTES"> for more information about this method.

This function can be used to see if your installation of a
specified module is up-to-date.
See L<"GENERAL NOTES"> for more information about this method.

Values of the returned hash reference
may be undef if the module is not installed, or a hash
reference.  The hash reference contains the following keys:
I<uptodate>, I<version> and
I<file>.  Their values are 0 or 1 if the file is not up-to-date
or is up-to-date, the number of the most recent version found
on the CPAN, and the file in which the most recent version was
found.

For example, assuming you have I<Acme::POE::Knee> but not I<XML::Twig>
installed, and provide the argument C<['Acme::POE::Knee', 'XML::Twig'>
the following data structure might be returned:

    {
        'XML::Twig' => undef,
        'Acme::POE::Knee' => {
            'version'  => '1.10',
            'file'     => 'C:\\Perl\\site\\lib\\Acme\\POE\\Knee.pm',
            'uptodate' => 1
        }
    }

=head2 validate(modules => [LIST]);

See L<"GENERAL NOTES"> for information about the I<modules> argument
or the keys of the returned hash reference.

Hash reference values will be either
an empty array reference (if no files are missing), an array reference
containing the missing files, or 0 if there was an error (such as
the module not being installed).

It is probably best to use the results of the C<installed>
method because not all modules have proper names.  For
instance, 'LWP' is installed as 'Libwww'.

=head2 installed();

This function returns all modules currently installed on
your system.

See L<"GENERAL NOTES"> for more information about this method.

The values in the returned hash reference are module objects.

If there was an ambiguity in finding the object, the value
will be 0.  An example of an ambiguous module is LWP, which
is in the packlist as 'libwww-perl', along with many other
modules.

=head2 flush(CACHE_NAME);

This method allows flushing of caches.
There are several things which can be flushed:

=over 4

=item * C<methods>

The return status of methods which have been attempted, such as
different ways of fetching files.  It is recommended that automatic
flushing be used instead.

=item * C<uris>

The return status of URIs which have been attempted, such as
different hosts of fetching files.  It is recommended that automatic
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

=head2 reload_indices([update_source => BOOL]);

This method refetches and reloads index files.  It accepts
one optional argument.  If the value of C<update_source> is
true, CPANPLUS will download new source files regardless.
Otherwise, if your current source files are up-to-date
according to your config, it will not fetch them.

It returns 0 in the event of failure, and 1 for success.

=head2 pathname(to => MODULE);

This function returns the path, from the CPAN author id, of
the distribution.  It returns 0 for failure.

The value for I<to> can be a module name, a module object, or
part of a distribution name.  For instance, the following
values for I<to> would all return C<'/M/MS/MSCHWERN/Test-Simple-0.42.tar.gz'>
(as of this writing):

=over 4

=item * C<'Test::Simple'>

=item * C<$cp->module_tree->{'Test::Simple'}>

=item * C<'Test-Simple-0.42.tar.gz'>

=back

The first two examples will return the most recent version of the module,
whereas the last will explicitly return version 0.42.

=head1 MODULE OBJECTS

=head2 Methods

Module objects belong to CPANPLUS::Internals::Module but
should not be created manually.  Instead, use the objects
returned by Backend methods, such as I<module_tree>.

For many Backend functions, it is also possible to call
the function with a module object instead of a Backend
object.  In this case the 'modules' argument of the Backend
function is no longer valid--the (single) module is assumed
to be the object through which the function is accessed.
All other arguments available for the Backend method may
be used.

The functions return almost what the Backend method returns,
except whereas the Backend method returns a hash reference
where each module name is a key, the Module methods return
only the value, because they can only be called on one module
at a time.

For example, C<$cp-E<gt>readme(modules =E<gt> 'Gtk');>
will return

    { 'Gtk' => $some_result }

but the module method, C<$gtk_module_obj-E<gt>readme();>
will return simply

    $some_result

The following methods are available:

=over 4

=item * C<$module_object-E<gt>details()>

=item * C<$module_object-E<gt>readme()>

=item * C<$module_object-E<gt>distributions()>

=item * C<$module_object-E<gt>files()>

Note that this method only works for installed modules, since it reads
the F<.packlist> present on the local disk.

=item * C<$module_object-E<gt>fetch()>

=item * C<$module_object-E<gt>install()>

=item * C<$module_object-E<gt>uninstall()>

=item * C<$module_object-E<gt>uptodate()>

=item * C<$module_object-E<gt>reports()>

=item * C<$module_object-E<gt>pathname()>

This method is an exception to the rule in that the module object
does not replace the I<modules> argument but the I<to> argument.

=item * C<$module_object-E<gt>modules()>

This method is another exception in that the module object replaces
the I<authors> argument instead of the I<modules> argument.

=back

In addition to these methods, access methods are available for
all the keys in the module object.  These are simply the name of
the key and return the value.

For example, C<$module_object-E<gt>path()> for the object shown
below would return C<'L/LB/LBROCARD'>.

=head2 Object

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

=item * C<author>

The CPAN identification for the module author.

=item * C<comment>

This is any comment which appears in the source files; it
is largely unused.

=item * C<description>

The description of the module.

=item * C<dslip>

Information on development stage, support level, language used,
interface style and public license.

The dslip consists of single-letter codes which can be expanded with
the C<details> method from either Backend or Modules.

=item * C<module>

The name of the module.

=item * C<package>

The file name of the module on CPAN.

=item * C<path>

The path of the module on CPAN, starting
from the CPAN author id directory.  For example, if a module
was found in
C</pub/mirror/CPAN/authors/id/I/IR/IROBERTS/Crypt-OpenSSL-RSA-0.12.tar.gz>
the value for path would be just
C<I/IR/IROBERTS>.

=item * C<prereqs>

Currently not in use.

=item * C<status>

Currently not in use.

=item * C<version>

The version of the module.

=item * C<_id>

The internal identification number of the Backend object that
created this object.

=head1 AUTHOR OBJECTS

=head2 Methods

Author objects belong to CPANPLUS::Internals::Author
but should not be created manually.  Instead, use the objects
returned by Backend methods such as I<author_tree>.

Functions which are available for author objects are also
available for Backend objects.  Calling through the author
object eliminates the need to use the I<authors> argument.

Like the Module object methods, the Author object methods
return the same results as the Backend methods, minus one
level of references.

The following methods may be called with an Author object:

=over 4

=item * C<$author_object-E<gt>distributions()>

=item * C<$author_object-E<gt>modules()>

=back

In addition to these methods, access methods are available for
all the keys in the author object.  These are simply the name of
the key and return the value.

=head2 Object

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

The internal identification number of the Backend object that
created this object.

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
L<ExtUtils::MakeMaker>, L<CPANPLUS::Internals::Module>, L<perlre>
http://testers.cpan.org

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
