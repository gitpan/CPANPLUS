# $File: //depot/cpanplus/dist/lib/CPANPLUS/Internals/Make.pm $
# $Revision: #15 $ $Change: 9265 $ $DateTime: 2003/12/11 20:21:43 $

#######################################################
###             CPANPLUS/Internals/Make.pm          ###
###  Subclass to make/install modules for cpanplus  ###
###         Written 23-02-2002 by Jos Boumans       ###
#######################################################

### Make.pm ###

package CPANPLUS::Internals::Make;

use strict;
use Data::Dumper;
use File::Spec;
use FileHandle;
use Config;
use Cwd;
use CPANPLUS::I18N;
use CPANPLUS::Tools::Check qw[check];


BEGIN {
    use vars        qw( $VERSION );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

sub _make {
    my $self    = shift;
    my %hash    = @_;
    my $conf    = $self->configure_object;
    my $err     = $self->error_object;
    my $modtree = $self->_module_tree;

    my $tmpl = {
        dir             => { required => 1, allow => sub { -d pop() } },
        module          => { default => '' },
        target          => { default => 'install'. allow => [qw|makefile make test dist|] },
        prereq_target   => { default => $conf->get_conf('prereqs') == 3 ? 'test': 'install' },
        perl            => { default => $^X },
        force           => { default => $conf->get_conf('force') },
        verbose         => { default => $conf->get_conf('verbose') },
        make            => { default => $conf->_get_build('make') },
        cpantest        => { default => $conf->get_conf('cpantest') },
        makemakerflags  => { default => $conf->get_conf('makemakerflags') },
        makeflags       => { default => $conf->get_conf('makeflags') },
        format          => { default => $conf->get_conf('format') },
        skiptest        => { default => $conf->get_conf('skiptest') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    ### yes, this is an evil hack.. make can either handle module objects or directories
    ### but since it also stores some data back INTO the object it got, we have to hashify
    ### the dir argument at *least*. So blessing it into Internals::Module is the easiest thing
    ### to do right now. Note we can't call it properly OO, since we are missing a lot of the
    ### required parameters. This data construct is ONLY to be used in _make()!!! -kane
    ### we have to store it in %args as well, since we unshift that in our make-queue later on
    ### if there are unsatisfied dependencies

    ### perhaps we shouldn't store the version of perl in config, but just use the one
    ### we were invoked with ($^X) unless the user specifies one specifically...
    ### i think that would make a few users happier -kane

    ### XXX dir == $modobj->extract.. perhaps we should not keep this data twice!
    my $dir             = $args->{dir};
    my $target          = lc $args->{'target'};
    my $prereq_target   = lc $args->{'prereq_target'};
    my $perl            = $args->{perl};
    my $force           = $args->{force};
    my $verbose         = $args->{verbose};
    my $make            = $args->{make};
    my $report          = $args->{cpantest};
    my $mmflags         = $args->{makemakerflags};
    my $makeflags       = $args->{makeflags};
    my $format          = $args->{format};
    my $skiptest        = $args->{skiptest};
    my $data            = $args->{'module'} ||
                            bless { module => $dir, _id => $self->{_id} },
                                "CPANPLUS::Internals::Module";

    my $captured; # capture buffer of _run

    ### if the prereq_target, which might be this modules target, is
    ### not 'install', then this function will go in an infinite loop:
    ### it will try to install the prereq needed, find that it may only
    ### go upto say, test and then return 1. the original module still won't
    ### find the prereq in @INC and it will keep on going. That's why we have
    ### to add it to @INC manually in a few special cases

    ### prereqs == 3 is a new setting that says 'build them for testing purposes
    ### but dont install them. Tricky setting, definately experimental

    if( ($target ne 'install') or ($conf->get_conf('prereqs') == 3) ) {
        my $lib     = File::Spec->catfile($dir,'blib', 'lib');
        my $arch    = File::Spec->catfile($dir,'blib', 'arch');

        my $p_lib = quotemeta $lib;
        my $p_arch = quotemeta $arch;

        unless( grep /^$p_lib/i, @INC )  { push @INC, $lib }
        unless( grep /^$p_arch$/i, @INC ) { push @INC, $arch }

        {   local $^W;      ### it will be complaining if $ENV{PERL5LIB]
                            ### is not defined (yet).
            my %p5lib = map { $_ => 1 } split $Config{path_sep}, $ENV{PERL5LIB};

            my @add;
            unless( $p5lib{$lib} )  { push @add, $lib }
            unless( $p5lib{$arch} ) { push @add, $arch }

            $ENV{PERL5LIB} = join(
                $Config{path_sep},
                split($Config{path_sep}, $ENV{PERL5LIB}),
                @add
            );
        }
    }

    ### mark the extraction dir in the module object ###
    $data->status->make_dir($dir);

    ### container for recursive rv's ###
    my $return;

    ### set this flag and say 'last SCOPE' to exit the sub prematurely and have the
    ### startdir restored, as well as the proper RV returned and the proper report
    ### sent out, if the user wanted that

    my $Makefile_PL = 'Makefile.PL';
    my $Makefile = 'Makefile';
    my $Make = $make;

    my $fail;
    SCOPE: {
        unless (chdir $dir) {
            $err->trap(
                error => loc("Make couldn't chdir to %1! I am in %2 now", $dir, cwd()),
            );
            $fail = 1;
            last SCOPE;
        }

        ### try to install the module ###

        my @makeargs = @{$self->_flags_arrayref($makeflags)};
        my $make_prereq;

        ### Here we take care of Module::Build installation ###
        if ( -e 'Build.PL' ) {
            ### prefer Makefile.PL if we don't have Module::Build ###

            my $req = { 'Module::Build' => '0.11' };
            my $have_build = $self->_can_use(
                modules  => $req,
                nocache  => 1,
                complain => 1,
            );

            if ($have_build or not -e 'Makefile.PL') {
                $make_prereq = $req unless $have_build;
                $Makefile_PL = 'Build.PL';
                $Makefile = 'Build';
                $Make = $perl;
                unshift @makeargs, $Makefile;
            }
        }

        ### 'perl Makefile.PL' ###
        ### check if the makefile.pl exists
        unless ( -e $Makefile_PL ) {
            $err->inform(
                msg     => loc("Author did not supply a %1 - Attempting to generate one", $Makefile_PL),
                quiet   => !$verbose
            );

            ### if not, we make our own, return 0 if that fails
            unless ( $self->_make_makefile( data => $data ) ) {

                ### store it if a module failed to install for some reason ###
                $self->{_todo}->{failed}->{ $data->{module} } = 1;

                $err->trap(
                    error => loc("Could not generate %1 - Aborting", $Makefile_PL)
                );

                $fail = 1;
                last SCOPE;
            }
        }

        ### we can only use open, backticks or system. and only the latter allows
        ### interactive mode. so we're screwed =/ -Kane
        ### not really; there's open3 -- see the _run() method. -autrijus

        PERL_MAKEFILE: {
            ### we can check for a 'Makefile' but that might be have produced a
            ### Makefile that CAME from a different version of perl
            ### thus screwing everything up.
            ### i suggest uncommenting this once we have a way to pass make options like 'clean'

            ### changed the dir structure so that every version of perl gets it's own
            ### build/ dir.. so it's safe to use this now -kane

            ### we must fix _extract first so it won't have to delete the dir
            ### every time =/ -kane

            ### if still missing essential make pieces, bail out here
            last PERL_MAKEFILE if $make_prereq;

            if ( -e $Makefile && (-M $Makefile < -M '.') && !$force ) {
                $err->inform( msg => loc("%1 already exists, not running 'perl %2' again, unless you force!", $Makefile, $Makefile_PL), quiet => !$verbose );
                last PERL_MAKEFILE;
            }

            my @args = @{$self->_flags_arrayref($mmflags)};

            unless( $self->_run(
                command => [$perl, $Makefile_PL, @args],
                buffer  => \$captured,
                verbose => 1,
            ) ) {
                ### store it if a module failed to install for some reason ###
                $self->{_todo}->{failed}->{ $data->{module} } = 1;

                $fail = 1;

                $err->trap( error => loc("BUILDING %1 failed! - %2", $Makefile, $!) );

                last SCOPE;
                ### failure, return overall => 0
                ### restore startdir
            }

            ### store that makefile was made successfully ###
            $data->status->makefile( 1 );

            if ($target eq 'makefile') {
                last SCOPE;

                ### succesfull, return overall => 1
                ### restore startdir
            }
        }

        ### this is where we find out what prereqs this module has,
        ### and install them accordingly.
        ### this probably needs some tidying up ###
        my $prereq = $self->_find_prereq(
                                    dir         => $dir,
                                    makefile    => $Makefile,
                                    prereq      => $make_prereq,
                                    verbose     => $verbose,
                            );
        unless ($prereq) {
            $err->trap( error => loc("Cannot determine prerequisites - Aborting") );
            $fail = 1;
            last SCOPE;
        }

        $data->status->prereq( $prereq );

        ### check if the prereq this module wants is something we already tried to install
        ### earlier this session: if so $self->{_todo}->{failed} will be 1.
        ### a succesfull install will set the above variable to 0. this way we can still
        ### check for 'defined'-ness.
        #print Dumper $self->{_todo}->{failed};

        {   my $flag;
            for my $mod (keys %$prereq) {
                if ( $self->{_todo}->{failed}->{$mod} ) {
                    $err->inform(
                        msg => loc("According to the cache, %1 failed to install before in this session.. returning!", $mod),
                        quiet => !$verbose
                    );

                    $flag = 1;
                }
            }

            if ($flag) {
                ### make sure we REMOVE this dir from the TODO list then, else we'll go into
                ### an infinite loop
                @{$self->{_todo}{make}} = grep { $_->{dir} ne $dir } @{$self->{_todo}{make}};
warn "FLAG SET! FAIL!";
                #print "dumpering _todo->make\n";
                #print Dumper $self->{_todo}->{make};

                $fail = 1;
                last SCOPE;
            }
warn "SHOULD NOT GET HERE" if $flag;           
        }

        ### if we're not allowed to follow prereqs, and there are some
        ### we return the list of prerequisites, and leave it at that.
        #print Dumper $prereq;

        ### this is gonna get messy... we need to know not only if we have a module yet or not
        ### but also whether or not we are trying to install it right now
        ### and what level of prereq we're in...
        ### i have an idea: an array ref in the object, with hashrefs in it
        ### one hashref for every time we found the prereqs, adding the hashrefs to the front
        ### of the array ref as we go.
        ### then, check the array ref for what modules are installed already
        ### yes, i know, messy... -kane

        ### we now also have module objects, so i suppose we should start storing this information
        ### THERE instead? definately a TODO!

        my $must_install;
        my %list;

        for my $mod (keys %$prereq) {

            ### we already have this module enqueued to be installed
            ### but apparently a /prereq/ also needs it
            ### this moves it up to first in the todo, without prompting
            ### the user for confirmation again


            ### check if the module (with specified version) is installed yet
            my $mod_data = $self->_check_install( module => $mod, version => $prereq->{$mod} );

            #print Dumper $mod_data;
            if ( $mod_data->{uptodate} ) {

                ### make sure we DONT install this ###
                ### $self->{_todo}->{install}->{$mod} = 0;
                $must_install->{$mod} = 0;

            } else {
                ### check if we're supposed to NOT install prereqs
                if ( (keys %list) && !$conf->get_conf('prereqs') ){
                    $err->inform(
                        msg     => loc("Prereqs are found, but not allowed to install! Returning list of prereqs"),
                        quiet   => !$verbose
                    );

                    $self->_restore_startdir;
                    return \@{[ keys %list ]};
                }

                unless ( keys(%{$modtree->{$mod}}) ) {
                    $err->trap( error => loc("No such module: %1, cannot satisfy dependency", $mod) );
                    next;
                }

                if ( grep { $_->{module}{module} eq $mod } @{$self->{_todo}{make}} ) {
                    $err->trap( error => loc("Recursive dependency detected in %1, skipping", $mod) );
                    next;
                }
                elsif ( defined $self->{_todo}->{failed}->{$mod}
                        or
                        ( defined $modtree->{$mod}->status->install
                          && $modtree->{$mod}->status->install == 1
                        )
                ) {
                    $err->inform(
                        msg => loc("According to the cache, prerequisite %1 is already installed", $mod),
                        quiet => !$verbose
                    );
                    next;
                }

                ### check if we're in shell mode, and if we should ask to follow prereqs.
                ### should probably use words rather than numbers -kane
                if ( $self->{_shell} and $conf->get_conf('prereqs') == 2 ) {
                    #$list{$mod} = 1 if $self->{_shell}->_ask_prereq( mod => $mod );

                    ### dont ask twice if we already know the answer ###
                    ### this hash is localised in Backend::install();

                    if ( defined $self->{_todo}->{prereqs}->{$mod} ) {
                        $list{$mod} = 1 if $self->{_todo}->{prereqs}->{$mod}
                    } else {
                        $list{$mod} = $self->{_todo}->{prereqs}->{$mod} =
                                $self->{_shell}->_ask_prereq( mod => $mod ) ? 1 : 0;
                    }

                } else {
                    ### must install this
                    $list{$mod} = 1;
                }

                if ( $list{$mod} ) {
                    $err->inform(
                        msg     => loc("Installing %1 to satisfy dependency", $mod),
                        quiet   => !$verbose
                    );
                }
            }
        }


        ### see if we have anything to install, if so, we'll need to exit this make, and install
        ### the prereqs first.
        if (%list) {

            ### store this dir and modname, we'll have to finish the make here later.
            unshift @{$self->{_todo}->{make}}, $args;

            ### enqueue this modules prereqs ###
            unshift @{$self->{_todo}->{install}},
                        [ map { $modtree->{$_} } grep { length } keys %list ];

            while (my $mod_ref = shift @{$self->{_todo}->{install}} ) {

                my $rv = $self->_install_module(
                    perl            => $perl,
                    modules         => $mod_ref,
                    target          => $prereq_target,
                    prereq_target   => $prereq_target,
                    force           => $force,
                    make            => $make,
                    makemakerlfags  => $mmflags,
                    makeflags       => $makeflags,
                    format          => $format,
                );

                ### add all the modules to the return value ###
                map { $return->{$_} = $rv->{$_} } keys %$rv;
            }

			### check what happened to the install we just requested
			### if not everything went ok, flag it, fail, and bail
			$fail++ && last SCOPE if grep { !$_->make_overall } values %$return;

        ### no prereqs need doing, let's go on installing ###
        } else {

            my @args = @makeargs;

            INSTALL: {

                MAKE: {
                    ### we can check for a 'blib' but that might be a run from a 'make' that was run on a
                    ### Makefile that CAME from a different version of perl
                    ### thus screwing everything up.
                    ### i suggest uncommenting this once we have a way to pass make options like 'clean'

                    ### changed the dir structure so that every version of perl gets it's own
                    ### build/ dir.. so it's safe to use this now -kane

                    ### we must fix _extract first so it won't have to delete the dir
                    ### every time =/ -kane

                    if ( -d 'blib' && (-M 'blib' < -M '.') && !$force ) {
                        $err->inform( msg => loc("Already ran 'make' for this module. Not running again unless you force!"), quiet => !$verbose );
                        last MAKE;
                    }

                    unless ( $self->_run(
                        command => [$Make, @args],
                        buffer  => \$captured,
                    ) ) {

                        ### store it if a module failed to install for some reason ###
                        $fail = 1;

                        $err->trap( error => loc("MAKE failed! - %1", $!) );

                        last SCOPE;
                        ### failed to run make, set overall => 0
                        ### restore startdir

                    }
                	
                	$data->status->make( 1 );

                    last INSTALL if $target eq 'make';
                    ### all ok, set overall => 1
                    ### restore startdir

                } ### end of MAKE

                MAKE_TEST: {
                unless ($skiptest) {

                    if( defined $data->status->make_test ) {
                        
                        if( $data->status->make_test && !$force ) {
                            $err->inform(
                                msg     => loc(q[Already tested this module - not running '%1' again unless you force],
                                                'make test' ),
                                quiet   => !$verbose
                            );
                            last MAKE_TEST;                                     
                        }
                         
                    }


                    unless ( $self->_run(
                        command => [$Make, @args, 'test'],
                        buffer  => \$captured,
                        verbose => 1
                    ) ) {
                        ### store it if a module failed to install for some reason ###
                        $fail = 1;

                        $err->trap( error => loc("MAKE TEST failed! - %1", $!) );

                        unless ($force) {
                            $fail = 1;
                            last SCOPE;

                            ### failed to run make test, set overall => 0
                            ### restore startdir
                        }
                    }

                    $data->status->make_test( 1 );

                    last INSTALL if $target eq 'test';
                    ### all ok, set overall => 1
                    ### restore startdir
                } }

                ### run from sudo if that was in the conf ###
                my $cmd     = [$Make, @args, 'install'];
                my $sudo    = $conf->_get_build('sudo');
                unshift @$cmd, $sudo if $sudo;

                unless ( $self->_run( command => $cmd ) ) {

                    $err->trap( error => loc("MAKE INSTALL failed! - %1", $!) );

                    $fail = 1;
                    last SCOPE;
                    ### failed to run make test, set overall => 0
                    ### restore startdir

                }

                $data->status->install( 1 );
                ### all ok, set overall => 1
                ### restore startdir

                ### nothing went wrong, but we DID install... mark that as well ###
                if( $target eq 'install' ) {
                    $self->{_todo}->{failed}->{ $data->{module} } = 0;
                }

            } ### end of INSTALL
        }

    } ### end of SCOPE:

    ### send an error report if the user wants that ###
    if ($report) {
        if (grep $_, values %{$self->{_todo}->{failed}}) {
            ### some prereq failed... don't send bogus report
            ### if 'flush' is set in your conf, it's reliable, otherwise it's not
            $err->inform(
                msg     => loc("Some prerequisites failed - skip sending test reports."),
                quiet   => !$verbose
            );
        }
        else {
            $self->_send_report(
                module => $data, buffer => $captured, failed => $fail
            );
        }
    }
    
    if($fail) {

        $self->{_todo}->{failed}->{ $data->{module} } = 1;
		$data->status->make_overall( 0 );
    } else {
        ### extra return status, makes it easier to check ###
        $data->status->make_overall( 1 );
    }

    ### add this data to the return value ###
    ### XXX this needs fixink for new Status.pm!!! XXX ###
    $return->{ $data->module() } = $data->status;

    ### set it back to the start dir we had when we entered this _make
    $self->_restore_startdir;

    ### if we still have modules left to do in our _tomake list, this is the time to do it!
    if ( $self->{_todo}->{make} and @{$self->{_todo}->{make}} ) {

        ### get the stored data for this session of 'make' ###
        my $stored = $self->{_todo}{make}->[0];

        ### retrieve the module object ###
        my $obj = $stored->{module};

        ### if we're trying to go _make in a dir we are already
        ### in, well, that's kinda stupid ;) -kane

        unless( $dir eq $stored->{dir} ) {
            ### call ourselves recursively to finish the make ###
            my $rv = $self->_make( %$stored );

            ### and return the data ###
            $return->{ $obj->module() } = $rv->{ $obj->module() };
        }

        ### and dump it off the TODO-stack ###
        shift @{$self->{_todo}{make}};

    }

    return $return;

} #_make


### convert scalar 'var=val' or arrayref flags into a hashref
sub _flags_hashref {
    my ($self, $flags) = @_;

    ### first, join arrayref flags (like ['A=B C=D', 'E=F']) together
    $flags = join(' ', @{$flags}) if UNIVERSAL::isa($flags, 'ARRAY');

    ### next, split scalars into a hashref and hand it to the caller
    $flags = {
        map { /=/ ? split('=', $_, 2) : ($_ => undef) }
            $flags =~ m/\s*((?:[^\s=]+=)?(?:"[^"]+"|'[^']+'|[^\s]+))/g
    } unless UNIVERSAL::isa($flags, 'HASH');

    return $flags;
}


### convert scalar or hashref flags into an arrayref
sub _flags_arrayref {
    my ($self, $flags) = @_;

    ### first, split scalar flags into hashref
    $flags = $self->_flags_hashref($flags) unless ref($flags);

    ### next, parse the hashref to an array and return it
    $flags = [ map {
        (defined $flags->{$_}) ? "$_=$flags->{$_}" : $_
    } sort keys %{$flags} ] if UNIVERSAL::isa($flags, 'HASH');

    return $flags;
}


### chdir back to the dir where the script is running in ###
sub _restore_startdir {
    my $self    = shift;
    my $conf    = $self->configure_object;
    my $err     = $self->error_object;
    my $verbose = $conf->get_conf('verbose');

    return 1 if chdir($conf->_get_build('startdir'));

    $err->inform(
        msg     => loc("Invalid start dir!"),
        quiet   => !$verbose
    );

    return 0;
}


### sub to generate a Makefile.PL in case the module didn't ship with one
sub _make_makefile {
    my $self = shift;
    my %hash = @_;
    my $err  = $self->error_object;

    my $tmpl = {
        data => { required => 1, allow => sub { UNIVERSAL::isa( pop(),
                                                'CPANPLUS::Internals::Module') }
        },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $fh = new FileHandle;

    unless ( $fh->open(">Makefile.PL") ) {
        $err->trap( error => loc("Could not create Makefile.PL - %1", $!) );
        return 0;
    }

    ### write the makefile
    print $fh qq|
### Auto-generated Makefile.PL by CPANPLUS.pm ###

    use ExtUtils::MakeMaker;

    WriteMakefile(
            NAME    => $args->{data}->{module},
            VERSION => $args->{data}->{version},
    );
|;

    $fh->close;
    return 1;
}

### scan the Makefile for prerequisites for the module about to be installed
sub _find_prereq {
    my $self = shift;
    my $conf = $self->configure_object;

    my %hash = @_;

    local $CPANPLUS::Tools::Check::ALLOW_UNKNOWN = 1;

    my $tmpl = {
        dir         => { allow => sub { -d pop() } },
        prereq      => { default => '' },
        makefile    => { required => 1, allow => [qw|Makefile Build|] },
        verbose     => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    return $args->{prereq} if $args->{prereq};

    if ($args->{makefile} eq 'Makefile') {
        return $self->_find_prereq_makemaker(
                                            dir     => $args->{dir},
                                            verbose => $args->{verbose}
                );
    }
    elsif ($args->{makefile} eq 'Build') {
        return $self->_find_prereq_module_build(
                                            dir     => $args->{dir},
                                            verbose => $args->{verbose}
                );
    }

    return 0;
}

sub _find_prereq_module_build {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        dir     => { required => 1, allow => sub { -d pop() } },
        verbose => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $fh = new FileHandle;

    require Module::Build;
    my $build = Module::Build->resume(
        properties => {
            config_dir      => File::Spec->catdir($args->{'dir'}, "_build"),
            build_script    => 'Build',
        }
    );

    my %p;
    my $failures = $build->prereq_failures;

    my @keys = qw(build_requires requires);
    push @keys, 'recommends' if $conf->get_conf('prereqs');

    foreach my $key (@keys) {
        my $fail = $failures->{$key} or next;
        foreach my $mod (keys %$fail) {
            next if $mod eq 'perl';
            $p{$mod} = $self->_version_to_number($fail->{$mod}{need});
        }
    }

    return \%p;
}

sub _version_to_number {
    my ($self, $version) = @_;

    return $version if ($version =~ /^\.?\d/);
    return 0;
}

sub _find_prereq_makemaker {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        dir     => { required => 1, allow => sub { -d pop() } },
        verbose => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $fh = new FileHandle;

    ### open the Makefile
    unless ( $fh->open(File::Spec->catfile($args->{'dir'}, "Makefile") ) ) {
        $err->trap( error => loc("Can't find %1: %2", "Makefile", $!) );
        return 0;
    }

    my %p;
    while (<$fh>) {
        last if /MakeMaker post_initialize section/;

        ### find prereqs
        my ($p) = m{^[\#]
                    \s+PREREQ_PM\s+=>\s+(.+)
                  }x;

        next unless $p;

        ### parse out the single prereqs
        while ( $p =~ m/(?:\s)([\w\:]+)=>(?:q\[(.*?)\],?|undef)/g ){

            ### In case a prereq is mentioned twice, complain.
            if ( defined $p{$1} ) {
                $err->inform(
                    msg   => loc("Warning: PREREQ_PM mentions %1 more than once, last mention wins!", $1),
                    quiet => !$args->{verbose}
                );
            }
            $p{$1} = $self->_version_to_number($2);
        }
        last;
    }
    return \%p;
}

1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
