# $File: //depot/cpanplus/dist/lib/CPANPLUS/Internals/Install.pm $
# $Revision: #11 $ $Change: 11204 $ $DateTime: 2004/09/20 20:15:05 $

#######################################################
###           CPANPLUS/Internals/Install.pm         ###
###     Subclass to install modules for cpanplus    ###
###         Written 12-03-2002 by Jos Boumans       ###
#######################################################

### Install.pm ###

package CPANPLUS::Internals::Install;

use strict;
use Cwd;
use DirHandle;
use FileHandle;
use Data::Dumper;
use CPANPLUS::I18N;
use CPANPLUS::Tools::Check qw[check];
use CPANPLUS::Tools::Module qw[check_install];
BEGIN {
    use vars        qw( $VERSION );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

### method to install modules from CPAN. does everything from fetching the file, to installing it ###
sub _install_module {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    local $CPANPLUS::Tools::Check::ALLOW_UNKNOWN = 1;

    my $tmpl = {
        modules => { required => 1, default => [], strict_type => 1 },
        verbose => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $mods        = {};

    for my $modobj ( @{ delete $args->{'modules'} } ) {

        ### flag to see if an install failed somewhere ###
        my $fail = 0;

        ### container for the module name ###
        my $m;

        LOOP: {

            ### assuming no one is stupid enough to overload the deref of a variable, this
            ### should work well enough; -kane
            ### let's allow subclassing here -autrijus

            unless ( UNIVERSAL::isa( $modobj, 'CPANPLUS::Internals::Module' ) ) {
                $err->trap(
                    error => loc("You did not pass a proper module object! %1 (%2)", "@_", $modobj).
                             ref($modobj),
                );

                ### mark we did nothing for this module ###
                $fail = 1;
                last LOOP;
            }

            ### we use the name way too often, time to shortcut... ###
            $m = $modobj->module();

            ### store we actually did something here ###
            $mods->{$m} = $modobj;

            ### check if any of the prereqs we're about to install wants us to get
            ### a newer version of perl... if so, skip, we dont want to upgrade perl
            if ($modobj->package =~ /^perl-\d/i ) {
                $err->inform(
                    msg => loc("Cannot fetch %1 (part of core perl distribution); skipping", $m),
                );

                ### mark we did nothing for this module ###
                $fail = 1;
                last LOOP;
            }

            my $is_bundle = 1 if $m =~ /^bundle::/i;

            ### get a hashref with all module information ###
            #my $modobj;
            #unless( $modobj = $self->_module_tree->{$m} ) {
            #    $err->trap( error => "could not find information for module $m" );
            #    $flag = 1;
            #    next;
            #}

            ### pass it to fetch, it knows how to get the right dir
            ### get the name of the file it fetched back
            my $file;
            unless ( $file = $self->_fetch( data => $modobj ) ) {
                $err->trap( error => qq[Could not fetch module $m] );

                $fail = 1;
                last LOOP;
            }

            ### store where we fetched the file ###
            $modobj->status->fetch( $file );

            ### in case of MD5 checks, we need the checksums and do the MD5
            ### check on them.
            ### this is hardcoded now, but should go into config:
            #my $check_md5 = 1;
            my $check_md5 = $conf->get_conf( 'md5' );


            if ($check_md5) {
                unless ( $self->_check_md5( data => $modobj ) ) {
                    $err->trap( error => loc("Checksums did not match for %1", $file) );

                    $fail = 1;
                    last LOOP;
                }
            }

            $modobj->status->md5(1);

            my $check_signature = $conf->get_conf( 'signature' );
            if ($check_md5 and $check_signature) {
                # checking for detached signature, if any.
                unless ($self->_check_detached_signature( mod => $modobj )) {
                    $err->trap( error => loc("Signature checking failed for %1", $file) );
                    $fail = 1;
                    last LOOP;
                }
            }

            ### extract the file, get the location it extracted to
            my $dir;
            unless ( $dir = $self->_extract( data => $modobj, %$args ) ) {
                $err->trap( error => loc("Could not obtain extraction directory for module %1", $m) );

                $fail = 1;
                last LOOP;
            }

            $modobj->status->extract( $dir );

            if ($check_signature) {
                unless ( $self->_check_signature( dir => $dir ) ) {
                    $err->trap( error => loc("Signature checking failed for %1", $file) );

                    $fail = 1;
                    last LOOP;
                }
            }

            $modobj->status->signature(1);

            ### make'ing the target. we get a return value
            ### that is a hash ref of module names and their objects
            ### we'll have to examine the rv to see if the overall
            ### make for *this* module went ok
            my $rv = $self->_make(dir => $dir, module => $modobj, %$args);

            ### XXX this needs fixink for new Status.pm!!! XXX ###
            unless ( $rv->{ $modobj->module() }->{make}->{overall} ) {
                $err->trap( error => loc("An error occurred handling module %1", $m) );

                $fail = 1;
                last LOOP;
            };

            ### store the status explicitly for the module of this session ###
            ### XXX this needs fixink for new Status.pm!!! XXX ###
            #$modobj->status->make( $rv->{$m}->{make} );

            ### make's rv is special, since it can contain full module install's
            ### data, and also for modules then we tried to install here (prereqs)
            ### we'll have to loop over the keys and store that we fiddled with them
            for my $modname ( sort keys %$rv ) {
                ### obsolete, we'll overwrite anyway at the end of the loop
                #unless( $m eq $modname ) {
                    $mods->{$modname} = $self->module_tree->{$modname}
                #}
            }

            if ( $is_bundle ) {
                my $res;
                unless ( $res = $self->_install_bundle( dir => [ $dir ], %$args) ) {
                    $err->trap( error => loc("An error occurred handling bundle %1", $m) );

                    $fail = 1;
                    last LOOP;
                };
                $modobj->status->bundle( $res );
            }

        } # LOOP

        # don't set this, since we may have not actually installed,
        # but just tested or so
        #$modobj->status->install( !$fail );

        ### refresh the data in $mods ###
        $mods->{$m} = $modobj;
    }


    ### perhaps we need to set a flag on how many/if modules succeeded/failed,
    ### and base our return value on that
    ### return $flag ? 0 : 1;

    ### this needs fixink for new Status.pm!!! ###
    #my %return = map { my $m = $_->module(); $m => {%{$_->{status}}} } values %$mods;

    ### Fix:
    my %return = map { $_->module => $_->status } values %$mods;

    return \%return;

} #_install_module

### this method contains logic to install a bundle from cpan.
### bundles right now come in 2 flavors:
### 1: a big archive file with all the modules in it
### 2: an archive labeled bundle::foo with a foo.pm file in it's root,
### containing a list of modules that are part of the bundle in a certain format
sub _install_bundle {
    my $self = shift;
    my %hash = @_;
    my $err  = $self->error_object;
    my $conf = $self->configure_object;


    my $tmpl = {
        dir     => { required => 1, default => [], strict_type => 1 },
        verbose => { default => $conf->get_conf('verbose') },
        prereq_target => { default => 'install' },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose = $args->{verbose};
    my $prereq_target = $args->{prereq_target};

    my $flag;
    for my $dir ( @{$args->{'dir'}} ) {
        my $dh = new DirHandle;

        ### open the dir of the newly extracted bundle
        unless ($dh->open($dir)) {
            $err->trap( error => loc("error opening dir %1: %2", $dir, $!) );
            $flag = 1; next;
        }

        ### find all files in the dir that end in '.pm'
        my @files = grep { -f } map { File::Spec->catfile($dir, $_) }
            grep { m|\.pm$|i } $dh->read;
        $dh->close;

        my $lib_dir = File::Spec->catdir( $dir, 'lib', 'Bundle' );
        if (-d $lib_dir and $dh->open($lib_dir)) {
            push @files, grep { -f } map { File::Spec->catfile($lib_dir, $_) }
                grep { m|\.pm$|i } $dh->read;
            $dh->close;
        }

        ### if there are .pm files we'll check them one by one for files to install
        ### although there really should be only ONE
        if ( @files ) {
            for my $file ( @files ) {
                ### if it was a .pm with a list of files in it, they'll be in the array ref $list
                my $list;
                unless ( $list = $self->_bundle_files( file => $file ) ) {
                    $err->trap( error => loc("could not obtain required modules from %1", $file) );
                    $flag=1; next;
                }

                ### tell the user there were no modules mentioned in $file,
                ### meaning it was probably a 'normal' .pm file
                unless ( scalar @$list ) {
                    $err->inform( msg => loc("No modules mentioned in %1", $file) );
                    next;
                }

                ### install all the modules that were stored in $list
                my $rv = $self->install(
                    modules         => $list,
                    target          => $prereq_target,
                    prereq_target   => $prereq_target,
                );
                unless ($rv) {
                    $err->trap( error => loc("An error occurred while installing bundles from %1", $file) );
                    $flag=1; next;
                }
            }
        } else {
            $err->trap( error => loc("no .pm files found in %1!", $dir) );
            next;
        }
    }

    return $flag ? 0 : 1;
}

### method to read the names of modules that are mentioned in a bundle
sub _bundle_files {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        file    => { required => 1, allow => sub { -e pop() && -s _ }  },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose = $args->{verbose};

    my $fh = new FileHandle;
    $fh->open($args->{file}) or (
        $err->trap( error => qq[could not open $args->{file}: $!] ),
        return 0
    );

    my (@list, $flag);
    my $modtree = $self->module_tree;

    while(<$fh>) {
        ### quick hack to read past the header of the file ###
        last if $flag && m|^=head|i;

        ### from perldoc cpan:
        ### =head1 CONTENTS
        ### In this pod section each line obeys the format
        ### Module_Name [Version_String] [- optional text]
        $flag = 1 if m|^=head1 CONTENTS|i;

        if ($flag && /^(?!=)(\S+)/) {
            my ($name, $modobj) = $self->_parse_module( mod => $1 );

            unless ($modobj) {
                $err->trap( error => loc("Cannot install bundled module: %1 does not exist!", $name) );
                next;
            }

            $err->inform(
                msg   => loc("Installing bundled module: %1", $name),
                quiet => !$verbose,
            );

            push @list, $modobj;
        }
    }
    return \@list;
}


### XXX this one can be replaced by CPANPLUS::Tools::Module::check_install()
### XXX but it would have to have the localization redone

### this checks if a certain module is installed already ###
### if it returns true, the module in question is already installed
### or we found the file, but couldn't open it, OR there was no version
### to be found in the module
### it will return 0 if the version in the module is LOWER then the one
### we are looking for, or if we couldn't find the desired module to begin with
### if the installed version is higher or equal to the one we want, it will return
### a hashref with he module name and version in it.. so 'true' as well.
sub _check_install {
    my $self = shift;
    my %hash = @_;
    my $err  = $self->error_object;
    my $conf = $self->configure_object;

    local $CPANPLUS::Tools::Check::ALLOW_UNKNOWN = 1;

    my $tmpl = {
            module  => { required   => 1        },
            verbose => { default    => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    if (my $href = check_install(%hash)) {
        return $href;
    } else {
        $self->error_object->trap(
                    error => loc(qq[Could not find '%1'], $args->{module})
                ) if $args->{verbose};
        return undef;
    }
}

### uninstall a module ###
sub _uninstall {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    local $CPANPLUS::Tools::Check::ALLOW_UNKNOWN = 1;

    my $tmpl = {
        module  => { required => 1 },
        verbose => { default => $conf->get_conf('verbose') },
    };
    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose = $args->{verbose};
    my $mod     = $args->{module};


    ### we can pass the arguments straight on to _files()
    my $files;
    unless ( $files = $self->_files(%$args) ) {
        $err->trap( error => loc("No files found for %1!", $mod) );
        return;
    }

    ### ditto for _directories()
    my $dirtree;
    unless ( $dirtree = $self->_directories(%$args) ) {
        $err->trap( error => loc("No directory tree found for %1!", $mod) );
        return;
    }

    ### remove the packlist file altogether
    my $flag;
    for my $file ( @$files, $self->_packlist_file(%$args)) {
        $err->inform(
                    msg     => loc("unlinking %1", $file),
                    quiet   => !$verbose
                );

        unless (unlink $file) {
            $err->trap( error => loc("could not unlink %1: %2", $file, $!) );
            $flag = 1;
        }
    }

    for my $dir ( sort @$dirtree ) {

        local *DIR;
        opendir DIR, $dir;
        my @count = readdir(DIR);
        close DIR;

        next unless @count == 2; # . and ..

        $err->inform(
                    msg     => loc("removing %1", $dir),
                    quiet   => !$verbose
                );

        unless (rmdir $dir) {

            ### this fails on my win2k machines.. it indeed leaves the
            ### dir, but it's not a critical error, since the files have
            ### been removed. --kane
            $err->trap( error => loc("could not remove %1: %2", $dir, $!) )
                unless $^O eq 'MSWin32';
        }
    }

    return !$flag;
}

sub _check_md5 {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        verbose     => { default => $conf->get_conf('verbose') },
        data        => { allow => sub { ref $_[1] &&
                                        $_[1]->isa('CPANPLUS::Internals::Module')
                                  } },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $modobj  = $args->{'data'};
    my $verbose = $args->{verbose};

    ### check prerequisites
    my $use_list = { 'Digest::MD5' => '0.0' };

    if ($self->_can_use(modules => $use_list)) {

        my $basedir = File::Spec->catdir(
                        $conf->_get_build('base'),
                        $conf->_get_ftp('base'),
                        $modobj->path,
                    );

        ### full path to both the archive and the checksums file ###
        my $archive = File::Spec->catfile( $basedir, $modobj->package );
        my $cs_file = File::Spec->catfile( $basedir, 'CHECKSUMS' );

        my $fh = new FileHandle;

        ### open the archive file ###
        unless ( $fh->open($archive) ) {
            $err->trap( error => loc("Could not open %1: %2", $archive, $!) );
            return undef;
        }

        ### set binmode, VERY important on windows ###
        binmode $fh;

        ### calculate the MD5 of that file ###
        my $md5 = Digest::MD5->new;
        $md5->addfile($fh);
        my $digest = $md5->hexdigest;


        ### make a note wether or not we already had a CHECKSUMS file on our disk ###
        my $flag;
        if ( -e $cs_file ) { $flag = 1; }

        my $checksums = $self->_get_checksums( mod => $modobj );

        CHECK: {
            if ( $checksums and $checksums->{ $modobj->package }->{'md5'} eq $digest ) {
                $err->inform(
                        msg     => loc("Checksum for %1 OK", $archive),
                        quiet   => !$verbose
                );
                return 1;

            } elsif ( $flag and (!$checksums or !(keys %{$checksums->{ $modobj->package }})) ) {
                    ### if we didnt already have a checksums file on our disk, we might have
                    ### an outdated one... in that case we'll refetch it and try again to see
                    ### if we get a matching MD5 -kane
                    unless( $checksums = $self->_get_checksums( mod => $modobj, force => 1 ) ) {
                        $err->trap(
                            error => loc("Unable to fetch checksums file! Can not verify this distribution is safe!") );
                        return undef;
                    }

                    $flag = 1;
                    redo CHECK;

            } else {
                $err->trap( error => loc("MD5 sums did not add up for %1", $modobj->package) );
                return undef;
            }
        } #CHECK

    } else {

        $err->trap(
            error => loc("You don't have %1! Please install it as soon as possible! Assuming %2 is trustworthy", "Digest::MD5", $modobj->package)
            );
        return 1;
    }
}

sub _check_signature {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        verbose     => { default => $conf->get_conf('verbose') },
        dir         => { allow => sub { -d pop() } },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose = $args->{verbose};
    my $dir     = $args->{'dir'};

    ### check prerequisites
    my $use_list = { 'Module::Signature' => '0.06' };

    if ($self->_can_use(modules => $use_list)) {
        my $old_cwd = Cwd::cwd();

        return undef unless $self->_chdir( dir => $dir );

        my $rv = Module::Signature::verify();

        if ($rv eq Module::Signature::SIGNATURE_OK() or
            $rv eq Module::Signature::SIGNATURE_MISSING()) {

            $self->_chdir( dir => $old_cwd );
            return 1;
        }

    } else {
        $err->trap(
            error => loc("You do not have %1! Please install it as soon as possible! ".
                         "Assuming %2 is trustworthy", "Module::Signature", $dir)
        );
        return 1;
    }

    return undef;
}


sub _check_detached_signature {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        mod         => { required => 1 },
        verbose     => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;
    my $modobj = $args->{mod};

    # XXX - more robust checking needed
    eval {
        $self->_get_checksums( mod => $modobj )->{ $modobj->package . ".sig"}
    } or return 1;

    my $local_file = $self->_get_detached_signature( mod => $modobj )
        or return undef;

    ### check prerequisites
    my $use_list = { 'Module::Signature' => '0.26' };

    if ($self->_can_use(modules => $use_list)) {
        return Module::Signature::_verify($local_file) == Module::Signature::SIGNATURE_OK();
    }
    else {
        $err->trap(
            error => loc("You do not have %1! Please install it as soon as possible! ".
                         "Assuming %2 is trustworthy", "Module::Signature", $modobj->package)
        );
        return 1;
    }
}

1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
