# $File: //depot/cpanplus/dist/lib/CPANPLUS/Internals.pm $
# $Revision: #4 $ $Change: 1963 $ $DateTime: 2002/11/04 16:32:10 $

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
use CPANPLUS::Configure;
use CPANPLUS::Error;
use CPANPLUS::Backend;
use CPANPLUS::I18N;

use CPANPLUS::Internals::Extract;
use CPANPLUS::Internals::Fetch;
use CPANPLUS::Internals::Install;
use CPANPLUS::Internals::Make;
#use CPANPLUS::Internals::Module;
use CPANPLUS::Internals::Search;
use CPANPLUS::Internals::Source;
use CPANPLUS::Internals::Report;
use CPANPLUS::Internals::Utils;

use Cwd;
use Config;
use Data::Dumper;
use FileHandle;
use File::Path ();

### can't use F::S::F - FreeBSD stable does not ship with it
### no big worry, F::S::F is just a wrapper for F::S anyway
#use File::Spec::Functions;


BEGIN {
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw(
                        CPANPLUS::Internals::Utils
                        CPANPLUS::Internals::Extract
                        CPANPLUS::Internals::Fetch
                        CPANPLUS::Internals::Install
                        CPANPLUS::Internals::Make
                        CPANPLUS::Internals::Search
                        CPANPLUS::Internals::Source
                        CPANPLUS::Internals::Report
                    );

    $VERSION    =   '0.040';
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
    my $count = 0;


    sub _inc_id { return ++$count; }

    sub _last_id { $count }

    sub _store_id {
        my $self    = shift;
        my $err     = $self->error_object;
        my $obj     = shift;

        my $ref = ref $obj;

        unless( $ref eq 'CPANPLUS::Backend' ) {

            $err->trap( error => loc("The object you passed has the wrong ref type: '%1'", $ref) );
            return 0;
        }

        $idref->{ $obj->{_id} } = $obj;

        return $obj->{_id};
    }

    ### this missed a bunch of keys when we needed them... ###
    sub _old_store_id {
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

        my $obj = $idref->{$id};

        return $obj;
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

    ### temporary warning until we fix the storing of multiple id's
    ### and their serialization:
    if( _last_id() ) {
        warn qq[CPANPLUS currently only supports one Backend object per running program\n];
        return undef;
    }

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
        _conf   => $conf,
        _error  => $err,
        _id     => _inc_id()
    };

    ### bless the hashref into the package ###
    bless ($data, $class);

    ### allow for dirs to be added to @INC at runtime, rather then compile time
    push @INC, @{$conf->get_conf('lib')};

    ### in case we're not allowed to actually install modules, we add their build dirs
    ### to @INC and $ENV{PERL5LIB}. we store the originals here, so we can restore them
    ### when we flush
    $data->{_lib} = [ @INC ];
    $data->{_perl5lib} = $ENV{PERL5LIB};

    ### store the current dir, so we may return to it, use it, etc.
    ### is this portable? -jmb
    ### changed to use File::Spec::Functions.. have to use File::Spec->catfile tho - Kane
    ### Why do we need File::Spec->catfile? -jmb
    ### to get the trailing dir separator - Kane
    ### but if you use File::Spec functions everywhere it won't matter -jmb
    #$conf->_set_build(startdir => File::Spec->catfile( cwd, '') ),
    $conf->_set_build( startdir => cwd ),
        or $err->trap( error => loc("couldn't locate current dir!") );

    ### check if we need to use Passive FTP.. required by some dumb servers
    ### and annoying firewalls
    ### should we check this here, or in the _fetch stuff? -jmb

    ### if we do it in _fetch, anyone calling _lwp_get directly wouldn't get
    ### the switch set... and even lynx adheres to it, so in the constructor
    ### is best imo - Kane
    ### yes, but maybe they shouldn't do that? :o)
    ### this works best, and always... let's leave it - Kane

    $ENV{FTP_PASSIVE} = 1, if $conf->_get_ftp('passive');

    ### this is failing if we simply delete ONE file...
    ### so an uptodate check for all of them is needed i think - Kane.
    ### we should also find a way to pass a 'force' flag to _check_uptodate
    ### to force refetching of the source files.
    ### there is a flag available in the sub, but how do we get the user to
    ### toggle it?

    return $data;
}

### check if we can use certain modules ###
### this is only used internally to see if we can use things like LWP or Net::FTP ###
sub _can_use {
    my $self = shift;
    my %args = @_;
    my $conf = $self->{_conf};
    my $err  = $self->{_error};


    ### we keep our own version of %INC, namely $self->{_inc}. This basically tells us
    ### whether or not we already did a '_can_use' on this module, and whether it was
    ### successful (1) or not (0).
    ### this gives us the chance to go through the scanning of usable modules faster
    ### (some modules are required by more then one method), whereas we still have the
    ### opportunity to force a re-check by deleting the key from $self->{_inc}

    my $who = (caller 1)[3];
    my $href = $args{'modules'} or die qq[$who did not give proper arguments];

    ### optional argument. if true, we will complain about not having these modules ###
    my $yell = $args{'complain'};

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
                error => loc("Already attempted to use %1, which was unsuccessful", $m),
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
                            error => loc("Using %1 was unsuccessful for %2 [THIS MAY BE A PROBLEM!]: %3", $m, $list[3], $@),
                            quiet => !$yell
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
                    error => loc("Using %1 was unsuccessful for %2 [THIS MAY BE A PROBLEM!]: %3", $m, $list[3], loc("Module not found")),
                    quiet => !$yell
                );

                return 0;
            }
        }
    }
    return 1;
}

### check if we can run some command ###
sub _can_run {
    my ($self, $command) = @_;

    return unless $self->_can_use(
        modules => { 'ExtUtils::MakeMaker' => '0.0' },
    );

    for my $dir (split /$Config{path_sep}/, $ENV{PATH}) {
        my $abs = File::Spec->catfile($dir, $command);
        return $abs if $abs = MM->maybe_command($abs);
    }
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
            $err->inform( msg => loc("%1 installed successfully", $mod) )
        } else {
            $err->trap( error => loc("Install of %1 failed in %2", $mod, $subname) );
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
        unless ($cache eq '_lib') {
            delete $self->{$cache};
        } else {
            ### reset @INC to it's original state ###
            @INC            = @{$self->{_lib}};
            $ENV{PERL5LIB}  = $self->{_perl5lib} || '';
        }
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

    if ($self->_can_use(modules => $use_list)) {

        my $cache;
        unless( $cache = $conf->get_conf('cache') ) {
            $err->inform( msg => loc("No cache limit entered, ignoring dir size") );
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
                            error => loc("could not unlink %1: %2", $aref->[0], $!)
                        );
                }

                $size -= $gs;
            }
        }
        return $size > $cache * 1024 ? 0 : 1;
    }
}

### parse a modname/distname/modobj into a ($name, $modobj) tuple --
### $name is the package name for distributions, or module name for
### modobj/modname entries. the $modobj is always a module object.
### returns an empty list for malformed distnames or nonexistent modnames.
sub _parse_module {
    my $self = shift;
    my %args = @_;

    my $err = $self->{_error};

    my $mod = $args{mod} or return 0;

    my ($name, $modobj);

    ### simple heuristic: if $mod isn't a object, and contains non-word,
    ### non-colon characters, we pad a leading '/' to signify it's a distname.
    if (not ref($mod) and $mod =~ /[^\w:]/) {
        $mod = "/$mod" unless $mod =~ m|^/|;
    }

    ### a distribution name - walk _modtree to find any module in it
    if ( $mod =~ m|/| ) {
        unless ($mod =~ m|.*/(.+)$|) {
            $err->trap( error => loc("%1 is not a proper distribution name!", $mod) );
            return ();
        }

        my $dist = $1;
        my $modtree = $self->module_tree;

        ### $guess contains our 'best guess' for the module entry
        my $guess = $dist;
        $guess =~ s/(?:[\.\d\-_])*\..*//;
        $guess =~ s/-/::/g;

        ### does the 'best guess' module exist?
        if (exists $modtree->{$guess} and $modtree->{$guess}{package} eq $dist) {
            ### yes - just assign it to $modobj then
            $modobj = $modtree->{$guess};
        }
        else {
            $guess =~ s/::/-/g;

            ### $path contains the guessed author of the dist
            my $author;

            ### no - walk modtree to see if anything else matches
            while (my ($key, $val) = each %{$modtree}) {
                ### wrong; the distname not matched at the beginning of string
                next if index($val->{package}, $guess);

                ### an approximate match - different version of the same dist?
                if ($val->{package} ne $dist) {
                    $author = $val->{author}
                        if $val->{package} =~ /^\Q$guess\E(?:[\.\d\-_])*\./;
                    next;
                }

                ### exact match
                $modobj = $val;
                keys %{$modtree}; last;
            }

            ### fill the author in unless we've found the exact match
            $mod = "/$author/$dist"
                unless $modobj or $mod =~ m|/.*/| or !defined($author);
        }

        unless ($modobj) {
            ### can't find any module in it -- must be an outdated dist
            ### we'll forge a fake module object, deduced by its name

            my @parts = split(/\/+/, $mod);

            my $file   = pop @parts;
            my $author = pop @parts;

            ### be extra friendly and pad the .tar.gz suffix where needed
            $file .= '.tar.gz' unless $file =~ /\.[A-Za-z]+$/;

            unless (length $author) {
                $err->trap( error => loc("%1 does not contain an author directory!", $mod) );
                return ();
            }

            my $path = File::Spec::Unix->catdir(
                substr($author, 0, 1), substr($author, 0, 2), $author
            );

            my $fetchdir = File::Spec->catdir(
                $self->{_conf}->_get_build(qw[base autdir]),
                $path,
            );

            $modobj = CPANPLUS::Internals::Module->new(
                module      => $file,           # full module name
                path        => $path,           # extended path, like /A/AB/ABIGAIL
                fetchdir    => $fetchdir,       # the path on the local disk
                author      => $author,         # module author
                package     => $file,           # package name, like 'foo-bar-baz-1.03.tar.gz'

                ### it doesn't use these -kane
                #_error      => $self->{_error}, # error object
                #_conf       => $self->{_conf},  # configure object
                _id         => $self->{_id},
            );
        }

        $name = File::Spec::Unix->catdir('', $modobj->{path}, $modobj->{package});
    }

    ### the user asked us for a module, say Acme::Bleach
    else {
        ### either we pass it a module object, OR just a name
        ### we have to accept objects to work properly with
        ### CPANPLUS::Internals::Module, cuz IT doesn't store a
        ### _modtree for $self.
        if ( ref($mod) and UNIVERSAL::isa($mod, 'CPANPLUS::Internals::Module') ) {
            ### ok, it's an object
            $modobj = $mod;
        } else {
            $modobj = $self->module_tree->{$mod} or return ();
        }

        unless ($modobj) {
            $err->trap( error => loc("Cannot find %1 in the module tree!", $mod) );
            return ();
        }

        $name = $modobj->{module};
    }

    return ($name, $modobj);
}


### Execute a command: $cmd may be a scalar or an arrayref of cmd and args
### $bufout is an scalar ref to store outputs, $verbose can override conf
sub _run {
    my ($self, %args) = @_;
    my ($cmd, $buffer, $verbose) = @args{qw|command buffer verbose|};
    my $err = $self->{_error};
    my ($buferr, $bufout);

    $$buffer = '';
    $verbose = $self->{_conf}->get_conf('verbose')
        unless defined $verbose;

    ### STDOUT message handler
    my $_out_handler = sub {
        my $buf = shift; print STDOUT $buf if $verbose;
        $$buffer .= $buf; $bufout .= $buf;
        $err->inform( msg => $1, quiet => 1 ) while $bufout =~ s/(.*)\n//;
    };

    ### STDERR message handler
    my $_err_handler = sub {
        my $buf = shift; print STDERR $buf if $verbose;
        $$buffer .= $buf; $buferr .= $buf;
        $err->trap( error => $1, quiet => 1 ) while $buferr =~ s/(.*)\n//;
    };

    my @cmd = ref($cmd) ? grep(length, @{$cmd}) : $cmd;
    my $is_win98 = ($^O eq 'MSWin32' and !Win32::IsWinNT());

    ### Kludge! This enables autoflushing for each perl process we launched.
    ### this stops warnings if $ENV{PERL5OPT} is not yet defined.
    ### patch proposed by: Jonathan Leffler - jleffler@us.ibm.com
    local $ENV{PERL5OPT} .= ' -MCPANPLUS::Internals::System=autoflush=1';#

    ### inform the user. note that we don't want to used mangled $verbose.
    $err->inform(
        msg   => loc("Running [%1]...", "@cmd"),
        quiet => !$self->{_conf}->get_conf('verbose'),
    );

    ### First, we prefer Barrie Slaymaker's wonderful IPC::Run module.
    if (!$is_win98 and $self->_can_use(
        modules  => { 'IPC::Run' => '0.55' },
        complain => ($^O eq 'MSWin32'),
    ) ) {
        STDOUT->autoflush(1); STDERR->autoflush(1);

        @cmd = ref($cmd) ? ( [ @cmd ], \*STDIN )
                         : map { /[<>|&]/ ? $_ : [ split / +/ ] } split(/\s*([<>|&])\s*/, $cmd);

        IPC::Run::run(@cmd, $_out_handler, $_err_handler);
    }

    ### Next, IPC::Open3 is know to fail on Win32, but works on Un*x.
    elsif ($^O !~ /^(?:MSWin32|cygwin)$/ and $self->_can_use(
        modules => { map { $_ => '0.0' } qw|IPC::Open3 IO::Select Symbol| },
    ) ) {
        $self->_open3_run(\@cmd, $_out_handler, $_err_handler);
    }

    ### Abandon all hope; falls back to simple system() on verbose calls.
    elsif ($verbose) {
        system(@cmd);
    }

    ### Non-verbose system() needs to have STDOUT and STDERR muted.
    else {
        local *SAVEOUT; local *SAVEERR;

        open(SAVEOUT, ">&STDOUT")
            or ($err->trap( error => loc("couldn't dup STDOUT: %1", $!) ), return);
        open(STDOUT, ">".File::Spec->devnull)
            or ($err->trap( error => loc("couldn't reopen STDOUT: %1", $!) ), return);

        open(SAVEERR, ">&STDERR")
            or ($err->trap( error => loc("couldn't dup STDERR: %1", $!) ), return);
        open(STDERR, ">".File::Spec->devnull)
            or ($err->trap( error => loc("couldn't reopen STDERR: %1", $!) ), return);

        system(@cmd);

        open(STDOUT, ">&SAVEOUT")
            or ($err->trap( error => loc("couldn't restore STDOUT: %1", $!) ), return);
        open(STDERR, ">&SAVEERR")
            or ($err->trap( error => loc("couldn't restore STDERR: %1", $!) ), return);
    }

    $_out_handler->("\n") if defined $bufout and length $bufout;
    $_err_handler->("\n") if defined $buferr and length $buferr;

    return !$?;
}


### IPC::Run::run emulator, using IPC::Open3.
sub _open3_run {
    my ($self, $cmdref, $_out_handler, $_err_handler) = @_;
    my $err = $self->{_error};
    my @cmd = @{$cmdref};

    ### Following code are adapted from Friar 'abstracts' in the
    ### Perl Monastery (http://www.perlmonks.org/index.pl?node_id=151886).

    my ($infh, $outfh, $errfh); # open3 handles

    my $pid = eval {
        IPC::Open3::open3(
            $infh = Symbol::gensym(),
            $outfh = Symbol::gensym(),
            $errfh = Symbol::gensym(),
            @cmd,
        )
    };

    if ($@) {
        $err->trap( error => loc("couldn't spawn process: %1", $@) );
        return;
    }

    my $sel = IO::Select->new; # create a select object
    $sel->add($outfh, $errfh); # and add the fhs

    STDOUT->autoflush(1); STDERR->autoflush(1);
    $outfh->autoflush(1) if UNIVERSAL::can($outfh, 'autoflush');
    $errfh->autoflush(1) if UNIVERSAL::can($errfh, 'autoflush');

    while (my @ready = $sel->can_read) {
        foreach my $fh (@ready) { # loop through buffered handles
            # read up to 4096 bytes from this fh.
            my $len = sysread $fh, my($buf), 4096;

            if (not defined $len){
                # There was an error reading
                $err->trap( error => loc("Error from child: %1", $!) );
                return;
            }
            elsif ($len == 0){
                $sel->remove($fh); # finished reading
                next;
            }
            elsif ($fh == $outfh) {
                $_out_handler->($buf);
            } elsif ($fh == $errfh) {
                $_err_handler->($buf);
            } else {
                $err->trap( error => loc("IO::Select error") );
                return;
            }
        }
    }

    waitpid $pid, 0; # wait for it to die
    return 1;
}

### can't use this.. then if ONE of the objects would go out of scope,
### it would remove the reference to the internals ID, and no more sub
### sequent ones could be generated. this, of course, is bad --kane
sub DESTROY { 1 } #my $self = shift; $self->_remove_id( $self->{_id} ) }

### sub to find the version of a certain perlbinary we've been passed ###
sub _perl_version {
    my $self = shift;
    my %args = @_;
    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    return 0 unless $args{perl};

    ### there might be a more elegant way to do this... ###
    my $cmd = $args{perl} . ' -MConfig -eprint+Config::config_vars+version';
    my ($perl_version) = (`$cmd` =~ /version='(.*)'/);

    return $perl_version;
}
1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
