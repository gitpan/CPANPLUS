# $File$
# $Revision$ $Change$ $DateTime$

#######################################################
###            CPANPLUS/Internals/Search.pm         ###
###     Subclass to query for module information    ###
###         Written 12-03-2002 by Jos Boumans       ###
#######################################################

### Query.pm ###

package CPANPLUS::Internals::Search;

use strict;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use Data::Dumper;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

### query the cpan tree based on the list of items to search for ###
sub _query_mod_tree {
    my $self = shift;
    my %args = @_;

    #my $i = '0000'; ### keep a counter, it'll be the key of the hashref
    ### not any longer.. it was only used in shell.pm and it's kinda silly
    ### to enforce that upon everyone in Internals already.
    my $href;

    ### let's see if we got a custom tree (perhaps a sub search?) or
    ### we should use the default tree.
    my $tree = keys %{$args{'data'}} ? $args{'data'} : $self->{_modtree};

    ### loop over the list provided, compare every element against the
    ### proper entry of the hashref in the cpan module tree
    ### if it matches, put it in the hashref we'll return.

    for my $el ( @{$args{'list'}} ) {

        ### i dont recall why i used a quotemeta here... -kane
        ### if we get an 'author' query, then we'll already have qualified reqexes
        ### so no more 'quotemeta' or that'll be BAD -kane
#        my $el =    $args{'type'} eq 'author'
#                    ? $arg
#                    : quotemeta $arg;

        if ($el =~ /\w/) {
            for (sort keys %$tree) {
                if ($tree->{$_}->{ $args{'type'} } =~ /$el/) {
                    $href->{$_} = $tree->{$_};
                } #if
            } #for
        } #if
    } #for

    return $href;

} #_query_mod_tree


### query the cpan tree based on the list of items to search for ###
sub _query_author_tree {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my @list;

    ### loop over the list provided, compare every element against the
    ### proper entry of the hashref in the cpan author tree
    ### if it matches, put it in the hashref we'll return.

    ### this hashref holds a list of CPAN id's that match the search criteria
    ### we then look in _query_mod_tree to find which modules are belonging
    ### to those id's

    for my $el ( @{$args{'list'}} ) {

        ### i dont recall why i used a quotemeta here... -kane
        # my $el = quotemeta $arg;

        if ($el =~ /\w/) {
            for (keys %{$self->{_authortree}}) {
                if ($self->{_authortree}->{$_}->{'name'} =~ /$el/ or /$el/) {
                    push @list, $_;    #build a regexp
                } #if
            } #for
        } #if
    } #for

    return \@list if $args{authors_only};


    ### if we are going to query again, we'll need to reconstruct the
    ### the regexp, else we'll get more matches than we bargained for;

    my @reglist = map { '^'.$_.'$' } @list;
    return $self->_query_mod_tree(type => 'author', list => \@reglist);

} #_query_author_tree




sub _distributions {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    ### all to please warnings...
    my $auth = $args{'author'};

    my $modules = $self->_query_mod_tree( list => [$auth], type => 'author' );

    ### if we didn't get any modules, the author doesn't have a checksums file
    ### in his home dir, so we can save ourselves some trouble and return.
    return 0 unless $modules;

    my $path;
    for my $mod ( keys %$modules ) {
        $path = File::Spec::Unix->catdir(
                    $conf->_get_ftp('base'),
                    $modules->{$mod}->{path}
                );
        last;
    }

    my $fetchdir = File::Spec->catdir(
                                $conf->_get_build('base'),
                                $conf->_get_ftp('base'),
                                $path,
                            );

    ### we always get a new file... ###
    my $file = $self->_fetch(
                        file        => 'CHECKSUMS',
                        dir         => $path,
                        fetchdir    => $fetchdir,
                        force       => 1,
        ) or return 0;

    my $fh = new FileHandle;
    unless ($fh->open($file)) {
        $err->trap( error => "Could not open $file: $!" );
        return 0;
    }

    my $in;
    { local $/; $in = <$fh> }
    $fh->close;

    ### eval into life the checksums file
    ### another way would be VERY nice - kane
    my $cksum;
    {   #local $@; can't use this, it's buggy -kane
        $cksum = eval $in or $err->trap( error => "eval error on checksums file: $@" );
    }

    return $cksum;
}


### Get a list of files which are used by a module ###
### pass it a module argument and a type for the type of files ###
sub _files {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    ### check prerequisites
    my $use_list = { 'ExtUtils::Installed' => '0.0' };

    if ($self->_can_use($use_list)) {

        my $inst;
        unless ($inst = ExtUtils::Installed->new() ) {
            $err->trap( error => qq[Could not create an ExtUtils::Installed object] );
            return 0;
        }

        ### all to please warnings...
        my $type = $args{'type'} || '';
        my $mod = $args{'module'};

        {   ### happy happy happy, joy joy joy
            ### yet another module that thinks it's ok to croak
            ### instead of return 0.
            ### I am NOT happy -kane

            my @files = eval { $inst->files( $mod, $type) };

            if ($@) {
                chomp $@;
                $err->trap( error => "Could no get files for $mod: $@" );
                return 0;
            }

            return @files ? \@files : 0;
        }

    } else {

        $err->trap( error => qq[You don't have ExtUtils::Installed available - can not find files for $args{'module'} ] );
        return 0;
    }
}


1;
