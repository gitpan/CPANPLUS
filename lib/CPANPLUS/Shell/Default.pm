# $File$
# $Revision$ $Change$ $DateTime$

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
    $VERSION    =   '0.01';
}

### our command set ###
my $cmd = {
    a   => "search",
    m   => "search",
    d   => "fetch",
    e   => "_expand_inc",
    f   => "distributions",
    i   => "install",
    h   => "_help",
    q   => "_quit",
    s   => "set_conf",
    l   => "details",
    '?' => "_help",
    ### too buggy to document ###
    u   => "uninstall",
    p   => "_print_stack",
};

### input check ###
my $maps = {
    m => "module",
    v => "version",
    d => "path",
    a => "author",
    p => "package",
    c => "comment",
};


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

    my $term = Term::ReadLine->new( 'CPAN Terminal', *STDIN, *STDOUT );
    my $prompt = "CPAN Terminal>";
    my $OUT = *STDOUT;

    ### store this in the object, so we can access the prompt anywhere if need be
    $self->{_term}  = $term;
    $cpan->{_shell} = $self;

    my $flag;
    my $href;

    ### Tries to probe for our ReadLine support status
    my $rl_avail = ($term->can('ReadLine'))                  # a) under an interactive shell?
	? (-t STDIN)                                         # b) do we have a tty terminal?
	    ? ($term->ReadLine ne "Term::ReadLine::Stub")    # c) external modules available?
		? ($self->_is_bad_terminal($term))           # d) should we disable the term?
		    ? "disabled"                             # a+b+c+d => "Bad" terminal
		    : "enabled"                              # a+b+c   => "Smart" terminal
		: "available (try 'i Term::ReadLine::Perl')" # a+b     => "Stub" terminal
	    : "suppressed"                                   # a       => "Dumb" terminal
	: "suppressed in batch mode";                        # none    => "Faked" terminal

    printf (<< ".", ref($self), $VERSION, $rl_avail);

%s -- CPAN exploration and modules installation (v%s)
*** Please report bugs to <cpanplus-bugs\@lists.sourceforge.net>.
*** ReadLine support %s.

.

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


        ### in case we got a command, and that command was either:
        ### h, q or ?, we execute the command since they are in the
        ### current package.
        if ( $cmd->{$key} && ( $key =~ /^[?hq]/ )) {
            my $method = $cmd->{$key};
            $self->$method();
            next;
        }

        if ( $key =~ /^p/ ) {

            my $method = $cmd->{$key};
            $self->$method( stack => $cpan->{_error}->flush(), file => $input );
            next;
        }

        ### clean out the error stack and the message stack ###
        $cpan->{_error}->flush();
        $cpan->{_error}->forget();

        if ( $key =~ /^\!/ ) {
            eval $input;
            warn $@ if $@;
            print "\n";
            next;
        }

        ### if input has no length, we either got a signal, or a command without a
        ### required string;
        ### in either case we take apropriate action and skip the rest of the loop
        unless( length $input ) {

            unless ( defined $input ) {
		        $self->{_signals}{INT}{count}++; # to counter the -- in continue block
            } elsif ( length $key ) {
                print "Improper command '$key'. Usage:\n";
                $self->_help();
            }

            next;
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
            if ($name =~ m/^c/) {;
                CPANPLUS::Configure::Setup::init($cpan->{_conf});
                next; # should be next SHELL I think? -jmb
            }

            ### allow lazy config options... not smart but possible ###
            my @options = sort $cpan->{_conf}->subtypes('conf');
            my $realname;
            for my $option (@options) {
                if ($option =~ m/^$name/) {
                    $realname = $option;
                    last;
                }
            }

            my $method = $cmd->{$key};

            if ($realname) {
                # determine the reference type of the original value
                my $type = ref($cpan->get_conf($realname));

		if ($type eq 'HASH') {
		    $value = {
                        map {
                            /=/ ? split('=', $_, 2) : ($_ => undef)
                        } $value =~ m/\s*((?:[^\s=]+=)?(?:"[^"]+"|'[^']+'|[^\s]+))/g
                    };
		}
		elsif ($type eq 'ARRAY') {
		    $value = [ $value =~ m/\s*("[^"]+"|'[^']+'|[^\s]+)/g ]
		}

                my $set = $cpan->$method( $realname => $value );

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

            } else {
                print "'$name' is not a valid configuration option!\n",
                      "Available options are:\n",
                      map { "    $_\n"; } @options,
            }

        ### i is for install.. it takes multiple arguments, so:
        ### i POE LWP
        ### is perfectly valid.
        } elsif ( $key =~ /^i/ ) {
            my @input = split /\s+/, $input;

            my @list;

            ### prepare the list of modules we'll have to install ###
            for my $mod (@input) {

                ### if we got a full file name...
                ### we'll just give it a go...
                if ( $mod =~ m|/| ) {
                    push @list, $mod;


                ### if this module is only numbers - meaning a previous lookup
                ### it will be stored in $href (the result of a previous search)
                ### keys in that hashref are numbers, not the module names.
                } elsif ( $mod !~ /\D/ ) {
                    if ( $flag ) {
                        ### zero pad to match hash key ###
                        my $mod = sprintf "%04d", $mod;

                        ### look up the module name in our hash ref ###
                        my $name = $href->{$mod}->{'module'};
                        if ( $name ) {
                            push @list, $name;
                            print "Installing: $name\n";
                        } else {
                            print "No such module: $mod\n"
                        }
                    } else {
                        print "No search was done yet!\n";
                    }

                } else {
                    ### apparently, this is a 'normal' module name - look it up
                    ### this look up will have to take place in the modtree,
                    ### not the $href;
                    if ( my $name = $cpan->{_modtree}->{$mod}->{'module'} ) {
                        push @list, $name;
                        print "Installing: $name\n";
                    } else {
                        print "No such module: $mod\n"
                    }
                }
            }

            ### try to install them, get the return status back
            my $status = $cpan->install( modules => [ @list ] );

            for my $key ( sort keys %$status ) {
                print   $status->{$key}
                        ? "Successfully installed $key\n"
                        : "Error installing $key\n";
            }

        ### d is for downloading modules.. can take multiple input like i does.
        ### so this works: d LWP POE
        } elsif ( $key =~ /^d/ ) {
            my @input = split /\s+/, $input;

            my @list;

            ### prepare the list of modules we'll have to install ###
            for my $mod (@input) {

                ### if we got a full file name...
                ### we'll just give it a go...
                if ( $mod =~ m|/| ) {
                    push @list, $mod;

                ### if this module is only numbers - meaning a previous lookup
                ### it will be stored in $href (the result of a previous search)
                ### keys in that hashref are numbers, not the module names.
                } elsif ( $mod !~ /\D/ ) {
                    if ( $flag ) {
                        ### zero pad to match hash key ###
                        my $mod = sprintf "%04d", $mod;

                        ### look up the module name in our hash ref ###
                        my $name = $href->{$mod}->{'module'};
                        if ( $name ) {
                            push @list, $name;
                            print "Fetching: $name\n";
                        } else {
                            print "No such module: $mod\n"
                        }
                    } else {
                        print "No search was done yet!\n";
                    }

                } else {
                    ### apparently, this is a 'normal' module name - look it up
                    ### this look up will have to take place in the modtree,
                    ### not the $href;
                    if ( my $name = $cpan->{_modtree}->{$mod}->{'module'} ) {
                        push @list, $name;
                        print "Fetching: $name\n";
                    } else {
                       print "No such module: $mod\n"
                    }
                }
            }

            ### get the result of our fetch... we store the modules in whatever
            ### dir the shell was invoked in.
            my $status = $cpan->fetch(
                modules     => [ @list ],
                fetchdir   => $cpan->{_conf}->_get_build( 'startdir'),
            );

            for my $key ( sort keys %$status ) {
                print   $status->{$key}
                        ? "Successfully fetched $key\n"
                        : "Error fetching $key\n";
            }


        ### l gives a Listing of details for modules.
        ### also takes multiple arguments, so:
        ### l LWP POE #works just fine
        } elsif ( $key =~ /^l/ ) {
            my $method = $cmd->{$key};

            my @list; my $res;

            ### split the input
            for my $mod ( split /\s+/, $input ) {

                ### if it's just digits, it was from a previous lookup
                if ( $mod =~ /^\d+$/ ) {
                    my $mod = sprintf "%04d", $mod;

                    push @list, $href->{$mod}->{'module'}

                ### else, it's a regular module name
                } else {
                    push @list, $mod;
                }
            }

            $res = $cpan->$method( modules => [ @list ] );

            for my $mod ( sort keys %$res ) {

                unless ( $res->{$mod}->{Package} ) {
                    print "\nNo details for $mod - are you sure it exists?\n";
                    next;
                }

                print "\nDetails for $mod:\n";
                for my $item ( sort keys %{$res->{$mod}} ) {
                    printf "%-30s %-30s\n", $item, $res->{$mod}->{$item}
                }
            }

        ### f gives a listing of distribution Files by a certain author
        ### also takes multiple arguments, so:
        ### f KANE DCONWAY #works just fine
        } elsif ( $key =~ /^f/ ) {
            my $method = $cmd->{$key};

            ### split the input
            my @list = split /\s+/, $input;

            my $res = $cpan->$method( authors => [ @list ] );

            unless ( $res ) {
                print "No authors found for your query\n";
                next;
            }

            for my $auth ( sort keys %$res ) {
                next unless $res->{$auth};
                for my $module ( sort keys %{$res->{$auth}} ) {

                    printf "%-12s %-12s %-50s\n", $auth, $res->{$auth}->{$module}->{size}, $module;
                }
                print "\n";
            }

        ### u uninstalls modules... not documented yet
        ### handle with care: unlinks files but doens't update packlist!
        } elsif ( $key =~ /^u/ ) {
            my $method = $cmd->{$key};

            my @list;

            ### split the input
            for my $mod ( split /\s+/, $input ) {

                ### if it's just digits, it was from a previous lookup
                unless ( $mod =~ /\D/ ) {
                    my $mod = sprintf "%04d", $mod;

                    my $name;
                    if ($name = $href->{$mod}->{'module'} ) {
                        push @list, $name;
                    } else {
                        print "Couldn't find a previous mach for $mod\n";
                    }

                ### else, it's a regular module name
                } else {
                    push @list, $mod;
                }
            }

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

            my $result = $cpan->$method(
                        type => $maps->{$key},
                        list => [ @regexps ],
                    );

            ### forget old searches...
            $href = {};

            ### if we got a result back....
            if ( $result ) {
                $flag = 1;
                my $i = '0000';

                ### store them in our $href; it's the storage for searches
                ### in Shell.pm
                for my $k ( sort keys %$result ) {
                    $href->{++$i} = $result->{$k};
                }

                ### pretty print some information about the search
                for (sort keys %$href) {
                    printf "%-5s %-50s %-7s %-10s\n",
                    $_, $href->{$_}->{'module'}, $href->{$_}->{'version'}, $href->{$_}->{'author'}
                }
            } else {
                print "Your search generated no results\n";
                next;
            }
        } else {
            print "unknown command '$key'. Usage:\n";
            $self->_help();
        }

        ### add this command to the history
        $term->addhistory($input) if $input =~ /\S/;

    } }

    ### continue the while loop in case we 'next' or 'last' it earlier
    ### to make sure the sig handler is still working properly
    continue {
        $self->{_signals}{INT}{count}--
            if $self->{_signals}{INT}{count}; # clear the sigint count
    }
}


# checks whether the Term::ReadLine is broken and needs to fallback to Stub
sub _is_bad_terminal {
    my $self = shift;
    return unless $^O eq 'MSWin32';

    # replace the term with the default (stub) one
    return $_[0] = $self->{_term} =
        Term::ReadLine::Stub->new( 'CPAN Terminal', *STDIN, *STDOUT );
}


sub _ask_prereq {
    my $obj     = shift;
    my %args    = @_;

    ### either it's called from Internals, or from the shell directly
    ### although the latter is unlikely...
    my $self = $obj->{_shell} || $obj;

    my $mod = $args{mod};

    print "\n$mod is a required module for this install. " .
            "Would you like me to install it? [Y/n]";

    while ( defined (my $input = $self->{_term}->readline) ) {

        if ( $input =~ /^y/i or !length $input) {
            ### must install this
            return $mod;
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

    print "\nStack printed succesfully\n";
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

sub _help {
    ### not yet public !! ##@
    #f                   # flush the cache on installed modules

    print <<EOL;
    a AUTHOR [ AUTHOR]  # search by author
    m MODULE [ MODULE]  # search by module
    i MODULE | NUMBER   # install module, by name or by search number
    d MODULE | NUMBER   # download module into current directory
    l MODULE [ MODULE]  # display detailed information about a module
    e DIR    [ DIR]     # add directories to your \@INC
    f AUTHOR [ AUTHOR]  # list all distributions by an author
    s OPTION VALUE      # set configuration options for this session
    p [ FILE]           # print the error stack (optionally to a file)
    h | ?               # display help
    q                   # exit

EOL
}

sub _quit {
    print "Exiting CPANPLUS shell\n";
    exit;
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

    CPAN Terminal>h

    CPAN Terminal>s verbose 1
    CPAN Terminal>e /home/kudra/perllib

    CPAN Terminal>m simple tcp
    CPAN Terminal>i 22 27 /K/KA/KANE/Acme-POE-Knee-1.10.zip

    CPAN Terminal>a damian

    CPAN Terminal>d XML::Twig

    CPAN Terminal>l DBD::Unify

    CPAN Terminal>f VROO?MANS$ DCROSS

    CPAN Terminal>p /tmp/cpanplus/errors

    CPAN Terminal>q

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

    0001    Acme::Pony    1.1     DCANTRELL
    0002    Acme::DWIM    1.05    DCONWAY

These columns correspond to the assigned number, module name,
version number and CPAN author identification.  Assigned numbers
can be used for a subsequent commands but are
reassigned for each search.  If no module version is listed,
the third field will be I<undef>.

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

    0001    Acme::POE::Knee    1.02    KANE

This is because while the CPAN author identification doesn't contain
the string, it B<is> found in the module author's full name (in this
case, I<Jos Boumans>).  There is currently no command to display the
author's full name.

=head2 i MODULE|NUMBER|FILENAME

This command installs a module by its case-sensitive name, by the
path and filename on CPAN, or by the number returned from a previous
search.  For instance:

=over 4

=item * C<i CGI::FormBuilder>

=item * C<i /K/KA/KANE/Acme-POE-Knee-1.10.zip>

=item * C<i 16>

This example would install result 0016 from the previous match.

=back

Install will search, fetch, extract and make the module.

=head2 d MODULE|NUMBER [MODULE|NUMBER]

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

=head2 l MODULE|NUMBER [MODULE|NUMBER]

This command lists detailed information about a module.

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

    KANE         12230        Acme-POE-Knee-1.00.zip
    KANE         14246        Acme-POE-Knee-1.01.zip
    KANE         12324        Acme-POE-Knee-1.02.zip
    KANE         6625         Acme-POE-Knee-1.10.zip

The first column is the CPAN author id, the second column is
the filesize, and the third is the name of the distribution.

=head2 s OPTION VALUE

The I<set> command can be used to override configuration settings for
the current session.  Available options:

=over 4

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

L<CPANPLUS::Backend>, L<CPANPLUS>

=cut
