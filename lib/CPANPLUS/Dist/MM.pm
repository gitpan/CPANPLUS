package CPANPLUS::Dist::MM;

use strict;
use vars    qw[@ISA $STATUS];
@ISA =      qw[CPANPLUS::Dist];

use CPANPLUS::inc;
use CPANPLUS::Internals::Constants;
use CPANPLUS::Error;
use FileHandle;
use Cwd;

use IPC::Cmd                    qw[run];
use Params::Check               qw[check];
use Module::Load::Conditional   qw[can_load check_install];
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';

local $Params::Check::VERBOSE = 1;

=pod

=head1 NAME

CPANPLUS::Dist::MM

=head1 SYNOPSIS

    my $mm = CPANPLUS::Dist->new( 
                                format  => 'makemaker',
                                module  => $modobj, 
                            );
    $mm->create;        # runs make && make test
    $mm->install;       # runs make install

    
=head1 DESCRIPTION

C<CPANPLUS::Dist::MM> is a distribution class for MakeMaker related
modules.
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
    $mm->status->ACCESSOR

=over 4

=item makefile ()

Location of the Makefile (or Build file). 
Set to 0 explicitly if something went wrong.

=item make ()

BOOL indicating if the C<make> (or C<Build>) command was successful.

=item test ()

BOOL indicating if the C<make test> (or C<Build test>) command was 
successful.

=item installed ()

BOOL indicating if the module was installed. This gets set after
C<make install> (or C<Build install>) exits successfully.

=item uninstalled ()

BOOL indicating if the module was uninstalled properly.

=item _create_args ()

Storage of the arguments passed to C<create> for this object. Used
for recursive calls when satisfying prerequisites.

=item _install_args ()

Storage of the arguments passed to C<install> for this object. Used
for recursive calls when satisfying prerequisites.

=back

=cut

=head1 METHODS

=head2 $bool = $dist->format_available();

Returns a boolean indicating whether or not you can use this package
to create and install modules in your environment.

=cut

### check if the format is available ###
sub format_available {
    my $dist = shift;
  
    ### we might be called as $class->format_available =/
    require CPANPLUS::Internals;
    my $cb   = CPANPLUS::Internals->_retrieve_id( 
                    CPANPLUS::Internals->_last_id );
    my $conf = $cb->configure_object;
  
    my $mod = "ExtUtils::MakeMaker";
    unless( can_load( modules => { $mod => 0.0 } ) ) {
        error( loc( "You do not have '%1' -- '%2' not available",
                    $mod, __PACKAGE__ ) ); 
        return;
    }
    
    unless( $conf->get_program('make') ) { 
        error( loc( "You do not have '%1' -- '%2' not available",
                    'make', __PACKAGE__ ) ); 
        return;
    }

    return 1;     
}

=pod $bool = $dist->init();

Sets up the C<CPANPLUS::Dist::MM> object for use. 
Effectively creates all the needed status accessors.

Called automatically whenever you create a new C<CPANPLUS::Dist> object.

=cut

sub init {
    my $dist    = shift;
    my $status  = $dist->status;
   
    $status->mk_accessors(qw[makefile make test created installed uninstalled
                            _create_args _install_args] );
    
    return 1;
}    

=pod

=head2 $bool = $dist->create([perl => '/path/to/perl', makemakerflags => 'EXTRA=FLAGS', make => '/path/to/make', makeflags => 'EXTRA=FLAGS', prereq_target => TARGET, force => BOOL, verbose => BOOL])

C<create> preps a distribution for installation. This means it will 
run C<perl Makefile.PL>, C<make> and C<make test>. 
This will also scan for and attempt to satisfy any prerequisites the
module may have. 

If you set C<skiptest> to true, it will skip the C<make test> stage.
If you set C<force> to true, it will go over all the stages of the 
C<make> process again, ignoring any previously cached results. It 
will also ignore a bad return value from C<make test> and still allow 
the operation to return true.

Returns true on success and false on failure.

You may then call C<< $dist->install >> on the object to actually
install it.

=cut

sub create {
    ### just in case you already did a create call for this module object
    ### just via a different dist object
    my $dist = shift;
    my $self = $dist->parent;
    
    ### we're also the cpan_dist, since we don't need to have anything
    ### prepared 
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
    my( $force, $verbose, $make, $makeflags, $skiptest, $prereq_target, $perl, 
        $mmflags, $prereq_format);
    {   local $Params::Check::ALLOW_UNKNOWN = 1;
        my $tmpl = {
            perl            => {    default => 
                                        $conf->get_program('perl') || $^X, 
                                    store => \$perl },
            makemakerflags  => {    default =>
                                        $conf->get_conf('makemakerflags'),
                                    store => \$mmflags },                 
            force           => {    default => $conf->get_conf('force'), 
                                    store   => \$force },
            verbose         => {    default => $conf->get_conf('verbose'), 
                                    store   => \$verbose },
            make            => {    default => $conf->get_program('make'), 
                                    store   => \$make },
            makeflags       => {    default => $conf->get_conf('makeflags'), 
                                    store   => \$makeflags },
            skiptest        => {    default => $conf->get_conf('skiptest'), 
                                    store   => \$skiptest },
            prereq_target   => {    default => '', store => \$prereq_target }, 
            ### don't set the default prereq format to 'makemaker' -- wrong!
            prereq_format   => {    #default => $self->status->installer_type,
                                    default => '',
                                    store   => \$prereq_format },                    
        };                                            

        $args = check( $tmpl, \%hash ) or return;
    }
    
    ### maybe we already ran a create on this object? ###
    return 1 if $dist->status->created && !$force;
        
    ### store the arguments, so ->install can use them in recursive loops ###
    $dist->status->_create_args( $args );
    
    ### chdir to work directory ###
    my $orig = cwd();
    unless( $cb->_chdir( dir => $dir ) ) {
        error( loc( "Could not chdir to build directory '%1'", $dir ) );
        return;
    }
    
    my $fail; my $prereq_fail;
    RUN: {
        ### don't run 'perl makefile.pl' again if there's a makefile already ###
        if( -e MAKEFILE->() && (-M MAKEFILE->() < -M $dir) && !$force ) {
            msg(loc("'%1' already exists, not running '%2 %3' again ".
                    " unless you force",
                    MAKEFILE->(), $perl, MAKEFILE_PL->() ), $verbose );
            
        } else {
            unless( -e MAKEFILE_PL->() ) {
                msg(loc("No '%1' found - attempting to generate one",
                        MAKEFILE_PL->() ), $verbose );
                        
                $dist->write_makefile_pl( 
                            verbose => $verbose, 
                            force   => $force 
                        );
                
                ### bail out if there's no makefile.pl ###
                unless( -e MAKEFILE_PL->() ) {
                    error( loc( "Could not find '%1' - cannot continue", 
                                MAKEFILE_PL->() ) );
        
                    ### mark that we screwed up ###
                    $dist->status->makefile(0);
                    $fail++; last RUN;
                }
            }    
    
            ### you can turn off running this verbose by changing
            ### the config setting below, although it is really not
            ### recommended
            my $run_verbose = $verbose || 
                              $conf->get_conf('allow_build_interactivity') ||
                              0;
    
            ### this makes MakeMaker use defaults if possible, according
            ### to schwern. See ticket 8047 for details.
            local $ENV{PERL_MM_USE_DEFAULT} = 1 unless $run_verbose; 
    
            ### turn off our PERL5OPT so no modules from CPANPLUS::inc get
            ### included in the makefile.pl -- it should build without
            ### also, modules that run in taint mode break if we leave
            ### our code ref in perl5opt
            local $ENV{PERL5OPT} = CPANPLUS::inc->original_perl5opt || ''; 
    
            ### make sure it's a string, so that mmflags that have more than
            ### one key value pair are passed as is, rather than as:
            ### perl Makefile.PL "key=val key=>val"
            my $captured; my $makefile_pl = MAKEFILE_PL->();
            unless(scalar run(  command => "$perl $makefile_pl $mmflags",
                                buffer  => \$captured,
                                verbose => $run_verbose, # may be interactive   
            ) ) {
                error( loc( "Could not run '%1 %2': %3 -- cannot continue",
                            $perl, MAKEFILE_PL->(), $captured ) );
                
                $dist->status->makefile(0);
                $fail++; last RUN;
            }
        }
        
        ### if we got here, we managed to make a 'makefile' ###
        $dist->status->makefile( MAKEFILE->($dir) );               
        
        ### start resolving prereqs ###
        my $prereqs = $self->status->prereqs;
        
        ### a hashref of prereqs on success, undef on failure ###
        $prereqs    ||= $dist->_find_prereqs( 
                                    verbose => $verbose,
                                    file    => $dist->status->makefile 
                                );
        
        unless( $prereqs ) {
            error( loc( "Unable to scan '%1' for prereqs", 
                        $dist->status->makefile ) );
        } else {
            $self->status->prereqs( $prereqs ); 
        
            ### this will set the directory back to the start
            ### dir, so we must chdir /again/           
            my $ok = $dist->_resolve_prereqs(
                                format   => $prereq_format,
                                verbose  => $verbose,
                                prereqs  => $prereqs,
                                target   => $prereq_target
                        
                        );
            
            unless( $cb->_chdir( dir => $dir ) ) {
                error( loc( "Could not chdir to build directory '%1'", $dir ) );
                return;
            }       
                      
            unless( $ok ) {
           
                #### use $dist->flush to reset the cache ###
                error( loc( "Unable to satisfy prerequisites for '%1' " .
                            "-- aborting install", $self->module ) );    
                $dist->status->make(0);
                $fail++; $prereq_fail++;
                last RUN;
            } 
        }      
        ### end of prereq resolving ###    
        
        my $captured;
        
        ### 'make' section ###    
        if( -d BLIB->($dir) && (-M BLIB->($dir) < -M $dir) && !$force ) {
            msg(loc("Already ran '%1' for this module [%2] -- " .
                    "not running again unless you force", 
                    $make, $self->module ), $verbose );
        } else {
            unless(scalar run(  command => [$make, $makeflags],
                                buffer  => \$captured,
                                verbose => $verbose ) 
            ) {
                error( loc( "MAKE failed: %1 %2", $!, $captured ) );
                $dist->status->make(0);
                $fail++; last RUN;
            }
            
            $dist->status->make(1);

            ### add this directory to your lib ###
            $cb->_add_to_includepath(
                directories => [ BLIB_LIBDIR->( $self->status->extract ) ]
            );
            
            last RUN if $skiptest;
        }
        
        ### 'make test' section ###                                           
        unless( $skiptest ) {

            ### turn off our PERL5OPT so no modules from CPANPLUS::inc get
            ### included in make test -- it should build without
            ### also, modules that run in taint mode break if we leave
            ### our code ref in perl5opt
            local $ENV{PERL5OPT} = CPANPLUS::inc->original_perl5opt || '';
        
            ### you can turn off running this verbose by changing
            ### the config setting below, although it is really not 
            ### recommended
            my $run_verbose =   
                        $verbose || 
                        $conf->get_conf('allow_build_interactivity') ||
                        0;

            ### XXX need to add makeflags here too? 
            ### yes, but they should really be split out -- see bug #4143
            unless(run( command => [$make, 'test', $makeflags],
                        buffer  => \$captured,
                        verbose => $run_verbose,
            ) ) {
                error( loc( "MAKE TEST failed: %1 %2", $!, $captured ) );
            
                ### send out error report here? or do so at a higher level?
                ### --higher level --kane.
                $dist->status->test(0);
               
                unless( $force ) {
                    $fail++; last RUN;     
                }
            
            } else {
                $dist->status->test(1);
            }
        }
    } #</RUN>
      
    unless( $cb->_chdir( dir => $orig ) ) {
        error( loc( "Could not chdir back to start dir '%1'", $orig ) );
    }  
    
    ### send out test report?
    ### only do so if the failure is this module, not its prereq
    if( $conf->get_conf('cpantest') and not $prereq_fail) {
        $cb->_send_report( 
            module  => $self,
            failed  => $fail,
            buffer  => CPANPLUS::Error->stack_as_string,
            verbose => $verbose,
            force   => $force,
        ) or error(loc("Failed to send test report for '%1'",
                    $self->module ) );
    }            
            
    return $dist->status->created( $fail ? 0 : 1);
} 

=pod

=head2 $href = $dist->_find_prereqs( file => '/path/to/Makefile', [verbose => BOOL])

Parses a C<Makefile> for C<PREREQ_PM> entries and distills from that
any prerequisites mentioned in the C<Makefile>

Returns a hash with module-version pairs on success and false on
failure.

=cut

sub _find_prereqs {
    my $dist = shift;
    my $self = $dist->parent;
    my $cb   = $self->parent;
    my $conf = $cb->configure_object;
    my %hash = @_;

    my ($verbose, $file);
    my $tmpl = {
        verbose => { default => $conf->get_conf('verbose'), store => \$verbose },
        file    => { required => 1, allow => FILE_READABLE, store => \$file },
    };
    
    my $args = check( $tmpl, \%hash ) or return;      
    
    my $fh = FileHandle->new();
    unless( $fh->open( $file ) ) {
        error( loc( "Cannot open '%1': %2", $file, $! ) );
        return;
    }
    
    my %p;
    while( <$fh> ) {
        my ($found) = m|^[\#]\s+PREREQ_PM\s+=>\s+(.+)|;         
        
        next unless $found;
        
        while( $found =~ m/(?:\s)([\w\:]+)=>(?:q\[(.*?)\],?|undef)/g ) {
            if( defined $p{$1} ) {
                msg(loc("Warning: PREREQ_PM mentions '%1' more than once. " .
                        "Last mention wins.", $1 ), $verbose );
            }
            
            $p{$1} = $cb->_version_to_number(version => $2);                  
        }
        last;
    }

    $self->status->prereqs( \%p );
    
    ### just to make sure it's not the same reference ###
    return { %p };                              
}       

=pod

=head2 $bool = $dist->install([make => '/path/to/make',  makemakerflags => 'EXTRA=FLAGS', force => BOOL, verbose => BOOL])

C<install> runs the following command:
    make install

Returns true on success, false on failure.    

=cut

sub install {
    ### just in case you did the create with ANOTHER dist object linked
    ### to the same module object
    my $dist = shift();
    my $self = $dist->parent;
    $dist    = $self->status->dist_cpan if $self->status->dist_cpan;       
   
    my $cb   = $self->parent;
    my $conf = $cb->configure_object;
    my %hash = @_;
    
    
    unless( $dist->status->created ) {
        error( loc( "You have not successfully created a '%2' distribution yet " .
                    "-- cannot install yet", __PACKAGE__ ) );
        return;
    }
 
    my $dir;
    unless( $dir = $self->status->extract ) {
        error( loc( "No dir found to operate on!" ) );
        return;
    }
    
    ### value set and false -- means failure ###
    if( defined $self->status->installed && !$self->status->installed ) {
        error( loc( "Module '%1' has failed to install before this session " .
                    "-- aborting install", $self->module ) );
        return;
    }
    
    my $args;
    my($force,$verbose,$make,$makeflags);
    {   local $Params::Check::ALLOW_UNKNOWN = 1;
        my $tmpl = {
            force       => {    default => $conf->get_conf('force'), 
                                store   => \$force },
            verbose     => {    default => $conf->get_conf('verbose'), 
                                store   => \$verbose },
            make        => {    default => $conf->get_program('make'), 
                                store   => \$make },
            makeflags   => {    default => $conf->get_conf('makeflags'), 
                                store   => \$makeflags },
        };      
    
        $args = check( $tmpl, \%hash ) or return;
    }
            
    $dist->status->_install_args( $args );
    
    my $orig = cwd();
    unless( $cb->_chdir( dir => $dir ) ) {
        error( loc( "Could not chdir to build directory '%1'", $dir ) );
        return;
    }
    
    my $fail; my $captured;
    
    ### 'make install' section ###
    ### XXX need makeflags here too? 
    ### yes, but they should really be split out.. see bug #4143
    my $cmd     = [$make, 'install', $makeflags];
    my $sudo    = $conf->get_program('sudo');
    unshift @$cmd, $sudo if $sudo;
    
    unless(scalar run(  command => $cmd,
                        verbose => $verbose,
                        buffer  => \$captured,
    ) ) {                   
        error( loc( "MAKE INSTALL failed: %1 %2", $!, $captured ) );
        $fail++; 
    }       
    
    unless( $cb->_chdir( dir => $orig ) ) {
        error( loc( "Could not chdir back to start dir '%1'", $orig ) );
    }   
    
    return $dist->status->installed( $fail ? 0 : 1 );
    
}

=pod

=head2 $bool = $dist->write_makefile_pl([force => BOOL, verbose => BOOL])

This routine can write a C<Makefile.PL> from the information in a 
module object. It is used to write a C<Makefile.PL> when the original
author forgot it (!!).

Returns 1 on success and false on failure.

The file gets written to the directory the module's been extracted 
to.

=cut

sub write_makefile_pl {
    ### just in case you already did a call for this module object
    ### just via a different dist object
    my $dist = shift;
    my $self = $dist->parent;
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
    
    my ($force, $verbose);
    my $tmpl = {
        force           => {    default => $conf->get_conf('force'),   
                                store => \$force },
        verbose         => {    default => $conf->get_conf('verbose'), 
                                store => \$verbose },   
    };                                          

    my $args = check( $tmpl, \%hash ) or return;    
    
    my $file = MAKEFILE_PL->($dir);
    if( -s $file && !$force ) {
        msg(loc("Already created '%1' - not doing so again without force", 
                $file ), $verbose );
        return 1;
    }     

    ### due to a bug with AS perl 5.8.4 built 810 (and maybe others)
    ### opening files with content in them already does nasty things;
    ### seek to pos 0 and then print, but not truncating the file
    ### bug reported to activestate on 19 sep 2004:
    ### http://bugs.activestate.com/show_bug.cgi?id=34051
    unlink $file if $force;

    my $fh = new FileHandle;
    unless( $fh->open( ">$file" ) ) {
        error( loc( "Could not create file '%1': %2", $file, $! ) );
        return;
    }
    
    my $mf      = MAKEFILE_PL->();
    my $name    = $self->module;
    my $version = $self->version;
    my $author  = $self->author->author;
    my $href    = $self->status->prereqs;
    my $prereqs = join ",\n", map { 
                                (' ' x 25) . "'$_'\t=> '$href->{$_}'" 
                            } keys %$href;  
    $prereqs ||= ''; # just in case there are none;                         
                             
    print $fh qq|
    ### Auto-generated $mf by CPANPLUS ###
    
    use ExtUtils::MakeMaker;
    
    WriteMakefile(
        NAME        => '$name',
        VERSION     => '$version',
        AUTHOR      => '$author',
        PREREQ_PM   => {
$prereqs                       
                    },
    );
    \n|;   
    
    $fh->close;
    return 1;
}                         
        
1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
