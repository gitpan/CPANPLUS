# $File: //member/autrijus/cpanplus/dist/lib/CPANPLUS/Internals.pm $
# $Revision: #3 $ $Change: 3540 $ $DateTime: 2002/03/26 04:28:49 $

#######################################################
###               CPANPLUS/Internals.pm             ###
### Module to provide an interface to the CPAN++    ###
###         Written 17-08-2001 by Jos Boumans       ###
#######################################################

### Internals.pm ###

package CPANPLUS::Internals;

use strict;
### required files. I think we can now get rid of Carp, since we use Error.pm
### Data::Dumper is here just for debugging - both are core, so no worries -Kane
use Carp;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use CPANPLUS::Backend;

use CPANPLUS::Internals::Extract;
use CPANPLUS::Internals::Fetch;
use CPANPLUS::Internals::Install;
use CPANPLUS::Internals::Make;
#use CPANPLUS::Internals::Module;
use CPANPLUS::Internals::Search;
use CPANPLUS::Internals::Source;

use Cwd;
use Data::Dumper;
use FileHandle;
use File::Path ();

### can't use F::S::F - FreeBSD stable does not ship with it
### no big worry, F::S::F is just a wrapper for F::S anyway
#use File::Spec::Functions;


BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter
                        CPANPLUS::Internals::Extract
                        CPANPLUS::Internals::Fetch
                        CPANPLUS::Internals::Install
                        CPANPLUS::Internals::Make
                        CPANPLUS::Internals::Search
                        CPANPLUS::Internals::Source
                    );

    $VERSION    =   '0.01';
}

### ROUGH FLOW OF THE MODULE ###

### --- this will need revision at some time probably, seeing the changes we've made -kane ###

### basically, the flow of the module is as follows:
### you call 'new', which then calls Configure and Error, to have its preferences
### and error handler available
### next, a check is done if the source files are up to date ( that is _check_uptodate ).
### if not, we'll try to fetch
### them using _fetch. more explanation about _fetch and friends further down.
### it then builds the author and module tree, which are also stored in the object.

### _query_auth_tree and _query_mod_tree are the 2 methods you can use to get back the full
### information about one or more modules.

### the most elaborate method you can call is _install_module. all other methods are called
### somewhere from here, so they'll be mentioned here:
### first, it will fetch the module. it by then assumes that only valid modules are passed.
### an invalid module will lead to an error from _fetch

### _fetch in turn will first try to call _lwp_get, which of course downloads with LWP
### if LWP is not available, we try _ftp_get, which uses Net::FTP - should be core at 5.8
### a command line tool still needs to be implemented, in case both of the above modules are
### not available
### information about where to fetch/store the modules is stored in Config.pm, which is accessed
### through the object Configure returns

### next, _extract is called. it in turn will call either _unzip or _untar. there's also _gunzip,
### which uses Compress::Zlib really to gunzip a file (currently only needed for the source files
### - 01mailrc.txt and 02package.details.txt)
### depending on the suffix of the file name, either _unzip or _untar will handle the extracting,
### and return a directory name where the extracted files may be found.
### here also we only have a pure perl implementation, requiring the Compress::Zlib and Archive::*
### modules. We still need to add a command line facility for this.
### NOTE: Commport is working on a pure perl bzip2, that might work for us.

### next, _make is called, which is arguably the most complex method for the simple reason it will
### call itself if need be.
### first _make will try to run 'perl Makefile.PL'. at the lack of a makefile, we'll try to
### make one ourselves using _make_makefile (adding in the version and module name only).
### at this point, we also run _check_prereq to see if this module has any prerequisites.
### if so, we check if they are already installed and if they're not, if we're allowed to
### install them (in case we aren't, we return a list of prereqs to the caller, so he can figure
### out what he wants to do with them.
### if prereqs are found, and we can install them, the current _make is aborted.
### we store the directory we were running this _make in to a list of 'todo' dirs.
### we then proceed by downloading the prereqs one by one, and running _make on them. If they have
### prereqs, the entire spectacle repeats itself.
### so recursively, we're installing all the modules.
### however, if a prereq would be a certain version of perl, we're skipping that.. we don't really
### want to upgrade perl now do we?
### when the last prereq is installed, we go back to a higher level module (on that caused prereqs to
### install) and now try to install it, seeing all prereqs should be met by now. This also will repeat
### itself until actually the module we wanted to install, is installed.

### all these individual steps can be called separately, like _fetch, _make, etc
### Backend.pm provides an interface for it, and actually does error checking.
### Internals.pm takes most everything at face value.

### Options, preferences etc are set in Config.pm, which the object Configure returns, checks in.
### here, all methods find things like: what host to use, where to store files, what command line
### tools are available, etc

### END ROUGH FLOW ###



### constructor ###
### this is what a Data::Dumper of the object would roughly look like:

#$VAR1 = bless( {
#   '_modtree' => {
#       'Servlet::Http::HttpServletResponse' => {
#           'path' => 'I/IX/IX/',
#           'module' => 'Servlet::Http::HttpServletResponse',
#           'comment' => undef,
#           'author' => 'IX',
#           'package' => 'libservlet-0.9.1.tar.gz',
#           'version' => 'undef',
#           'dslip' => 'impf',
#       },
#       'Convert::Units::Base' => {
#           'path' => 'R/RR/RRWO/',
#           'module' => 'Convert::Units::Base',
#           'comment' => undef,
#           'author' => 'RRWO',
#           'package' => 'Convert-Units-0.43.tar.gz',
#           'version' => '0.43'
#           'dslip' => 'impf',
#       },
#       # etc...
#   },
#   '_authortree' => {
#       'JEREMIE' => {
#           'email' => 'jer@jeremie.com',
#           'name' => 'Jeremie Miller'
#       },
#       'MERLIN' => {
#           'email' => 'merlin.cpan@merlin.org',
#           'name' => 'Merlin Hughes'
#       },
#   },
#   '_error' => bless( {
#       'INFORM' => [
#           'already downloaded /home/cpanplus/02packages.details.txt.gz, won\'t download again without force',
#           'already downloaded /home/cpanplus/01mailrc.txt.gz, won\'t download again without force',
#           'updating source files'
#       ],
#       'DEBUG' => 1,
#       'MSG' => 'already downloaded /home/cpanplus/02packages.details.txt.gz, won\'t download again without force',
#       'ERROR' => '',
#       'STACK' => []
#   }, 'CPANPLUS::Error' ),
#   '_conf' => bless( {}, 'CPANPLUS::Configure' )
#}, 'CPANPLUS::Internals' );

### _authortree is the parsed version of 01mailrc.txt, telling us the email and the full name going
### with a CPAN id.. we use it to look up modules written by a certain author.
### _modtree is the actual list of modules on CPAN, and is obtained by parsing 02packages.details.txt
### _conf is the object returned by Configure.pm, which accesses the variables/preferences in Config.pm
### _error is the object returned by Error.pm, which takes care of error handling in cpanplus.
### it allows for a stacktrace, carp level and verbosity settings.


{
    my $idref = {};
    my $count = 5;


    sub _inc_id { return ++$count; }

    sub _store_id {
        my $self = shift;
        my %hash = @_;

        ### allowed data ###
        my $_data = {
            _id         => { required => 1 },   # the id under which to store the info
            _authortree => { required => 1 },   # the author tree
            _modtree    => { required => 1 },   # the module tree
            _error      => { required => 1 },   # reference to the error object from _init()
            _conf       => { required => 1 },   # reference to the configure object from _init()
        };


        ### we're unable to use this check now because it requires a working backend object ###
        #my $args = $Class->_is_ok( $_data, \%hash );
        #return 0 unless keys %$args;

        #my $object;
        ### put this in a loop so we can easily add stuff later if desired -kane
        #for my $key ( keys %$args ) {
        #    $object->{$key} = $args->{$key};
        #}

        my $object;
        ### so for now, this is the alternative ###
        for my $key ( keys %$_data ) {

            if ( $_data->{$key}->{required} && !$hash{$key} ) {
                die "Missing key $key\n";
                return 0;
            }

            if( defined $hash{$key} ) {
                if( $hash{$key} ) {
                    $object->{$key} = $hash{$key};
                }
            } else {
                $object->{$key} = $_data->{$key}->{default};
            }
        }

        my $id = $hash{_id};

        $idref->{$id} = $object;

        return $id;
    }

    sub _retrieve_id {
        my $self    = shift;
        my $id      = shift;

        return $idref->{$id};
    }

    sub _remove_id {
        my $self    = shift;
        my $id      = shift;

        return delete $idref->{$id};
    }
}


sub _init {
    my $class = shift;
    my %args = @_;

    ### constructor options to Configure need to be added -> Josh ###
    ### not pretty, but works for now -jmb
    ### no, we want stuff to override SEPERATE config options,
    ### like a way to specify another 'perl.exe'
    ### so new should be called like this:
    ### my $CP = CPANPLUS::Backend->new( perl => '/usr/bin/perl4' )
    ### or something - Kane
    ### ok, I added it to CPANPLUS::Backend.pm
    ### Configure shouldn't be called anymore I guess -jmb
    #my $conf = $args{conf} || new CPANPLUS::Configure;

    ### should really be a fatal exception to NOT get a configuration hash passed
    ### we can't use error.pm here yet... hmm =( -kane
    my $conf = $args{conf} or die qq[No configuration data passed to ] . $class->_whoami();

    ### only set message_level to 1 for development;
    ### will display many messages despite verbosity settings
    ### you can also set 'error_level'. it defaults to '1'.
    ### set it to 0 to just store errors but not act on them.
    ### or set it larger then 1 to actually make errors fatal (not recommended)
    my $err = CPANPLUS::Error->new(
        message_level   => (    defined $conf->get_conf('debug')
                                ? $conf->get_conf('debug')
                                : 1 ),

        error_track     => 1);

    my $data = {
        _conf     => $conf,
        _error    => $err,
    };

    ### bless the hashref into the package ###
    bless ($data, $class);

    ### allow for dirs to be added to @INC at runtime, rather then compile time
    push @INC, @{$conf->get_conf('lib')};

    ### store the current dir, so we may return to it, use it, etc.
    ### is this portable? -jmb
    ### changed to use File::Spec::Functions.. have to use File::Spec->catfile tho - Kane
    ### Why do we need File::Spec->catfile? -jmb
    ### to get the trailing dir separator - Kane
    ### but if you use File::Spec functions everywhere it won't matter -jmb
    #$conf->_set_build(startdir => File::Spec->catfile( cwd, '') ),
    $conf->_set_build( startdir => cwd ),
        or $err->trap( error => "couldn't locate current dir!" );

    ### check if we need to use Passive FTP.. required by some dumb servers
    ### and annoying firewalls
    ### should we check this here, or in the _fetch stuff? -jmb

    ### if we do it in _fetch, anyone calling _lwp_get directly wouldn't get
    ### the switch set... and even lynx adheres to it, so in the constructor
    ### is best imo - Kane
    ### yes, but maybe they shouldn't do that? :o)
    ### this works best, and always... let's leave it - Kane

    $ENV{FTP_PASSIVE} = 1, if $conf->_get_ftp('passive');

    ### a check to see if our source files are still up to date ###
    $err->inform(
        msg     => qq(checking if source files are up to date),
        quiet   => !$conf->get_conf('verbose')
    );

    ### this is failing if we simply delete ONE file...
    ### so an uptodate check for all of them is needed i think - Kane.
    ### we should also find a way to pass a 'force' flag to _check_uptodate
    ### to force refetching of the source files.
    ### there is a flag available in the sub, but how do we get the user to
    ### toggle it?

    my $uptodate = 1;

    for my $name (qw[auth mod dslip]) {
        for my $file ( $conf->_get_source( $name ) ) {
            $data->_check_uptodate(
                file => File::Spec->catfile(
                            $conf->_get_build('base'), $file
                ),
                name => $name,
                update_source => 0
            ) or $uptodate = 0;
        }
    }

    $data->{_id} = $data->_inc_id();

    ### build the trees ###
    ### perhaps there should be a method that builds all of the trees? -jmb
    $data->{_authortree}    = $data->_create_author_tree    (uptodate => $uptodate);
    $data->{_modtree}       = $data->_create_mod_tree       (uptodate => $uptodate);

    my $id = $data->_store_id(
                _id         => $data->{_id},
                _authortree => $data->{_authortree},
                _modtree    => $data->{_modtree},
                _error      => $data->{_error},
                _conf       => $data->{_conf},
    );

    unless ( $id == $data->{_id} ) {
        die qq[ID's do not match: $id vs $data->{_id}. Storage failed! -- ], $data->_whoami();
    }

    return $data;
}

### check if we can use certain modules ###
### this is only used internally to see if we can use things like LWP or Net::FTP ###
sub _can_use {
    my $self = shift;
    my $href = shift;
    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    ### we keep our own version of %INC, namely $self->{_inc}. This basically tells us
    ### whether or not we already did a '_can_use' on this module, and whether it was
    ### successful (1) or not (0).
    ### this gives us the chance to go through the scanning of usable modules faster
    ### (some modules are required by more then one method), whereas we still have the
    ### opportunity to force a re-check by deleting the key from $self->{_inc}

    for my $m (keys %$href) {

        ### check if we already successfully 'use'd this module ###
        if ( $self->{_inc}->{$m}->{usable} ) {
            next;

        ### else, check if the hash key is defined already, meaning $mod => 0,
        ### indicating UNSUCCESSFUL prior attempt of usage
        } elsif ( defined $self->{_inc}->{$m}->{usable}
                    && ($self->{_inc}->{$m}->{version} >= $href->{$m} )
                ) {

            $err->trap(
                error => "Already attempted to use $m, which was unsuccessful",
                quiet => 1
            );
            return;

        ### if we got here, this is the first time we're trying to use this module,
        ### or more accurately, there's no record of us trying in $self->{_inc}
        ### or the version is a LOWER one then we tried to use before...
        } else {
            my @list = caller 1;

            ### check if we have AN version of the module installed
            ### maybe we should expand on the version stuff in the future,
            ### allowing to check for say, 'Archive::Tar 0.22' or so
            my $mod_data = $self->_check_install( module => $m, version => $href->{$m} );

            #print Dumper $mod_data;

            $self->{_inc}->{$m}->{version} = $href->{$m};

            if ( $mod_data->{uptodate} ) {

                ### if we found the module in @INC, we eval it in to our package ###
                {   #local $@; can't use this, it's buggy -kane
                    eval "use $m";

                    ### in case anything goes wrong, log the error, the fact we tried to
                    ### use this module and return 0;
                    if ( $@ ) {

                        $self->{_inc}->{$m}->{usable} = 0;

                        $err->trap(
                            error => "Using $m was unsuccessful for $list[3]: $@",
                            quiet => 0
                        );
                        return 0;

                    ### no error, great. log in _inc and check the next one
                    } else {
                        $self->{_inc}->{$m}->{usable} = 1;
                        next;
                    }
            }

            ### module not found in @INC, store the result in _inc and return 0
            } else {
                $self->{_inc}->{$m}->{usable} = 0;

                $err->trap(
                    error => "Using $m was unsuccessful for $list[3]: Module not found",
                    quiet => 0
                );

                return 0;
            }
        }
    }
    return 1;
}

sub _whoami { return (caller 1)[3] }

### proto type code to auto upgrade
### not actually used yet
sub _auto_upgrade {
    my $self = shift;
    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $subname = $self->_whoami();

    my $prereq_store = $conf->get_conf('prereqs');

    $conf->set_conf( prereqs => 1 ) unless $prereq_store == 1;

    ### this should come out of $conf ###
    ### jmb, please fix =) - kane ###
    my @upgrades = qw(
        Compress::Zlib
        Archive::Tar
        Net::FTP
        Archive::Zip
        LWP
        Storable
        Digest::MD5
    );

    my $flag;
    ### looping thru them one by one so we can catch the errors more
    ### explicitly - kane
    for my $mod ( @upgrades ) {

        my $rv = $self->_install_module( modules => [$mod] );

        if ($rv) {
            ### being explicitly verbose ###
            $err->inform( msg => "$mod installed succesfully" )
        } else {
            $err->trap( error => "Install of $mod failed in $subname" );
            $flag = 1;
        }
    }

    $conf->set_conf( prereqs => $prereq_store );

    ### return 0 if one of the modules failed to install ###
    return $flag ? 0 : 1;
}



### flush cached data
sub _flush {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    for my $cache( @{$args{'list'}} ) {
        delete $self->{$cache};
    }

    return 1;
}

sub _cache_control {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $subname = $self->_whoami();
    my ($method) = $subname =~ m|.+::(.+?)|;

    ### check prerequisites
    my $use_list = {
            'File::Find'  => '0.0',
            'File::Spec'  => '0.0',
            'Cwd'         => '0.0',
    };

    if ($self->_can_use($use_list)) {

        my $cache;
        unless( $cache = $conf->get_conf('cache') ) {
            $err->inform( msg => "No cache limit entered, ignoring dir size" );
            return 1;
        }

        my $href;
        my $size;
        my $sub = sub {
            push @{ $href->{ sprintf "%09i", -M $_ } }, [ File::Spec->catfile(cwd, $_), -s $_ ];
            $size += -s $_;
        };

        ### $href will look something like this:
        ### 000000187' => [
        ###         [
        ###             'D:\\tmp\\bot\\multopia\\Multopia\\Config.pm',
        ###             818
        ###         ],
        ###         [
        ###             'D:\\tmp\\bot\\multopia\\Multopia\\DataBase.pm',
        ###             5639
        ###         ]
        ### ],
        ### the key is the age in days of a file group, the value is an array ref
        ### ->[0] is the file name, ->[1] is the file size in bytes

        for my $dir ( qw[moddir autdir] ) {

            find($sub, File::Spec->catfile(
                            $conf->_get_build('base'),
                            $conf->_get_build( $dir )
                        )
                    );

            ### get the list of ages in oldest-first order
            my @list = reverse sort keys %$href;


            ### while the size of the
            while ( $size > $cache * 1024 ) {
                my $key = shift @list;

                last unless $key;

                my $gs;
                for my $aref ( @{ $href->{ $key } } ) {
                    $gs += $aref->[1];
                    unlink $aref->[0] or
                        $err->trap(
                            error => qq[could not unlink $aref->[0]: $!]
                        );
                }

                $size -= $gs;
            }
        }
        return $size > $cache * 1024 ? 0 : 1;
    }
}

sub DESTROY { my $self = shift; $self->_remove_id( $self->{_id} ) }

1;
