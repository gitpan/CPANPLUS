# $File: //depot/cpanplus/dist/lib/CPANPLUS/Internals/Extract.pm $
# $Revision: #8 $ $Change: 10305 $ $DateTime: 2004/03/03 11:54:09 $

#######################################################
###            CPANPLUS/Internals/Extract.pm        ###
###     Subclass to extract modules for cpanplus    ###
###         Written 23-02-2002 by Jos Boumans       ###
#######################################################

### Extract.pm ###

package CPANPLUS::Internals::Extract;

use strict;
use File::Path ();
use Data::Dumper;
use CPANPLUS::I18N;
use CPANPLUS::Tools::Check qw[check];


BEGIN {
    use vars        qw($VERSION);
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

sub _extract {
    my $self = shift;
    my %hash = @_;

    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    ### check if we got a specific file argument,
    ### or if we're trying to extract a package (module data)
    ### no argument supplied, we should return
    #my $file = $args{'file'} || $args{'data'}->{'package'} || return 0;


    my $tmpl = {
        file        => { default => '' },
        perl        => { default => $conf->_get_build('perl') || $^X },
        force       => { default => $conf->get_conf('force') },
        verbose     => { default => $conf->get_conf('verbose') },
        extractdir  => { default => '' },
        data        => { allow => sub { ref $_[1] &&
                                        $_[1]->isa('CPANPLUS::Internals::Module')
                                  } },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    unless( $args->{file} or $args->{data} ) {
        $err->trap( error => 'Do not know what file you want me to extract!' );
        return undef;
    }

    ### hack to allow CPAN style dir structure
    my $file = $args->{file}
            || File::Spec->catfile(
                   $conf->_get_build('base'),
                   $conf->_get_ftp('base'),
                   $args->{data}->path,
                   $args->{data}->package,
               );

    # We're going to do some chdir'ing, so make sure we're using an
    # absolute filename.
    $file = File::Spec->rel2abs($file);

    unless( -s $file ) {
        $err->trap( error => loc("%1 has zero size! Can not extract!", $file) );
        return 0;
    }

    my $force   = $args->{force};
    my $perl    = $args->{perl};
    my $verbose = $args->{verbose};

    ### we already extracted this file once this run.
    ### so return the dir, unless force is in effect -kane
    my $loc =   $self->{_extracted}->{$file} ||
                (ref $args->{data} ? $args->{data}->status->extract : '');


    if ( $loc and -d $loc and !$force ) {
        $err->inform(
                msg     => loc("Already extracted '%1' to '%2'. Won't extract again without force", $file, $loc),
                quiet   => !$verbose,
        );
        return $loc;
    }

    ### clean up path - File::Spec->catfile assumes the last arg is *only* a file but we
    ### gave it path+file - perhaps we could 'cheat' and use File::Spec->catdir? -jmb
    #$file = File::Spec->canonpath($file);

    my $perl_version = $self->_perl_version( perl => $perl );

    ### chdir to the cpanplus build base directory
    my $base = $args->{'extractdir'}
            || File::Spec->catdir(
                            $conf->_get_build('base'),
                            $perl_version,
                            $conf->_get_build('moddir')
                );

    ### if the dir doesn't exist yet, create it ###
    unless( -d $base ) {

        unless( $self->_mkdir( dir => $base ) ) {
            $err->inform(
                msg   => loc("Could not create %1", $base),
                quiet => !$verbose,
            );
            return 0;
        }
    }

    unless ( chdir $base ) {
        $err->trap( error => loc("could not cd into %1", $base) );
        return 0;
    }

    my $dir;
    ### is it a .tar.gz, .tgz or .gz file
    # man, let the regexps speak for themselves! -jmb
    if ( $file =~ m/.+?\.(?:(?:tar\.)?gz|tgz)$/i ) {
        $dir = $self->_untar( file => $file ) or return 0;

    ### else, it might be a .zip file
    } elsif ( $file =~ m|.+?\.zip$|i ) {
        $dir = $self->_unzip( file => $file ) or return 0;

    ### ok, unknown format, abort!
    } else {
        $err->trap( error => loc("Unknown file format for %1", $file) );
        return 0;
    }

    ### done extracting the files, cd back to the dir we were started in
    my $orig = $conf->_get_build('startdir');

    chdir $orig or $err->inform( msg => loc("Could not chdir into %1", $orig) );

    ### the dir we extracted everything into
    my $extract_dir = File::Spec->catdir($base, $dir);

    ### make a log in the cache, so we know NOT to extract this thing again
    ### if we come across it
    $self->{_extracted}->{$file} = $extract_dir;

    return $extract_dir;

} #_extract


sub _untar {
    my $self = shift;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my %hash = @_;

    my $tmpl = {
            file    => { required => 1, allow => sub { -e pop() && -s _ } },
            verbose => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $file    = $args->{'file'};
    my $verbose = $args->{'verbose'};

    my $dir;

    ### check prerequisites
    my $use_list    = { 'Archive::Tar' => '0.0' };
    my $have_module = $self->_can_use( modules => $use_list );

    ### have to use eval here; Tar.pm has all kinds of bugs we can't trap
    ### beforehand; even the latest version breaks on some debian systems.
    if ( $have_module ) { eval {
    
        ### workaround to prevent Archive::Tar from setting uid, which
        ### is a potential security hole. -autrijus
        ### have to do it here, since A::T needs to be /loaded/ first ###
        {   no strict 'refs'; local $^W; local $SIG{__WARN__} = sub {};
            
            ### older versions of archive::tar <= 0.23
            *Archive::Tar::chown = sub {};

            eval {
                require Archive::Tar::Constant;
                *Archive::Tar::Constant::CAN_CHOWN = sub { 0 };
            }
        }    
        
        ### for version of archive::tar > 1.04
        local $Archive::Tar::Constant::CHOWN = 0;
        
        $err->inform(
            msg     => "Untarring $file",
            quiet   => !$verbose
        );

        ### not sure archive::tar even has a return status of any use
        ### if we create a new() Tar object first
        my $tar = Archive::Tar->new();

        ### we can then get something useful from the return code
        ### older versions of A::T do not have ->error method,
        ### just $error package variable
        $tar->read($file,1) or $err->trap( error => $Archive::Tar::error );

        ### alternately, we could do it in one step if we don't
        ### mind asking $Archive::Tar::error directly
        #my $tar = Archive::Tar->new($file), or croak $Archive::Tar::error;

        my @list = $tar->list_files;
        ($dir) = $list[0] =~ m[(?:./)*(\S+?)(?:/|$)]
            or $err->trap( error => loc("Could not read dir name from %1", $file) );

        if ($dir) {
            eval { File::Path::rmtree($dir) }; # non-fatal

            if($@) { $err->trap( error => loc("Error removing %1: %2", $dir, $@) ); }

            for (@list) {
                $err->inform(
                    msg   => loc("Extracting %1", $_),
                    quiet => !$verbose
                );
                ### I just noticed that we don't bail if this fails.
                ### Probably because Archive::Tar sucks a bit?
                ### (at least the earlier version) -jmb

                ### from what i get from the docs, it doesn't return anything...
                ### so yeah, that does suck - kane
            }

            local $^W; # quell 'splice() offset past end of array' warnings
            $tar->extract(@list);
        }

        ### the current (0.22) version of Archive::Tar has a new
        ### extract_archive() method that is probably more efficient
        ### but we can't expect anything more than 0.076 :o(
        ### (we probably want the ability to be more verbose anyway) -jmb
        #$tar->extract_archive($file), or croak $tar->error;

        ### problem is that 0.22 requires compress::zlib 1.13.. AS perl doesn't
        ### ship with that, nor can we build it on a wintendo. hence, we can't
        ### use 0.22.. and yes, that does suck. hopefully a new(er) release of AS
        ### will actually have C::Zlib 1.13 and we can upgrade.
        ### (should ask brev) - Kane

    }; # end eval
        $err->trap( error => loc("An error occurred extracting %1: %2", $args->{file}, $@) ) if $@;
    } # end if

    if ( !$dir and my ($tar, $gzip) = $conf->_get_build( qw|tar gzip| ) ) {
        ### either Archive::Tar failed, or the user doesn't have it installed

        $err->inform( msg => loc("Untarring %1", $file), quiet => !$verbose );

        my $captured;

        unless( $self->_run(
            command => "$gzip -cd $file | $tar -tf -",
            buffer  => \$captured,
            verbose => 0,
        ) ) {
            $err->trap( error => loc("could not call tar/gzip: %1", $!));
            return 0;
        }

        ### find the extraction dir ###
        foreach (split(/\n/, $captured)) {
            ($dir) = m{(?:.[/\\])*(\S+?)(?:[/\\]|$)} unless defined($dir);
            $err->inform(
                msg   => loc("Extracting %1", $_),
                quiet => !$verbose
            );
        }

        if ($dir) {
            File::Path::rmtree($dir);
            $self->_run( command => "$gzip -cd $file | $tar -xf -" ) or
                $err->trap( error => "tar/gzip error: $!" );
        }
        else {
            $err->trap( error => loc("Could not read dir name from %1", $file) );
        }
    }
    elsif (!$have_module) {
        $err->trap(
            error => loc("You don't have %1! Please install it as soon as possible!", "Archive::Tar")
        );
        return 0;
    }

    return $dir;

} #_untar


sub _unzip {
    my $self = shift;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my %hash = @_;

    my $tmpl = {
            file    => { required => 1, allow => sub { -e pop() && -s _ } },
            verbose => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $file    = $args->{'file'};
    my $verbose = $args->{'verbose'};

    my $dir;

    ### check prerequisites
    ### maybe we should check that at top of module?
    my $use_list = { 'Archive::Zip' => '0.0' };

    if ($self->_can_use(modules => $use_list)) {

        $err->inform(
            msg   => loc("Unzipping %1", $file),
            quiet => !$verbose
        );

        ### not sure archive::zip even has a return status of any use ###
        #my $zip = Archive::Zip->new($file) or croak $!;

        ### we can get a return status like this:
        my $zip = Archive::Zip->new();

        unless ( $zip->read($file) == &Archive::Zip::AZ_OK ){
            $err->trap( error => loc("Unable to read %1", $file) );
            return 0;
        }

        ### well, ok, it's not really useful, but I think it *does* carp a bit -jmb

        ### extract all the files ###
        my @list = $zip->members;
        ($dir) = $list[0]->{fileName} =~ m[(\S+?)(?:/|$)] or
            $err->trap( error => loc("Could not read dir name from %1", $file) );

        for (@list) {
            $err->inform(
                msg     => "Extracting $_->{fileName}",
                quiet   => !$verbose,
            );

            unless ($zip->extractMember($_) == &Archive::Zip::AZ_OK) {
                $err->trap( error => loc("Extraction of %1 from %2 failed", $_, $file) );
                return 0;
            } #unless

        } #for
    } elsif ( my $unzip = $conf->_get_build( 'unzip' ) ) {

        $err->inform( msg => loc("Unzipping %1", $file), quiet => !$verbose );

        my $captured;

        unless( $self->_run(
            command => [ $unzip, '-qql', $file ],
            buffer  => \$captured,
            verbose => 0,
        ) ) {
            $err->trap( error => loc("could not call unzip: %1", $!));
            return 0;
        }

        ### find the extraction dir ###
        foreach (split(/\n/, $captured)) {
            ($dir) = m{(?:.[/\\])*(\S+?)(?:[/\\]|$)} unless defined($dir);
            $err->inform(
                msg     => loc("Extracting %1", $_),
                quiet   => !$verbose,
            );
        }

        if ($dir) {
            File::Path::rmtree($dir);
            $self->_run( command => [ $unzip, '-qq', $file ] ) or
                $err->trap( error => loc("unzip error: %1", $!) );
        }
        else {
            $err->trap( error => loc("Could not read dir name from %1", $file) );
        }

    } else {
        $err->trap(
            error => loc("You don't have %1! Please install it as soon as possible!", "Archive::Zip")
        );
        return 0;
    }

    return $dir;

} #_unzip


sub _gunzip {
    my $self = shift;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my %hash = @_;

    my $tmpl = {
            file => { required => 1, allow => sub { -e pop() && -s _ } },
            name => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $file = $args->{'file'};
    my $name = $args->{'verbose'};


    my $use_list = { 'Compress::Zlib' => '0.0' };

    ### check if we have the needed modules first ###
    if ($self->_can_use(modules => $use_list)) {

        $err->inform(
            msg   => loc("Gunzipping %1", $file),
            quiet => !$conf->get_conf('verbose')
        );

        my $gz = Compress::Zlib::gzopen($file, 'rb');

        unless( $gz ) {
            $err->trap(
                    error => loc("unable to open %1: %2", $file, $Compress::Zlib::gzerrno)
            );
            return 0;
        }

        my $buffer;

        ### check if we have an output file to print to ###
        if ($name) {
            my $fh;
            unless( $fh = FileHandle->new(">$name") ) {
                $err->trap( error => loc("File creation failed: %1", $!) );
                return 0;
            }

            $fh->print($buffer), while $gz->gzread($buffer) > 0;
            $fh->close;

            return 1;

        ### else append to $str
        } else {
            my $str = '';
            $str .= $buffer, while $gz->gzread($buffer) > 0;

            return $str;
        }
    } elsif ( my $gzip = $conf->_get_build( 'gzip' ) ) {
        my $str = '';

        unless( $self->_run(
            command => [ $gzip, '-cdf', $file ],
            buffer  => \$str,
            verbose => 0,
        ) ) {
            $err->trap( error => loc("could not call gzip: %1", $!));
            return 0;
        }

        ### check if we have an output file to print to ###
        if ($name) {
            my $fh;
            unless( $fh = FileHandle->new(">$name") ) {
                $err->trap( error => loc("File creation failed: %1", $!) );
                return 0;
            }

            $fh->print($str);
            $fh->close;
            return 1;
        }

        return $str;

    } else {
        $err->trap(
            error => loc("You don't have %1! Please install it as soon as possible!", "Compress::Zlib")
        );
        return 0;
    }

} #_gunzip

1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
