# $File$
# $Revision$ $Change$ $DateTime$

################################################################
###                CPANPLUS/Internals/Source.pm              ###
### Subclass to fetch, munge and update sources for cpanplus ###
###             Written 12-03-2002 by Jos Boumans            ###
################################################################

### Source.pm ###

package CPANPLUS::Internals::Source;

use strict;
use CPANPLUS::Configure;
use CPANPLUS::Internals::Module;
use CPANPLUS::Internals::Author;
use CPANPLUS::Error;
use Data::Dumper;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

### this builds a hash reference with the structure of the cpan module tree ###
sub _create_mod_tree {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    ### this is test code to tinker with dslip information.. this might go in
    ### a seperate sub... - Kane
    ### seems to work fine now. fixed warnings regarding dslip, i think we can
    ### leave it in - Kane
    my $dslip_tree = $self->_create_dslip_tree( %args );


    ### check if we can retrieve a frozen data structure with storable ###
    my $storable = $self->_can_use( {'Storable' => '0.0'} ) if $conf->get_conf('storable');

    ### find the location of the stored data structure ###
    ### bleh!  changed to use File::Spec->catfile -jmb
    my $stored = File::Spec->catfile($conf->_get_build('base'), $conf->_get_source('smod'));

    if ($storable && -e $stored && $args{'uptodate'}) {
        $err->inform(
            msg     => "Retrieving $stored ",
            quiet   => !$conf->get_conf('verbose')
        );
        my $href = Storable::retrieve($stored);

        return $href;

    ### else, we'll build a new one ###
    ### if we have storable and we're allowed to use it, we'll freeze it though ###
    } else {

        ### changed to use File::Spec->catfile(), now OS safe -jmb
        my $file = File::Spec->catfile($conf->_get_build('base'), $conf->_get_source('mod'));

        my @list = split /\n/, $self->_gunzip( file => $file );

        my $tree = {};
        my $flag;
        for (@list) {

            ### quick hack to read past the header of the file ###
            ### this is still rather evil... fix some time - Kane
            $flag = 1 if m|^\s*$|;
            next unless $flag;

            ### skip empty lines ###
            next if m|^\s*$|;
            chomp;

            my @data = split /\s+/;

            ### filter out the author and filename as well ###
            my ($author, $package) = $data[2] =~ m|(\w+)/([^/]+)$|sg;

            ### remove file name from the path
            $data[2] =~ s|/[^/]+$||;

            ### adding the dslip info
            ### probably can use some optimization
            my $dslip;
            for my $item ( qw[ statd stats statl stati ] ) {
                ### checking if there's an entry in the dslip info before catting it on.
                ### appeasing warnings this way
                $dslip .=   $dslip_tree->{ $data[0] }->{$item}
                            ? $dslip_tree->{ $data[0] }->{$item}
                            : ' ';
            }

            ### Every module get's stored as a module object ###
            $tree->{ $data[0] } = CPANPLUS::Internals::Module->new(
                    module      => $data[0],   # full module name
                    version     => $data[1],   # version number
                    path        => $data[2],   # extended path on the cpan mirror, like /A/AB/ABIGAIL
                    comment     => $data[3],   # comment on the module
                    author      => $author,    # module author
                    package     => $package,   # package name, like 'foo-bar-baz-1.03.tar.gz'
                    description => $dslip_tree->{ $data[0] }->{'description'},
                    dslip       => $dslip,
                    prereqs     => {},
                    status      => undef,
                    _id         => $self->{_id},    #id of this internals object
            );

            ### The old way, we use CPANPLUS::Internals::Module now... -kane ###

#            ### the key of the hash is the module name.
#            ### seems most convenient since most searches are on module name
#            ### full data is in the hash ref, pointed to by the key..
#            $tree->{$data[0]} = {
#                module      => $data[0],   # full module name
#                version     => $data[1],   # version number
#                path        => $data[2],   # extended path on the cpan mirror, like /author/id/A/AB/ABIGAIL
#                comment     => $data[3],   # comment on the module
#                author      => $author,    # module author
#                package     => $package,   # package name, like 'foo-bar-baz-1.03.tar.gz'
#                description => $dslip_tree->{ $data[0] }->{'description'}
#            };
#
#            $tree->{ $data[0] }->{'dslip'} = $dslip;

        } #for

        if ($storable) {
            Storable::store($tree, $stored) or $err->trap( error => 'could not store $stored!' );
        }

        return $tree;
    }
} #_create_mod_tree

sub _create_author_tree {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    ### check if we can retrieve a frozen data structure with storable ###
    my $storable = $self->_can_use( {'Storable' => '0.0'} ) if $conf->get_conf('storable');

    ### $stored is the name of the frozen data structure ###
    ### changed to use File::Spec->catfile -jmb
    my $stored = File::Spec->catfile($conf->_get_build('base'), $conf->_get_source('sauth'));

    if ($storable && -e $stored && $args{'uptodate'}) {
        my $href = Storable::retrieve($stored);
        $err->inform(
            msg => "Retrieving $stored ",
            quiet => !$conf->get_conf('verbose')
        );
        return $href;

    ### else, we'll build a new one ###
    ### if we have storable and we're allowed to use it, we'll freeze it though ###
    } else {
        my $tree = {};

        ### changed to use File::Spec->catfile(), now OS safe -jmb
        my $file = File::Spec->catfile($conf->_get_build('base'), $conf->_get_source('auth'));

        my @list = split /\n/, $self->_gunzip(file => $file);

        for (@list) {
            my($id, $name, $email) = m/^alias \s+
                                        (\S+) \s+
                                        "([^\"\<]+) \s+ <(.+)>"
                                      /x;
            $tree->{$id} = CPANPLUS::Internals::Author->new(
                name    => $name,           #authors name
                email   => $email,          #authors email address
                cpanid  => $id,             #authors CPAN ID
                _id     => $self->{_id},    #id of this internals object
            );
        }

        if ($storable) {
            Storable::store($tree, $stored) or $err->trap( error => 'could not store $stored!' );
        }

        return $tree;
    }

} #_create_author_tree


### not used yet, have to think of better implementation ###
sub _create_dslip_tree {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    ### check if we can retrieve a frozen data structure with storable ###
    my $storable = $self->_can_use( {'Storable' => '0.0'} ) if $conf->get_conf('storable');

    ### $stored is the name of the frozen data structure ###
    ### changed to use File::Spec->catfile -jmb
    my $stored = File::Spec->catfile($conf->_get_build('base'), $conf->_get_source('sdslip'));

    if ($storable && -e $stored && $args{'uptodate'}) {
        my $href = Storable::retrieve($stored);
        $err->inform(
            msg     => "Retrieving $stored ",
            quiet   => !$conf->get_conf('verbose')
        );
        return $href;

    ### else, we'll build a new one ###
    ### if we have storable and we're allowed to use it, we'll freeze it though ###
    } else {

        ### get the file name of the source ###
        my $file = File::Spec->catfile($conf->_get_build('base'), $conf->_get_source('dslip'));

        my $in = $self->_gunzip(file => $file);

        ### get rid of the comments and the code ###
        $in =~ s|.+}\s||s;

        ### split '$cols' and '$data' into 2 variables ###
        my ($ds_one, $ds_two) = split ';', $in, 2;

        ### eval them into existance ###
        ### still not too fond of this solution - kane ###
        my ($cols, $data);
        {   #local $@; can't use this, it's buggy -kane

            $cols = eval $ds_one;
            if ($@){ $err->trap( error => qq[Error in eval of dslip source files: $@] )}

            $data = eval $ds_two;
            if ($@){ $err->trap( error => qq[Error in eval of dslip source files: $@] )}
        }

        my $tree = {};
        my $primary = "modid";

        ### this comes from CPAN::Modulelist
        ### which is in 03modlist.data.gz
        for (@$data){
            my %hash;
            @hash{@$cols} = @$_;
            $tree->{$hash{$primary}} = \%hash;
        }

        if ($storable) {
            Storable::store($tree, $stored) or $err->trap( error => 'could not store $stored!' );
        }

        return $tree;
    }

} #_create_dslip_tree

### these are the definitions used for dslip info
### they shouldn't change over time.. so hardcoding them doesn't appear to
### be a problem. if it is, we need to parse 03modlist.data better to filter
### all this out.
### right now, this is just used to look up dslip info from a module
sub _dslip_defs {
    my $self = shift;

    my $aref = [

        # D
        [ q|Development Stage|, {
            i   => q(Idea, listed to gain consensus or as a placeholder),
            c   => q(under construction but pre-alpha (not yet released)),
            a   => q(Alpha testing),
            b   => q(Beta testing),
            R   => q(Released),
            M   => q(Mature (no rigorous definition)),
            S   => q(Standard, supplied with Perl 5),
        }],

        # S
        [ q|Support Level|, {
            m   => q(Mailing-list),
            d   => q(Developer),
            u   => q(Usenet newsgroup comp.lang.perl.modules),
            n   => q(None known, try comp.lang.perl.modules),
        }],

        # L
        [ q|Language Used|, {
            p   => q(Perl-only, no compiler needed, should be platform independent),
            c   => q(C and perl, a C compiler will be needed),
            h   => q(Hybrid, written in perl with optional C code, no compiler needed),
            '+' => q(C++ and perl, a C++ compiler will be needed),
            o   => q(perl and another language other than C or C++),
        }],

        # I
        [ q|Interface Style|, {
            f   => q(plain Functions, no references used),
            h   => q(hybrid, object and function interfaces available),
            n   => q(no interface at all (huh?)),
            r   => q(some use of unblessed References or ties),
            O   => q(Object oriented using blessed references and/or inheritance),
        }],

        # P
        [ q|Public License|, {
            p   => q(Standard-Perl: user may choose between GPL and Artistic),
            g   => q(GPL: GNU General Public License),
            l   => q(LGPL: "GNU Lesser General Public License" (previously known as "GNU Library General Public License")),
            b   => q(BSD: The BSD License),
            a   => q(Artistic license alone),
            o   => q(other (but distribution allowed without restrictions)),
        }],
    ];

    return $aref;
}


### this method checks wether or not the source files we are using are still up to date
### josh, you changed a bunch on this sub, document please? -Kane
# not really, but it will change soon anyway, and I will doc then -jmb
sub _check_uptodate {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $flag;
    unless ( -e $args{'file'} && (
            ( stat $args{'file'} )[9]
            + $self->{_conf}->_get_source('update') )
            > time ) {
        $flag = 1;
    }

    if ( $flag or $args{'update_source'} ) {

         if ( $self->_update_source( name => $args{'name'} ) ) {
              return 0;       # return 0 so 'uptodate' will be set to 0, meaning no use
                              # of previously stored hashrefs!
         } else {
              $err->inform(
                  msg => "unable to update source, attempting to get away with using old source file!",
                  quiet => !$conf->get_conf('verbose')
              );
              return 1;
         }

    } else {
        return 1;
    }
}


### this sub fetches new source files ###
sub _update_source {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    $err->inform(
        msg => "updating source files",
        quiet => !$conf->get_conf('verbose')
    );

    my $base = $conf->_get_build('base');
    my $now = time;

    {   ### this could use a clean up - Kane
        ### no worries about the / -> we get it from the _ftp configuration, so
        ### it's not platform dependant. -kane
        my ($dir, $file) = $conf->_get_ftp( $args{'name'} ) =~ m|(.+/)(.+)$|sg;
        my $rv = $self->_fetch(
                     file      => $file,
                     dir       => $dir,
                     fetchdir  => $base,
                     force     => 1,
                 );

        ### this will throw warnings if we have no host (ie, when using local files)
        ### fix? -kane
        unless ($rv) {
            $err->trap( error => "Couldn't fetch $file from " . $conf->_get_ftp('host') );
            return 0;
        }

        ### `touch` the file, so windoze knows it's new -jmb
        ### works on *nix too, good fix -Kane
        utime ( $now, $now, File::Spec->catfile($base, $file) ) or
            $err->trap( error => "Couldn't touch $file" );

    }
    return 1;
}

1;
