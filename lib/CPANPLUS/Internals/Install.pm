# $File: //member/autrijus/cpanplus/devel/lib/CPANPLUS/Internals/Install.pm $
# $Revision: #4 $ $Change: 3542 $ $DateTime: 2002/03/26 06:48:38 $

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

    for my $href ( @{$args{"modules"}} ) {


        ### check if we really got a hashref... just a double check ###
        ### this doesn't work, the objects are now blessed, so we get a package name back.
        #unless ( ref $href eq 'HASH' ) {
            
        ### assuming no one is stupid enough to overload the deref of a variable, this 
        ### should work well enough; -kane    
        unless ( ref $href eq 'CPANPLUS::Internals::Module' and "$href" =~ /HASH/ ) {
            $err->trap(error => qq[You did not pass a proper module object! @_ ($href)].ref($href));
            $flag = 1;
            next;
        }

        ### we use the name way too often, time to shortcut... ###
	    my $m = $href->{module};

        my $is_bundle = 1 if $m =~ /^bundle::/i;

        ### get a hashref with all module information ###
        #my $href;
        #unless( $href = $self->{_modtree}->{$m} ) {
        #    $err->trap( error => "could not find information for module $m" );
        #    $flag = 1;
        #    next;
        #}

        ### pass it to fetch, it knows how to get the right dir
        ### get the name of the file it fetched back
        my $file;
        unless ( $file = $self->_fetch(data => $href) ) {
            $err->trap( error => "could not fetch module $m" );
            $flag = 1;
            next;
        }

        ### in case of MD5 checks, we need the checksums and do the MD5
        ### check on them.
        ### this is hardcoded now, but should go into config:
        #my $check_md5 = 1;
        my $check_md5 = $conf->get_conf( 'md5' );


        if ($check_md5) {
            my $fetchdir = File::Spec->catdir (
                                $conf->_get_build('base'),
                                $conf->_get_ftp('base'),
                                $href->{path},
                            );

            my $cs_file;
            unless ( $cs_file = $self->_fetch(
                                    dir         => $conf->_get_ftp('base') . $href->{path},
                                    fetchdir    => $fetchdir,
                                    file        => 'CHECKSUMS',
                                    force       => 1,
                    )
            ) {
                $err->trap( error => "could not fetch 'CHECKSUMS' for $file" );
                $flag = 1;
                next;
            }


            unless ( $self->_check_md5(
                                checksum_file   => $cs_file,
                                data            => $href,
                   )
            ) {
                $err->trap( error => "Checksums did not match for $file" );
                $flag = 1;
                next;
            }
        }

        ### extract the file, get the location it extracted to
        my $dir;
        unless ( $dir = $self->_extract( data => $href, %args ) ) {
            $err->trap( error => "could not obtain extraction directory for module $m" );
            $flag = 1;
            next;
        }


        ### make'ing the target. we get a return value
        ### of 0 (failure), 1 (success) or an arrayref of prereqs
        ### in case we're not allowed to install them
        ### need to handle that case
        my $rv;
        unless ( $rv = $self->_make(dir => $dir, module => $href) ) {
            $err->trap( error => "error installing module $m" );
            $flag = 1;
            next;
        };

        if ( $is_bundle ) {
            my $res;
            unless ( $res = $self->_install_bundle( dir => [ $dir ] ) ) {
                $err->trap( error => "error installing bundle $m" );
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
        my $dh = new FileHandle;

        ### open the dir of the newly extracted bundle
        opendir $dh, "$dir" or (
            $err->trap( error => "error opening dir $dir: $!" ) &&
            ($flag = 1) && next
        );

        ### find all files in the dir that end in '.pm'
        my @files = grep { m|\.pm$|i && -f File::Spec->catfile( $dir, $_ ) } readdir $dh;
        closedir $dh;

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
                : ( $self->{_modtree}->{$args{module}}->{version} || '0.0' );
                #: $self->{_modtree}->{$args{module}}->{version};

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
### bug: we can't update the packlist properly.. so it will seem like the modules are
### still around... so we need some fixes here... -kane
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
        return 0;
    }

    my $flag;
    for my $file ( @$files ) {
        $err->inform( msg => qq[unlinking $file], quiet => !$conf->get_conf('verbose') );
        unless (unlink $file) {
            $err->trap( error => qq[could not unlink $file: $!] );
            $flag = 1;
        }
    }

    return $flag ? 0 : 1;
}

sub _check_md5 {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $href = $args{'data'};

    ### check prerequisites
    my $use_list = { 'Digest::MD5' => '0.0' };

    if ($self->_can_use($use_list)) {

        my $file = File::Spec->catfile(
                        $conf->_get_build('base'),
                        $conf->_get_ftp('base'),
                        $href->{'path'},
                        $href->{'package'}
                    );

        my $fh = new FileHandle;
        $fh->open($args{'checksum_file'})
                or $err->trap( error => "Could not open $args{checksum_file}: $!" );

        my $in;
        { local $/; $in = <$fh> }
        $fh->close;

        ### open the archive file ###
        $fh->open($file) or $err->trap( error => "Could not open $file: $!" );

        ### set binmode, VERY important on windows
        binmode $fh;

        ### calculate the MD5 of that file ###
        my $md5 = Digest::MD5->new;
        $md5->addfile($fh);
        my $digest = $md5->hexdigest;

        ### eval into life the checksums file
        ### another way would be VERY nice - kane
        my $cksum;
        {   #local $@; can't use this, it's buggy -kane
            $cksum = eval $in or $err->trap( error => "eval error on checksums file: $@" );
        }

        #print "CHECKSUM IN FILE: $cksum->{ $href->{package} }->{md5} \n";
        #print "CHECKSUM FOUND: $digest\n";

        if ( $cksum->{ $href->{'package'} }->{'md5'} eq $digest ) {
            return 1;
        } else {
            $err->trap( error => "MD5 sums did not add up for $href->{package}" );
            return 0;
        }
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
