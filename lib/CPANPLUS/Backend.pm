# $File: //depot/cpanplus/dist/lib/CPANPLUS/Backend.pm $
# $Revision: #16 $ $Change: 7779 $ $DateTime: 2003/08/29 17:16:26 $

#######################################################
###                 CPANPLUS/Backend.pm             ###
### Module to provide OO interface to the CPAN++    ###
###         Written 17-08-2001 by Jos Boumans       ###
#######################################################

package CPANPLUS::Backend;

require 5.005;
use strict;

use CPANPLUS::I18N;
use CPANPLUS::Configure;
use CPANPLUS::Internals;
use CPANPLUS::Internals::Module;
use CPANPLUS::Backend::RV;
# use CPANPLUS::Dist;
# obsolete now, use CPANPLUS::Tools::Check instead
#use CPANPLUS::Backend::InputCheck;

use CPANPLUS::Tools::Check qw[check];

use Data::Dumper;


BEGIN {
    use vars        qw(@ISA $VERSION);
    @ISA        =   qw(CPANPLUS::Internals);
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
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        type            => { required => 1, default => '' },
        list            => { required => 1, default => [] },
        force           => { default => $conf->get_conf('force') },
        verbose         => { default => $conf->get_conf('verbose') },
        authors_only    => { default => 0 },
        data            => { default => {} },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    return undef unless $self->_check_input( %$args );

    my $href;

    ### type can be 'author' or 'module' or any other 'module-obj' key
    ### _query_author_tree will find authors matching the patterns
    ### and then do a _query_mod_tree with the finds
    if( $args->{'type'} eq 'author' ) {
        $href = $self->_query_author_tree(
                    map { $_ => $args->{$_} } qw[list authors_only verbose]
        );
    } else {
        $href = $self->_query_mod_tree(
                    map { $_ => $args->{$_} } qw[data list type verbose]
        );
    }

    return $href;
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


sub install {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        modules         => { required => 1, default => [], strict_type => 1 },
        force           => { default => $conf->get_conf('force') },
        verbose         => { default => $conf->get_conf('verbose') },
        format          => { default => $conf->get_conf('format') },
        makeflags       => { default => undef }, # hashref
        make            => { default => undef },
        perl            => { default => undef },
        makemakerflags  => { default => undef }, # hashref
        fetchdir        => { default => undef },
        extractdir      => { default => undef },
        skiptest        => { default => undef },
        target          => { default => 'install' },
        prereq_target   => { default => '' },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $force = $args->{'force'};

    my $href;
    my $flag = 0;
    my $list;

    my $ab_prefix = $conf->_get_build('autobundle_prefix');

    for my $mod ( @{$args->{"modules"}} ) {

        my $name;
        my $modobj;

        ### autobundle caveat: we dont know how to install versions
        ### that are *not* the latest version.. pause provides not enough
        ### information for that =/
        ### so right now, we just install the latest rather than guessing
        ### but this needs fixing  --kane
        if( my $is_file = -f $mod       # path to a file
            or ($ab_prefix and $mod =~ m|^$ab_prefix|)   # looks like an autobundle
        ) {

            my $file;
            unless ( $is_file ) {
                my $guess = File::Spec->catfile(
                                    $conf->_get_build('base'),
                                    $self->_perl_version( perl => $args->{perl} || $^X ),
                                    $conf->_get_build(qw|distdir autobundle|),
                                    $mod . '.pm'
                            );
                unless( -f $guess && -r _ ) {
                    $err->trap( error => loc(qq[Could not read from %1], $guess) );
                    $flag = 1;
                    next;

                } else {
                    $file = $guess;
                }

            } else {
                $file = $mod;
            }

            $list = $self->_bundle_files( file => $file );

            unless( $list ) {
                $err->trap( error => loc(qq[Problem parsing %1], $file) );
                $flag = 1;
                next;
            }

        } else {
            my $answer = $self->parse_module(modules => [$mod]);

            ### input checker.. if we couldn't parse this module, make sure we warn
            ### about it
            unless( $answer->ok ) {
                $err->trap( error => loc( qq[Unknown module '%1'; Could not parse it properly.], $mod ) );
                $flag = 1;
                next;
            }

            my $mods = $answer->rv;

            ### this *could* lead to problems if someone specified a bunch of
            ### modules, then a snapshot and more modules and wanted to turn
            ### the snapshot into a dist and that failed -- yes, i know a VERY
            ### unlikely scenario and a 'well dont do that then' sort of thing.
            ### but in that case $name would still be pointing at the *previous*
            ### module object, rather than at the one for the snapshot
            ($name, $modobj) = each %$mods;


            unless( $name =~ m|/|           # it's a location on a cpan server
                    or $name =~ /^Bundle::/ # it's a bundle file
                    or $force               # or force was enabled
                ) {

                my $res =  $self->_check_install( module => $name, version => $modobj->{version}, verbose => 0 );

                if ($res->{uptodate}) {
                    my $do_install = $args->{target} eq 'install';
                    $err->inform(
                        msg => loc("Module %1 already up to date; ", $name).
                            ($do_install ? loc("won't install without force!")
                                         : loc("continuing anyway."))
    		    );
                    next if $do_install;
                }
            }

            $list = [$modobj];
        }

        my $format = $args->{format};
        undef $format if $format and $format =~ /^MakeMaker$/i;

        my $target = $format ? 'test' : $args->{target};

        my %opts =  map     { $_ => $args->{$_} }
                    grep    { defined $args->{$_} }
                            qw[ force make makeflags makemakerflags perl fetchdir
                                extractdir skiptest prereq_target];

        ### a localised hash to store which prereqs where prompted for already
        ### this means you'll only be asked /once/ about each prereq rather than
        ### once each time a modules /says/ it has the prereq
        local $self->{_todo}->{prereqs} = {};

        my $rv = $self->_install_module(
                            %opts,
                            modules => $list,
                            target  => $target,
        );

        for my $mod ( sort keys %$rv ) {
            my $mobobj = $self->module_tree->{$mod};

            #unless ( $rv->{$mod}->install ) {
            unless ( $modobj->status->make_overall ) {
                $args->{target} eq 'test'
                    ? $err->trap( error => loc("Testing %2 failed!", $name) )
                    : $err->trap( error => loc("Installing %2 failed!", $name) );
                $flag = 1;
            }

            ### if they wanted to make a dist: ###
            if( $format && $args->{target} eq 'install' ) {
                my $rv2 = $self->dist(
                                    modules         => [$mobobj],
                                    makeflags       => $args->{makeflags},
                                    perl            => $args->{perl},
                                    make            => $args->{make},
                                    format          => $format,
                );

                unless($rv2->ok) {
                    $err->trap( error => loc("Error creating %1 from %2", $format, $mod) );
                    $flag = 1;
                    next;
                }

                my $meth = "dist_\L$format";

                unless( $modobj->status->$meth()->install ) {
                    $err->trap( error => loc("Error installing %1 as %2", $mod, $format) );
                    $flag = 1;
                    next;

                }
            }

            $modobj->status->install(!$flag);

            ### set the return value ###
            $href->{$mod} = $modobj->status->install;
        }
    }

    ### flush the install status of the modules we installed so far ###
    $self->flush('modules') if $self->configure_object->get_conf('flush');

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
}


sub fetch {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        modules     => { required => 1, default => [], strict_type => 1},
        fetchdir    => { default => '' },
        force       => { default => $conf->get_conf('force') },
        verbose     => { default => $conf->get_conf('verbose') },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $force = $args->{'force'};

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
    my $flag = 0;

    for my $mod ( @{$args->{'modules'}} ) {
        my $answer = $self->parse_module(modules => [$mod]);

        $answer->ok or ($flag=1,next);

        my $mods = $answer->rv;

        my ($name, $modobj) = each %$mods;

        my $rv = $self->_fetch(
            data        => $modobj,
            fetchdir    => $args->{'fetchdir'},
            force       => $force,
        );

        unless ($rv) {
            $err->trap( error => loc("fetching %1 failed!", $name) );
            $href->{ $name } = 0;
            $flag = 1;
        } else {
            $href->{ $name } = $modobj->status->fetch;
        }
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
}


sub extract {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        files       => { required => 1, default => [], strict_type => 1},
        extractdir  => { default => '' },
        force       => { default => $conf->get_conf('force') },
        verbose     => { default => $conf->get_conf('verbose') },
        perl        => { default => $^X },
    };


    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $href;
    my $flag = 0;

    for my $file ( @{ delete $args->{'files'} } ) {
        #$args->{'file'} = $file;

        ### will either return a filename, or '0' for now
        my $rv = $self->_extract( file => $file, %$args );

        unless ($rv) {
            $err->trap( error => loc("extracting %1 failed!", $file) );
            $href->{ $file } = 0;
            $flag = 1;
        } else {
            $href->{ $file } = $rv;
        }
    }
    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
}


sub make {
    my $self = shift;
    my %hash = @_;
    my $err  = $self->error_object;
    my $conf = $self->configure_object;

    ### input check ? ###

    my $_data = {
        dirs            => { required => 1, default => [], strict_type => 1 },
        force           => { default => $conf->get_conf('force') },
        verbose         => { default => $conf->get_conf('verbose') },
        makeflags       => { default => undef }, # hashref
        make            => { default => undef },
        perl            => { default => undef },
        makemakerflags  => { default => undef }, # hashref
        skiptest        => { default => undef },
        target          => { default => 'install' },
        prereq_target   => { default => 'install' },
        type            => { default => 'MakeMaker' },
    };


    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $href;
    my $flag = 0;
    for my $dir ( @{$args->{'dirs'}} ) {
        my $rv = $self->_make( dir => $dir, %$args );

        ### both the original module-directory, as all the prereqs
        ### will be in this rv
        for my $mod ( sort keys %$rv ) {
            unless ( $rv->{$mod}->{make}->{overall} ) {
                $err->trap( error => loc("Making %1 failed!", $mod) );
                $flag = 1;
            }

            $href->{ $mod } = $rv->{$mod}->{make};
        }

        #unless ( $rv ) {
        #    $err->trap( error => "make'ing for $dir failed!");
        #    $href->{ $dir } = 0;
        #} else {
        #    $href->{ $dir } = $rv;
        #}
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
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
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    ### input check ? ###
    ### possible are: ``prog'', ``man'' or ``all'',
    my $_data = {
        modules => { required => 1, default => [], strict_type => 1 },
        verbose => { default => $conf->get_conf('verbose') },
        type    => { default => 'all' },
    };


    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $href;
    my $flag = 0;

    for my $mod ( @{delete  $args->{'modules'}} ) {
        my $answer = $self->parse_module(modules => [$mod]);

        $answer->ok or ($flag=1,next);

        my $mods = $answer->rv;

        my ($name, $modobj) = each %$mods;

        my $rv = $self->_files( module => $modobj->{module}, %$args );

        unless ( $rv ) {
            $err->trap( error => loc("Could not get files for %1", $name));
            $href->{ $name } = 0;
            $flag = 1;
        } else {
            $href->{ $name } = $rv;
        }
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
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
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    ### input check ? ###
    ### possible are: ``prog'', ``man'' or ``all'',
    my $_data = {
        modules => { required => 1, default => [], strict_type => 1},
        type    => { default => 'all' },
        force   => { default => $conf->get_conf('force') },
        verbose => { default => $conf->get_conf('verbose') },
    };


    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $href;
    my $flag = 0;

    for my $mod ( @{$args->{'modules'}} ) {
        my $answer = $self->parse_module(modules => [$mod]);

        $answer->ok or ($flag=1,next);

        my $mods = $answer->rv;

        my ($name, $modobj) = each %$mods;

        my $rv = $self->_uninstall( module => $modobj->{module}, %$args );

        unless ( $rv ) {
            $err->trap( error => loc("Could not uninstall %1", $name));
            $href->{ $name } = 0;
            $flag = 1;
        } else {
            $modobj->status->install(0);
            $modobj->status->uninstall(1);

            $href->{ $name } = $modobj->status->uninstall;
        }
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
}

### wrapper for CPANPLUS::Internals::_check_install ###
### check if something's up to date against the newest CPAN version
sub uptodate {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        modules => { required => 1, default => [], strict_type => 1},
        force   => { default => $conf->get_conf('force') },
        verbose => { default => $conf->get_conf('verbose') },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $href;
    my $flag = 0;

    for my $mod ( @{$args->{'modules'}} ) {
        my $answer = $self->parse_module(modules => [$mod]);

        $answer->ok or ($flag=1,next);

        my $mods = $answer->rv;

        my ($name, $modobj) = each %$mods;

        $href->{$name} = $self->_check_install(
            module  => $modobj->module,
            version => $modobj->version,
            #silence the 'Could not check version on URI::file' warnings
            #verbose => $args->{verbose},
            verbose => 0,
        );

        $flag = 1 unless $href->{$name};
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
}

sub installed {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    ### input check ? ###
    my $_data = {
        modules => { default => undef }, # arrayref
        force   => { default => $conf->get_conf('force') },
        verbose => { default => $conf->get_conf('verbose') },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $href;
    my $flag = 0;

    if ($args->{'modules'} and ( ref $args->{'modules'} eq 'ARRAY') ) {
        for my $mod ( @{$args->{'modules'}} ) {
            my $answer = $self->parse_module(modules => [$mod]);

            $answer->ok or ($flag=1,next);

            my $mods = $answer->rv;

            my ($name, $modobj) = each %$mods;

            my $rv = $self->_installed( module  => $modobj );

            $href->{$name} = $rv || 0;
            $flag = 1 unless $rv;
        }

    } else {
        $href = $self->_all_installed;
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,       # no real way to check
                                    );
    return $rv;
}

### validates if all files for a module are actually there, as per .packlist ###
sub validate {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    ### input check ? ###
    my $_data = {
        modules => { required => 1, default => [], strict_type => 1 },
        force   => { default => $conf->get_conf('force') },
        verbose => { default => $conf->get_conf('verbose') },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $href;
    my $flag = 0;

    for my $mod ( @{$args->{'modules'}} ) {
        my $answer = $self->parse_module(modules => [$mod]);

        $answer->ok or ($flag=1,next);

        my $mods = $answer->rv;

        my ($name, $modobj) = each %$mods;

        my $rv = $self->_validate_module( module  => $modobj->{module} );

        $href->{$name} = (UNIVERSAL::isa($rv, 'ARRAY') and scalar @$rv) ? $rv : 0;
        $flag = 1 unless $href->{$name};
    }


    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
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
        modules => [ qw( _todo _lib) ],
        path    => [ qw( _inc ) ],
        extract => [ qw( _extract ) ],
        lib     => [ qw( _lib ) ],
        all     => [ qw( _uris _methods _todo _inc _extract _lib) ],
    };

    my $list;
    return undef unless $list = $cache->{ lc $input };

    my $flag;
    if ( $self->_flush( list => $list ) ) {
        $self->error_object->inform(
                            msg     => loc("All cached data has been flushed"),
                            quiet   => !$conf->get_conf('verbose'),
                        );
        $flag = 1;
    }

    return $flag;

}

### wrapper for CPANPLUS::Configure::get_conf ###
sub get_conf {
    my $self = shift;
    my @list = @_;

    return undef unless @list;

    my $href;
    for my $opt ( @list ) {
        $href->{$opt} = $self->configure_object->get_conf($opt);
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => \@list,
                                        rv      => $href,
                                        ok      => 1
                                    );
    return $rv;

}

### wrapper for CPANPLUS::Configure::set_conf ###
sub set_conf {
    my $self = shift;

    # is there a better way to check this without a warning?
    my %args = @_, if scalar(@_) % 2 == 0;
    return undef unless %args;

    my $href;

    my $flag = 0;
    for my $key (sort keys %args) {
        if ( $self->configure_object->set_conf( $key => $args{$key} ) ) {
            #$self->error_object->inform( msg => "$key set to $args{$key}" );
            $href->{$key} = $args{$key};
        } else {
            $self->error_object->inform( msg => loc("unknown key: %1", $key) );
            $href->{$key} = undef;
            $flag = 1;
        }
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => \%args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
}

sub details {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        modules => { required => 1, default => [], strict_type => 1 },
        force   => { default => $conf->get_conf('force') },
        verbose => { default => $conf->get_conf('verbose') },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $dslip_def = $self->_dslip_defs();
    my $modtree   = $self->module_tree();
    my $authtree  = $self->author_tree();
    my @modules   = @{$args->{modules}};

    my $result;
    my $flag = 0;

    for my $mod ( @modules ) {

        my $answer = $self->parse_module(modules => [$mod]);

        $answer->ok or ($flag=1,next);

        my $mods = $answer->rv;

        my ($name, $modobj) = each %$mods;

        my @dslip = split '', $modobj->{dslip};
        my $author = $authtree->{$modobj->{'author'}}
            or ($result->{$name} = 0, $flag=1, next);

        #### fill the result; distributions don't have a 'version'.
        my $have;
        if( my $rv = $modobj->uptodate( verbose => 0 ) ) {
            $have = $rv->{version};
        } else {
            $have = loc('None');
        }

        $result->{$name} = {
            Author              => loc("%1 (%2)", $author->{name}, $author->{email}),
            Package             => $modobj->{package},
            Description         => $modobj->{description} || loc('None given'),
        (!ref($name) and $name =~ /[^\w:]/) ? () : (
            'Version on CPAN'   => $modobj->{version}     || loc('None given'),
            'Version Installed' => $have,
        ) };

        for my $i (0 .. $#dslip) {
            $result->{$name}->{ $dslip_def->[$i]->[0] } =
                $dslip_def->[$i]->[1]->{ $dslip[$i] } || loc('Unknown');
        }
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $result,
                                        ok      => !$flag,
                                    );
    return $rv;
}

### looks for all distributions by a given author ###
sub distributions {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        authors => { required => 1, default => [], strict_type => 1 },
        force   => { default => $conf->get_conf('force') },
        verbose => { default => $conf->get_conf('verbose') },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my @authors = map { "(?i:$_)" } @{$args->{authors}};

    my $list = $self->_query_author_tree( list => \@authors, authors_only => 1 );

    my $href;
    my $flag = 0;
    for my $auth ( sort keys %$list ) {
        my $rv = $self->_distributions( author => '^'.$auth.'$' );

        unless ( $rv ) {
            $err->trap( error => loc("Could not find distributions for %1", $auth));
            $href->{ $auth } = 0;
            $flag = 1;
        } else {
            $href->{ $auth } = $rv;
        }
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
}

### looks up all the modules by a given author ###
sub modules {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        authors         => { required => 1, default => [], strict_type => 1 },
        authors_only    => { default => 0 },
        force           => { default => $conf->get_conf('force') },
        verbose         => { default => $conf->get_conf('verbose') },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $href;
    for my $auth ( @{$args->{authors}} ) {

        my $result = $self->search(
            type         => 'author',
            list         => ['^'.$auth.'$'],

            ### are we really supposed to be taking this argument here? ###
            authors_only => $args->{authors_only},
            data         => $args->{data},
        );

        for my $key ( sort keys %$result ) {
            $href->{$auth}->{$key} = $self->module_tree->{$key};
        }
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => 1,
                                    );
    return $rv;
}


### fetches the readme file ###
sub readme {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        modules => { required => 1, default => [], strict_type => 1},
        force   => { default => $conf->get_conf('force') },
        verbose => { default => $conf->get_conf('verbose') },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $force = $args->{'force'};

    my $href;
    my $flag = 0;

    for my $mod ( @{$args->{'modules'}} ) {
        my $answer = $self->parse_module(modules => [$mod]);

        $answer->ok or ($flag=1,next);

        my $mods = $answer->rv;

        my ($name, $modobj) = each %$mods;

        ### will either return a filename, or '0' for now
        my $rv = $self->_readme(
            module => $modobj,
            force  => $force,
        );

        unless ($rv) {
            $err->trap( error => loc("fetching readme for %1 failed!", $name) );
            $href->{ $name } = 0;
            $flag = 1;
        } else {
            $modobj->status->readme( $rv );

            $href->{ $name } = $modobj->status->readme;
        }
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
}

### displays the CPAN test result of given distributions; a wrapper for Report.pm
sub reports {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        modules         => { required => 1, default => [], strict_type => 1 },
        all_versions    => { default => 0 },
        force           => { default => $conf->get_conf('force') },
        verbose         => { default => $conf->get_conf('verbose') },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $href;
    my $flag = 0;

    foreach my $mod (@{$args->{modules}}) {
        my ($name, $modobj) = $self->_parse_module( mod => $mod );

        if (my $dist = $modobj->{package}) {
            $href->{$name} = $self->_query_report(
                package      => $dist,
                all_versions => $args->{all_versions},
            ) or ($flag=1,next);

        }
        else {
            $err->trap( error => loc("Cannot find distribution for %1, skipping", $mod) );
        }
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
}

### method to reload and optionally refetch the index files ###
sub reload_indices {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $_data = {
        update_source   => { required => 1, default => 0 },
        force           => { default => $conf->get_conf('force') },
        verbose         => { default => $conf->get_conf('verbose') },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    ### this forcibly refetches the source files if 'update_source' is true
    ### if false, it checks whether they are still up to date (as compared to
    ### the TTL in Config.pm -kane
    my $uptodate = $self->_check_trees(update_source => $args->{update_source} );

    unless($uptodate) {   ### uptodate => 0 means they'll have to be rebuilt ###
        my $rv = $self->_build_trees( uptodate => 0 );

        unless ($rv) {
            $err->trap( error => loc("Error rebuilding trees!") );
            return undef;
        }
    }

    return 1;
}

### canonizes a modobj, modname or distname into its pathname.
sub pathname {
    my $self = shift;
    my %hash = @_;
    my $err  = $self->error_object;

    my $_data = {
        to   => { required => 1, default => '' },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    ### only takes one argument, so raise exception if it's an arrayref
    my $to = $args->{to};
    if (ref($to) eq 'ARRAY') {
        $err->trap( error => loc("Array reference passed, but 'to' only takes one argument.") );
        return undef;
    }

    my $rv = $self->parse_module(modules => [$to]);

    $rv->ok or return undef;

    my $mods = $rv->rv;

    my ($name, $modobj) = each %$mods;

    ### have to explicitly check for File::Spec::Unix since it won't be
    ### already use'd on non-nix platforms
    return undef unless $self->_can_use(
        modules => { 'File::Spec::Unix' => '0.0' },
    );

    return File::Spec::Unix->catdir('', $modobj->{path}, $modobj->{package});
}

sub parse_module {
    my $self = shift;
    my %hash = @_;
    my $err  = $self->error_object;

    my $_data = {
        modules => { required => 1, default => [] },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $href;
    my $flag = 0;

    for my $mod ( @{$args->{modules}} ) {

        my ($name, $modobj) = $self->_parse_module( mod => $mod );

        if ($name) {
            $href->{$name} = $modobj;
        } else {
            $flag = 1;
        }
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                        object  => $self,
                                        type    => $self->_whoami(),
                                        args    => $args,
                                        rv      => $href,
                                        ok      => !$flag,
                                    );
    return $rv;
}

sub dist {
    my $self = shift;
    my $err = $self->error_object;
    my %hash = @_;

    my $_data = {
        modules         => { required => 1, default => [], strict_type => 1 },
        format          => { required => 1, allow => qr/^(?:MakeMaker|PPM|Ports|PAR|Build|RPM|Deb)$/i }, # add new ones here
        make            => { default => undef },
        perl            => { default => undef },
        makeflags       => { default => undef },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash ) or return undef;
    $self->_can_use( modules => { 'CPANPLUS::Dist' => '0.0' } ) or return undef;

    my $href;
    my $flag = 0;

    for my $mod ( @{$args->{modules}} ) {

        my $answer = $self->parse_module(modules => [$mod]);

        $answer->ok or ($flag=1,next);

        my $mods = $answer->rv;

        my ($name, $modobj) = each %$mods;

        my $dist;
        unless( $dist = CPANPLUS::Dist->new(
                                    format  => $args->{format},
                                    module  => $modobj,
        ) ) {
            $err->trap( error => loc(qq[Could not create Dist::%1 object for %2], $args->{format}, $name) );
            $flag = 1;
            next;
        }

        ### undef is a valid value too, so make sure to send options only
        ### if they are defined
        my %opts = map {
                        $_ => $args->{$_}
                    } grep { defined $args->{$_} } qw[make makeflags perl];

        my $created = $dist->create( %opts );

        $flag = 1 unless values %$created;

        my $format = 'dist_' . lc $args->{format};
        $href->{$name} = $modobj->status->$format( $dist );
    }

    ### create a rv object ###
    my $rv = CPANPLUS::Backend::RV->new(
                                    object  => $self,
                                    type    => $self->_whoami(),
                                    args    => $args,
                                    rv      => $href,
                                    ok      => !$flag,
                                );
    return $rv;
}

### creates a local mirror of cpan with only the latest distributions
sub local_mirror {
    my $self = shift;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;
    my %hash = @_;

    my $_data = {
        path            => { default => $conf->_get_build('base') },
        force           => { default => $conf->get_conf('force') },
        verbose         => { default => $conf->get_conf('verbose') },
        no_index_files  => { default => 0 },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    $args->{path} = File::Spec->catdir( $args->{path}, $conf->_get_ftp('base') );

    my $quiet = !$args->{'verbose'};

    unless( -d $args->{path} ) {
        unless( $self->_mkdir( dir => $args->{path} ) ) {
            $err->trap(
                    error   => loc(qq[Could not create '%1', giving up], $args->{path}),
                    quiet   => $quiet,
            );
            return undef;
        }
    } elsif( ! -w _ ) {
        $err->trap(
                error   => loc(qq[Could not write to '%1', giving up], $args->{path}),
                quiet   => $quiet,
        );
        return undef;
    }

    my $rv = {};
    my $flag = 0;

    my $uptodate = $self->_check_trees(
        path            => $args->{path},
        verbose         => $args->{verbose},
        update_source   => $args->{force},
    );
    $self->_build_trees(uptodate => $uptodate);

    for my $auth ( sort { $a->cpanid cmp $b->cpanid } values %{$self->author_tree} ) {

        $err->inform(
                msg     => loc(qq[Updating packages for '%1'], $auth->cpanid),
                quiet   => $quiet,
        );

        my @mods = sort values %{ $auth->modules || {} };

        ### take care of fetching the checkums file first ###
        if(@mods) {

            ### some code duplication here, should clean up later ###
            {
                my $obj = $mods[0];

                my $path = File::Spec->catdir($args->{path}, $obj->path);

                unless( -d $path ) {
                    unless( $self->_mkdir( dir => $path ) ) {
                        $err->trap(
                                error => loc(qq[Could not create '%1'], $path),
                                quiet => $quiet,
                        );
                        $flag = 1;
                        next;
                    }
                }

                unless( $self->_get_checksums( mod => $obj, fetchdir => $path ) ) {
                    $err->trap(
                            error => loc( qq[Could not fetch %1 file for %2],
                                        'CHECKSUMS' . $auth->cpanid ),
                            quiet => $quiet,
                    );
                    $flag = 1;
                    next;
                }
            }

            my %packages;
            $packages{$_->package} = $_ for @mods;
            for my $mod (map $packages{$_}, sort keys %packages) {
                my $path = File::Spec->catdir($args->{path}, $mod->path);

                my $full = File::Spec->catfile( $path, $mod->package );

                if( -e $full ) {
                    $err->inform(
                            msg     => loc( q[package '%1' already up to date, skipping],
                                            $mod->package ),
                            quiet   => $quiet,
                    );
                    $rv->{ $mod->package } = $full;
                    next;
                }

                unless( -d $path ) {
                    unless( $self->_mkdir( dir => $path ) ) {
                        $err->trap(
                                error => loc(qq[Could not create '%1'], $path),
                                quiet => $quiet,
                        );
                        $flag = 1;
                        next;
                    }
                }

                unless( $mod->fetch( fetchdir => $path ) ) {
                    $err->trap(
                            error => loc(qq[Could not fetch '%1'], $mod->package),
                            quiet => $quiet,
                    );
                    $flag = 1;
                    next;
                } else {
                    $rv->{ $mod->package } = $full;
                }
            }
        }
    }

    ### create a rv object ###
    return CPANPLUS::Backend::RV->new(
                                    object  => $self,
                                    type    => $self->_whoami(),
                                    args    => $args,
                                    rv      => $rv,
                                    ok      => !$flag,
                                );
}



### doesn't allow you to write your own filenames right now..
### too much hassle splitting directories, finding the proper
### file, printing out whether it can be installed with just the
### filename or needing the full path, etc...
sub autobundle {
    my $self = shift;
    my %hash; # = @_;

    my $err  = $self->error_object;
    my $conf = $self->configure_object;

    ### default directory for the bundle ###
    my $dir = File::Spec->catdir(
                $conf->_get_build('base'),
                $self->_perl_version( perl => $^X ),
                $conf->_get_build(qw|distdir autobundle|),
            );

    ### default filename for the bundle ###
    my($year,$month,$day) = (localtime)[5,4,3];
    $year += 1900; $month++; my($ext) = 0;

    my $prefix = $conf->_get_build('autobundle_prefix');
    my $format = "${prefix}_%04d_%02d_%02d_%02d";

    my $name        = sprintf( $format, $year, $month, $day, $ext);
    my $filename    = $name . '.pm';

    my $_data = {
        file    => { default => $filename },
        dir     => { default => $dir },
        force   => { default => 0 },
    };

    ### Input Check ###
    my $args = check( $_data, \%hash );
    return undef unless $args;

    my $flag;

    unless( -d $args->{dir} ) {
        unless( $self->_mkdir( dir => $args->{dir} ) ) {
            $err->trap( error => loc( qq[Could not create directory '%1'], $args->{dir} ) );
            $flag = 1;
        }
    }

    my $path;
    my $force = $args->{force} || $conf->get_conf('force');

    BLOCK: {
    unless( $flag ) {
        $path = File::Spec->catfile($args->{dir}, $args->{file});

        while (-f $path) {

            #if( $hash{file} && !$force) {
            #    $err->trap( error => loc( qq[File already exists: %1. Will not overwrite unless you force], $path ));
            #    $flag = 1;
            #    last BLOCK;
            #
            #} else {
                $name           = sprintf($format, $year, $month, $day, ++$ext);
                $args->{file}   = $name . '.pm';
                $path           = File::Spec->catfile($dir,$args->{file});
            #}
        }

        my $FH;
        unless( open $FH, ">$path" ) {
            $err->trap( error => loc( qq[Could not open %1 for writing: %2\n], $path, %! ));
            $flag = 1;
            last BLOCK;
        }


        #my $string;
        #for my $mod ( sort keys %{$self->installed->rv} ) {
        #    my $version = $mod->version || 'undef';
        #    $string .= qq[$mod $version\n\n];
        #}

        my $string = join "\n\n",
                        map {
                            my $modobj = $self->module_tree->{$_};
                            qq[$_ ] . ($modobj->uptodate->{version} || 'undef')
                        } sort keys %{$self->installed->rv};

        my $now     = scalar localtime;
        my $head    = '=head1';
        my $pkg     = __PACKAGE__;
        my $version = $self->VERSION;
        my $perl_v  = join '', `$^X -V`;

        print $FH <<EOF;
package $name;

\$VERSION = '0.01';

1;

__END__

$head NAME

$name - Snapshot of your installation at $now

$head SYNOPSIS

perl -MCPANPLUS -e "install $name"

$head CONTENTS

$string

$head CONFIGURATION

$perl_v

$head AUTHOR

This bundle has been generated autotomatically by
    $pkg $version

EOF

    close $FH;
    } } ### end unless, end BLOCK

    ### create a rv object ###
    return CPANPLUS::Backend::RV->new(
                                    object  => $self,
                                    type    => $self->_whoami(),
                                    args    => $args,
                                    rv      => $path,
                                    ok      => !$flag,
                                );
}


1;

__END__

=pod

=head1 NAME

CPANPLUS::Backend - Object-oriented interface for CPAN++

=head1 SYNOPSIS

    use CPANPLUS::Backend;

    my $cp = new CPANPLUS::Backend;


    ##### Methods which return trees of objects #####

    my $module_obj  = $cp->module_tree()->{'Dir::Purge'};
    my $all_authors = $cp->author_tree();


    ##### Methods which return objects #####

    my $err  = $cp->error_object();
    my $conf = $cp->configure_object();

    ### Methods returning RV objects

    my $mod_search = $cp->search(type => 'module',
                                 list => ['xml', '^dbix?']);

    my $auth_search = $cp->search(type         => 'author',
                                  list         => ['(?i:mi)'],
                                  data         => $search,
                                  authors_only => 1);

    $cp->flush('modules');

    my $bundle = $cp->autobundle();

    my $extract = $cp->extract(files => [$fetch_result->{B::Tree},
                                         '/tmp/POE-0.17.tar.gz']);

    my $make = $cp->make(dirs   => ['/home/munchkin/Data-Denter-0.13']
                         target => 'skiptest');


    my $installed = $cp->installed();

    my $validated = $cp->validate(modules => ['Rcs', $module_obj]);


    ### Backend methods with corresponding Module methods

    ##
    # Backend method
    my $fetch_result = $cp->fetch(modules  => ['Dir::Purge'])
    my $rv = $fetch_result->rv();

    # Module method
    # The value of $rv->{'Dir::Purge'} is returned by the module method
    my $module = $cp->module_tree()->{'Dir::Purge'};
    $module->fetch();
    ##


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

    ## The same result via Backend, Module and Author methods
    my $mods_by_same_auth = $cp->modules(authors => ['JV']);
    my $result = $mods_by_same_auth->rv();

    my $dt = $cp->module_tree()->{'Debug::Trace'};
    $$result{'JV'} = $dt->modules();

    $$result{'JV'} = $all_authors->{'JV'}->modules();
    ##

    # Backend method
    my $dists_by_same_auth = $cp->distributions(authors => ['KANE']);


    ##### Methods with other return values #####

    ### Backend and Module methods

    # Backend method
    my $path = $cp->pathname(to => 'C::Scan');
    my $reload = $cp->reload_indices(update_source => 1);

    ### Module methods
    my $result = $module_obj->extract();


=head1 DESCRIPTION

CPANPLUS::Backend is the OO interface to CPAN.
It is designed to be used by other programs, such as custom
install scripts or tailored shells.

See CPANPLUS::Shell::Default if you are looking for a ready-made interactive
interface.

If you prefer to use a package manager to manage distributions,
refer to CPANPLUS::Dist.

The CPANPLUS::Backend interface will become stable with the release
of CPANPLUS version 1.0.

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

In general the return values of these methods will be a
I<CPANPLUS::Backend::RV> object.  If the RV object cannot
be created, I<undef> will be returned.  Versions before 0.04
returned hash references.

A synopsis of the result can be obtained by using the RV method
C<ok>, which will return a boolean value indicating success or failure.
For instance:

    my $err = $cp->error_object();

    ...

    my $result = $cp->some_backend_function(modules => ['Acme::Comment']);
    print 'Error: '.$err->stack() unless $result->ok();

In boolean context, the RV object returns the value of C<ok>, so the
last line could actually be written like this:

    print 'Error: '.$err->stack() unless ($result);

If you want to examine the results in more detail, please refer
to L<CPANPLUS::Backend::RV> for descriptions of the other methods available.

=head2 new(CONFIGURATION)

This creates and returns a backend object.

Arguments may be provided to override CPAN++ settings.

Provide either a single CPANPLUS::Configure object:

    my $backend = new CPANPLUS::Backend($config);

or use the following syntax:

    my $backend = new CPANPLUS::Backend(conf => {debug => 0,
                                                 verbose => 1});

Refer to L<CPANPLUS::Configure> for a list of available options.

=head2 error_object()

This function returns a CPANPLUS::Error object which maintains errors
and warnings for this backend session.

Be aware that you should flush the error and warning caches for long-running
programs.

See L<CPANPLUS::Error> for details on using the error object.

=head2 configure_object()

This function returns a CPANPLUS::Configure object for the current
invocation of Backend.

See L<CPANPLUS::Configure> for available methods and note that you
modify this object at your own risk.

=head2 module_tree()

This method will return a hash reference where each key in the
hash is a module name and the values are module objects.

Refer to L<"MODULE OBJECTS"> for more information on using
module objects.

=head2 author_tree()

This function returns a hash reference with all authors.  Each key
corresponds to a CPAN identification.  The values are author
objects.

Refer to L<"AUTHOR OBJECTS"> for more information on using
author objects.

=head2 search(type => TYPE, list => [LIST], [data => PREVIOUS_RESULT], [authors_only => BOOL])

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

=head2 details(modules => [LIST])

See L<"GENERAL NOTES"> for more information about methods with
I<modules> arguments.

Values for the I<rv> section of the RV object are 0 for unavailable
modules.  Available modules have hash references with the following
keys:

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

=head2 readme(modules => [LIST])

See L<"GENERAL NOTES"> for more information about methods with
I<modules> arguments.

The C<rv()> values this method returns are the contents of
the readme files, or 0 for errors.

=head2 install(modules => [LIST], format => PM, make => PROGRAM, makeflags => FLAGS, makemakerflags => FLAGS, perl => PERL, force => BOOL, fetchdir => DIRECTORY, extractdir => DIRECTORY, target => STRING, prereq_target => STRING, skiptest => BOOL)

See L<"GENERAL NOTES"> for more information about methods with
I<modules> arguments.

Install is a shortcut for performing C<fetch>, C<extract> and C<make>
on the specified modules.  If a full filename is supplied, it will be
treated as an autobundle.

Optional arguments can be used to override configuration information.

=over 4

=item * C<format> 

Run install with the format of the given package manager. This is 
handy when you're, for example, on windows and like your perl package
management done by C<PPM>. Entering a format will make C<CPANPLUS>
build a package conforming to that package managers specifications 
and install it as such.

See L<CPANPLUS::Dist> for details on what package managers have 
interfaces ot them available.

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

The path of the perl to use.
This will default to $^X (ie. the perl used to start the script).

=item * C<force>

Force downloads even if files of the same name exist and
force installation even if tests fail by setting force to
a true value.  It will also force installation even if the
module is up-to-date.

=item * C<fetchdir>

The directory fetched files should be stored in.  By default
it will store in your cpanplus home directory.  If called
from the command line (as in C<perl -MCPANPLUS -e'fetch POE'>),
it will default to the current working directory.

=item * C<extractdir>

The directory files will be extracted into.  For example, if you
provide C</tmp> as an argument and the file being extracted is
C<POE-0.17.tar.gz>, the extracted files will be in C</tmp/POE-0.17>.

=item * C<target>

The objective of this attempt.  It can be one of C<makefile>, C<make>,
C<test>, or C<install> (the default).  Each target implies all the
preceding ones.

=item * C<skiptest>

If this flag is set to true, tests will be skipped.

=item * C<prereq_target>

This argument is the objective when making prerequisite modules.
It takes the same range of values as C<target> and also defaults
to C<install>.  Usually C<install> is the correct value, or the
parent module won't make properly.

If the prerequisite target is set to test, prerequisites won't be
installed, but their build directory will be added to the PERL5LIB
environment variable, so it will be in the path.  This option is
useful when building distributions.

=back

Note that a failure in C<ok()> does not identify the source of the problem,
which could be caused by a dependency rather than the named module.
It also does not indicate in what stage of the installation procedure
the failure occurred.  For more detailed information it is
necessary to examine the RV and/or error objects.

=head2 fetch(modules => [LIST], force => BOOL, fetchdir => DIRECTORY)

This function will retrieve the distributions that contains the modules
specified with the C<modules> argument.
Refer to L<"GENERAL NOTES"> for more information about methods with
I<modules> arguments.

The remaining arguments are optional.  A true value for force means
that pre-existing files will be overwritten.  Fetchdir behaves like
the C<install> argument of the same name.

The return value for C<rv()> will be a hash reference for each
module; values are either the fully qualified path plus the file
name of the saved module, or, in the case of failure, 0.

Here is an example of a successful return value:

    'C:\\temp\\Acme-POE-Knee-1.10.zip'

=head2 extract(files => [FILES], extractdir => DIRECTORY)

Given the full local path and file name of a module, this function
will extract it.

Successful C<rv()> values will be the directory the file was
extracted to.

Extractdir is optional and behaves like the C<install> argument
of the same name.

=head2 make(dirs => [DIRECTORIES], force => BOOL, makeflags => FLAGS, makemakerflags => FLAGS, perl => PERL, target => string, prereq_target => STRING)

This function will attempt to install the module in the specified
directory with C<perl Makefile.PL>, C<make>, C<make test>, and
C<make install>.

Optional arguments are described fully in C<install>.

Below is an example of the data structure returned by C<rv()>:

    {
        'D:\\cpanplus\\5.6.0\\build\\Acme-Bleach-1.12' => {
            'install' => 1,
            'dir' => 'D:\\cpanplus\\5.6.0\\build\\Acme-Bleach-1.12',
            'prereq' => {},
            'overall' => 1,
            'test' => 1
    }


=head2 uninstall(modules => [LIST], type => TYPE)

This function uninstalls the modules specified.  There are
three possible arguments for type: I<prog>, I<man> and I<all>
which specify what files should be uninstalled: program files,
man pages, or both.  The default type is I<all>.

C<rv()> gives boolean indications of status for each module name key.

Note that C<uninstall> only uninstalls the module you ask for --
It does not track prerequisites for you, nor will it warn you if 
you uninstall a module another module depends on!

See L<"GENERAL NOTES"> for more information about this method.

=head2 files(modules => [LIST])

This function lists all files belonging to a module if the module is
installed.  See L<"GENERAL NOTES"> for more information about this
method.

The module's C<rv()> value will be 0 if the module is not installed.
Otherwise, it will be an array reference of files as shown below:

    [
        'C:\\Perl\\site\\lib\\Acme\\POE\\demo_race.pl',
        'C:\\Perl\\site\\lib\\Acme\\POE\\Knee.pm',
        'C:\\Perl\\site\\lib\\Acme\\POE\\demo_simple.pl'
    ];

=head2 distributions(authors => [CPAN_ID [CPAN_ID]])

This provides a list of all distributions by the author of the
module (given in the form of the CPAN author identification).
This information is provided by the CHECKSUMS file in the authors
directory.

Here is a cropped example of the CPAN author id 'KANE':

    ...
    'rv' => {
        'KANE' => {
            'CPANPLUS-0.033.tar.gz' => {
                'md5-ungz' => 'ccf827622d95479d6c02aa2f851468f2',
                'mtime' => '2002-04-30',
                'shortname' => 'cpan0033.tgz',
                'md5' => 'ce911062b432dcbf93a19a0f1ec87bbc',
                'size' => '192376'
            },
            'Acme-POE-Knee-1.01.zip' => {
                'mtime' => '2001-08-14',
                'shortname' => 'acmep101.zip',
                'md5' => '4ba5db4c515397ec1b841f7474c8f406',
                'size' => '14246'
            },
            'Acme-Comment-1.00.tar.gz' => {
                'md5-ungz' => '166b8df707a22180a46c9042bd0deef8',
                'mtime' => '2002-05-12',
                'shortname' => 'acmec100.tgz',
                'md5' => 'dec0c064ba3055042fecffc5e0add648',
                'size' => '6272'
            },
        }
    }

=head2 modules(authors => [CPAN_ID [CPAN_ID]])

Given a CPAN author identification, this function will return
modules by the author specified as an RV object.

=head2 reports(modules => [LIST], all_versions => BOOL)

This function queries the CPAN tester database at
I<http://testers.cpan.org/> for test results of specified module objects,
module names or distributions.

The optional argument C<all_versions> controls whether all versions of
a given distribution should be grabbed.  It defaults to false
(fetching only reports for the current version).

See L<"GENERAL NOTES"> for more information about this method.

The C<rv()> function will give the following data structure:

    'Devel::Size' => [
        {
            'dist' => 'Devel-Size-0.54',
            'grade' => 'PASS',
            'platform' => 'linux 2.2.16c32_iii i586-linux'
        },
        {
            'dist' => 'Devel-Size-0.54',
            'grade' => 'PASS',
            'platform' => 'linux 2.4.16-6mdksmp i386-linux'
        },
        {
            'dist' => 'Devel-Size-0.54',
            'grade' => 'PASS',
            'platform' => 'solaris 2.7 sun4-solaris'
        },
        {
            'dist' => 'Devel-Size-0.54',
            'grade' => 'PASS',
            'platform' => 'solaris 2.8 sun4-solaris'
        }
    ]

The status of the test can be one of the following:
UNKNOWN, PASS, FAIL or NA (not applicable).

=head2 uptodate(modules => [LIST])

This function can be used to see if your installation of a
specified module is up-to-date.
See L<"GENERAL NOTES"> for more information about this method.

Values for the module from C<rv()> may be undef if the module
is not installed, or a hash reference.  The hash reference
contains the following keys:
I<uptodate>, I<version> and
I<file>.

The version is your currently installed version.
The file is where the module is installed on your system.
Uptodate is 1 if your version is equal to or higher than the
most recent version found on the CPAN, and 0 if it is not.

For example, assuming you have I<Acme::POE::Knee> but not I<XML::Twig>
installed, and provide the argument C<['Acme::POE::Knee', 'XML::Twig']>
the following data structure might be returned:

    {
        'XML::Twig' => undef,
        'Acme::POE::Knee' => {
            'version'  => '1.10',
            'file'     => 'C:\\Perl\\site\\lib\\Acme\\POE\\Knee.pm',
            'uptodate' => 1
        }
    }


=head2 validate(modules => [LIST])

See L<"GENERAL NOTES"> for information about the I<modules> argument
or the keys of the returned hash reference.

The C<rv()> module values will be either
an empty array reference (if no files are missing), an array reference
containing the missing files, or 0 if there was an error (such as
the module in question is not installed).

It is probably best to use the results of the C<installed>
method because not all modules have proper names.  For
instance, 'LWP' is installed as 'Libwww'.

=head2 installed()

This function returns all modules currently installed on
your system.

See L<"GENERAL NOTES"> for more information about this method.

Values of modules returned by C<rv()> will be the location
of the module.

For example, the following code:

    my $rv = $cp->installed();
    print Dumper $rv->rv();

might give something like the following (example cropped):

    $VAR1 = {
        ...
        'URI::telnet' => '/usr/local/lib/perl5/site_perl/5.005/URI/telnet.pm'
        'Tie::Array' => '/usr/local/lib/perl5/5.6.1/Tie/Array.pm',
        'URI::file' => '/usr/local/lib/perl5/site_perl/5.005/URI/file.pm',
        ...
    }

If there was an ambiguity in finding the object, the value
will be 0.  An example of an ambiguous module is LWP, which
is in the packlist as 'libwww-perl', along with many other
modules.

=head2 local_mirror( path => WHERE, [no_index_files => BOOL, force => BOOL, verbose => BOOL] )

Creates a local mirror of CPAN, of only the most recent sources in a
location you specify. If you set this location equal to a custom host
in your C<CPANPLUS::Config> you can use your local mirror to install 
from.

It takes the following argument:

=over 4

=item path

The location where to create the local mirror

=item no_index_files

Disable fetching of index files. This is ok if you don't plan to use
the local mirror as your primary sites, or if you'd like uptodate 
index files be fetched from elsewhere.

Defaults to false.

=item force

Forces refetching of packages, even if they are there already.

Defaults to whatever setting you have in your C<CPANPLUS::Config>.

=item verbose

Prints more messages about what it's doing.

Defaults to whatever setting you have in your C<CPANPLUS::Config>.

=back

=head2 flush(CACHE_NAME)

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

=item * C<lib>

This resets PERL5LIB which is changed to ensure that while installing
modules they are in our @INC.

=item * C<all>

Flush all of the aforementioned caches.

=back

=head2 reload_indices([update_source => BOOL])

This method refetches and reloads index files.  It accepts
one optional argument.  If the value of C<update_source> is
true, CPANPLUS will download new source files regardless.
Otherwise, if your current source files are up-to-date
according to your config, it will not fetch them.

=head2 autobundle()

This method autobundles your current installation as
I<$cpanhome/$version/dist/autobundle/Snapshot_xxxx_xx_xx_xx.pm>.
For example, it might create:

    D:\cpanplus\5.6.0\dist\autobundle\Snapshot_2002_11_03_03.pm

=head2 pathname(to => MODULE)

This function returns the path, from the CPAN author id, of
the distribution when C<rv()> is used.  0 is used for failure.

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

Module methods return a subsection of what Backend methods
return.  The value of the module name key in the I<rv> portion
of the RV object is returned.  For example,
C<$cp-E<gt>uptodate(modules =E<gt> ['Devel::Size']);>
might return:

    bless( {
        'args' => {
            'modules' => [
                'Devel::Size'
            ]
        },
        'rv' => {
            'Devel::Size' => {
                'version' => '0.54',
                'file' => '/usr/local/lib/perl5/site_perl/5.6.1/i386-freebsd/Dev
el/Size.pm',
                'uptodate' => 1
             }
         },
         '_id' => 1,
             'type' => 'CPANPLUS::Backend::uptodate',
             'ok' => '1'
         }, 'CPANPLUS::Backend::RV' );

but when called as the Module method C<$ds-E<gt>uptodate();> just
the following will be returned:

    {
        'version' => '0.54',
        'file' => '/usr/local/lib/perl5/site_perl/5.6.1/i386-freebsd/Devel/Size.pm',
        'uptodate' => 1
    };

Refer to the Backend methods to determine what type of data structure
will be returned for the Module method of the same name.

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

=item * C<$module_object-E<gt>extract()>

In order to use this method, you must have first used I<fetch()>.

=item * C<$module_object-E<gt>pathname()>

This method is an exception to the rule in that the module object
does not replace the I<modules> argument but the I<to> argument.

=item * C<$module_object-E<gt>modules()>

This method is another exception in that the module object replaces
the I<authors> argument instead of the I<modules> argument.

=item * C<$module_object-E<gt>status()>

This method returns an C<CPANPLUS::Internals::Module::Status> object,
which provides methods to tell you about the current status of the 
module object. For example, where it has been saved to, what prereqs
it has and so on.

Please refer to the L<CPANPLUS::Internals::Module::Status> manpage
for details.

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
        'status' => bless( {}, 'CPANPLUS::Internals::Module::Status' ),
        'prereqs' => {},
        'module' => 'Acme::Buffy',
        'comment' => '',
        'author' => 'LBROCARD',
        '_id' => 6,
        'package' => 'Acme-Buffy-1.2.tar.gz',
        'version' => '1.3'
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

Currently not in use, but this information is included in
the return value for C<make()> and C<install()>

=item * C<status>

Internal storage for module status.

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
return the value of C<$rv{rv}{'Name'}> where 'Name' corresponds
to the name of the author (or module, in the case of the
Module methods) and $rv is a return value object.

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
L<CPANPLUS::Backend::RV>, L<CPANPLUS::Dist>,
L<ExtUtils::MakeMaker>, L<CPANPLUS::Internals::Module>, L<perlre>
http://testers.cpan.org

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
