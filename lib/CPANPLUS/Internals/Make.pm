# $File: //member/autrijus/cpanplus/dist/lib/CPANPLUS/Internals/Make.pm $
# $Revision: #21 $ $Change: 4069 $ $DateTime: 2002/04/30 18:07:25 $

#######################################################
###             CPANPLUS/Internals/Make.pm          ###
###  Subclass to make/install modules for cpanplus  ###
###         Written 23-02-2002 by Jos Boumans       ###
#######################################################

### Make.pm ###

package CPANPLUS::Internals::Make;

use strict;
use File::Spec;
use FileHandle;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use Cwd;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

sub _make {
    my $self    = shift;
    my %args    = @_;
    my $conf    = $self->{_conf};
    my $err     = $self->{_error};
    my $modtree = $self->_module_tree;

    my $dir    = $args{'dir'};
    my $data   = $args{'module'};

    ### make target: may also be 'makefile', 'make', 'test' or 'skiptest'
    my $target        = lc($args{'target'}) || 'install';
    ### target of prereqs: may also be 'makefile', 'make', 'test' or 'skiptest'
    my $prereq_target = lc($args{'prereq_target'}) || 'install';

    ### test for Backend->flush
    ###print "this is todo: ", Dumper $self->{_todo};

    unless (chdir $dir) {
        $err->trap(
            error => "Make couldn't chdir to $dir! I am in " . cwd " . now"
        );
        return 0;
    }

    ### perhaps we shouldn't store the version of perl in config, but just use the one
    ### we were invoked with ($^X) unless the user specifies one specifically...
    ### i think that would make a few users happier -kane
    my ($perl, $force, $make, $report, $mmflags, $makeflags)
        = @args{qw|perl force make cpantest makemakerflags makeflags|};

    ### fill in the defaults; checks for definedness, not truth value. -autrijus
    $perl      = $^X                               unless defined $perl;
    $force     = $conf->get_conf('force')          unless defined $force;
    $make      = $conf->_get_build('make')         unless defined $make;
    $report    = $conf->get_conf('cpantest')       unless defined $report;
    $mmflags   = $conf->get_conf('makemakerflags') unless defined $mmflags;
    $makeflags = $conf->get_conf('makeflags')      unless defined $makeflags;
 
    my $verbose = $conf->get_conf('verbose');
    my $captured; # capture buffer of _run

    ### try to install the module ###

    ### 'perl Makefile.PL' ###
    ### check if the makefile.pl exists
    unless ( -e 'Makefile.PL' ) {
        $err->inform(
            msg     => "Author did not supply a Makefile.PL - Attempting to generate one",
            quiet   => !$verbose
        );

        ### if not, we make our own, return 0 if that fails
        unless ( $self->_make_makefile( data => $args{module} ) ) {

            ### store it if a module failed to install for some reason ###
            $self->{_todo}->{failed}->{ $data->{module} } = 1;

            $err->trap(
                error => "Could not generate Makefile.PL - Aborting"
            );
            $self->_restore_startdir;
            return 0;
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

        #if ( -e 'Makefile' && !$force ) {
        #    $err->inform( msg => qq[Makefile already exists, not running 'perl Makefile.PL' again, unless you force!], quiet => !$verbose );
        #    last PERL_MAKEFILE;
        #}

        my @args = @{$self->_flags_arrayref($mmflags)};

        ### BIG CAVEAT: We're forced to use the $|=1 trick to ensure proper
        ###             ordering of STDIN, STDOUT and STDERR in captured buffer
        unless( $self->_run(
            command => [$perl, '-e', '$|=1;do"Makefile.PL"', @args],
            buffer  => \$captured,
            verbose => 1
        ) ) {
            ### store it if a module failed to install for some reason ###
            $self->{_todo}->{failed}->{ $data->{module} } = 1;

            $err->trap( error => "BUILDING MAKEFILE failed! - $!" );
            $self->_send_report( module => $data, buffer => $captured) if $report;
            $self->_restore_startdir;
            return 0;
        }

        if ($target eq 'makefile') {
            $self->_restore_startdir;
            return 1;
        }
    }


    ### this is where we find out what prereqs this module has,
    ### and install them accordingly.
    ### this probably needs some tidying up ###


    my $prereq = $self->_find_prereq( dir => $dir );

    ### check if the prereq this module wants is something we already tried to install
    ### earlier this session: if so $self->{_todo}->{failed} will be 1.
    ### a succesfull install will set the above variable to 0. this way we can still
    ### check for 'defined'-ness.
    #print Dumper $self->{_todo}->{failed};

    {   my $flag;
        for my $mod (keys %$prereq) {
            if ( $self->{_todo}->{failed}->{$mod} ) {
                $err->inform(
                    msg => "According to the cache, $mod failed to install before in this session.. returning!",
                    quiet => !$verbose
                );

                $flag = 1;
            }
        }

        if ($flag) {
            $self->_restore_startdir;
            return 0;
        }
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
                    msg     => "Prereqs are found, but not allowed to install! Returning list of prereqs",
                    quiet   => !$verbose
                );

                $self->_restore_startdir;
                return \@{[ keys %list ]};
            }

            unless ( keys(%{$modtree->{$mod}}) ) {
                $err->trap( error => "No such module: $mod, cannot satisfy dependency" );
                next;
            }

            if ( grep { $_->{module}{module} eq $mod } @{$self->{_todo}{make}} ) {
                $err->trap( error => "Recursive dependency detected in $mod, skipping" );
                next;
            }
            elsif ( defined $self->{_todo}->{failed}->{$mod} ) {
                $err->inform(
                    msg => "According to the cache, prerequisite $mod is already installed",
                    quiet => !$verbose
                );
                next;
            }

            ### check if we're in shell mode, and if we should ask to follow prereqs.
            ### should probably use words rather than numbers -kane
            if ( $self->{_shell} and $conf->get_conf('prereqs') == 2 ) {
                $list{$mod} = 1 if $self->{_shell}->_ask_prereq( mod => $mod );
            } else {
                ### must install this
                $list{$mod} = 1;
            }

            if ( $list{$mod} ) {
                $err->inform(
                    msg     => "Installing $mod to satisfy dependency",
                    quiet   => !$verbose
                );
            }
        }
    }


    ### see if we have anything to install, if so, we'll need to exit this make, and install
    ### the prereqs first.
    if (%list) {

        ### store this dir and modname, we'll have to finish the make here later.
        unshift @{$self->{_todo}->{make}}, \%args;

        ### enqueue this modules prereqs ###
        unshift @{$self->{_todo}->{install}}, [ map {
            $modtree->{$_}
        } keys %list ];

        while (my $mod_ref = shift @{$self->{_todo}->{install}} ) {
            $self->_install_module(
                modules       => $mod_ref,
                target        => $prereq_target,
                prereq_target => $prereq_target,
            );
        }

    } else {
        my @args = @{$self->_flags_arrayref($makeflags)};

        INSTALL: {
            ### ok, so we have no prereqs to take care of, let's go on with installing ###

            MAKE: {
                ### we can check for a 'blib' but that might be a run from a 'make' that was run on a
                ### Makefile that CAME from a different version of perl
                ### thus screwing everything up.
                ### i suggest uncommenting this once we have a way to pass make options like 'clean'

                #if ( -d 'blib' && !$force ) {
                #    $err->inform( msg => qq[Already ran 'make' for this module. Not running again unless you force!], quiet => !$verbose );
                #    last MAKE;
                #}

                unless ( $self->_run(
                    command => [$make, @args],
                    buffer  => \$captured,
                ) ) {
                    ### store it if a module failed to install for some reason ###
                    $self->{_todo}->{failed}->{ $data->{module} } = 1;

                    $err->trap( error => "MAKE failed! - $!" );
                    $self->_send_report( module => $data, buffer => $captured) if $report;
                    $self->_restore_startdir;
                    return 0;
                }

                last INSTALL if $target eq 'make';
            }

            if ($target ne 'skiptest') {
                unless ( $self->_run(
                    command => [$make, @args, 'test', "TEST_VERBOSE=(eval(chr(36).q(|=1))-1)"],
                    buffer  => \$captured,
                    verbose => 1
                ) ) {
                    ### store it if a module failed to install for some reason ###
                    $self->{_todo}->{failed}->{ $data->{module} } = 1;

                    $err->trap( error => "MAKE TEST failed! - $!" );
                    $self->_send_report( module => $data, buffer => $captured) if $report;

                    unless ($force) {
                        $self->_restore_startdir;
                        return 0;
                    }
                }
                else {
                    $self->_send_report( module => $data, buffer => $captured) if $report;
                }

                last INSTALL if $target eq 'test';
            }

            {
                unless ( $self->_run(
                    command => [$make, @args, 'install'],
                ) ) {
                    ### store it if a module failed to install for some reason ###
                    $self->{_todo}->{failed}->{ $data->{module} } = 1;

                    $err->trap( error => "MAKE INSTALL failed! - $!" );
                    $self->_restore_startdir;
                    return 0;
                }
            }

        }

        $self->_restore_startdir;

        ### nothing went wrong, but we DID install... mark that as well ###
        $self->{_todo}->{failed}->{ $data->{module} } = 0;

        return 1;
    }

    ### if we still have modules left to do in our _tomake list, this is the time to do it!
    if ( @{$self->{_todo}->{make}} ) {
        $self->_make( %{ $self->{_todo}{make}->[0] } );
        shift @{$self->{_todo}{make}};
    }

    ### indicate success ###
    return 1;

} #_make


### convert scalar 'var=val' or orrayref flags into a hashref
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
    my $self = shift;
    my $conf = $self->{_conf};
    my $err  = $self->{_error};
    my $verbose = $conf->get_conf('verbose');

    return 1 if chdir($conf->_get_build('startdir'));

    $err->inform(
        msg     => "Invalid start dir!",
        quiet   => !$verbose
    );

    return 0;
}


### sub to generate a Makefile.PL in case the module didn't ship with one
sub _make_makefile {
    my $self = shift;
    my %args = @_;

    my $err  = $self->{_error};

    my $fh = new FileHandle;

    unless ( $fh->open(">Makefile.PL") ) {
        $err->trap( error => "Could not create Makefile.PL - $!" );
        return 0;
    }

    ### write the makefile
    print $fh qq|
### Auto-generated Makefile.PL by CPANPLUS.pm ###

    use ExtUtils::MakeMaker;

    WriteMakefile(
            NAME    => $args{data}->{module},
            VERSION => $args{data}->{version},
    );
|;

    $fh->close;
    return 1;
}

### scan the Makefile for prerequisites for the module about to be installed
sub _find_prereq {
    my $self = shift;
    my %args = @_;
    my $conf = $self->{_conf};
    my $err  = $self->{_error};
    my $fh = new FileHandle;

    ### open the Makefile
    unless ( $fh->open(File::Spec->catfile($args{'dir'}, "Makefile") ) ) {
        $err->trap( error => "Can't find the Makefile: $!" );
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
        while ( $p =~ m/(?:\s)([\w\:]+)=>q\[(.*?)\],?/g ){

            ### In case a prereq is mentioned twice, complain.
            if ( defined $p{$1} ) {
                $err->inform(
                    msg   => "Warning: PREREQ_PM mentions $1 more than once, last mention wins!",
                    quiet => !$conf->get_conf('verbose')
                );
            }
            $p{$1} = $2;
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
