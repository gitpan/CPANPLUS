# $File: //member/autrijus/cpanplus/dist/lib/CPANPLUS/Internals/Extract.pm $
# $Revision: #3 $ $Change: 3544 $ $DateTime: 2002/03/26 07:48:03 $

#######################################################
###            CPANPLUS/Internals/Extract.pm        ###
###     Subclass to extract modules for cpanplus    ###
###         Written 23-02-2002 by Jos Boumans       ###
#######################################################

### Extract.pm ###

package CPANPLUS::Internals::Extract;

use strict;
use CPANPLUS::Configure;
use CPANPLUS::Error;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

sub _extract {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    ### check if we got a specific file argument,
    ### or if we're trying to extract a package (module data)
    ### no argument supplied, we should return
    #my $file = $args{'file'} || $args{'data'}->{'package'} || return 0;

    ### hack to allow CPAN style dir structure
    my $file = $args{file}
            || File::Spec->catfile(
                   $conf->_get_build('base'),
                   $conf->_get_ftp('base'),
                   $args{data}->{path},
                   $args{data}->{package},
               );

    ### we already extracted this file once this run. 
    ### so return the dir, unless force is in effect -kane
    if ( $self->{_extracted}->{$file} and !$conf->get_conf('force') ) {
        $err->inform( 
                msg     => qq[already extracted $file. Won't extract again without force], 
                quiet   => !$conf->get_conf('verbose'),
        );
        return $self->{_extracted}->{$file};
    }
    
    ### clean up path - File::Spec->catfile assumes the last arg is *only* a file but we
    ### gave it path+file - perhaps we could 'cheat' and use File::Spec->catdir? -jmb
    #$file = File::Spec->canonpath($file);

    ### chdir to the cpanplus build base directory
    my $base = $args{'fetchdir'}
            || File::Spec->catdir($conf->_get_build(qw/base moddir/));

    unless ( chdir $base ) {
        $err->trap( error => "could not cd into $base" );
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
        $err->trap( error => "Unknown file format for $file" );
        return 0;
    }

    ### done extracting the files, cd back to the dir we were started in
    my $orig = $conf->_get_build('startdir');

    chdir $orig or $err->inform( msg => "Could not chdir into $orig" );

    ### the dir we extracted everything into
    my $extract_dir = File::Spec->catdir($base, $dir);

    ### make a log in the cache, so we know NOT to extract this thing again
    ### if we come across it 
    $self->{_extracted}->{$file} = $extract_dir;

    return $extract_dir;
    
} #_extract


sub _untar {
    my $self = shift;
    my %args = @_;

    my $file = $args{'file'};

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $dir;

    ### check prerequisites
    ### maybe we should check that at top of module?
    my $use_list = { 'Archive::Tar' => '0.0' };

    my $verbose = $conf->get_conf('verbose');

    if ( $self->_can_use( $use_list ) ) {

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
        ($dir) = $list[0] =~ m[(\S+?)(?:/|$)]
            or $err->trap( error => "Could not read dir name from $file" );

        for (@list) {
            $err->inform(
                msg => "Extracting $_",
                quiet => !$verbose
            );
            $tar->extract($_);
            ### I just noticed that we don't bail if this fails.
            ### Probably because Archive::Tar sucks a bit?
            ### (at least the earlier version) -jmb

            ### from what i get from the docs, it doesn't return anything...
            ### so yeah, that does suck - kane
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

    } elsif ( my ($tar,$gzip) = $conf->_get_build( qw|tar gzip| ) ) {
        my $fh = new FileHandle;
        $fh->open("$gzip -cd $file | $tar -xvf - |") or (
                $err->trap( error => "could not call tar/gzip: $!")
                && return 0 );

        ### find the extraction dir ###
        my $rootdir = File::Spec->rootdir();
        while(<$fh>){
            chomp;
            ($dir) = m|(\S+)$rootdir\s*$|sig unless $dir;
            $err->inform(
                msg     => $_,
                quiet   => !$verbose,
            );
        }

        $dir or $err->trap( error => "Could not read dir name from $file" );

        close $fh;

    } else {
        $err->trap(
            error => "You don't have Archive::Tar! Please install it as soon as possible!"
        );
        return 0;
    }

    return $dir;

} #_untar


sub _unzip {
    my $self = shift;
    my %args = @_;

    my $file = $args{'file'};

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $dir;
    my $verbose = $conf->get_conf('verbose'); # avoid multiple calls

    ### check prerequisites
    ### maybe we should check that at top of module?
    my $use_list = { 'Archive::Zip' => '0.0' };

    if ($self->_can_use($use_list)) {

        $err->inform(
            msg   => "Unzipping $file",
            quiet => !$verbose
        );

        ### not sure archive::zip even has a return status of any use ###
        #my $zip = Archive::Zip->new($file) or croak $!;

        ### we can get a return status like this:
        my $zip = Archive::Zip->new();

        unless ( $zip->read($file) == &Archive::Zip::AZ_OK ){
            $err->trap( error => "Unable to read $file" );
            return 0;
        }

        ### well, ok, it's not really useful, but I think it *does* carp a bit -jmb

        ### extract all the files ###
        my @list = $zip->members;
        ($dir) = $list[0]->{fileName} =~ m[(\S+?)(?:/|$)] or
            $err->trap( error => "Could not read dir name from $file" );

        for (@list) {
            $err->inform(
                msg     => "Extracting $_->{fileName}",
                quiet   => !$verbose,
            );

            unless ($zip->extractMember($_) == &Archive::Zip::AZ_OK) {
                $err->trap( error => "Extraction of $_ from $file failed" );
                return 0;
            } #unless

        } #for
    } elsif ( my $zip = $conf->_get_build( 'unzip' ) ) {
        my $fh = new FileHandle;
        $fh->open("$zip -qql $file |") or (
                $err->trap( error => "could not call unzip: $!")
                && return 0 );

        my $rootdir = File::Spec->rootdir();
        while(<$fh>){
            chomp;
            ($dir) = m|(\S+)$rootdir\s*$|sig unless $dir;
            $err->inform(
                msg     => $_,
                quiet   => !$verbose,
            );
        }

        close $fh;

    } else {
        $err->trap(
            error => "You don't have Archive::Zip! Please install it as soon as possible!"
        );
        return 0;
    }

    return $dir;

} #_unzip


sub _gunzip {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $use_list = { 'Compress::Zlib' => '0.0' };

    ### check if we have the needed modules first ###
    if ($self->_can_use($use_list)) {

        $err->inform(
            msg   => "Gunzipping $args{'file'}",
            quiet => !$conf->get_conf('verbose')
        );

        ### gzip isn't catching the error properly if the file
        ### is non-existent apparently... -Kane
        unless ( -e $args{'file'} ) {
            $err->trap( error => "Can't find file $args{'file'}" );
            return 0;
        }

        my $gz = Compress::Zlib::gzopen($args{'file'}, 'rb');

        unless( $gz ) {
            $err->trap( error => "unable to open " . $args{'file'} . ": " .
                                 $Compress::Zlib::gzerrno );
            return 0;
        }

        my $buffer;

        ### check if we have an output file to print to ###
        if ($args{'name'}) {
            my $fh;
            unless( $fh = FileHandle->new(">$args{name}") ) {
                $err->trap( error => "File creation failed: $!" );
                return 0;
            }

            $fh->print($buffer), while $gz->gzread($buffer) > 0;
            $fh->close;

            return 1;

        ### else append to $str
        } else {
            my $str;
            $str .= $buffer, while $gz->gzread($buffer) > 0;

            return $str;
        }
    } elsif ( my $gzip = $conf->_get_build( 'gzip' ) ) {

        my $fh = new FileHandle;

        open($fh, "$gzip -cdf $args{'file'} |") or (
                $err->trap( error => "could not call gzip: $!")
                && return 0 );

        my $str;
        while(<$fh>){ $str .= $_ }
        close $fh;
        return $str;

    } else {
        $err->trap(
            error => "You don't have Compress::Zlib! Please install it as soon as possible!"
        );
        return 0;
    }

} #_gunzip

1;
