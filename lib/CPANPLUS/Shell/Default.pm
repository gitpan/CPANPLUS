# $File: //depot/cpanplus/dist/lib/CPANPLUS/Shell/Default.pm $
# $Revision: #18 $ $Change: 8345 $ $DateTime: 2003/10/05 17:25:48 $

##################################################
###            CPANPLUS/Shell/Default.pm       ###
### Module to provide a shell to the CPAN++    ###
###         Written 17-08-2001 by Jos Boumans  ###
##################################################

### Default.pm ###

### READ PLEASE -jmb
### when you update _help() you need to update the docs :o)
### would be nice to do this automatically somehow?

package CPANPLUS::Shell::Default;
use strict;

BEGIN {
    use vars        qw( $VERSION @ISA);
    @ISA        =   qw( CPANPLUS::Shell::_Base );
    $VERSION    =   '0.03';
}

use CPANPLUS::Shell ();
use CPANPLUS::Backend;
use CPANPLUS::I18N;
use CPANPLUS::Tools::Term;
use CPANPLUS::Tools::Check qw[check];

use Cwd;
use Term::ReadLine;
use Data::Dumper;
use FileHandle;

### our command set ###
my $cmd = {
    a   => "search",
    m   => "search",
    d   => "fetch",
    e   => "_expand_inc",
    f   => "distributions",
    i   => "install", # target => install
    t   => "install", # target => test
    h   => "_help",
    q   => "_quit", # also called on EOF and abnormal exits
    s   => "set_conf",
    c   => "reports",
    l   => "details",
    x   => "reload_indices",
    '?' => "_help",
    p   => "_print_stack",
    r   => "readme",
    o   => "uptodate",
    u   => "uninstall",
    v   => "_show_banner",
    # w => redisplay of the cache
    # z => open a command prompt in these dists
    # b => write a bundle
};
### free letters: g j k n y ###


### input check ###
my $maps = {
    m => "module",
    a => "author",
    ### not used yet ###
    v => "version",
    d => "path",
    p => "package",
    c => "comment",
};

sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    ### Will call the _init constructor in Internals.pm ###
    my $self = $class->SUPER::_init( brand => loc('CPAN Terminal') );

    return $self;
}

### The CPAN terminal interface ###
sub shell {
    my $self = shift;

    ### make an object ###
    my $cpan = new CPANPLUS::Backend;
    my $term = Term::ReadLine->new( $self->brand );
    my $prompt = $self->brand . "> ";

    ### set up tab completion hooks ###
    if (!$term->isa('CPANPLUS::Shell::_Faked')) {
        ### embeds the $cpan object in a closure ###
        $term->Attribs->{completion_function} = sub {
            _complete($cpan, @_);
        };
    }

    ### store this in the object, so we can access the prompt anywhere if need be
    $self->term(    $term);
    $self->backend( $cpan);

    ### this is not nice, we should do this better ###
    $cpan->{_shell} = $self;

    $self->_show_banner($cpan);
    $self->_input_loop($cpan, $prompt) or print "\n"; # print only on abnormal quits
    $self->_quit;
}

### input loop. returns true if exited normally via 'q'.
sub _input_loop {
    my ($self, $cpan, $prompt) = @_;

    $self->format("%5s %-50s %8s %-10s\n");

    my $term = $self->term;
    my $cache = [];      # results of previous search
    my $normal_quit;

    ### somehow it's caching previous input ###
    while (
        defined (my $input = eval { $term->readline($prompt) } )
        or $self->signals->{INT}{count} == 1
    ) { eval {

        ### re-initiate all signal handlers
        while (my ($sig, $entry) = each %{$self->signals} ) {
            $SIG{$sig} = $entry->{handler} if exists($entry->{handler});
        }


        ### parse the input: all commands are 1 letter, followed
        ### by a space, followed by an arbitrary string
        ### the first letter is the command key
        my $key; my $options;
        {   # why the block? -jmb
            # to hide the $1. -autrijus
            { $input =~ s/^([!?])/$1 /; }
            $input =~ s/^\s*([\w\?\!])\w*\s*//;
            chomp $input;
            $key = lc($1);

            ### grab command line options like --no-force and --verbose ###
            ($options,$input) = $term->parse_options($input);
        }


        ### exit the loop altogether
        if ($key =~ /^q/) { $normal_quit = 1; last }

        ### in case we got a command, and that command was either
        ### h or ?, we execute the command since they are in the
        ### current package.
        if ( $cmd->{$key} && ( $key =~ /^[?h]/ )) {
            my $method = $cmd->{$key};
            $self->$method();
            return;
        }

        ### dump stack, takes an optional 'file' argument for the stack to
        ### be printed to
        if ( $key =~ /^p/ ) {

            my $stack = $cpan->error_object->summarize( %$options );

            my $method = $cmd->{$key};
            $self->$method( stack => $stack, file => $input );
            return;
        }

        ### clean out the error stack and the message stack ###
        $cpan->error_object->flush();
        $cpan->error_object->forget();

        ### check for other commands that does not require an argument ###
        if ( $key =~ /^\!/ ) {
            # $input = 'system($ENV{SHELL} || $ENV{COMSPEC})' unless length $input;
            eval $input;
            $cpan->error_object->trap( error => $@ ) if $@;
            print "\n";
            return;

        } elsif ( $key =~ /^x/ ) {
            my $method = $cmd->{$key};

            print loc("Fetching new indices and rebuilding the module tree"), "\n";
            print loc("This may take a while..."), "\n";

            $cpan->$method(update_source => 1, %$options);

            return;
        } elsif ( $key =~ /^v/ ) {
            my $method = $cmd->{$key};
            $self->$method($cpan);
            return;

        } elsif ( $key =~ /^b/ ) {
            print loc(qq[Writing bundle file... This may take a while\n]);

            ### see backend's autobundle method to see why custom filenames
            ### are disabled --kane

            #my $args = {};
            #if( $input =~ /\S/ ) {
            #    my @parts = File::Spec->splitpath( $input );
            #
            #    $args = {
            #        file    => pop @parts,
            #        dir     => File::Spec->catdir(@parts),
            #    }
            #}
            #my $rv = $cpan->autobundle( %$args );


            my $rv = $cpan->autobundle;

            print $rv->ok
                ? loc( qq[\nWrote autobundle to %1\n], $rv->rv )
                : loc( qq[\nCould not create autobundle\n] );

            return;

        } elsif ( $key =~ /^w/ ) {

            $self->_pager_open if ($#{$cache} >= $self->_term_rowcount);

            print scalar @$cache
                ? (loc("Here is a listing of your previous search result:"), "\n")
                : (loc("No search was done yet."), "\n");

            my $i;
            for my $obj (@$cache) {

                ### first item is undef, so we can start counting from 1 ###
                $obj ? $i++ : next;

                my $fmt_version = $self->_format_version( version => $obj->version );

                    printf $self->format,
                           $i, ($obj->module, $fmt_version, $obj->author);
            }

            $self->_pager_close;

            return;

        } elsif ( $key =~ /^o/ ) {
            my $method = $cmd->{$key};

            my $modtree = $cpan->module_tree();
            my @list = $input
                    ? $self->_select_modules(
                            input   => $input,
                            prompt  => "Checking",
                            cache   => $cache,
                            key     => 'module',
                        )
                    : ();

            if ($input and !@list) {
                print loc("No modules to check."), "\n";
                return;
            }

            ### this option is just for the o command, not for the backend methods ###
            my $long = delete $options->{long} if defined $options->{long};
            delete $options->{short}; # backward compatibility

            my $inst = $cpan->installed( %$options, modules => @list ? \@list : undef );

            if( !$inst->rv or (!$inst->ok && $input) ) {
                print loc("Could not find installation files for all the modules"), "\n";
                return;
            }
            my $href = $cpan->$method( %$options, modules => [sort keys %{$inst->rv}] );

            my $res = $href->rv;
            $cache = [ undef ]; # most carbon-based life forms count from 1

            ### keep a cache by default ###
            my $seen = {};

            for my $name ( sort keys %$res ) {
                next unless $res->{$name}->{uptodate} eq '0';

		### dont list more than one module belonging to a package
		### blame H. Merijn Brand... -kane
                my $pkg = $modtree->{$name}->package;

                if ( $long or !$seen->{$pkg}++ ) {
                    push @{$cache}, $modtree->{$name};
                }
            }

            $self->_pager_open if ($#{$cache} >= $self->_term_rowcount);

            ### pretty print some information about the search
            for (1 .. $#{$cache}) {

                my ($module, $version, $author) = @{$cache->[$_]}{qw/module version author/};

                my $have    = $self->_format_version( version => $res->{$module}->{version} );
                my $can     = $self->_format_version( version => $version );

                my $local_format = "%5s %10s %10s %-40s %-10s\n";

                printf $local_format, $_, ($have, $can, $module, $author);
            }

            if ($#{$cache} == 0) {
                print loc("All module(s) up to date."), "\n";
            }

            $self->_pager_close;

            return;
        }



        ### if input has no length, we either got a signal, or a command without a
        ### required string;
        ### in either case we take apropriate action and skip the rest of the loop
        unless ( length $input or $key =~ /^s/ ) {

            unless ( defined $input ) {
                $self->{_signals}{INT}{count}++; # to counter the -- in continue block
            } elsif ( length $key ) {
                print loc("Improper command '%1'. Usage:", $key), "\n";
                $self->_help();
            }

            return;
        }

        ### s for set options ###
        if ( $key =~ /^s/ ) {
            ### perhaps we should go with FULL conf names,
            ### rather than expanding shortcuts -kane

            ### from CPAN.pm :o)
            # CPAN::Shell::o and CPAN::Config::edit are closely related. 'o conf'
            # should have been called set and 'o debug' maybe 'set debug'

            ### set configuration options
            my ($name, $value) = $input =~ m/(\w+)\s*(.*?)\s*$/;

            ### redo setup configuration?
            if ($name =~ m/^conf/i) {
                CPANPLUS::Configure::Setup->init(
                    conf    => $cpan->configure_object,
                    term    => $self->term,
                    backend => $cpan,
                );
                return;
            }
            elsif ($name =~ m/^save/i) {;
                $cpan->configure_object->save;
                print loc("Your CPAN++ configuration info has been saved!"), "\n\n";
                return;
            }

            ### allow lazy config options... not smart but possible ###
            my $conf = $cpan->configure_object;
            my @options = sort $conf->subtypes('conf');
            my $realname;
            for my $option (@options) {
                if (defined $name and $option =~ m/^$name/) {
                    $realname = $option;
                    last;
                }
            }

            my $method = $cmd->{$key};

            if ($realname) {
                $self->_set_config(
                    key    => $realname,
                    value  => $value,
                    method => $method,
                );
            } else {
                local $Data::Dumper::Indent = 0;
                print loc("'%1' is not a valid configuration option!", $name), "\n" if defined $name;
                print loc("Available options and their current values are:"), "\n";

                my $local_format = "    %-".(sort{$b<=>$a}(map(length, @options)))[0]."s %s\n";

                foreach $key (@options) {
                    my $val = $conf->get_conf($key);
                    ($val) = ref($val)
                                ? (Data::Dumper::Dumper($val) =~ /= (.*);$/)
                                : "'$val'";
                    printf $local_format, $key, $val;
                }
            }

        ### i is for install.. it takes multiple arguments, so:
        ### i POE LWP
        ### is perfectly valid.
        } elsif ( $key =~ /^[it]/ ) {
            ### prepare the list of modules we'll have to test/install ###
            my $target = ($key =~ /^i/) ? 'install' : 'test';

            my @list = $self->_select_modules(
                input   => $input,
                prompt  => ($key =~ /^i/) ? loc('Installing') : loc('Testing'),
                cache   => $cache,
                key     => 'module',
            );

            ### try to install them, get the return status back
            my $href = $cpan->install(
                                target      => $target,
                                %$options,
                                modules     => [ @list ],
                            );

            my $status = $href->rv;

            for my $key ( sort keys %$status ) {

                print $status->{$key}
                    ? (loc("Successfully %tense(%1,past) %2", $target, $key), "\n")
                    : (loc("Error %tense(%1,present) %2", $target, $key), "\n" );

            }
            
            my $flag;
            for ( @list ) { 
                $flag++ unless ref $href->rv && $href->rv->{$_} 
            }
            
            if( $href->ok and !$flag ) {
                print loc("All modules %tense(%1,past) successfully", $target), "\n";
            } else {
                print loc("Problem %tense(%1,present) one or more modules", $target), "\n";
                warn loc("*** You can view the complete error buffer by pressing '%1' ***\n", 'p')
                            unless $cpan->configure_object->get_conf('verbose');
            }

        ### d is for downloading modules.. can take multiple input like i does.
        ### so this works: d LWP POE
        } elsif ( $key =~ /^d/ ) {
            ### prepare the list of modules we'll have to fetch ###
            my @list = $self->_select_modules(
                input   => $input,
                prompt  => loc('Fetching'),
                cache   => $cache,
                key     => 'module',
            );

            ### get the result of our fetch... we store the modules in whatever
            ### dir the shell was invoked in.
            my $href = $cpan->fetch(
                fetchdir   => $cpan->configure_object->_get_build('startdir'),
                %$options,
                modules     => [ @list ],
            );

            my $status = $href->rv;

            for my $key ( sort keys %$status ) {
                print   $status->{$key}
                        ? (loc("Successfully fetched %1", $key), "\n")
                        : (loc("Error fetching %1", $key), "\n");
            }

            print $href->ok
                    ? (loc("All files downloaded successfully"), "\n")
                    : (loc("Problem downloading one or more files"), "\n");


        ### c is for displaying RT/CPAN Testing results.
        ### requires LWP.
        } elsif ( $key =~ /^c/ ) {
            ### prepare the list of modules we'll have to query ###
            my @list = $self->_select_modules(
                input   => $input,
                cache   => $cache,
                key     => 'module',
            );

            ### get the result of our listing...
            my $method = $cmd->{$key};
            my $res = $cpan->$method( %$options, modules => [ @list ] )->rv;

            foreach my $name (@list) {
                my $dist = $cpan->pathname(to => $name);
                my $url;

                foreach my $href ($res->{$name} || $res->{$dist}) {
                    print "[$dist]\n";

                    unless ($href) {
                        print loc("No reports available for this distribution."), "\n";
                        next;
                    }

                    foreach my $rv (@{$href}) {
                        printf "%8s %s%s\n", @{$rv}{'grade', 'platform'},
                                             ($rv->{details} ? ' (*)' : '');
                        $url ||= $rv->{details} if $rv->{details};
                    }
                }

                if ($url) {
                    $url =~ s/#.*//;
                    print "==> $url\n\n";
                }
                else {
                    print "\n";
                }
            }

        ### l gives a Listing of details for modules.
        ### also takes multiple arguments, so:
        ### l LWP POE #works just fine
        } elsif ( $key =~ /^l/ ) {
            ### prepare the list of modules we'll have to list ###
            my @list = $self->_select_modules(
                input   => $input,
                cache   => $cache,
                key     => 'module',
            );

            my $method = $cmd->{$key};
            my $href = $cpan->$method( %$options, modules => [ @list ] );

            my $res = $href->rv;

            for my $mod ( sort keys %$res ) {
                unless ( $res->{$mod} ) {
                    print loc("No details for %1 - it's probably outdated.", $mod), "\n";
                    next;
                }

                print loc("Details for %1", $mod), "\n";
                for my $item ( sort keys %{$res->{$mod}} ) {
                    printf "%-30s %-30s\n", $item, $res->{$mod}->{$item}
                }
                print "\n";
            }

        ### f gives a listing of distribution Files by a certain author
        ### also takes multiple arguments, so:
        ### f KANE DCONWAY #works just fine
        } elsif ( $key =~ /^f/ ) {
            ### split the input
            my @list = split /\s+/, $input;

            my $method = $cmd->{$key};
            my $href = $cpan->$method( %$options, authors => [ @list ] );

            my $res = $href->rv;

            unless ( $res and keys %$res ) {
                print loc("No authors found for your query"), "\n";
                return;
            }

            $cache = [ undef ]; # most carbon-based life forms count from 1

            for my $auth ( sort keys %$res ) {
                next unless $res->{$auth};

                my $path = '/'.substr($auth, 0, 1).'/'.substr($auth, 0, 2).'/'.$auth;

                $self->_pager_open if (keys %{$res->{$auth}} >= $self->_term_rowcount);

                for my $dist ( sort keys %{$res->{$auth}} ) {
                    push @{$cache}, "$path/$dist"; # full path to dist

                    ### pretty print some information about the search
                    printf $self->format,
                           $#{$cache}, $dist, $res->{$auth}->{$dist}->{size}, $auth;
                }

                $self->_pager_close;
            }

        ### r prints the readme file for a certain module
        ### also takes multiple arguments, so:
        ### r POE DBI #works just fine
        ### alltho you probably shouldn't do that
        } elsif ( $key =~ /^r/ ) {
            ### split the input
            my @list = $self->_select_modules(
                input   => $input,
                cache   => $cache,
            );

            my $method = $cmd->{$key};
            my $href = $cpan->$method( %$options, modules => [ @list ] );

            my $res = $href->rv;

            unless ( $res ) {
                print loc("No README found for your query"), "\n";
                return;
            }

            for my $mod ( sort keys %$res ) {

                unless ($res->{$mod}) {
                    print loc("No README found for %1", $mod), "\n";
                } else {
                    $self->_pager_open;
                    print $res->{$mod};
                    $self->_pager_close;
                }

                print "\n";
            }

        ### u uninstalls modules
        } elsif ( $key =~ /^u/ ) {
            ### prepare the list of modules we'll have to query ###
            my @list = $self->_select_modules(
                input   => $input,
                prompt  => loc('Uninstalling'),
                cache   => $cache,
                key     => 'module',
            );

            my $method = $cmd->{$key};
            my $href = $cpan->$method( %$options, modules => [ @list ] );

            my $res = $href->rv;

            for my $mod ( sort keys %$res ) {
                print $res->{$mod}
                    ? (loc("Uninstalled %1 successfully", $mod), "\n")
                    : (loc("Uninstalling %1 failed", $mod), "\n");
            }

            print $href->ok
                    ? (loc("All modules uninstalled successfully"), "\n")
                    : (loc("Problem uninstalling one or more modules"), "\n");

        ### e Expands your @INC during runtime...
        ### e /foo/bar "c:\program files"

        } elsif ( $key =~ /^e/ ) {
            my $method = $cmd->{$key};

            ### need to fix this so dirs with spaces are allowed ###
            ### I thought this *was* the fix? -jmb
            my $rv = $self->$method(
                    lib => [ $input =~ m/\s*("[^"]+"|'[^']+'|[^\s]+)/g ]
            );

        } elsif ( $key =~ /^z/ ) {
            my @list = $self->_select_modules(
                input   => $input,
                prompt  => loc('Opening shell for module'),
                cache   => $cache,
                key     => 'module',
            );

            my $conf    = $cpan->configure_object;
            my $shell   = $conf->_get_build('shell');

            unless($shell) {
                print loc("Your config does not specify a subshell!"), "\n",
                      loc("Perhaps you need to re-run your setup?"), "\n";

                next;
            }

            my $cwd = cwd();

            for my $mod (@list) {
                my $answer = $cpan->parse_module(modules => [$mod]);
                $answer->ok or next;

                my $mods = $answer->rv;
                my ($name, $obj) = each %$mods;

                my $dir = $obj->status->extract;

                unless( defined $dir ) {
                    $obj->fetch;
                    $dir = $obj->extract();
                }

                unless( defined $dir ) {
                    print loc("Could not determine where %1 was extracted to", $mod), "\n";
                    next;
                }

                unless( chdir $dir ) {
                    print loc("Could not chdir from %1 to %2: %3", $cwd, $dir, $!), "\n";
                    next;
                }

                if( system($shell) and $! ) {
                    print loc("Error executing your subshell: %1", $!), "\n";
                    next;
                }

                unless( chdir $cwd ) {
                    print loc("Could not chdir back to %1 from %2: %3", $cwd, $dir, $!), "\n";
                }
            }

        } elsif ( $key =~ /^[ma]/ ) {
            ### we default here to searching it seems, why not explicit? -jmb
            ### fixed -kane
            my $method = $cmd->{$key};

            ### build regexes.. this will break in anything pre 5.005_XX
            ### we add the /i flag here for case insensitive searches
            my @regexps = map { "(?i:$_)" } split /\s+/, $input;

            my $res = $cpan->$method(
                    %$options,
                    type => $maps->{$key},
                    list => [ @regexps ],
            );

            ### if we got a result back....
            if ( $res and keys %{$res} ) {
                ### forget old searches...
                $cache = [ undef ]; # most carbon-based life forms count from 1

                ### store them in our $cache; it's the storage for searches
                ### in Shell.pm
                for my $k ( sort keys %{$res} ) {
                    push @{$cache}, $res->{$k};
                }

                $self->_pager_open if ($#{$cache} >= $self->_term_rowcount);

                ### pretty print some information about the search
                for (1 .. $#{$cache}) {
                    my ($module, $version, $author) =
                        @{$cache->[$_]}{qw/module version author/};

                    my $fmt_version = $self->_format_version( version => $version );

                    printf $self->format,
                           $_, ($module, $fmt_version, $author);
                }

                $self->_pager_close;
            } else {
                print loc("Your search generated no results"), "\n";
                return;
            }
        } else {
            print loc("Unknown command '%1'. Usage:", $key), "\n";
            $self->_help();
        }

        ### add this command to the history - nope, it's already done
        # $term->addhistory($input) if $input =~ /\S/;

    }; # eval

    $cpan->error_object->trap( error => $@ ) if $@;

    ### continue the while loop in case we 'next' or 'last' it earlier
    ### to make sure the sig handler is still working properly
    } continue {
        $self->signals->{INT}{count}--
            if $self->signals->{INT}{count}; # clear the sigint count
    }

    return $normal_quit;
}

### complete receives the current line so far and current word, and
### returns a list of strings describing possible completions
sub _complete {
    my ($cpan, $word, $line) = @_;

    ### if no previous input, completions are the available commands ###
    unless ($line =~ /\S/) {
        ### XXX these one-char completions aren't particularly enlightening
        ### suggested improvement is to write longer aliases for commands,
        ### using classes like Text::Abbrev
        return keys %$cmd;
    }
    $line =~ s/^\s+//;

    ### complete CPAN Terminal> a<tab> kind of stuff to 'a ' for valid cmds ###
    if ($word eq $line && $cmd->{substr($line, 0, 1)}) {
        return $word;
    }

    ### rework command line. @args contains all the words already written ###
    ### $word has the string completion was requested for ###
    my ($key, @args) = split /\s+/, $line;

    ### one-time flags ###
    if ($args[-1] =~ /^--?(.*)/) {
        my $conf = $cpan->configure_object;
        my @options = sort $conf->subtypes('conf');
        my $argname = qr<^(?i:$1)>;

        @options = ('long') if $key eq 'o';

        return map "--$_", grep { $_ =~ $argname } @options;
    }

    if (@args && $args[-1] eq $word) {
        pop @args;
    }

    ### TODO: completions missing for: e p
    ### command-specific completions ###
    if ($key =~ /^[itudlrc]/) { # cmds which expect modulenames as args
        ### XXX fixme, how better to express it's a "module" search? ###
        my $method = $cmd->{'m'};
        my $type = $maps->{'m'};

        ### the words in @arg already completed in prevoius matches ###
        my $re_str = "^";
        ### XXX this bit was too clever attempt, won't work :-( ###
        #foreach (@args) {
        #    my $quoted = quotemeta($_);
        #    $re_str .= "(?!$quoted)";
        #}
        unless ($word) {
            $re_str .= ".*";
        } else {
            ### ignoring case if the word is in lowercase (vi smartcase) ###
            my $quoted = quotemeta($word);
            if (lc($word) eq $word) {
                $re_str .= "(?i:$quoted)";
            } else {
                $re_str .= $quoted;
            }
        }
        #warn "computed regex = $re_str";

        ### temporary shut up verbose, otherwise the screen gets cluttered ###
        ### XXX: suggested improvement: preload the things match depends on ###
        my $old_verbose = $cpan->get_conf( 'verbose' )->rv;
        $cpan->set_conf( verbose => 0 );

        my $results = $cpan->$method(
            type => $type,
            list => [qr<$re_str>],
        ) || {};

        ### restore verbose ###
        $cpan->set_conf( verbose => $old_verbose );

        ### strip already completed names ###
        my %args;
        @args{@args} = (1)x@args;
        return sort grep { !$args{$_} } map { $_->{$type} } values %$results;
    }

    ### options ###
    if ($key =~ /^s/) {
        ### do not attempt completing values for options ###
        return if @args;

        my $conf = $cpan->configure_object;
        my @options = sort $conf->subtypes('conf');
        my $argname = qr<^(?i:$word)>;

        return grep { $_ =~ $argname } 'conf', 'save', @options;
    }

    ### Perhaps add completions for a m f and o, too?

    return;
}


### choose modules - either as digits (choose from $cache), or by name
### return the $key property of module object, or itself if there's no $key
sub _select_modules {
    my ($self, %hash) = @_;
    my $modtree = $self->{_backend}->module_tree;

    my $tmpl = {
        input   => { required => 1 },
        cache   => { required => 1, default => [], strict_type => 1 },
        prompt  => { },
        key     => { },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my ($input, $prompt, $cache, $key) = @{$args}{qw|input prompt cache key|};

    my @ret;

    ### expand .. in $input
    $input =~ s{\b(\d+)\s*\.\.\s*(\d+)\b}
               {join(' ', ($1 < 1 ? 1 : $1) .. ($2 > $#{$cache} ? $#{$cache} : $2))}eg;

    $input = join(' ', 1 .. $#{$cache}) if $input eq '*';
    $input =~ s/'/::/g; # perl 4 convention

    foreach my $mod (split /\s+/, $input) {
        if ( $mod =~ /[^\w:]/ ) {
            # contains non-word, non-colon characters; must be a distname.
            push @ret, $mod;
        }

        ### if this module is only numbers - meaning a previous lookup
        ### it will be stored in $cache (the result of a previous search)
        ### keys in that haslist are numbers, not the module names.

        elsif ( $mod !~ /\D/ and $mod > 0 ) {
            unless ($cache and @{$cache}) {
                print loc("No search was done yet!"), "\n";
            }

            ### look up the module name in our array ref ###
            ### it may not be a proper object, but distnames from 'f' ###

            elsif ( my $obj = $cache->[$mod] ) {
                $obj = $obj->{$key} if defined $key and ref($obj);
                print "$prompt: $obj\n" if defined $prompt;
                push @ret, $obj;
            }
            else {
                print loc("No such module: %1", $mod), "\n";
            }
        }

        ### apparently, this is a 'normal' module name - look it up
        ### this look up will have to take place in the modtree,
        ### not the $cache;
        elsif ( my $obj = $modtree->{$mod} ) {
            $obj = $obj->{$key} if defined $key;
            print "$prompt: $obj\n" if defined $prompt;
            push @ret, $obj;
        }

        ### nothing matched
        else {
            print loc("No such module: %1", $mod), "\n";
        }
    }

    return @ret;
}

sub _format_version {
    my $self = shift;
    my %hash = @_;

    my $tmpl = {
        version => { default => 0 }
    };

    my $args = check( $tmpl, \%hash ) or return undef;
    my $version = $args->{version};

    ### fudge $version into the 'optimal' format
    $version = sprintf('%3.4f', $version);
    $version = '' if $version == '0.00';

    ### do we have to use $&? speed hit all over the module =/ --kane
    $version =~ s/(00?)$/' ' x (length $&)/e;

    return $version;
}



### asks whether to report testing result or not
### XXX should probably be moved then! XXX
sub _ask_report {
    my $obj     = shift;
    my %hash    = @_;

    ### either it's called from Internals, or from the shell directly
    ### although the latter is unlikely...
    my $self   = $obj->{_shell} || $obj;


    my $tmpl = {
        grade   => { required => 1, allow => qr/^\w+$/ },
        dist    => { required => 1, default => '', strict_type => 1 },
    };

    my $args = check( $tmpl, \%hash ) or return undef;


    return 'n' unless UNIVERSAL::can($self->term, 'ask_yn');
    return $self->term->ask_yn(
                        prompt  =>  loc("Report %1's testing result (%2)?: ",
                                        $args->{dist}, uc($args->{grade})
                                    ),
                        default => 'n',
            );
}


### dumps a message stack
sub _print_stack {
    my $self = shift;
    my %hash = @_;

    my $tmpl = {
        stack   => { required => 1 },
        file    => { default => '' },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $stack = $args->{'stack'};
    my $file = $args->{'file'};

    if ($file) {
        my $fh = new FileHandle;
        unless ( $fh->open(">$file") ) {
            warn qq[could not open $file: $!\n];
            return 0 ;
        }

        print $fh join "\n", @$stack;
        $fh->close or warn $!;

    } else {
        print join "\n", @$stack;
    }

    print "\n", loc("Stack printed successfully"), "\n";
    return 1;
}


### add dirs to the @INC at runtime ###
sub _expand_inc {
    my $self    = shift;
    my %args    = @_;
    my $err     = $self->{_error};

    for my $lib ( @{$args{'lib'}} ) {
        push @INC, $lib;
        print qq[Added $lib to your \@INC\n];
    }
    return 1;
}

### shows help information
my @Help;
sub _help {
    my $self = shift;

    @Help = (
loc('[General]'                                                                     ),
loc('    h | ?                  # display help'                                     ),
loc('    q                      # exit'                                             ),
loc('    v                      # version information'                              ),
loc('[Search]'                                                                      ),
loc('    a AUTHOR ...           # search by author(s)'                              ),
loc('    m MODULE ...           # search by module(s)'                              ),
loc('    f AUTHOR ...           # list all distributions by author(s)'              ),
loc("    o [ MODULE ... ]       # list installed module(s) that aren't up to date"  ),
loc('    w                      # display the result of your last search again'     ),
loc('[Operations]'                                                                  ),
loc('    i MODULE | NUMBER ...  # install module(s), by name or by search number'   ),
loc('    t MODULE | NUMBER ...  # test module(s), by name or by search number'      ),
loc('    u MODULE | NUMBER ...  # uninstall module(s), by name or by search number' ),
loc('    d MODULE | NUMBER ...  # download module(s) into current directory'        ),
loc('    l MODULE | NUMBER ...  # display detailed information about module(s)'     ),
loc('    r MODULE | NUMBER ...  # display README files of module(s)'                ),
loc('    c MODULE | NUMBER ...  # check for module report(s) from cpan-testers'     ),
loc('    z MODULE | NUMBER ...  # extract module(s) and open command prompt in it'  ),
loc('[Local Administration]'                                                        ),
loc('    e DIR ...              # add directories to your @INC'                     ),
loc('    b                      # write a bundle file for your configuration'       ),
loc('    s [OPTION VALUE]       # set configuration options for this session'       ),
loc('    s conf | save          # reconfigure settings / save current settings'     ),
loc('    ! EXPR                 # evaluate a perl statement'                        ),
loc('    p [FILE]               # print the error stack (optionally to a file)'     ),
loc('    x                      # reload CPAN indices'                              ),
    ) unless @Help;

    $self->_pager_open if (@Help >= $self->_term_rowcount);
    print map {"$_\n"} @Help;
    $self->_pager_close;
}


### displays quit message
sub _quit {
    print loc("Exiting CPANPLUS shell"), "\n";
}

1;

__END__

=pod

=head1 NAME

CPANPLUS::Shell::Default - Default command-line interface for CPAN++

=head1 SYNOPSIS

To begin use one of these two commands.  This will start your default
shell, which, unless you modified it in your configuration, will be
CPANPLUS::Shell::Default.

    cpanp

    perl -MCPANPLUS -e 'shell'

Shell commands:

    CPAN Terminal> h

    CPAN Terminal> s verbose 1
    CPAN Terminal> e /home/kudra/perllib

    CPAN Terminal> m simple tcp poe
    CPAN Terminal> i 22..27 /A/AL/ALIZTA/Crypt-Enigma-0.01.tar.gz 6 DBI-1.20

    CPAN Terminal> u Acme::POE::Knee 21

    CPAN Terminal> a damian

    CPAN Terminal> t Mail::Box

    CPAN Terminal> c DBI

    CPAN Terminal> r POE

    CPAN Terminal> d --force=1 --no-verbose XML::Twig

    CPAN Terminal> l DBD::Unify

    CPAN Terminal> f VROO?MANS$ DCROSS

    CPAN Terminal> ! die 'Kenny';
    CPAN Terminal> p --all /tmp/cpanplus/errors

    CPAN Terminal> w

    CPAN Terminal> z HTML::Template
    % gremlin[1009] /root/.cpanplus/build/5.6.1/HTML-Template-2.6> exit

    CPAN Terminal> o
    CPAN Terminal> i *

    CPAN Terminal> x
    CPAN Terminal> b

    CPAN Terminal> q

=head1 DESCRIPTION

CPANPLUS::Default::Shell is the default interactive shell for CPAN++.
If command-line interaction isn't desired, use CPANPLUS::Backend
instead.

You can also use CPANPLUS::Backend to create your own shell if
this one doesn't suit your tastes.

=head1 OPTIONS

The shell will accept any combination of options before arguments.
Options are prefaced with C<-->.  Note that not all options may be
appropriate for all commands.  Options affect just the command
being issued.

The options available are the same as the options which can
be specified to the underlying Backend methods.  Refer to the
Backend method of the same name as the command for a listing
of the options available in L<CPANPLUS::Backend>.  For example,
to find what options I<i> (install) accepts, look at the
documentation for the C<install> method in Backend.

Options may be specified as just the option name, or as I<=1>
to turn on the option, and prefaced with I<no-> or followed
by I<=0> to set them off.  In short, these two commands are
equivalent--they both turn on force:

    --force
    --force=1

To turn off force, either of the following would work:

    --no-force
    --force=0

Naturally this syntax only applies to boolean options.  For other
options, the following might be more appropriate:

    --fetchdir=/home/kane/foo

=head1 TAB COMPLETION

Tab completion is available for the following commands: I<i> I<t> I<u>
I<d> I<l> I<r> I<c> and I<s>.  For all commands other than I<s> it
will expand modules, and for I<s> it expands config arguments.

=head1 COMMANDS

=head2 h|?

I<Help> lists available commands and is also the default output if
no valid command was given.

=head2 q

I<Quit> exits the interactive shell.

=head2 m MODULE [MODULE]

This command performs a case-insensitive match for a module or modules.
Either a string or a tailored regular expression can be used.  For
example:

=over 4

=item * C<m poe>

This will search for modules matching the regular expression C</poe/i>.

=item * C<m poe acme>

This will search for modules matching C</(poe)|(acme)/i>.

=item * C<m ^acme::.*>

This search would look for all C<Acme> submodules.

=back

The list of matching modules will be printed in four columns.  For
example:

    1 Acme::Pony                1.1   DCANTRELL
    2 Acme::DWIM                1.05  DCONWAY

These columns correspond to the assigned number, module name,
version number and CPAN author identification.  Assigned numbers
can be used for a subsequent commands, either singly (I<2>) or
inclusively (I<1..2>).  Numbers are reassigned for each search.

If no module version is listed, the third field will be I<undef>.

=head2 a AUTHOR [AUTHOR]

The I<author> command performs a case-insensitive search for an author
or authors.  A string or a regular expression may be specified; both
CPAN author identifications and full names will be searched.
For example:

=over 4

=item * C<a ingy bergman>

=item * C<a ^michael>

=back

This command gives the same output format as the I<module> command.
Sometimes the output may not be what you expected.  For instance,
if you searched for I<jos>, the following listing would be included:

    1 Acme::POE::Knee           1.02  KANE

This is because while the CPAN author identification doesn't contain
the string, it B<is> found in the module author's full name (in this
case, I<Jos Boumans>).  There is currently no command to display the
author's full name.

=head2 i MODULE|NUMBER|FILENAME [MODULE|NUMBER|FILENAME]

This command installs a module by its case-sensitive name, by the
path and filename on CPAN, or by the number returned from a previous
search.  Distribution names need only to be complete enough for
distinction.  That is to say, I<DBI-1.20> is sufficient; the
author can be deduced from the named portion.

Examples:

=over 4

=item * C<i CGI::FormBuilder>

=item * C<i /K/KA/KANE/Acme-POE-Knee-1.10.zip>

=item * C<i DBI-1.20>

=item * C<i 16..18 2>

This example would install results 16 through and including 18 and 2
from the most recent results.

=item * C<i *>

This would install all results.

=back

Install will search, fetch, extract and make the module.

=head2 t MODULE|NUMBER|FILENAME [MODULE|NUMBER|FILENAME]

This command is exactly the same as the C<i> above, only it
will not actually install modules, but will stop after
the C<make test> step.  Unlike the C<i> command, it performs
on modules that are already installed, even if the C<force>
flag is set to false.

=head2 u MODULE|NUMBER [MODULE|NUMBER]

This command will uninstall the specified modules (both
program files and documentation).   Modules can be
specified by their case-sensitive names, or by the numbered
result from the last search.

=head2 c MODULE|NUMBER|FILENAME [MODULE|NUMBER|FILENAME]

This command fetches test results from the CPAN tester's
website at I<http://testers.cpan.org> and displays the
results for the most recent version of a module, specified
by its case-insensitive name, or by the number of a
previous search.

If passed the path and filename of the module, it will
display the test results for the version specified.

=head2 r MODULE|NUMBER|DIST [MODULE|NUMBER|DIST]

The read command displays the readme for the specified
module or distribution.  It accepts the case-sensitive name of the
module or a number from a previous result, and can accept
multiple arguments.

=head2 d MODULE|NUMBER|FILENAME [MODULE|NUMBER|FILENAME]

This command will download the module or modules in the current
directory.  It is case sensitive.   Like install, it can also
accept a fully qualified file name from a CPAN mirror, relative
to the /authors/id directory.  All file names should begin with
a I</>.

=over 4

=item * C<d CGI::FormBuilder>

=item * C<d /K/KA/KANE/Acme-POE-Knee-1.10.zip>

=back

=head2 e DIRECTORY [DIRECTORY]

This command adds directories to your C<@INC>.  CPAN++ will check
to see if modules are already installed on your system, so if
there is a custom library directory it should be specified.
Examples:

=over 4

=item * C<e /home/ann/perl/lib>

=item * C<e 'C:\Perl Lib' C:\kane>

=back

=head2 l MODULE|NUMBER|DIST [MODULE|NUMBER|DIST]

This command lists detailed information about a module or distribution.


=over 4

=item * C<l Net::FTP>

=back

Example output from the list command:

    Details for Net::FTP:
    Description          Interface to File Transfer Protocol
    Development Stage    Alpha testing
    Interface Style      plain Functions, no references used
    Language Used        Perl-only, no compiler needed
    Package              libnet-1.09.tar.gz
    Support Level        Developer
    Version              2.61

=head2 f AUTHOR [AUTHOR]

This command gives a listing of distribution files by the author
or authors specified.  It accepts a case-insensitive regular
expression.

=over 4

=item * C<f ^KANE$>

=back

Output from the previous command would look like this:

    1 Acme-POE-Knee-1.00.zip    12230 KANE
    2 Acme-POE-Knee-1.01.zip    14246 KANE
    3 Acme-POE-Knee-1.02.zip    12324 KANE
    4 Acme-POE-Knee-1.10.zip     6625 KANE
    5 CPANPLUS-0.01.tar.gz     120689 KANE
    6 CPANPLUS-0.02.tar.gz     121967 KANE

The first column is the search result number, which can be used for subsequent
commands.  Next is name of the distribution, the third column is the file's
size, and the fourth is the CPAN author id.

=head2 s [conf | save | OPTION VALUE]

The I<set> command can be used to change configuration settings.
If there are no arguments, current settings are displayed.

I<s conf> will let the user go through the configuration process
again, and save the settings to L<CPANPLUS::Config>.

I<s save> will save the current settings for this session.

The I<OPTION VALUE> form will override current settings for this
session; they will be cleared away when the Shell exits.  Available
options are:

=over 4

=item * C<cpantest 0|1>

Disable or enable the CPAN test reporting feature.

=item * C<debug 0|1>

Disable or enable debugging mode.

=item * C<flush 0|1>

Flush will automatically flush the cache if enabled.

=item * C<force 0|1>

If enabled, modules which fail C<make test> will be forced to
attempt installation.

=item * C<makeflags FLAG [FLAG]>

Add flags to the make command.  For example, I</C> on win32.

=item * C<makemakerflags FLAG [FLAG]>

Add flags to the C<perl Makefile.PL> command.

=item * C<md5 0|1>

Disable or enable md5 checks.

=item * C<prereqs 0|1|2>

Zero disallows prerequisites, 1 allows them, and 2 offers
a decision prompt for each prerequisite.

=item * C<storable 0|1>

Set to 1 to use storable.

=item * C<verbose 0|1>

Suppress or inform of messages about actions being taken.

=item * C<lib DIR [DIR]>

Allows directories to be added and used as 'use lib.'

=back

=head2 p [--option] [FILE]

This allows the printing of stored errors, either to standard out
or the specified file.

An option may be supplied if desired.  Available options are I<--all>,
I<--msg> and I<--error>.  If no option is supplied, I<--error> will
be assumed.  The I<--all> flag prints both errors and messages, while
the I<--msg> flag prints just messages.

It is useful to include I<--all> output when reporting a bug.

=head2 o [--long] [MODULE]

This command lists installed modules which are out-of-date.

Example output:

    1   0.05     0.06   Acme::ComeFrom         AUTRIJUS
    2   1.01     1.07   Acme::EyeDrops         ASAVIGE
    3   1.00     1.01   Acme::USIG             RCLAMP
    4   2.04     2.1011 DBD::mysql             JWIED
    5   1.13     1.15   File::MMagic           KNOK

The first column is the search result number, which can be used for
subsequent commands.  Next is the version you have installed, followed
by the latest version of the module on CPAN.  Finally the name of the
module and the author's CPAN identification are given.

You can provide a module name to only check if that module is still up
to date.
By default, only one module per package is printed as being out of
date. If you provide the C<--long> option however, all modules will be
printed.

=head2 w

The 'what' command will print the results from the last match.  This
is useful if they have scrolled off your buffer.

=head2 x

This command refetches and reloads index files regardless of
whether your current indices are up-to-date or not.

=head2 b

This command will autobundle your current installation and write
it to I<$cpanhome/$version/dist/autobundle/Snapshot_xxxx_xx_xx_xx.pm>.

For example, the bundle might be written as:

    D:\cpanplus\5.6.0\dist\autobundle\Snapshot_2002_11_03_03.pm

=head2 z MODULE|NUMBER|FILENAME

The I<z> command will open a command prompt in the distribution
directory.  If the module hasn't been downloaded and extracted
yet, this will be done first.  Exiting the command prompt will
return you to the CPANPLUS shell.  If multiple modules are entered,
a new command prompt will be given for each module.


=head2 !

This command evals all input after it as perl code, and
puts any errors in the error stack.

=head1 AUTHORS

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt> and
Joshua Boschert E<lt>jambe@cpan.orgE<gt>.

This pod text by Ann Barcomb E<lt>kudra@cpan.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001, 2002 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=head1 ACKNOWLEDGMENTS

Andreas Koenig E<lt>andreas.koenig@anima.deE<gt> authored
the original CPAN.pm module.

=head1 SEE ALSO

L<CPANPLUS::Backend>, L<CPANPLUS>, http://testers.cpan.org

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
