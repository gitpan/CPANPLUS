# $File: //depot/cpanplus/dist/lib/CPANPLUS/Shell/Classic.pm $
# $Revision: #2 $ $Change: 2926 $ $DateTime: 2002/12/25 15:39:55 $

##################################################
###            CPANPLUS/Shell/Classic.pm       ###
###    Backwards compatible shell for CPAN++   ###
###      Written 08-04-2002 by Jos Boumans     ###
##################################################

package CPANPLUS::Shell::Classic;

### TODO LIST ###
# clean         make clean
#
# r             this will need a decent _installed method somehwere in internals..
#               the current one kinda sucks
#
# u             we dont track this information

use strict;
use CPANPLUS::Backend;

use Term::ReadLine;
use Data::Dumper;
use File::Spec;
use Cwd;

# The 'Classic' shell was never localized, so we wouldn't, either. ;)
# use CPANPLUS::I18N;

BEGIN {
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( CPANPLUS::Shell::_Base);
    $VERSION    =   '0.01';
}

### our command set ###
my $cmd = {
    h   => "_help",
    '?' => "_help",

    a   => "_author",
    b   => "_bundle",
    d   => "_distribution",
    m   => "_module",
    # i => does a b and m

    r   => "uptodate",
    u   => "_uninstalled",
    o   => "set_conf",
    q   => "_quit",

    readme  => "readme",
};

### semi-global vars ###

### make an object ###
my $cpan = new CPANPLUS::Backend;
my $conf = $cpan->configure_object();

### subs ###
### CPANPLUS::Shell::Default needs it's own constructor, seeing it will just access
### CPANPLUS::Backend anyway
sub new {
    my $proto = shift;
    my $class = ref($proto) || $proto;

    ### Will call the _init constructor in Internals.pm ###
    my $self = $class->SUPER::_init( brand => 'cpan' );

    return $self;
}

### The CPAN terminal interface ###
sub shell {
    my $self = shift;

    my $term = Term::ReadLine->new( $self->brand );
    my $prompt = $self->brand . "> ";

    $conf->set_conf( verbose => 1 );

    ### store this in the object, so we can access the prompt anywhere if need be
    $self->term(    $term);
    $self->backend( $cpan);

    $cpan->{_shell} = $self;

    $self->_show_banner($cpan);
    $self->_input_loop($cpan, $prompt) or print "\n"; # print only on abnormal quits
    $self->_quit;
}

### shell code, to keep stuff looping ###

    ### input loop. returns true if exited normally via 'q'.
    sub _input_loop {
        my ($self, $cpan, $prompt) = @_;
        my $term = $self->term;

        my $normal_quit;
        my $force_store;

        ### somehow it's caching previous input ###
        while (
            defined (my $input = eval { $term->readline($prompt) } )
            or $self->signals->{INT}{count} == 1
        ) {  eval {

            next unless length $input;

            INNER_EVAL: {

            ### re-initiate all signal handlers
            while (my ($sig, $entry) = each %{$self->signals}) {
                $SIG{$sig} = $entry->{handler} if exists($entry->{handler});
            }

            ### parse the input: all commands are 1 letter, followed
            ### by a space, followed by an arbitrary string
            ### the first letter is the command key
            my $key;
            {   # why the block? -jmb
                # to hide the $1. -autrijus
                $input =~ s|^\s*([\w\?\!]+)\s*||;

                #{ $input =~ s/^([!?])/$1 /; }
                #input =~ s|^\s*([\w\?\!])\w*\s*||;


                chomp $input;
                $key = lc($1);
            }

            ### let's see if we need to force some command here ###
            ### if so, set force to 1 and redo the loop
            if ($key =~ /^force$/ ) {
                $force_store = $conf->get_conf('force');

                $conf->set_conf( force => 1 );

                redo INNER_EVAL;
            }

            ### exit the loop altogether ###
            ### 'last' doesn't work, must use exit for now... -kane
            if ($key =~ /^q/) { $normal_quit = 1; exit; }

            if ($key eq '!' ) {
                eval $input;
                warn $@ if $@;
                next;
            }

            ### display the help ###
            if ($key =~ /^[h?]$/) {
                my $method = $cmd->{$key};
                $self->$method( );
                next;
            }


            ### author information ###
            if ($key =~ /^[ambd]$/) {
                ### load the appropriate method from our $cmd hash ###
                my $method = $cmd->{$key};
                my $aref = $self->$method( split /\s+/, $input );

                my $class = {
                    a   => 'Author',
                    m   => 'Module',
                    b   => 'Bundle',
                    d   => 'Distribution',
                    #u   => 'Uptodate',
                }->{$key};

                $self->_pretty_print(
                                    input   => $input,
                                    result  => $aref,
                                    class   => $class,
                                );

            } elsif ( $key eq 'i' ) {

                my $class = {
                    d   => 'Distribution',
                    b   => 'Bundle',
                    m   => 'Module',
                    a   => 'Author',
                };

                my $results;
                for my $k ( sort keys %$class ) {

                    my $method = $cmd->{$k};

                    my $aref = $self->$method( split /\s+/, $input );

                    $results += $self->_pretty_print(
                                            input   => $input,
                                            result  => $aref,
                                            class   => $class->{$k},
                                            short   => 1
                                        );
                }
                print $results
                    ? "$results items found\n"
                    : "No objects found of any type for argument $input";

            } elsif ( $key eq 'r' ) {
                my $method = $cmd->{$key};

                my $modtree = $cpan->module_tree() ;

                my $class = "Uptodate";

                ### is there certain modules we should check,
                ### or should we just check them all?
                ### -- all, this is per CPAN.pm spec:
                ### r   NONE   reinstall recommendations

                ### better print this warning out, we're not very fast here
                ### even if CPAN.pm doesn't do this
                my $inst = $cpan->installed();

                ### check the module status, uptodate or not
                my $res = $cpan->$method( modules => [keys %{$inst->rv}] )->rv;

                $self->_pretty_print(
                                input   => $input,
                                result  => $res,
                                class   => $class,
                            );


            } elsif ( $key eq 'u' ) {
                print qq[Sorry, CPANPLUS doesn't keep track of this kind of information\n];
                next;

            } elsif ( $key eq 'o' ) {

                $input =~ s|\s*(\w+)\s*||;
                my $type = lc $1;

                if( $type eq 'debug' ) {
                    print   qq[Sorry you can not set debug options through ] .
                            qq[this shell in CPANPLUS\n];
                    next;
                } elsif ( $type eq 'conf' ) {

                    ### from CPAN.pm :o)
                    # CPAN::Shell::o and CPAN::Config::edit are closely related. 'o conf'
                    # should have been called set and 'o debug' maybe 'set debug'

                    #    commit             Commit changes to disk
                    #    defaults           Reload defaults from disk
                    #    init               Interactive setting of all options

                    ### set configuration options
                    my ($name, $value) = $input =~ m/(\w+)\s*(.*?)\s*$/;

                    ### redo setup configuration?
                    if ($name eq 'init') {
                        CPANPLUS::Configure::Setup->init(
                            conf    => $cpan->configure_object,
                            term    => $self->term,
                            backend => $cpan,
                        );
                        return;

                    } elsif ($name eq 'commit' ) {;
                        $cpan->configure_object->save;
                        print "Your CPAN++ configuration info has been saved!\n\n";
                        return;

                    } elsif ($name eq 'defaults' ) {
                        print   qq[Sorry, CPANPLUS can not restore default for you.\n] .
                                qq[Perhaps you should run the interactive setup again.\n] .
                                qq[\ttry running 'o conf init'\n];
                        return;
                    }

                    ### allow lazy config options... not smart but possible ###
                    my $conf    = $cpan->configure_object;
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

                        print   qq[    commit             Commit changes to disk\n] .
                                qq[    defaults           Reload defaults from disk\n] .
                                qq[    init               Interactive setting of all options\n\n];

                        my $local_format = "    %-".(sort{$b<=>$a}(map(length, @options)))[0]."s %s\n";

                        foreach $key (@options) {
                            my $val = $conf->get_conf($key);
                            ($val) = ref($val)
                                        ? (Data::Dumper::Dumper($val) =~ /= (.*);$/)
                                        : "'$val'";
                            printf $local_format, $key, $val;
                        }
                    }
                } else {
                    print   qq[Known options:\n] .
                            qq[  conf    set or get configuration variables\n] .
                            qq[  debug   set or get debugging options\n];
                }
            }
            ### end of the one letter commands ###

            elsif ( $key eq 'get' ) {

                for my $mod (split /\s+/, $input) {

                    my $obj;
                    unless( $obj = $cpan->module_tree->{$mod} ) {
                        print "Warning: Cannot $key $input, don't know what it is\n";
                        print "Try the command\n\n";
                        print "\ti /$mod/\n\n";
                        print "to find objects with matching identifiers.\n";

                        next;
                    }

                    #my $rv      = $cpan->fetch( modules => [$obj] );
                    #my $href    = $cpan->extract( files => [ $rv->{$obj->module} ] );

                    $obj->fetch();
                    $obj->extract();

                }
            } elsif ( $key eq 'readme' ) {
                my $method = $cmd->{$key};

                for my $mod (split /\s+/, $input) {

                    my $obj;
                    unless( $obj = $cpan->module_tree->{$mod} ) {
                        print "Warning: Cannot $key $input, don't know what it is\n";
                        print "Try the command\n\n";
                        print "\ti /$mod/\n\n";
                        print "to find objects with matching identifiers.\n";

                        next;
                    }

                    my $readme = $obj->readme;

                    unless ($readme) {
                        print qq[No README file found for $mod\n];
                    } else {
                        $self->_pager_open;
                        print $readme, "\n";
                        $self->_pager_close;
                    }
                }

            } elsif ( $key =~ /^make|test|install|clean$/ ) {

                if( $key eq 'clean' ) {
                    print qq[Sorry, we don't know how to 'make clean' yet\n];
                    next;
                }

                my $method = $cmd->{$key};

                my $program = $conf->_get_build('make');
                my $options = $conf->get_conf('makeflags');

                my $flags = $self->_stringify_makeflags($options);

                for my $mod (split /\s+/, $input) {

                    my ($name,$obj) = %{ $cpan->parse_module( modules => [$mod] )->rv };

                    my $rv = $obj->install( target => $key );

                    my $status  = $rv->{install} ? 'OK' : 'NOT OK';
                    my $add     = $key eq 'make' ? ''   : $key;

                    print qq[  "$program" $flags $add -- $status\n];
                }

            } elsif ( $key eq 'reload' ) {

                if ( $input =~ /cpan/i ) {
                    print qq[You want to reload the CPAN code\n];
                    print qq[Just type 'q' and then restart... Trust me, it is MUCH safer\n];

                } elsif ( $input =~ /index/i ) {
                    $cpan->reload_indices(update_source => 1);

                } else {
                    print qq[cpan     re-evals the CPANPLUS.pm file\n];
                    print qq[index    re-reads the index files\n];
                }

            } elsif ( $key eq 'look' ) {

                my @modules = split /\s+/, $input;

                my $conf    = $cpan->configure_object;
                my $shell   = $conf->_get_build('shell');

                unless($shell) {
                    print   qq[Your config does not specify a subshell!\n] .
                            qq[Perhaps you need to re-run your setup?\n];

                    next;
                }
                my $cwd = cwd();

                for my $mod (@modules) {
                    my $obj = $cpan->module_tree->{$mod};

                    unless($obj) {
                        print   qq[Warning: Cannot look $mod, don't know what it is.].
                                qq[Try the command\n\n    i /$mod/   \n\n].
                                qq[to find object with matching identifiers.\n];
                        next;
                    }

                    my $dir = $obj->status->{extract};

                    unless( $dir ) {
                        $obj->fetch();
                        $dir = $obj->extract();
                    }

                    #$dir = $obj->status->{extract};

                    unless( $dir ) {
                        print qq[Could not determine where $mod was extracted too\n];
                        next;
                    }

                    unless( chdir $dir ) {
                        print qq[Could not chdir from $cwd to $dir: $!\n];
                        next;
                    }

                    if( system($shell) and $! ) {
                        print qq[Error executing your subshell: $!\n];
                        next;
                    }

                    unless( chdir $cwd ) {
                        print qq[Could not chdir back to $cwd from $dir: $!\n];
                    }
                }

            } elsif ( $key eq 'ls' ) {
                my @list;

                for my $auth (split /\s+/, $input) {
                    unless ( $cpan->author_tree->{uc $auth} ) {
                        print qq[$key command rejects argument $auth: not an author\n];
                        next;
                    }

                    push @list, uc $auth;
                }

                my $rv = $cpan->distributions( authors => [map {'^'.$_.'$'} @list] );

                $self->_pp_ls( result => $rv->rv, input => [@list] );

            } elsif ( $key eq 'autobundle' ) {

                print qq[Writing bundle file... This may take a while\n];

                my $rv = $cpan->autobundle();

                print $rv->ok
                    ? qq[\nWrote autobundle to ] . $rv->rv . qq[\n]
                    : qq[\nCould not create autobundle\n];

                next;

            } else {

                print qq[Unknown command '$key'. Type ? for help.\n];

            }

            } # INNER_EVAL:



        }; #}# end of eval and OUTER_EVAL

        warn $@ if $@;

        ### continue the while loop in case we 'next' or 'last' it earlier
        ### to make sure the sig handler is still working properly
        } continue {

            ### restore the previous setting of $force ###
            $conf->set_conf( force => $force_store ) unless $force_store;

            #$self->{_signals}{INT}{count}--
            #    if $self->{_signals}{INT}{count}; # clear the sigint count
        }

        return $normal_quit;
    }


    ### displays quit message
    sub _quit {

        ### well, that's what CPAN.pm says...
        print "Lockfile removed\n";
    }


### END SHELL STUFF ###

sub _pretty_print {
    my $self = shift;
    my %args = @_;

    my $class = $args{'class'} or return 0;

    if( $class eq 'Bundle' or $class eq 'Module' ) {
        return $self->_pp_module( %args );

    } elsif( $class eq 'Author' ) {
        return $self->_pp_author( %args );

    } elsif( $class eq 'Distribution' ) {
        return $self->_pp_distribution( %args );

    } elsif( $class eq 'Uptodate' ) {
        return $self->_pp_uptodate( %args );

    } else {
        return 0;
    }
}



### get author output back ###
sub _author {
    my $self = shift;
    my @args = scalar @_ ? @_ : ('/./'); # build a regex that matches all

    my @list;
    for my $author (@args) {
        $author = uc $author;

        ### if it's a regex... ###
        if ($author =~ m|/(.+)/|) {
            my $href = $cpan->search(
                                type            => 'author',
                                list            => ["(?i:$1)"],
                                authors_only    => 1,
                        );

            push @list, map { $href->{$_} } sort keys %$href;

        } else {
            my $obj = $cpan->author_tree->{$author} or next;

            push @list, $obj;
        }
    }
    return \@list;
}

sub _pp_author {
    my $self = shift;
    my %args = @_;

    my $aref    = $args{'result'}   or return 0;
    my $class   = $args{'class'}    or return 0;
    my $input   = $args{'input'};    ### no input means 'all'
    my $short   = $args{'short'};   ### display short version regardless?

    my $results = @$aref;

    if ( $results == 0 ) {
        print "No objects of type $class found for argument $input\n" unless $short;
        next;

    } elsif ( ($results == 1) and !$short) {

        ### should look like this:
        #cpan> a KANE
        #Author id = KANE
        #    EMAIL        boumans@frg.eur.nl
        #    FULLNAME     Jos Boumans

        my $obj = shift @$aref;

        print "$class id = ", $obj->cpanid(), "\n";
        printf "    %-12s %s\n", 'EMAIL', $obj->email();
        printf "    %-12s %s%s\n", 'FULLNAME', $obj->name();

    } else {

        ### should look like this:
        #Author          KANE (Jos Boumans)
        #Author          LBROCARD (Leon Brocard)
        #2 items found

        for my $obj ( @$aref ) {
            printf qq[%-15s %s ("%s" (%s))\n],
                $class, $obj->cpanid, $obj->name, $obj->email;
        }
        print "$results items found\n" unless $short;
    }
    return $results;
}


### find all bundles matching a query ###
sub _bundle {
    my $self = shift;
    my @args = scalar @_ ? @_ : ('/./'); # build a regex that matches all

    my @list;
    for my $bundle (@args) {
        ### if it's a regex... ###
        if ($bundle =~ m|/(.+)/|) {
            my $href = $cpan->search( type => 'module', list => ["^(?i:Bundle::.*?$1)"] );
            push @list, values %$href;

        } else {
            my $obj = $cpan->module_tree->{"Bundle::$bundle"} or next;

            push @list, $obj;
        }
    }
    return \@list;
}

sub _distribution {
    my $self = shift;
    my @args = scalar @_ ? @_ : ('/./'); # build a regex that matches all

    my @list;
    for my $module (@args) {
        ### if it's a regex... ###
        if ( my ($match) = $module =~ m|^/(.+)/$|) {

            ### something like /FOO/Bar.tar.gz/ was entered
            if (my ($path,$package) = $match =~ m|^/?(.+)/(.+)$|) {
                my $seen;

                my $data = $cpan->search( type => 'package', list => ["(?i:$package)"] );
                my $href = $cpan->search( type => 'path', list => ["(?i:$path)"], data => $data );

                ### make sure we dont list the same dist twice
                for my $val ( values %$href ) {
                    next if $seen->{$val->package()}++;

                    push @list, $val;
                }

            ### something like /FOO/ or /Bar.tgz/ was entered
            ### so we look both in the path, as well as in the package name
            } else {
                my $seen;
                {
                    my $href = $cpan->search( type => 'package', list => ["(?i:$match)"] );

                    ### make sure we dont list the same dist twice
                    for my $val ( values %$href ) {
                        next if $seen->{$val->package()}++;

                        push @list, $val;
                    }
                }
                {
                    my $href = $cpan->search( type => 'path', list => ["(?i:$match)"] );

                    ### make sure we dont list the same dist twice
                    for my $val ( values %$href ) {
                        next if $seen->{$val->package()}++;

                        push @list, $val;
                    }
                }
            }
        } else {

            ### user entered a full dist, like: R/RC/RCAPUTO/POE-0.19.tar.gz
            if (my ($path,$package) = $module =~ m|^/?(.+)/(.+)$|) {
                my $data = $cpan->search( type => 'package', list => ['^'.$package.'$'] );
                my $href = $cpan->search( type => 'path', list => ['^'.$path.'$'], data => $data);

                ### make sure we dont list the same dist twice
                my $seen;
                for my $val ( values %$href ) {
                    next if $seen->{$val->package()}++;

                    push @list, $val;
                }
            }
        }
    }
    return \@list;
}

sub _pp_distribution {
    my $self = shift;
    my %args = @_;

    my $aref    = $args{'result'}   or return 0;
    my $class   = $args{'class'}    or return 0;
    my $input   = $args{'input'};   ### no input means 'all'
    my $short   = $args{'short'};   ### display short version regardless?

    my $results = @$aref;

    if ( $results == 0 ) {
        print "No objects of type $class found for argument $input\n" unless $short;
        next;

    } elsif ( ($results == 1) and !$short) {

        ### should look like this:
        #Distribution id = S/SA/SABECK/POE-Component-Client-POP3-0.02.tar.gz
        #    CPAN_USERID  SABECK (Scott Beck <scott@gossamer-threads.com>)
        #    CONTAINSMODS POE::Component::Client::POP3

        my $obj     = shift @$aref;
        my $href    = $cpan->search( type => 'package', list => ['^'.$obj->package.'$'] );
        my $aut_obj = $cpan->author_tree->{ $obj->author() };

        my $format = "    %-12s %s\n";

        print "$class id = ", $obj->path(), '/', $obj->package(), "\n";
        printf $format, 'CPAN_USERID',
                    $obj->author() .' ('. $aut_obj->name .' ('. $aut_obj->email .'))';

        ### yes i know it's ugly, but it's what cpan.pm does
        printf $format, 'CONTAINSMODS', join (' ', sort keys %$href);

    } else {

        ### should look like this:
        #Module          LWP             (G/GA/GAAS/libwww-perl-5.64.tar.gz)
        #Module          POE             (R/RC/RCAPUTO/POE-0.19.tar.gz)
        #2 items found

        for my $obj ( @$aref ) {
            printf "%-15s %s\n", $class, $obj->path() .'/'. $obj->package();
        }

        print "$results items found\n" unless $short;
    }

    return $results;
}



### find all modules matching a query ###
sub _module {
    my $self = shift;
    my @args = scalar @_ ? @_ : ('/./'); # build a regex that matches all

    my @list;
    for my $module (@args) {
        ### if it's a regex... ###
        if ($module =~ m|/(.+)/|) {
            my $href = $cpan->search( type => 'module', list => ["(?i:$1)"] );
            push @list, map { $href->{$_} } sort keys %$href;

        } else {
            my $obj = $cpan->module_tree->{$module} or next;

            push @list, $obj;
        }
    }
    return \@list;
}

sub _pp_module {
    my $self = shift;
    my %args = @_;

    my $aref    = $args{'result'}   or return 0;
    my $class   = $args{'class'}    or return 0;
    my $input   = $args{'input'};   ### no input means 'all'
    my $short   = $args{'short'};   ### display short version regardless?

    my $results = @$aref;

    if ( $results == 0 ) {
        print "No objects of type $class found for argument $input\n" unless $short;
        next;

    } elsif ( ($results == 1) and !$short) {

        ### should look like this:
        #Module id = LWP
        #    DESCRIPTION  Libwww-perl
        #    CPAN_USERID  GAAS (Gisle Aas <gisle@ActiveState.com>)
        #    CPAN_VERSION 5.64
        #    CPAN_FILE    G/GA/GAAS/libwww-perl-5.64.tar.gz
        #    DSLI_STATUS  RmpO (released,mailing-list,perl,object-oriented)
        #    MANPAGE      LWP - The World-Wide Web library for Perl
        #    INST_FILE    C:\Perl\site\lib\LWP.pm
        #    INST_VERSION 5.62

        my $obj = shift @$aref;

        my $aut_obj     = $cpan->author_tree->{ $obj->author() };
        my $uptodate    = $cpan->uptodate( modules => [$obj] )->rv;

        my $format = "    %-12s %s%s\n";

        print "$class id = ", $obj->module(), "\n";
        printf $format, 'DESCRIPTION',  $obj->description() if $obj->description();
        printf $format, 'CPAN_USERID',  $aut_obj->cpanid() . " (" . $aut_obj->name() . " <" . $aut_obj->email() . ">)";
        printf $format, 'CPAN_VERSION', $obj->version();
        printf $format, 'CPAN_FILE',    $obj->path() . '/' . $obj->package();
        printf $format, 'DSLI_STATUS',  $self->_pp_dslip("status"=>$obj->dslip()) if $obj->dslip() =~ /\w/;
        #printf $format, 'MANPAGE',      $obj->foo();
        #printf $format, 'CONATAINS, ### this is for bundles... CPAN.pm downloads them,
        # parses and goes from there...
        printf $format, 'INST_FILE',    $uptodate->{$obj->module}->{file} || '(not installed)';
        printf $format, 'INST_VERSION', $uptodate->{$obj->module}->{version}

    } else {

        ### should look like this:
        #Module          LWP             (G/GA/GAAS/libwww-perl-5.64.tar.gz)
        #Module          POE             (R/RC/RCAPUTO/POE-0.19.tar.gz)
        #2 items found

        for my $obj ( @$aref ) {
            printf "%-15s %-15s (%s)\n", $class, $obj->module(), $obj->path() .'/'. $obj->package();
        }
        print "$results items found\n" unless $short;
    }

    return $results;
}

sub _pp_dslip {
    my $self = shift;
    my %args = @_;

    my (%_statusD, %_statusS, %_statusL, %_statusI);

    @_statusD{qw(? i c a b R M S)} = qw(unknown idea pre-alpha alpha beta released mature standard);
    @_statusS{qw(? m d u n)}       = qw(unknown mailing-list developer comp.lang.perl.* none);
    @_statusL{qw(? p c + o h)}     = qw(unknown perl C C++ other hybrid);
    @_statusI{qw(? f r O h)}       = qw(unknown functions references+ties object-oriented hybrid);

    my $status = $args{'status'} or return 0;
    my @status = split("", $status);

    my $results = sprintf( "%s (%s,%s,%s,%s)",
        $status,
        $_statusD{$status[0]},
        $_statusS{$status[1]},
        $_statusL{$status[2]},
        $_statusI{$status[3]}
    );

    return $results;
}


sub _pp_uptodate {
    my $self = shift;
    my %args = @_;

    my $res     = $args{'result'}   or return 0;
    my $class   = $args{'class'}    or return 0;
    my $input   = $args{'input'};   ### no input means 'check all';

    ### store the ones that are actually NOT uptodate ###
    ### keep a counter of how many results we got as well ###
    my $store;
    my $result;
    my $none;

    for my $name ( sort keys %$res ) {
        if( $res->{$name}->{version} == 0 ){ $none++ }

        next unless $res->{$name}->{uptodate} eq '0';

        $store->{$name} = $res->{$name};
        $result++;
    }

    my $format  = "%-25s %9s %9s  %s\n";

    unless( $result ) {
        my $string = $input
                        ? "for $input"
                        : '';
        print "All modules are up to date $string\n";
        next;
    } else {
        printf $format, (
                            'Package namespace',
                            'installed',
                            'latest',
                            'in CPAN file'
                        );
    }

    for my $name ( sort keys %$store ) {
        my $uptodate = $store->{$name};

        my $modobj = $cpan->module_tree->{$name};

        printf $format, (
                            $name,
                            $uptodate->{version},
                            $modobj->version(),
                            $modobj->path() .'/'. $modobj->package(),
                        );
    }

    if ($none)  { print "$none installed modules have no (parsable) version number\n"; }

    return $result;
}

sub _uninstalled {
    my $self = shift;

    ### let's see if we got args or not ###
    my @args; my $flag;
    if ( scalar @_  ) {
        @args = @_ ;
    } else {
        $flag = 1;
    }

    my $inst = $cpan->installed();

    my $rv;
    ### get all the modules matching the criteria ###
    for my $module (@args) {
        ### if it's a regex... ###
        if ($module =~ m|/(.+)/|) {
            my $href = $cpan->search( type => 'module', list => ["(?i:$1)"] );

            while( my($k,$v) = each %$href ) {
                next if $inst->{$k};
                $rv->{$k} = $v;
            }

        } else {
            my $obj = $cpan->module_tree->{$module} or next;
            next if $inst->{ $obj->module };

            $rv->{ $obj->module } = $obj;
        }
    }

    if ($flag) {
        $rv = $cpan->module_tree;
        for my $k ( keys %{$rv} ) {
            print "looking at $k\n";
            delete $rv->{$k} if $inst->{$k};

        }
    }

    return $rv;
}

sub _pp_ls {
    my $self = shift;
    my %args = @_;

    my $result = $args{result}  or return 0;
    my $input   = $args{input}  or return 0;

    my $format = "%8d %10s %s/%s\n";

    ### ensure we are printing it out in the proper order ###
    for my $auth (@$input) {
        my $cksum = $result->{$auth} or next;

        for my $dist ( sort keys %$cksum ) {
            printf $format, $cksum->{$dist}->{size},
                            $cksum->{$dist}->{mtime},
                            $auth, $dist;
        }
    }
}

sub _stringify_makeflags {
    my $self = shift;
    my $opts = shift;

    my $str;
    if( ref $opts eq 'HASH' ) {
        while(my ($k,$v) = each %$opts ) {
            $str .= "$k=$v ";
        }
    } elsif ( ref $opts eq 'ARRAY' ) {
        $str = join " ", @$opts;
    } elsif ( ref $opts eq 'SCALAR' ) {
        $str = $opts;
    } else {
        warn qq[Odd makeflags set: ] . ref $opts . qq[. Do not know how to parse\n];
        $str = '';
    }
    return $str;
}


sub _help {
    print qq[
Display Information
 a                                    authors
 b         string           display   bundles
 d         or               info      distributions
 m         /regex/          about     modules
 i         or                         anything of above
 r         none             reinstall recommendations
 u                          uninstalled distributions

Download, Test, Make, Install...
 get                        download
 make                       make (implies get)
 test      modules,         make test (implies make)
 install   dists, bundles   make install (implies test)
 clean                      make clean
 look                       open subshell in these dists' directories
 readme                     display these dists' README files

Other
 h,?           display this menu       ! perl-code   eval a perl command
 o conf [opt]  set and query options   q             quit the cpan shell
 reload cpan   load CPAN.pm again      reload index  load newer indices
 autobundle    Snapshot                force cmd     unconditionally do cmd
];

}

=pod

=head1 NAME

CPANPLUS::Shell::Classic - CPAN.pm emulation for CPAN++

=head1 DESCRIPTION

The Classic shell is designed to provide the feel of the CPAN.pm shell
using CPANPLUS underneath.

For detailed documentation, refer to L<CPAN>.

=head1 AUTHORS

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt>.

This pod text by Ann Barcomb E<lt>kudra@cpan.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001, 2002 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=head1 SEE ALSO

L<CPAN>

=cut


# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
