# $File: //member/autrijus/cpanplus/dist/lib/CPANPLUS/Internals/Make.pm $
# $Revision: #3 $ $Change: 3544 $ $DateTime: 2002/03/26 07:48:03 $

#######################################################
###             CPANPLUS/Internals/Make.pm          ###
###  Subclass to make/install modules for cpanplus  ###
###         Written 23-02-2002 by Jos Boumans       ###
#######################################################

### Make.pm ###

package CPANPLUS::Internals::Make;

use strict;
use File::Spec;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use Cwd;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

sub _run {
    my ($self, $cmd, $verbose) = @_;

    $verbose = $self->{_conf}->get_conf('verbose')
        unless defined $verbose;

    return !system($cmd) if $verbose; # prints everything

    # non-verbose mode: inhibit STDOUT
    my $err  = $self->{_error};

    local *SAVEOUT;

    unless (open(SAVEOUT, ">&STDOUT")) {
        $err->trap( error => "couldn't dup STDOUT: $!" );
        return 0;
    }

    open STDOUT, '>'. File::Spec->devnull;

    my $rv = system($cmd);

    unless (open(STDOUT, ">&SAVEOUT")) {
        $err->trap( error => "couldn't restore STDOUT: $!" );
        return 0;
    }

    return !$rv;
}

sub _make {
    my $self = shift;
    my %args = @_;
    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $dir = $args{'dir'};
    my $data = $args{'module'};

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
    my $perl   = $args{'perl'}              || $^X;
    my $force  = $args{'force'}             || $conf->get_conf('force');
    my $flag   = $args{'makeflags'}         || $conf->get_conf('makeflags');
    my $make   = $args{'make'}              || $conf->_get_build('make');
    my %mmflags= %{$args{'makemakerflags'}  || $conf->get_conf('makemakerflags')};

    my $verbose = $conf->get_conf('verbose');

    ### try to install the module ###

    #unless ( open $fh, qq($perl Makefile.PL PREFIX=$target |) ) {

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
            return 0;
        }
    }
    ### We HAVE to use system() here so as to allow for interactive
    ### makefiles. Here's the rundown of conciderations:
    ###
    ### cmd         verbose ctrl   rv?      interactive?
    ### system          n           y           y
    ### backticks       y           y           n
    ### exec            y           n           y
    ### open            y           y           n
    ###
    ### seeing we NEED a return value (to do error checks),
    ### we can only use open, backticks or system. and only the latter allows
    ### interactive mode. so we're screwed =/ -Kane

    PERL_MAKEFILE: {
        ### we can check for a 'Makefile' but that might be have produced a 
        ### Makefile that CAME from a different version of perl
        ### thus screwing everything up.
        ### i suggest uncommenting this once we have a way to pass make options like 'clean'
        
        #if ( -e 'Makefile' && !$force ) {
        #    $err->inform( msg => qq[Makefile already exists, not running 'perl Makefile.PL' again, unless you force!], quiet => !$verbose );
        #    last PERL_MAKEFILE;
        #}

        my @args = map {
            (defined $mmflags{$_}) ? "$_=$mmflags{$_}" : $_
        } sort keys %mmflags;

        unless( $self->_run( "$perl Makefile.PL @args", 1 ) ) { # always verbose
            ### store it if a module failed to install for some reason ###
            $self->{_todo}->{failed}->{ $data->{module} } = 1;

            $err->trap( error => "BUILDING MAKEFILE failed! - $!" );
            return 0;
        }
    }

#    {
#        local $?;   # be sure it's undef
#        my @output = `$perl Makefile.PL PREFIX=$target`;
#        unless ( $? ) {
#            for (@output) { chomp; $err->inform( msg => $_, quiet => !$verbose ) }
#        } else {
#            $err->trap( error => "BUILDING MAKEFILE failed! - $?" );
#            return 0;
#        }
#    }

#    {   my $fh;
#        open $fh, "$perl Makefile.PL PREFIX=$target |" or
#            (   $err->trap( error => "BUILDING MAKEFILE failed! - $?" ),
#                return 0
#            );
#
#        while (<$fh>) { chomp; $err->inform( msg => $_, quiet => !$verbose ) }
#        close $fh;
#    }

    ### the way cpan.pm does it ###
    ### definate no-no
#    $system = "$perl $switch Makefile.PL $CPAN::Config->{makepl_arg}";
#
#    if (defined($pid = fork)) {
#        if ($pid) { #parent
#            # wait;
#            waitpid $pid, 0;
#        } else {    #child
#            exec $system;
#        }
#    }

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

            } elsif ( defined $self->{_todo}->{failed}->{$mod} ) {
                $err->inform(
                    msg => "According to the cache, prerequisite $mod is already installed",
                    quiet => !$verbose
                );
            }
        }

        return 0 if $flag;
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
                return \@{[ keys %list ]};
            }

            ### check if any of the prereqs we're about to install wants us to get
            ### a newer version of perl... if so, skip, we dont want to upgrade perl
            if ($mod =~ /^base$/i or $self->{_modtree}->{$mod}->{package} =~ /^perl\W/i ) {
                $err->inform(
                    msg => "The module you're trying to install wants to upgrade your version of perl" .
                            " but you probably dont want that, so we're skipping",
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

        ### store this dir, we'll have to finish the make here later.
        unshift @{$self->{_todo}->{make}}, $dir;

        ### enqueue this modules prereqs ###
        unshift @{$self->{_todo}->{install}}, [ map {
            $self->{_modtree}->{$_}
        } keys %list ];
    
        while (my $mod_ref = shift @{$self->{_todo}->{install}} ) {
            $self->_install_module( modules => $mod_ref );
        }
    
    } else {

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
    
                unless ( $self->_run("$make $flag") ) {
                    ### store it if a module failed to install for some reason ###
                    $self->{_todo}->{failed}->{ $data->{module} } = 1;
    
                    $err->trap( error => "MAKE failed! - $!" );
                    return 0;
                }
            }
    
            {
                unless ( $self->_run("$make $flag test", 1) ) { # always verbose
                    ### store it if a module failed to install for some reason ###
                    $self->{_todo}->{failed}->{ $data->{module} } = 1;
    
                    $err->trap( error => "MAKE TEST failed! - $!" );
                    return 0;
                }
            }
    
            {
                unless ( $self->_run("$make $flag install") ) {
                    ### store it if a module failed to install for some reason ###
                    $self->{_todo}->{failed}->{ $data->{module} } = 1;
    
                    $err->trap( error => "MAKE INSTALL failed! - $!" );
                    return 0;
                }
            }
    
            ### chdir back to the dir where the script is running in ###
            chdir $conf->_get_build('startdir') or
                $err->inform(
                    msg     => "Invalid start dir!",
                    quiet   => !$verbose
                );
    
            ### nothing went wrong, but we DID install... mark that as well ###
            $self->{_todo}->{failed}->{ $data->{module} } = 0;
    
            return 1;
        }
    }
 
    ### if we still have modules left to do in our _tomake list, this is the time to do it!
    if ( length @{$self->{_todo}->{make}} ) { $self->_make( dir => shift @{$self->{_todo}->{make}} ) }

    ### indicate success ###
    return 1;

} #_make

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
