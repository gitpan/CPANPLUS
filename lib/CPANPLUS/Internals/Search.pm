# $File: //depot/cpanplus/dist/lib/CPANPLUS/Internals/Search.pm $
# $Revision: #4 $ $Change: 11204 $ $DateTime: 2004/09/20 20:15:05 $

#######################################################
###            CPANPLUS/Internals/Search.pm         ###
###     Subclass to query for module information    ###
###         Written 12-03-2002 by Jos Boumans       ###
#######################################################

### Search.pm ###

package CPANPLUS::Internals::Search;

use strict;
use CPANPLUS::I18N;
use CPANPLUS::Tools::Check qw[check];

use Data::Dumper;


BEGIN {
    use vars        qw( $VERSION );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

### query the cpan tree based on the list of items to search for ###
sub _query_mod_tree {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;

    my $tmpl = {
        data    => { default => {}, strict_type => 1 },
        list    => { required => 1, default => [], strict_type => 1 },
        type    => { required => 1, allow => [qw|path module author comment package version dslip|] },
        verbose => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    #my $i = '0000'; ### keep a counter, it'll be the key of the hashref
    ### not any longer.. it was only used in shell.pm and it's kinda silly
    ### to enforce that upon everyone in Internals already.
    my $href = {};

    ### let's see if we got a custom tree (perhaps a sub search?) or
    ### we should use the default tree.
    my $tree = keys %{$args->{'data'}} ? $args->{'data'} : $self->_module_tree;

    ### loop over the list provided, compare every element against the
    ### proper entry of the hashref in the cpan module tree
    ### if it matches, put it in the hashref we'll return.

    for my $el ( @{$args->{'list'}} ) {

        ### i dont recall why i used a quotemeta here... -kane
        ### if we get an 'author' query, then we'll already have qualified reqexes
        ### so no more 'quotemeta' or that'll be BAD -kane
#        my $el =    $args{'type'} eq 'author'
#                    ? $arg
#                    : quotemeta $arg;

        if ($el =~ /\w/) {
            for (sort keys %$tree) {
                if ($tree->{$_}->{ $args->{'type'} } =~ /$el/) {
                    $href->{$_} = $tree->{$_};
                } #if
            } #for
        } #if
    } #for

    return $href;

} #_query_mod_tree


### query the cpan tree based on the list of items to search for ###
sub _query_author_tree {
    my $self        = shift;
    my %hash        = @_;
    my $conf        = $self->configure_object;
    my $err         = $self->error_object;
    my $at          = $self->author_tree;

    my $tmpl = {
        data            => { default => {}, strict_type => 1 }, 
        list            => { required => 1, default => [], strict_type => 1 },
        authors_only    => { default => 0 },
        verbose         => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my @list;
    my $authortree;  
    
    ### in case of a limited search set ###
    if( my @obs = values %{$args->{data}} ) {
        for ( @obs ) {
            $authortree->{ $_->author } = $at->{ $_->author };          
        }
    } else {
        $authortree = $at;
    }
          
    ### loop over the list provided, compare every element against the
    ### proper entry of the hashref in the cpan author tree
    ### if it matches, put it in the hashref we'll return.

    ### this hashref holds a list of CPAN id's that match the search criteria
    ### we then look in _query_mod_tree to find which modules are belonging
    ### to those id's

    for my $el ( @{$args->{'list'}} ) {

        ### i dont recall why i used a quotemeta here... -kane
        # my $el = quotemeta $arg;

        if ($el =~ /\w/) {
            for (keys %{$authortree}) {
                if ($authortree->{$_}->{'name'} =~ /$el/ or /$el/) {
                    push @list, $_;    #build a regexp
                } #if
            } #for
        } #if
    } #for

    ### in case we are only interested in the author object: ###
    if ( $args->{authors_only} ) {
        my $rv;
        for my $auth (@list) { $rv->{$auth} = $self->author_tree->{$auth} }
        return $rv;
    }

    ### if we are going to query again, we'll need to reconstruct the
    ### the regexp, else we'll get more matches than we bargained for;
    my @reglist = map { '^'.$_.'$' } @list;
    return $self->_query_mod_tree( 
                        type => 'author', 
                        list => \@reglist, 
                        data => $args->{data} 
                    );

} #_query_author_tree


sub _distributions {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        verbose => { default => $conf->get_conf('verbose') },
        author  => { required => 1 },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    ### all to please warnings...
    my $auth = $args->{'author'};

    my $modules = $self->_query_mod_tree( list => [$auth], type => 'author' );

    ### if we didn't get any modules, the author doesn't have a checksums file
    ### in his home dir, so we can save ourselves some trouble and return.
    return 0 unless $modules;

    while(  my ($name,$mod) = each %$modules ) {
        ### a lot of modules could be found for ONE author.
        ### but they are all in the same CHECKSUMS file.
        ### so we can exit the loop after the first one... -kane
        return $self->_get_checksums( mod => $mod, force => 1 );
    }
}


### Get a list of files which are used by a module ###
### pass it a module argument and a type for the type of files ###
sub _files {
    return shift->_extutils_installed(@_, method => 'files');
}

### Ditto, but returns the installed directory tree ###
sub _directories {
    return shift->_extutils_installed(@_, method => 'directory_tree');
}

### Ditto, but returns the packlist file name ###
sub _packlist_file {
    my $packlist = shift->_extutils_installed(@_, method => 'packlist')
        or return 0;

    return $packlist->[0]->packlist_file;
}

### Utility function to return a ExtUtils::Installed object; not directly used
sub _extutils_installed {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        verbose => { default => $conf->get_conf('verbose') },
        type    => { default => '' },
        module  => { required => 1 },
        method  => { required => 1, allow =>  [qw|files directory_tree packlist|] },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $type    = $args->{'type'};
    my $mod     = $args->{'module'};
    my $method  = $args->{'method'};

    ### check prerequisites
    my $use_list = { 'ExtUtils::Installed' => '0.0' };

    if ($self->_can_use(modules => $use_list)) {

        my $inst;
        unless ($inst = ExtUtils::Installed->new() ) {
            $err->trap( error => loc("Could not create an ExtUtils::Installed object") );
            return 0;
        }

        {   ### happy happy happy, joy joy joy
            ### yet another module that thinks it's ok to croak
            ### instead of return 0.
            ### I am NOT happy -kane

            my @files  = eval { $inst->$method( $mod, $type ) };

            if ($@) {
                chomp $@;
                $err->trap( error => loc("Could no get %1 for %2: %3", $method, $mod, $@) );
                return 0;
            }

            return @files ? \@files : 0;
        }

    } else {

        $err->trap(
            error => loc(   "You don't have ExtUtils::Installed available - " .
                            "can not find files for %1", $mod )
        );
        return 0;
    }
}


sub _readme {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        verbose => { default => $conf->get_conf('verbose') },
        force   => { default => $conf->get_conf('force') },
        module  => { required => 1, allow => sub { UNIVERSAL::isa( pop(),
                                                'CPANPLUS::Internals::Module') }
                    },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $mod     = $args->{'module'};

    ### build the path we need to look at on the cpan mirror ###
    my $path    = File::Spec::Unix->catdir(
                        $conf->_get_ftp('base'),
                        $mod->path
                    );

    ### and the dir we need to save to ###
    my $fetchdir = File::Spec->catdir(
                                $conf->_get_build('base'),
                                $conf->_get_ftp('base'),
                                $mod->path,
                            );

    ### what is the name of the file we need? ###
    my $package = $mod->package;

    my $flag;
    if ( $package =~ s/(.+?)\.(?:(?:tar\.)?gz|tgz)$/$1\.readme/i ) {
        $flag = 1;

    ### else, it might be a .zip file
    } elsif ( $package =~ s/(.+?)\.zip$/$1\.readme/i ) {
        $flag = 1;
    }

    unless ($flag) {
        $err->trap( error => loc("unknown package %1", $mod->package) );
        return 0;
    }

    my $file = $self->_fetch(
                        file        => $package,
                        dir         => $path,
                        fetchdir    => $fetchdir,
        ) or return 0;

    my $fh = new FileHandle;
    unless ($fh->open($file)) {
        $err->trap( error => loc("Could not open %1: %2", $file, $!) );
        return 0;
    }

    my $in;
    { local $/; $in = <$fh> }
    $fh->close;

    return $in;
}

##-> sub CPAN::Module::inst_file ;
#sub inst_file {
#    my($self) = @_;
#    my($dir,@packpath);
#    @packpath = split /::/, $self->{ID};
#    $packpath[-1] .= ".pm";
#    foreach $dir (@INC) {
#        my $pmfile = File::Spec->catfile($dir,@packpath);
#        if (-f $pmfile){
#            return $pmfile;
#        }
#    }
#    return;
#}
#'
sub _installed {
    my $self    = shift;
    my %hash    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $tmpl = {
        module  => { default => '' },
        verbose => { default => $conf->get_conf("verbose") },
    };

    my $args    = check( $tmpl, \%hash ) or return undef;
    my $modobj  = $args->{module} or return $self->_all_installed(%$args);

    ### check prerequisites
    my $use_list = { 'File::Spec' => '0.0' };

    if ($self->_can_use(modules => $use_list)) {
        my $name = $modobj->module();

        my @path = split /::/, $name;

        my $module = (pop @path) . '.pm';

        for my $dir( @INC ) {
            my $file = File::Spec->catfile( $dir, @path, $module );

            if( -f $file ) {
                return $file;
            }
        }

        ### if we got here, we didn't find the file =/
        ### silence it for now, if you're doing a generic 'what files do
        ### i have installed' it will flood your screen
        #$err->trap( error => qq[Could not find any files for $name] );
        return undef;

    } else {
        $err->trap( error => loc("You do not have File::Spec installed!") );
        return undef;
    }
}

### according to a bug report by allen smith,
### _installed wasn't doing the right thing, nor was it fast enough
### we try with a more CPAN.pm-like way and rename this one to _old_installed
### so we can switch back if required --kane
sub _all_installed {
    my $self    = shift;
    #my %args    = @_;
    my $err     = $self->error_object;
    my $conf    = $self->configure_object;

    my $uselist = { 'File::Find' => '0.0' };

    if ( $self->_can_use(modules => $uselist) ) {
        ### grab the module tree ###
        my $modtree = $self->_module_tree();

        my ($rv, %seen);

        foreach my $dir (@INC) {
            next if $dir eq '.';
            File::Find::find(sub {
                return unless /\.pm$/;
                return if $seen{$File::Find::name}++;

                my $mod = $File::Find::name;
                $mod = substr($mod, length($dir) + 1, -3);
                $mod =~ s|/|::|g;
                $rv->{$mod} = $File::Find::name
                    if exists $modtree->{$mod};
            }, $dir);
        }

        return $rv;

    } else {
        $err->trap(error => loc("You do not have ExtUtils::Installed available!") );
        return 0;
    }
}


sub _validate_module {
    my $self = shift;
    my %hash = @_;
    my $err  = $self->error_object;
    my $conf = $self->configure_object;

    my $tmpl = {
        module => { required => 1 },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    ### return 0 if we didn't get the proper arguments.. shouldn't happen tho
    my $mod = $args->{'module'};

    ### let's first see if we have the module installed even
    ### will return undef if not, and a hashref if so -kane
    my $rv = $self->_check_install(module => $mod);

    unless($rv){
        $err->trap( error => loc("Module %1 not installed! Can not validate!", $mod) );
        return 0;
    }

    my $uselist = { 'ExtUtils::Installed' => '0.0' };

    if ( $self->_can_use(modules => $uselist) ) {

        my $inst = new ExtUtils::Installed;

        ### eval needed.. this silly module just DIES on an error.. GREAT! -kane
        my @list = eval { $inst->validate($mod) };

        if ($@){ $err->trap( error => loc("Error while validating %1: %2", $mod, $@) ); }

        return \@list;

    } else {
        $err->trap(error => loc("You do not have ExtUtils::Installed available!") );
        return 0;
    }
}

1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
