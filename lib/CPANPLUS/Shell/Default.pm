# $File: //member/autrijus/cpanplus/devel/lib/CPANPLUS/Shell/Default.pm $
# $Revision: #83 $ $Change: 4122 $ $DateTime: 2002/05/06 13:31:47 $

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
use Carp;
use CPANPLUS::Backend;
use Term::ReadLine;
use Data::Dumper;
use FileHandle;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
    $VERSION    =   '0.02';
}

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
};

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

my $brand = 'CPAN Terminal';

### CPANPLUS::Shell::Default needs it's own constructor, seeing it will just access
### CPANPLUS::Backend anyway
sub new {
    my $self = ( bless {}, shift );

    ### signal handler ###
    $SIG{INT} = $self->{_signals}{INT}{handler} = sub {
        unless ($self->{_signals}{INT}{count}++) {
            warn "Caught SIGINT\n";
        }
        else {
            warn "Got another SIGINT\n"; die;
        }
    };

    $self->{_signals}{INT}{count} = 0; # count of sigint calls

    return $self;
}


### The CPAN terminal interface ###
sub shell {
    my $self = shift;

    ### make an object ###
    my $cpan = new CPANPLUS::Backend;

    my $term = Term::ReadLine->new( $brand );
    my $prompt = "$brand> ";

    ### store this in the object, so we can access the prompt anywhere if need be
    $self->{_term}    = $term;
    $self->{_backend} = $cpan;
    $cpan->{_shell}   = $self;

    $self->_show_banner($cpan);
    $self->_input_loop($cpan, $prompt) or print "\n"; # print only on abnormal quits
    $self->_quit;
}

### input loop. returns true if exited normally via 'q'.
sub _input_loop {
    my ($self, $cpan, $prompt) = @_;
    my $term = $self->{_term};

    my $cache; # results of previous search
    my $format = "%5s %-50s %8s %-10s\n";
    my $normal_quit;

    ### somehow it's caching previous input ###
    while (
        defined (my $input = eval { $term->readline($prompt) } )
        or $self->{_signals}{INT}{count} == 1
    ) { eval {

        ### re-initiate all signal handlers
        while (my ($sig, $entry) = each %{$self->{_signals}}) {
            $SIG{$sig} = $entry->{handler} if exists($entry->{handler});
        }


        ### parse the input: all commands are 1 letter, followed
        ### by a space, followed by an arbitrary string
        ### the first letter is the command key
        my $key;
        {   # why the block? -jmb
            # to hide the $1. -autrijus
            $input =~ s/^\s*([\w\?\!])\w*\s*//;
            chomp $input;
            $key = lc($1);
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
            my $method = $cmd->{$key};
            $self->$method( stack => $cpan->{_error}->flush(), file => $input );
            return;
        }

        ### clean out the error stack and the message stack ###
        $cpan->{_error}->flush();
        $cpan->{_error}->forget();

        ### check for other commands that does not require an argument ###
        if ( $key =~ /^\!/ ) {
            # $input = 'system($ENV{SHELL} || $ENV{COMSPEC})' unless length $input;
            eval $input;
            $cpan->{_error}->trap( error => $@ ) if $@;
            print "\n";
            return;

        } elsif ( $key =~ /^x/ ) {
            my $method = $cmd->{$key};

            print "Fetching new indices and rebuilding the module tree\n";
            print "This may take a while...\n";

            $cpan->$method(update_source => 1);

            return;
        } elsif ( $key =~ /^v/ ) {
            my $method = $cmd->{$key};
            $self->$method($cpan);
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
                    : keys %{ $modtree };

            unless( length @list ) {
                print "No modules to check\n";
                next;
            }

            if(!$input) {
                print "Checking against all files on the CPAN\n";
                print "\tThis may take a while...\n";
            }


            my $res = $cpan->$method( modules => \@list );

            $cache = [ undef ]; # most carbon-based life forms count from 1
            for my $name ( sort keys %$res ) {
                next unless $res->{$name}->{uptodate} eq '0';
                push @{$cache}, $modtree->{$name};
            }
            $self->_pager_open if ($#{$cache} >= $self->_term_rowcount);

            ### pretty print some information about the search
            for (1 .. $#{$cache}) {

                my ($module, $version, $author) = @{$cache->[$_]}{qw/module version author/};

                my $have    = $self->_format_version( version => $res->{$module}->{version} );
                my $can     = $self->_format_version( version => $version );

                my $local_format = "%5s %8s %8s %-44s %-10s\n";

                printf $local_format, $_, ($have, $can, $module, $author);
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
                print "Improper command '$key'. Usage:\n";
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
                    conf => $cpan->configure_object,
                    term => $self->{_term},
                );
                return;
            }
            elsif ($name =~ m/^save/i) {;
                $cpan->configure_object->save;
                print "Your CPAN++ configuration info has been saved!\n\n";
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
                print "'$name' is not a valid configuration option!\n" if defined $name;
                print "Available options and their current values are:\n";

                my $local_format = "    %-".(sort{$b<=>$a}(map(length, @options)))[0]."s %s\n";

                foreach $key (@options) {
                    my $val = $conf->get_conf($key);
                    ($val) = ref($val) ? (Data::Dumper::Dumper($val) =~ /= (.*);$/) : "'$val'";
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
                prompt  => "\u${target}ing", # Installing / Testing
                cache   => $cache,
                key     => 'module',
            );

            ### try to install them, get the return status back
            my $status = $cpan->install( modules => [ @list ], target => $target );

            for my $key ( sort keys %$status ) {
                print   $status->{$key}
                        ? "Successfully ${target}ed $key\n"
                        : "Error ${target}ing $key\n";
            }

        ### d is for downloading modules.. can take multiple input like i does.
        ### so this works: d LWP POE
        } elsif ( $key =~ /^d/ ) {
            ### prepare the list of modules we'll have to fetch ###
            my @list = $self->_select_modules(
                input   => $input,
                prompt  => 'Fetching',
                cache   => $cache,
                key     => 'module',
            );

            ### get the result of our fetch... we store the modules in whatever
            ### dir the shell was invoked in.
            my $status = $cpan->fetch(
                modules     => [ @list ],
                fetchdir   => $cpan->{_conf}->_get_build('startdir'),
            );

            for my $key ( sort keys %$status ) {
                print   $status->{$key}
                        ? "Successfully fetched $key\n"
                        : "Error fetching $key\n";
            }


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
            my $res = $cpan->$method( modules => [ @list ] );

            foreach my $name (@list) {
                my $dist = $self->{_backend}->pathname(to => $name);
                my $url;

                foreach my $href ($res->{$name} || $res->{$dist}) {
                    print "[$dist]\n";

                    unless ($href) {
                        print "No reports available for this distribution.\n";
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
            my $res = $cpan->$method( modules => [ @list ] );

            for my $mod ( sort keys %$res ) {
                unless ( $res->{$mod} ) {
                    print "No details for $mod - it's probably outdated.\n";
                    next;
                }

                print "Details for $mod:\n";
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
            my $res = $cpan->$method( authors => [ @list ] );

            unless ( $res and keys %$res ) {
                print "No authors found for your query\n";
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
                    printf $format,
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
            my $res = $cpan->$method( modules => [ @list ] );

            unless ( $res ) {
                print "No README found for your query\n";
                next;
            }

            for my $mod ( sort keys %$res ) {

                unless ($res->{$mod}) {
                    print qq[No README file found for $mod];
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
                prompt  => 'Uninstalling',
                cache   => $cache,
                key     => 'module',
            );

            my $method = $cmd->{$key};
            my $res = $cpan->$method( modules => [ @list ] );

            for my $mod ( sort keys %$res ) {
                print $res->{$mod}
                    ? "Uninstalled $mod succesfully\n"
                    : "Uninstalling $mod failed\n";
            }

        ### e Expands your @INC during runtime...
        ### e /foo/bar "c:\program files"

        } elsif ( $key =~ /^e/ ) {
            my $method = $cmd->{$key};

            ### need to fix this so dirs with spaces are allowed ###
            ### I thought this *was* the fix? -jmb
            my $rv = $self->$method(
                    lib => [ $input =~ m/\s*("[^"]+"|'[^']+'|[^\s]+)/g ]
            );

        } elsif ( $key =~ /^[ma]/ ) {
            ### we default here to searching it seems, why not explicit? -jmb
            ### fixed -kane
            my $method = $cmd->{$key};

            ### build regexes.. this will break in anything pre 5.005_XX
            ### we add the /i flag here for case insensitive searches
            my @regexps = map { "(?i:$_)" } split /\s+/, $input;

            my $res = $cpan->$method(
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

                    printf $format,
                           $_, ($module, $fmt_version, $author);
                }

                $self->_pager_close;
            } else {
                print "Your search generated no results\n";
                return;
            }
        } else {
            print "Unknown command '$key'. Usage:\n";
            $self->_help();
        }

        ### add this command to the history - nope, it's already done
        # $term->addhistory($input) if $input =~ /\S/;

    }; # eval

    $cpan->{_error}->trap( error => $@ ) if $@;

    ### continue the while loop in case we 'next' or 'last' it earlier
    ### to make sure the sig handler is still working properly
    } continue {
        $self->{_signals}{INT}{count}--
            if $self->{_signals}{INT}{count}; # clear the sigint count
    }

    return $normal_quit;
}


### display shell's banner, takes the Backend object as argument
sub _show_banner {
    my ($self, $cpan) = @_;
    my $term = $self->{_term};

    ### Tries to probe for our ReadLine support status
    my $rl_avail = ($term->can('ReadLine'))                      # a) under an interactive shell?
        ? (-t STDIN)                                             # b) do we have a tty terminal?
            ? (!$self->_is_bad_terminal($term))                  # c) should we enable the term?
                ? ($term->ReadLine ne "Term::ReadLine::Stub")    # d) external modules available?
                    ? "enabled"                                  # a+b+c+d => "Smart" terminal
                    : "available (try 'i Term::ReadLine::Perl')" # a+b+c   => "Stub" terminal
                : "disabled"                                     # a+b     => "Bad" terminal
            : "suppressed"                                       # a       => "Dumb" terminal
        : "suppressed in batch mode";                            # none    => "Faked" terminal

    $rl_avail = "ReadLine support $rl_avail.";
    $rl_avail = "\n*** $rl_avail" if (length($rl_avail) > 45);

    printf (<< ".", $self->which, $self->which->VERSION, $cpan->VERSION, $rl_avail);

%s -- CPAN exploration and modules installation (v%s)
*** Please report bugs to <cpanplus-bugs\@lists.sourceforge.net>.
*** Using CPANPLUS::Backend v%s.  %s

.
}


### checks whether the Term::ReadLine is broken and needs to fallback to Stub
sub _is_bad_terminal {
    my $self = shift;
    return unless $^O eq 'MSWin32';

    # replace the term with the default (stub) one
    return $_[0] = $self->{_term} =
        Term::ReadLine::Stub->new($brand);
}


### choose modules - either as digits (choose from $cache), or by name
### return the $key property of module object, or itself if there's no $key
sub _select_modules {
    my ($self, %args) = @_;
    my ($input, $prompt, $cache, $key) = @args{qw|input prompt cache key|};
    my $cpan = $self->{_backend};
    my $modtree = $cpan->_module_tree;
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
                print "No search was done yet!\n";
            }

            ### look up the module name in our array ref ###
            ### it may not be a proper object, but distnames from 'f' ###

            elsif ( my $obj = $cache->[$mod] ) {
                $obj = $obj->{$key} if defined $key and ref($obj);
                print "$prompt: $obj\n" if defined $prompt;
                push @ret, $obj;
            }
            else {
                print "No such module: $mod\n";
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
            print "No such module: $mod\n";
        }
    }

    return @ret;
}

{
my $win32_console;

### determines row count of current terminal; defaults to 25.
sub _term_rowcount {
    my ($self, %args) = @_;
    my $cpan    = $self->{_backend};
    my $default = $args{default} || 25;

    if ( $^O eq 'MSWin32' ) {
        if ($cpan->_can_use( modules => { 'Win32::Console' => '0.0' } )) {
            $win32_console ||= Win32::Console->new;
            my $rows = ($win32_console->Info)[-1];
            return $rows;
        }

    } else {

        if ($cpan->_can_use( modules => { 'Term::Size' => '0.0' } )) {
            my ($cols, $rows) = Term::Size::chars();
            return $rows;
        }
    }

    return $default;
}

}

sub _format_version {
    my $self = shift;
    my %args = @_;

    my $version = $args{'version'} or return 0;

    ### fudge $version into the 'optimal' format
    $version = sprintf('%3.4f', $version);
    $version = '' if $version == '0.00';
    $version =~ s/(00?)$/' ' x (length $&)/e;

    return $version;
}


### parse and set configuration options: $method should be 'set_conf'
sub _set_config {
    my ($self, %args) = @_;
    my ($key, $value, $method) = @args{qw|key value method|};
    my $cpan = $self->{_backend};

    # determine the reference type of the original value
    my $type = ref($cpan->get_conf($key)->{$key});

    if ($type eq 'HASH') {
        $value = $cpan->_flags_hashref($value);
    }
    elsif ($type eq 'ARRAY') {
        $value = [ $value =~ m/\s*("[^"]+"|'[^']+'|[^\s]+)/g ]
    }

    my $set = $cpan->$method( $key => $value );

    for my $key (sort keys %$set) {
        my $val = $set->{$key};
        $type = ref($val);

        if ($type eq 'HASH') {
            print "$key was set to:\n";
            print map {
                defined($value->{$_})
                    ? "    $_=$value->{$_}\n"
                    : "    $_\n"
            } sort keys %{$value};
        }
        elsif ($type eq 'ARRAY') {
            print "$key was set to:\n";
            print map { "    $_\n" } @{$value};
        }
        else {
            print "$key was set to $set->{$key}\n";
        }
    }
}


### open a pager handle
sub _pager_open {
    my $self  = shift;
    my $cpan  = $self->{_backend};
    my $cmd   = $cpan->{_conf}->_get_build('pager') or return;

    $self->{_old_sigpipe} = $SIG{PIPE};
    $SIG{PIPE} = 'IGNORE';

    my $fh = new FileHandle;
    unless ( $fh->open("| $cmd") ) {
        $cpan->{_error}->trap( error => "could not pipe to $cmd: $!\n" );
        return 0;
    }

    $fh->autoflush(1);
    $self->{_pager}     = $fh;
    $self->{_old_outfh} = select $fh;

    return $fh;
}


### print to the current pager handle, or STDOUT if it's not opened
sub _pager_close {
    my $self  = shift;
    my $pager = $self->{_pager} or return;

    $pager->close if (ref($pager) and $pager->can('close'));

    undef $self->{_pager};
    select $self->{_old_outfh};
    $SIG{PIPE} = $self->{_old_sigpipe};
}

sub _ask_prereq {
    my $obj     = shift;
    my %args    = @_;

    ### either it's called from Internals, or from the shell directly
    ### although the latter is unlikely...
    my $self = $obj->{_shell} || $obj;

    my $mod = $args{mod};

    print "\n$mod is a required module for this install.\n";

    return $self->_ask_yn(
        prompt  => "Would you like me to install it? [Y/n]: ",
        default => 'y',
    ) ? $mod : 0;
}


### asks whether to report testing result or not
sub _ask_report {
    my $obj     = shift;
    my %args    = @_;

    ### either it's called from Internals, or from the shell directly
    ### although the latter is unlikely...
    my $self   = $obj->{_shell} || $obj;
    my $dist   = $args{dist};
    my $grade  = $args{grade};

    return $self->_ask_yn(
        prompt  => "Report ${dist}'s testing result (\U$grade\E)? [y/N]: ",
        default => 'n',
    );
}


### dumps a message stack
### generic yes/no question interface
sub _ask_yn {
    my ($self, %args) = @_;
    my $prompt  = $args{prompt};
    my $default = $args{default};

    while ( defined (my $input = $self->{_term}->readline($prompt)) ) {
        $input = $default unless length $input;

        if ( $input =~ /^y/i ) {
            return 1;
        } elsif ( $input =~ /^n/i ) {
            return 0;
        } else {
            print "Improper answer, please reply 'y[es]' or 'n[o]'\n";
        }
    }
}


sub _print_stack {
    my $self = shift;
    my %args = @_;

    my $stack = $args{'stack'};
    my $file = $args{'file'};

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

    print "\nStack printed successfully\n";
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
sub _help {
    my $self = shift;
    my @Help = split("\n", << 'EOL', -1);
[General]
    h | ?                  # display help
    q                      # exit
    v                      # version information
[Search]
    a AUTHOR ...           # search by author(s)
    m MODULE ...           # search by module(s)
    f AUTHOR ...           # list all distributions by author(s)
    o                      # list installed module(s) that aren't up to date
[Operations]
    i MODULE | NUMBER ...  # install module(s), by name or by search number
    t MODULE | NUMBER ...  # test module(s), by name or by search number
    u MODULE | NUMBER ...  # uninstall module(s), by name or by search number
    d MODULE | NUMBER ...  # download module(s) into current directory
    l MODULE | NUMBER ...  # display detailed information about module(s)
    r MODULE | NUMBER ...  # display README files of module(s)
    c MODULE | NUMBER ...  # check for module report(s) from cpan-testers
[Local Administration]
    e DIR ...              # add directories to your @INC
    s [OPTION VALUE]       # set configuration options for this session
    s conf | save          # reconfigure settings / save current settings
    ! EXPR                 # evaluate a perl statement
    p [FILE]               # print the error stack (optionally to a file)
    x                      # reload CPAN indices
EOL

    $self->_pager_open if (@Help >= $self->_term_rowcount);
    print map {"$_\n"} @Help;
    $self->_pager_close;
}


### displays quit message
sub _quit {
    print "Exiting CPANPLUS shell\n";
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

    CPAN Terminal> d XML::Twig

    CPAN Terminal> l DBD::Unify

    CPAN Terminal> f VROO?MANS$ DCROSS

    CPAN Terminal> ! die 'wild rose';
    CPAN Terminal> p /tmp/cpanplus/errors

    CPAN Terminal> o
    CPAN Terminal> i *

    CPAN Terminal> x

    CPAN Terminal> q

=head1 DESCRIPTION

CPANPLUS::Default::Shell is the default interactive shell for CPAN++.
If command-line interaction isn't desired, use CPANPLUS::Backend
instead.

You can also use CPANPLUS::Backend to create your own shell if
this one doesn't suit your tastes.

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

=head2 p [FILE]

This allows the printing of stored errors, either to standard out
or the specified file.

It is useful to include this output when reporting a bug.

=head2 o

This command lists installed modules which are out-of-date.

Example output:

    1   0.05     0.06   Acme::ComeFrom         AUTRIJUS
    2   1.01     1.07   Acme::EyeDrops         ASAVIGE
    3   1.00     1.01   Acme::USIG             RCLAMP
    4   2.04     2.1011 DBD::mysql             JWIED
    5   1.13     1.15   File::MMagic           KNOK

The first column is the search result number, which can be used for subsequent
commands.  Next is the version you have installed, followed by the latest
version of the module on CPAN.  Finally the name of the module and the
author's CPAN identification are given.

=head2 x

This command refetches and reloads index files regardless of
whether your current indices are up-to-date or not.

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
