# $File$
# $Revision$ $Change$ $DateTime$

#######################################################
###           CPANPLUS/Internals/Install.pm         ###
###     Subclass to install modules for cpanplus    ###
###         Written 12-03-2002 by Jos Boumans       ###
#######################################################

### Install.pm ###

package CPANPLUS::Internals::Install;

use strict;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use DirHandle;
use FileHandle;
use Data::Dumper;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

### method to install modules from CPAN. does everything from fetching the file, to installing it ###
sub _install_module {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $flag;

    for my $href ( @{$args{'modules'}} ) {
        ### assuming no one is stupid enough to overload the deref of a variable, this
        ### should work well enough; -kane
        ### let's allow subclassing here -autrijus

        unless ( UNIVERSAL::isa( $href, 'CPANPLUS::Internals::Module' ) ) {
            $err->trap(
                error => "You did not pass a proper module object! @_ ($href)".
                         ref($href),
            );
            $flag = 1;
            next;
        }

        ### we use the name way too often, time to shortcut... ###
            my $m = $href->{module};

        ### check if any of the prereqs we're about to install wants us to get
        ### a newer version of perl... if so, skip, we dont want to upgrade perl
        if ($m =~ /^base$/i or $href->{package} =~ /^perl-\d/i ) {
            $err->inform(
                msg => "Cannot fetch $m (part of core perl distribution); skipping",
            );

            next;
        }

        my $is_bundle = 1 if $m =~ /^bundle::/i;

        ### get a hashref with all module information ###
        #my $href;
        #unless( $href = $self->_module_tree->{$m} ) {
        #    $err->trap( error => "could not find information for module $m" );
        #    $flag = 1;
        #    next;
        #}

        ### pass it to fetch, it knows how to get the right dir
        ### get the name of the file it fetched back
        my $file;
        unless ( $file = $self->_fetch(data => $href) ) {
            $err->trap( error => qq[Could not fetch module $m] );
            $flag = 1;
            next;
        }

        ### in case of MD5 checks, we need the checksums and do the MD5
        ### check on them.
        ### this is hardcoded now, but should go into config:
        #my $check_md5 = 1;
        my $check_md5 = $conf->get_conf( 'md5' );


        if ($check_md5) {
            unless ( $self->_check_md5(
                        data        => $href,
                    )
             ) {
                $err->trap( error => qq[Checksums did not match for $file] );
                $flag = 1;
                next;
            }
        }

        ### extract the file, get the location it extracted to
        my $dir;
        unless ( $dir = $self->_extract( data => $href, %args ) ) {
            $err->trap( error => qq[Could not obtain extraction directory for module $m] );
            $flag = 1;
            next;
        }


        ### make'ing the target. we get a return value
        ### of 0 (failure), 1 (success) or an arrayref of prereqs
        ### in case we're not allowed to install them
        ### need to handle that case
        my $rv;
        unless ( $rv = $self->_make(dir => $dir, module => $href, %args) ) {
            $err->trap( error => qq[Error installing module $m] );
            $flag = 1;
            next;
        };

        if ( $is_bundle ) {
            my $res;
            unless ( $res = $self->_install_bundle( dir => [ $dir ], %args) ) {
                $err->trap( error => qq[Error installing bundle $m] );
                $flag = 1;
                next;
            };
        }

    }

    ### perhaps we need to set a flag on how many/if modules succeeded/failed,
    ### and base our return value on that
    return $flag ? 0 : 1;

} #_install_module

### this method contains logic to install a bundle from cpan.
### bundles right now come in 2 flavors:
### 1: a big archive file with all the modules in it
### 2: an archive labeled bundle::foo with a foo.pm file in it's root,
### containing a list of modules that are part of the bundle in a certain format
sub _install_bundle {
    my $self = shift;
    my %args = @_;

    my $err = $self->{_error};

    my $flag;
    for my $dir ( @{$args{'dir'}} ) {
        my $dh = new DirHandle;

        ### open the dir of the newly extracted bundle
        unless ($dh->opendir($dir)) {
            $err->trap( error => "error opening dir $dir: $!" );
            $flag = 1; next;
        }

        ### find all files in the dir that end in '.pm'
        my @files = grep { m|\.pm$|i && -f File::Spec->catfile( $dir, $_ ) } $dh->readdir;
        $dh->closedir;

        ### if there are .pm files we'll check them one by one for files to install
        ### although there really should be only ONE
        if ( @files ) {
            for my $file ( @files ) {
                ### if it was a .pm with a list of files in it, they'll be in the array ref $list
                my $list;
                unless ( $list = $self->_bundle_files( file => File::Spec->catfile( $dir, $file ) ) ) {
                    $err->trap( error => "could not obtain required modules from $file" );
                    $flag=1; next;
                }

                ### tell the user there were no modules mentioned in $file,
                ### meaning it was probably a 'normal' .pm file
                unless ( scalar @$list ) {
                    $err->msg( inform => "No modules mentioned in $file" );
                    next;
                }

                ### install all the modules that were stored in $list
                my $rv;
                unless( $rv = $self->_install_module( modules => $list ) ) {
                    $err->trap( error => "An error occurred while installing bundles from $file" );
                    $flag=1; next;
                }
            }
        } else {
            $err->trap( error => "no .pm files found in $dir!" );
            next;
        }
    }

    return $flag ? 0 : 1;
}

### method to read the names of modules that are mentioned in a bundle
sub _bundle_files {
    my $self = shift;
    my %args = @_;
    my $err  = $self->{_error};

    my $fh = new FileHandle;
    $fh->open($args{file}) or (
        $err->trap( error => qq[could not open $args{file}: $!] ),
        return 0
    );

    my (@list, $flag);
    while(<$fh>) {
        ### quick hack to read past the header of the file ###
        last if $flag && m|^=head|i;

        ### from perldoc cpan:
        ### =head1 CONTENTS
        ### In this pod section each line obeys the format
        ### Module_Name [Version_String] [- optional text]
        $flag = 1 if m|^=head1 CONTENTS|i;

        push @list, $1 if $flag && /^(?!=)(\S+)/;
    }
    return \@list;
}



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
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $version = defined $args{version} # prevent warnings
                ? $args{version}
                : ( $self->_module_tree->{$args{module}}->{version} || '0.0' );

    ### avoid the 'undef' isn't numeric - warning ###
    $version = '0.0', if $version =~ /^undef/i;

    my $module = File::Spec->catfile( split(/::/, $args{module}) );

    my $href;

    ### allow for extra dirs to be scanned, that might not be in @INC ###
    DIR: for my $dir ( @INC ) {
        my $filename = File::Spec->catfile($dir, "$module.pm");

        if (-e $filename ) {

            ### defaults ###
            $href = {
                file        => $filename,
                uptodate    => 0,
                version     => 0,
            };

            my $fh = new FileHandle;
            if ($fh->open($filename)) {

                local $_; # the 'while (<IN>)' has issues -jmb
                while (<$fh>) {

                    # the following regexp comes from the ExtUtils::MakeMaker
                    # documentation.
                    if (/([\$*])(([\w\:\']*)\bVERSION)\b.*\=/) {

                        ### this will eval the version in to $VERSION if it
                        ### was declared as $VERSION in the module.
                        ### else the result will be in $res.
                        ### this is a fix on skud's Module::InstalledVersion
                        {   local $VERSION;
                            #local $@; - can't use this, it's buggy -kane
                            my $res = eval $_;

                            ### default to '0.0' if there REALLY is no version
                            ### all to satisfy warnings
                            #$href->{version} = $VERSION || $res;
                            $href->{version} = $VERSION || $res || '0.0';

                            $href->{uptodate} = 1 if ($version <= $href->{version});
                            close $fh;
                            return $href;
                        }
                    }
                }

                ### if we got here, we didn't find the version
                $err->inform(
                    msg     => "Can't check version on $args{module}... assuming it's up to date",
                    quiet   => !$conf->get_conf('verbose')
                );
                $href->{uptodate} = 1;

            } else {
                $err->trap( error => "Can't open $filename: $!" );
            }
            close $fh;
        }
    }
    
    return $href;
}

### uninstall a module ###
sub _uninstall {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    ### all to please warnings...
    my $mod = $args{'module'};

    ### we can pass the arguments straight on to _files()
    my $files;
    unless ( $files = $self->_files(%args) ) {
        $err->trap( error => qq[No files found for $mod!] );
        return;
    }

    ### ditto for _directories()
    my $dirtree;
    unless ( $dirtree = $self->_directories(%args) ) {
        $err->trap( error => qq[No directory tree found for $mod!] );
        return;
    }

    ### remove the packlist file altogether
    my $flag;
    for my $file ( @$files, $self->_packlist_file(%args)) {
        $err->inform( 
                    msg     => qq[unlinking $file], 
                    quiet   => !$conf->get_conf('verbose') 
                );
        
        unless (unlink $file) {
            $err->trap( error => qq[could not unlink $file: $!] );
            $flag = 1;
        }
    }

    for my $dir ( sort @$dirtree ) {
        $err->inform( 
                    msg     => qq[removing $dir], 
                    quiet   => !$conf->get_conf('verbose') 
                );

        ### Check if the $dir is empty
        local *DIR;
        opendir DIR, $dir;
        my @count = readdir(DIR);
        close DIR;

        next unless @count == 2; # . and ..

        unless (rmdir $dir) {
            $err->trap( error => qq[could not remove $dir: $!] );
            $flag = 1;
        }
    }

    return !$flag;
}

sub _check_md5 {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $href = $args{'data'};

    ### check prerequisites
    my $use_list = { 'Digest::MD5' => '0.0' };

    if ($self->_can_use(modules => $use_list)) {

        my $basedir = File::Spec->catdir(
                        $conf->_get_build('base'),
                        $conf->_get_ftp('base'),
                        $href->{'path'},
                    );

        ### full path to both the archive and the checksums file ###
        my $archive = File::Spec->catfile( $basedir, $href->{'package'} );
        my $cs_file = File::Spec->catfile( $basedir, 'CHECKSUMS' );

        my $fh = new FileHandle;

        ### open the archive file ###
        unless ( $fh->open($archive) ) {
            $err->trap( error => "Could not open $archive: $!" );
            return 0;
        }

        ### set binmode, VERY important on windows ###
        binmode $fh;

        ### calculate the MD5 of that file ###
        my $md5 = Digest::MD5->new;
        $md5->addfile($fh);
        my $digest = $md5->hexdigest;


        ### make a note wether or not we already had a CHECKSUMS file on our disk ###
        my $flag;
        if ( -e $cs_file ) { $flag = 1 }

        my $checksums = $self->_get_checksums( mod => $href );

        CHECK: {
            if ( $checksums->{ $href->{'package'} }->{'md5'} eq $digest ) {
                $err->inform( 
                        msg     => qq[Checksum for $archive OK],
                        quiet   => !$conf->get_conf('verbose')
                );          
                return 1;
            
            } else {
                if ( !$flag and defined $checksums->{$href->{'package'}} ) {
                    ### if we didnt already have a checksums file on our disk, we might have
                    ### an outdated one... in that case we'll refetch it and try again to see
                    ### if we get a matching MD5 -kane

                    $checksums = $self->_get_checksums( mod => $href, force => 1 );
                    $flag = 1;
                    redo CHECK;

                } else {
                    $err->trap( error => "MD5 sums did not add up for $href->{package}" );
                    return 0;
                }
            }
        } #CHECK

    } else {

        $err->trap(
            error => "You don't have Digest::MD5! " .
                     "Please install it as soon as possible! " .
                     "Assuming $href->{package} is trustworthy"
            );
        return 1;
    }
}

1;
