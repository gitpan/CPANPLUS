package CPANPLUS::Dist::Build;

use strict;
use vars    qw[@ISA $STATUS];
@ISA =      qw[CPANPLUS::Dist];

use CPANPLUS::inc;
use CPANPLUS::Internals::Constants;
use CPANPLUS::Error;

use Module::Build;
use FileHandle;
use Cwd;

use IPC::Cmd                    qw[run];
use Params::Check               qw[check];
use Module::Load::Conditional   qw[can_load check_install];
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';

local $Params::Check::VERBOSE = 1;

=pod

=head1 NAME

CPANPLUS::Dist::Build

=head1 SYNOPSIS

    my $build = CPANPLUS::Dist->new( 
                                format  => 'build',
                                module  => $modobj, 
                            );
    $build->create;     # runs build && build test
    $build->install;    # runs build install

    
=head1 DESCRIPTION

C<CPANPLUS::Dist::Build> is a distribution class for C<Module::Build> 
related modules.
Using this package, you can create, install and uninstall perl 
modules. It inherits from C<CPANPLUS::Dist>.

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
    $build->status->ACCESSOR

=over 4

=item build_pl ()

Location of the Build file. 
Set to 0 explicitly if something went wrong.

=item build ()

BOOL indicating if the C<Build> command was successful.

=item test ()

BOOL indicating if the C<Build test> command was successful.

=item installed ()

BOOL indicating if the module was installed. This gets set after
C<Build install> exits successfully.

=item uninstalled ()

BOOL indicating if the module was uninstalled properly.

=item _create_args ()

Storage of the arguments passed to C<create> for this object. Used
for recursive calls when satisfying prerequisites.

=item _install_args ()

Storage of the arguments passed to C<install> for this object. Used
for recursive calls when satisfying prerequisites.

=item _mb_object ()

Storage of the C<Module::Build> object we used for this installation.

=back

=cut

 
=head1 METHODS

=head2 format_available();

Returns a boolean indicating whether or not you can use this package
to create and install modules in your environment.

=cut 
 
### check if the format is available ###
sub format_available {
    my $mod = "Module::Build";
    unless( can_load( modules => { $mod => 0.0 } ) ) {
        error( loc( "You do not have '%1' -- '%2' not available",
                    $mod, __PACKAGE__ ) ); 
        return;
    }
    
    return 1;     
} 
 
 
=pod $bool = $dist->init();

Sets up the C<CPANPLUS::Dist::Build> object for use. 
Effectively creates all the needed status accessors.

Called automatically whenever you create a new C<CPANPLUS::Dist> object.

=cut

sub init {
    my $dist    = shift;
    my $status  = $dist->status;
   
    $status->mk_accessors(qw[build_pl build test created installed uninstalled
                            _create_args _install_args _mb_object] );
    
    return 1;
}     

=pod

=head2 $dist->create([perl => '/path/to/perl', buildflags => 'EXTRA=FLAGS', prereq_target => TARGET, force => BOOL, verbose => BOOL])

C<create> preps a distribution for installation. This means it will 
run C<perl Build.PL>, C<Build> and C<Build test>. 
This will also satisfy any prerequisites the module may have. 

If you set C<skiptest> to true, it will skip the C<Build test> stage.
If you set C<force> to true, it will go over all the stages of the 
C<Build> process again, ignoring any previously cached results. It 
will also ignore a bad return value from C<Build test> and still allow 
the operation to return true.

Returns true on success and false on failure.

You may then call C<< $dist->install >> on the object to actually
install it.
Returns true on success and false on failure.

=cut 
   
sub create {
    ### just in case you already did a create call for this module object
    ### just via a different dist object
    my $dist = shift;
    my $self = $dist->parent;
    
    ### we're also the cpan_dist, since we don't need to have anything
    ### prepared from another installer
    $dist    = $self->status->dist_cpan if      $self->status->dist_cpan;     
    $self->status->dist_cpan( $dist )   unless  $self->status->dist_cpan;  
   
    my $cb   = $self->parent;
    my $conf = $cb->configure_object;
    my %hash = @_;

    my $dir;
    unless( $dir = $self->status->extract ) {
        error( loc( "No dir found to operate on!" ) );
        return;
    }
   
    my $args;
    my( $force, $verbose, $buildflags, $skiptest, $prereq_target,
        $perl, $prereq_format);
    {   local $Params::Check::ALLOW_UNKNOWN = 1;
        my $tmpl = {
            force           => {    default => $conf->get_conf('force'), 
                                    store   => \$force },
            verbose         => {    default => $conf->get_conf('verbose'), 
                                    store   => \$verbose },
            perl            => {    default => $^X, store => \$perl },
            ## can't do this yet
            buildflags      => {    default => $conf->get_conf('buildflags'), 
                                    store   => \$buildflags },
            skiptest        => {    default => $conf->get_conf('skiptest'), 
                                    store   => \$skiptest },
            prereq_target   => {    default => '', store => \$prereq_target },                     
            prereq_format   => {    default => $self->status->installer_type,
                                    store   => \$prereq_format },
        };                                            

        $args = check( $tmpl, \%hash ) or return;
    }    
    
    return 1 if $dist->status->created && !$force;
    
    $dist->status->_create_args( $args );
    
    ### chdir to work directory ###
    my $orig = cwd();
    unless( $cb->_chdir( dir => $dir ) ) {
        error( loc( "Could not chdir to build directory '%1'", $dir ) );
        return;
    }
    
    ### XXX buildflags to new_from_context don't work yet -- see TODO
    ### ken williams suggested using 'split_like_shell' to parse a string
    ### into valid options, but it doesn't seem to work properly.. rather
    ### than key=>value pairs, we get something like this:
    # [kane@myriad ~...inc/Module]$ perlc -MModule::Build -le'print join $/, 
    # Module::Build->split_like_shell(q[--verbose=1 --destdir=/tmp])'
    # --verbose=1
    # --destdir=/tmp
    error(loc("'%1' does not support flags to it's '%2' method yet, so they ".
                "will be ignored", 'Module::Build', 'new_from_context')) 
        if $buildflags;

    my $fail; my $prereq_fail; 
    RUN: {
    
        ### XXX currently doesn't accept args.. but when it does, it
        ### wants key-val pairs, but we just have a string...
        ### piece of sh*t, stop DYING! --kane
        my $mb = eval { Module::Build->new_from_context() };
        
        if( !$mb or $@ ) {
            error(loc("Could not create Module::Build object: %1",$@));
            $fail++; last RUN;
        }
        
        $dist->status->_mb_object( $mb );
        
        ### resolve prereqs ###
        my $prereqs = $dist->_find_prereqs( verbose => $verbose );
        
        ### XXX mangle prereqs because our uptodate() function can't
        ### handle M::B version ranges -- perhaps always use M::B to
        ### verify if modules are up to date, but that would cause a
        ### dependency
        ### so for now, always use the most recent version of a module
        ### if the prereq was somehow unsatisfied
        my $mangled_prereqs = {};
        for my $mod (keys %$prereqs) {
            my $modobj = $cb->module_tree($mod);
            unless( $modobj ) {
                error(loc("Unable to find '%1' in the module tree ".
                          "-- unable to satisfy prerequisites", $mod));
                $fail++; last RUN;     
            }
            $mangled_prereqs->{ $mod } = $modobj->version;
        }            
        
        ### this will set the directory back to the start
        ### dir, so we must chdir /again/  
        my $ok = $dist->_resolve_prereqs(
                        format  => $prereq_format,
                        verbose => $verbose,
                        prereqs => $mangled_prereqs,
                        target  => $prereq_target,
                    );             
        
        unless( $cb->_chdir( dir => $dir ) ) {
            error( loc( "Could not chdir to build directory '%1'", $dir ) );
            return;
        }       
        
        unless( $ok ) {
            #### use $dist->flush to reset the cache ###
            error( loc( "Unable to satisfy prerequisites for '%1' " .
                        "-- aborting install", $self->module ) );    
            $dist->status->build(0);
            $fail++; $prereq_fail++;
            last RUN;
        } 
        
        eval { $mb->dispatch('build') };
        if( $@ ) {
            error(loc("Could not run '%1': %2", 'Build', $@));
            $dist->status->build(0);
            $fail++; last RUN;
        }   
        
        $dist->status->build(1);     
   
        ### add this directory to your lib ###
        $cb->_add_to_includepath(
            directories => [ BLIB_LIBDIR->( $self->status->extract ) ]
        );

        unless( $skiptest ) {
            eval { $mb->dispatch('test') };
            if( $@ ) {
                error(loc("Could not run '%1': %2", 'Build test', $@));
                
                unless($force) {
                    $dist->status->test(0);
                    $fail++; last RUN;
                }
            } else {
                $dist->status->test(1);      
            }
        }      
    }
 
    unless( $cb->_chdir( dir => $orig ) ) {
        error( loc( "Could not chdir back to start dir '%1'", $orig ) );
    } 
    
    ### send out test report? ###
    if( $conf->get_conf('cpantest') and not $prereq_fail ) {
        $cb->_send_report( 
            module  => $self,
            failed  => $fail,
            buffer  => CPANPLUS::Error->stack_as_string,
            verbose => $verbose,
            force   => $force,
        ) or error(loc("Failed to send test report for '%1'",
                    $self->module ) );
    }
    
    return $dist->status->created( $fail ? 0 : 1 );
}     
 
sub _find_prereqs {
    my $dist = shift;
    my $mb   = $dist->status->_mb_object;
    my $self = $dist->parent;
    
    ### Lame++, at least return an empty hashref...
    my $prereqs = $mb->requires || {};   
    $self->status->prereqs( $prereqs );
      
    return $prereqs;
}    

=head2 $dist->install([verbose => BOOL, perl => /path/to/perl]) 

Actually installs the created dist.

Returns true on success and false on failure.

=cut
 
sub install {
    ### just in case you already did a create call for this module object
    ### just via a different dist object
    my $dist = shift;
    my $self = $dist->parent;
    
    ### we're also the cpan_dist, since we don't need to have anything
    ### prepared from another installer
    $dist    = $self->status->dist_cpan if $self->status->dist_cpan;  
    my $mb   = $dist->status->_mb_object;
   
    my $cb   = $self->parent;
    my $conf = $cb->configure_object;
    my %hash = @_;
    
    my $verbose; my $perl;
    my $tmpl ={
        verbose => { default => $conf->get_conf('verbose'),
                     store   => \$verbose },
        perl    => { default => $conf->get_program('perl') || $^X, 
                     store   => \$perl },
    };
    
    my $args = check( $tmpl, \%hash ) or return;
    $dist->status->_install_args( $args );
    
    my $dir;
    unless( $dir = $self->status->extract ) {
        error( loc( "No dir found to operate on!" ) );
        return;
    }
    
    my $orig = cwd();
    
    unless( $cb->_chdir( dir => $dir ) ) {
        error( loc( "Could not chdir to build directory '%1'", $dir ) );
        return;
    }  
   
    ### value set and false -- means failure ###
    if( defined $self->status->installed && !$self->status->installed ) {
        error( loc( "Module '%1' has failed to install before this session " .
                    "-- aborting install", $self->module ) );
        return;
    }
   
    my $fail;
    
    ### hmm, how is this going to deal with sudo?
    ### for now, check effective uid, if it's not root,
    ### shell out, otherwise use the method
    if( $> ) {
        ### we need to load Module::build here now, or perl might
        ### load the wrong version
        
        ### perl5opt is too late =/
        ### add it explicitly 
        my @opts = split /\s+/, $ENV{'PERL5OPT'};
       
        my $cmd     = [$perl, @opts, '-MModule::Build', 
                        BUILD->($dir), 'install'];
        my $sudo    = $conf->get_program('sudo');
        unshift @$cmd, $sudo if $sudo;


        my $buffer;
        unless( scalar run( command => $cmd,
                            buffer  => \$buffer,
                            verbose => $verbose ) 
        ) {
            error(loc("Could not run '%1': %2", 'Build install', $buffer));
            $fail++;
        }    
    } else {
        eval { $mb->dispatch('install') };       
        if( $@ ) {
            error(loc("Could not run '%1': %2", 'Build install', $@));
            $fail++;
        }   
    }

    
    unless( $cb->_chdir( dir => $orig ) ) {
        error( loc( "Could not chdir back to start dir '%1'", $orig ) );
    }   
    
    return $dist->status->installed( $fail ? 0 : 1 );
}   
   
=head1 KNOWN ISSUES

There are some known issues with Module::Build, that we hope the 
authors will resolve at some point, so we can make full use of
Module::Build's power.

=over 4

=item * Passing build flags to 'new_from_context'

This is sadly not possible until Module::Build is patched to support
the parsing of stringified arguments as options to it's 
C<new_from_context> method. This means you are stuck with the default 
behaviour of the Build.PL in the distribution.

=item * Uninstall modules installed by Module::Build

Module::Build doesn't write a so called C<packlist> file, which holds 
a list of all files installed by a distribution. Without this file we
don't know what to remove. Until Module::Build generates this 
C<packlist>, we are unable to remove any installations done by it.

=item * Module::Build's version comparison is not supported.

Module::Build has it's own way of defining what versions are considered
satisfactory for a prerequisite, and which ones aren't. This syntax is
something specific to Module::Build and we currently have no way to see
if a module on disk, on cpan or something similar is satisfactory 
according to Module::Build's version comparison scheme.
As a work around, we now simply assume that the most recent version on
CPAN satisfies a dependency.

=back

=cut
   
1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
