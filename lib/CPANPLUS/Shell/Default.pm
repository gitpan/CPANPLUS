package CPANPLUS::Shell::Default;

use strict;

use CPANPLUS::inc;
use CPANPLUS::Error;
use CPANPLUS::Backend;
use CPANPLUS::Configure::Setup;
use CPANPLUS::Internals::Constants;
use CPANPLUS::Internals::Constants::Report qw[GRADE_FAIL];

use Cwd;
use IPC::Cmd;
use Term::UI;
use Data::Dumper;
use Term::ReadLine;

use Module::Load                qw[load];
use Params::Check               qw[check];
use Module::Load::Conditional   qw[can_load];
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';

local $Params::Check::VERBOSE = 1;

BEGIN {
    use vars        qw[ $VERSION @ISA ];
    @ISA        =   qw[ CPANPLUS::Shell::_Base::ReadLine ];
    $VERSION    =   '0.051';
}

load CPANPLUS::Shell;

my $map = {
    'm'     => '_search_module',
    'a'     => '_search_author',
    '!'     => '_bang',
    '?'     => '_help',
    'h'     => '_help',
    'q'     => '_quit',
    'r'     => '_readme',
    'v'     => '_show_banner',
    'w'     => '__display_results',
    'd'     => '_fetch',
    'z'     => '_shell',
    'f'     => '_distributions',
    'x'     => '_reload_indices',
    'i'     => '_install',
    't'     => '_install',
    'l'     => '_details',
    'p'     => '_print',
    's'     => '_set_conf',
    'o'     => '_uptodate',
    'b'     => '_autobundle',
    'u'     => '_uninstall',
    '/'     => '_meta',         # undocumented for now
    'c'     => '_reports',
};
### free letters: e g j k n y ###


### will be filled if you have a .default-shell.rc and
### Config::Auto installed
my $rc = {};

### the shell object, scoped to the file ###
my $Shell;
my $Brand   = loc('CPAN Terminal');
my $Prompt  = $Brand . '> ';

=pod

=head1 NAME

CPANPLUS::Shell::Default

=head1 SYNOPSIS

    ### loading the shell:
    $ cpanp                     # run 'cpanp' from the command line
    $ perl -MCPANPLUS -eshell   # load the shell from the command line


    use CPANPLUS::Shell qw[Default];    # load this shell via the API
                                        # always done via CPANPLUS::Shell

    my $ui = CPANPLUS::Shell->new;
    $ui->shell;                         # run the shell
    $ui->dispatch_on_input('x');        # update the source using the
                                        # dispatch method

    ### when in the shell:
    ### Note that all commands can also take options.
    ### Look at their underlying CPANPLUS::Backend methods to see
    ### what options those are.
    cpanp> h                # show help messages
    cpanp> ?                # show help messages

    cpanp> m Acme           # find acme modules, allows regexes
    cpanp> a KANE           # find modules by kane, allows regexes
    cpanp> f Acme::Foo      # get a list of all releases of Acme::Foo

    cpanp> i Acme::Foo      # install Acme::Foo
    cpanp> i Acme-Foo-1.3   # install version 1.3 of Acme::Foo
    cpanp> i 1 3..5         # install search results 1, 3, 4 and 5
    cpanp> i *              # install all search results
    cpanp> a KANE; i *;     # find modules by kane, install all results
    cpanp> t Acme::Foo      # test Acme::Foo, without installing it
    cpanp> u Acme::Foo      # uninstall Acme::Foo
    cpanp> d Acme::Foo      # download Acme::Foo
    cpanp> z Acme::Foo      # download & extract Acme::Foo, then open a
                            # shell in the extraction directory

    cpanp> c Acme::Foo      # get a list of test results for Acme::Foo
    cpanp> l Acme::Foo      # view details about the Acme::Foo package
    cpanp> r Acme::Foo      # view Acme::Foo's README file
    cpanp> o                # get a list of all installed modules that
                            # are out of date

    cpanp> s conf           # show config settings
    cpanp> s conf md5 1     # enable md5 checks
    cpanp> s program        # show program settings
    cpanp> s edit           # edit config file
    cpanp> s reconfigure    # go through initial configuration again
    cpanp> s save           # save config to disk

    cpanp> ! [PERL CODE]    # execute the following perl code
    cpanp> /source FILE     # read in commands from FILE

    cpanp> b                # create an autobundle for this computers
                            # perl installation
    cpanp> x                # reload index files
    cpanp> p [FILE]         # print error stack (to a file)
    cpanp> v                # show the banner
    cpanp> w                # show last search results again

    cpanp> q                # quit the shell

=head1 DESCRIPTION

This module provides the default user interface to C<CPANPLUS>. You
can start it via the C<cpanp> binary, or as detailed in the L<SYNOPSIS>.

=cut

### XXX note classic shell when done

sub new {
    my $class   = shift;

    my $cb      = new CPANPLUS::Backend;
    my $self    = $class->SUPER::_init(
                            brand   => $Brand,
                            term    => Term::ReadLine->new( $Brand ),
                            prompt  => $Prompt,
                            backend => $cb,
                            format  => "%5s %-50s %8s %-10s\n",
                        );
    ### make it available package wide ###
    $Shell = $self;

    my $rc_file = File::Spec->catfile(
                        $cb->configure_object->get_conf('base'),
                        DOT_SHELL_DEFAULT_RC,
                    );


    if( -e $rc_file && -r _ ) {
        $rc = _read_configuration_from_rc( $rc_file );
    }

    ### register install callback ###
    $cb->_register_callback(
            name    => 'install_prerequisite',
            code    => \&__ask_about_install,
    );

    ### execute any login commands specified ###
    $self->dispatch_on_input( input => $rc->{'login'} )
            if defined $rc->{'login'};

    ### register test report callbacks ###
    $cb->_register_callback(
            name    => 'edit_test_report',
            code    => \&__ask_about_edit_test_report,
    );

    $cb->_register_callback(
            name    => 'send_test_report',
            code    => \&__ask_about_send_test_report,
    );


    return $self;
}

sub shell {
    my $self = shift;
    my $term = $self->term;

    $self->_show_banner;
    $self->_input_loop && print "\n";
    $self->_quit;
}

sub _input_loop {
    my $self    = shift;
    my $term    = $self->term;
    my $cb      = $self->backend;

    my $normal_quit = 0;
    while (
        defined (my $input = eval { $term->readline($self->prompt) } )
        or $self->_signals->{INT}{count} == 1
    ) {
        ### re-initiate all signal handlers
        while (my ($sig, $entry) = each %{$self->_signals} ) {
            $SIG{$sig} = $entry->{handler} if exists($entry->{handler});
        }

	print "\n";
        last if $self->dispatch_on_input( input => $input );

        ### flush the lib cache ###
        $cb->_flush( list => [qw|lib|] );

    } continue {
        $self->_signals->{INT}{count}--
            if $self->_signals->{INT}{count}; # clear the sigint count
    }

    return 1;
}

### return 1 to quit ###
sub dispatch_on_input {
    my $self = shift;
    my $conf = $self->backend->configure_object();
    my $term = $self->term;
    my %hash = @_;

    my($string, $noninteractive);
    my $tmpl = {
        input          => { required => 1, store => \$string },
        noninteractive => { required => 0, store => \$noninteractive },
    };

    check( $tmpl, \%hash ) or return;

    ### indicates whether or not the user will receive a shell
    ### prompt after the command has finished.
    $self->noninteractive($noninteractive) if defined $noninteractive;

    my @cmds =  split ';', $string;
    while( my $input = shift @cmds ) {

        ### to send over the socket ###
        my $org_input = $input;

        my $key; my $options;
        {   ### make whitespace not count when using special chars
            { $input =~ s|^\s*([!?/])|$1 |; }

            ### get the first letter of the input
            $input =~ s|^\s*([\w\?\!/])\w*\s*||;

            chomp $input;
            $key =  lc($1);

            ### allow overrides from the config file ###
            if( defined $rc->{$key} ) {
                $input = $rc->{$key} . $input;
            }

            ### grab command line options like --no-force and --verbose ###
            ($options,$input) = $term->parse_options($input)
                unless $key eq '!';
        }

        ### emtpy line? ###
        return unless $key;

        ### time to quit ###
        return 1 if $key eq 'q';

        my $method = $map->{$key};

        ### dispatch meta locally at all times ###
        $self->$method(input => $input, options => $options), next
            if $key eq '/';

        ### flush unless we're trying to print the stack
        CPANPLUS::Error->flush unless $key eq 'p';

        ### connected over a socket? ###
        if( $self->remote ) {

            ### unsupported commands ###
            if( $key eq 'z' or
                ($key eq 's' and $input =~ /^\s*edit/)
            ) {
                print "\n", loc("Command not supported over remote connection"),
                        "\n\n";

            } else {
                my($status,$buff) = $self->__send_remote_command($org_input);

                print "\n", loc("Command failed!"), "\n\n" unless $status;

                $self->_pager_open if $buff =~ tr/\n// > $self->_term_rowcount;
                print $buff;
                $self->_pager_close;
            }

        ### or just a plain local shell? ###
        } else {

            unless( $self->can($method) ) {
                print loc("Unknown command '%1'. Usage:", $key), "\n";
                $self->_help;

            } else {

                ### some methods don't need modules ###
                my @mods;
                @mods = $self->_select_modules($input)
                        unless grep {$key eq $_} qw[! m a v w x p s b / ? h];

                eval { $self->$method(  modules => \@mods,
                                        options => $options,
                                        input   => $input,
                                        choice  => $key )
                };
                warn $@ if $@;
            }
        }
    }

    return;
}

sub _select_modules {
    my $self    = shift;
    my $input   = shift or return;
    my $cache   = $self->cache;
    my $cb      = $self->backend;

    ### expand .. in $input
    $input =~ s{\b(\d+)\s*\.\.\s*(\d+)\b}
               {join(' ', ($1 < 1 ? 1 : $1) .. ($2 > $#{$cache} ? $#{$cache} : $2))}eg;

    $input = join(' ', 1 .. $#{$cache}) if $input eq '*';
    $input =~ s/'/::/g; # perl 4 convention

    my @rv;
    for my $mod (split /\s+/, $input) {

        ### it's a cache look up ###
        if( $mod =~ /^\d+/ and $mod > 0 ) {
            unless( scalar @$cache ) {
                print loc("No search was done yet!"), "\n";

            } elsif ( my $obj = $cache->[$mod] ) {
                push @rv, $obj;

            } else {
                print loc("No such module: %1", $mod), "\n";
            }

        } else {
            my $obj = $cb->parse_module( module => $mod );

            unless( $obj ) {
                print loc("No such module: %1", $mod), "\n";

            } else {
                push @rv, $obj;
            }
        }
    }

    unless( scalar @rv ) {
        print loc("No modules found to operate on!\n");
        return;
    } else {
        return @rv;
    }
}

sub _format_version {
    my $self    = shift;
    my $version = shift;

    ### fudge $version into the 'optimal' format
    $version = 0 if $version eq 'undef';
    $version =~ s/_//g; # everything after gets stripped off otherwise
    $version = sprintf('%3.4f', $version);
    $version = '' if $version == '0.00';
    $version =~ s/(00?)$/' ' x (length $1)/e;

    return $version;
}

sub __display_results {
    my $self    = shift;
    my $cache   = $self->cache;

    my @rv = @$cache;

    if( scalar @rv ) {

        $self->_pager_open if $#{$cache} >= $self->_term_rowcount;

        my $i = 1;
        for my $mod (@rv) {
            next unless $mod;   # first one is undef
                                # humans start counting at 1

            printf $self->format,
                            $i,
                            $mod->module,
                            $self->_format_version($mod->version),
                            $mod->author->cpanid();
            $i++;
        }

        $self->_pager_close;

    } else {
        print loc("No results to display"), "\n";
    }
}


sub _quit {
    my $self = shift;

    $self->dispatch_on_input( input => $rc->{'logout'} )
            if defined $rc->{'logout'};

    print loc("Exiting CPANPLUS shell"), "\n";
}

###########################
### actual command subs ###
###########################


### print out the help message ###
### perhaps, '?' should be a slightly different version ###
my @Help;
sub _help {
    my $self = shift;
    my %hash    = @_;

    my $input;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            input   => { required => 0, store => \$input }
        };

        my $args = check( $tmpl, \%hash ) or return;
    }

    @Help = (
loc('[General]'                                                                     ),
loc('    h | ?                  # display help'                                     ),
loc('    q                      # exit'                                             ),
loc('    v                      # version information'                              ),
loc('[Search]'                                                                      ),
loc('    a AUTHOR ...           # search by author(s)'                              ),
loc('    m MODULE ...           # search by module(s)'                              ),
loc('    f MODULE ...           # list all releases of a module'                    ),
loc("    o [ MODULE ... ]       # list installed module(s) that aren't up to date"  ),
loc('    w                      # display the result of your last search again'     ),
loc('[Operations]'                                                                  ),
loc('    i MODULE | NUMBER ...  # install module(s), by name or by search number'   ),
loc('    t MODULE | NUMBER ...  # test module(s), by name or by search number'      ),
loc('    u MODULE | NUMBER ...  # uninstall module(s), by name or by search number' ),
loc('    d MODULE | NUMBER ...  # download module(s)'                               ),
loc('    l MODULE | NUMBER ...  # display detailed information about module(s)'     ),
loc('    r MODULE | NUMBER ...  # display README files of module(s)'                ),
loc('    c MODULE | NUMBER ...  # check for module report(s) from cpan-testers'     ),
loc('    z MODULE | NUMBER ...  # extract module(s) and open command prompt in it'  ),
loc('[Local Administration]'                                                        ),
loc('    b                      # write a bundle file for your configuration'       ),
loc('    s program [OPT VALUE]  # set program locations for this session'           ),
loc('    s conf    [OPT VALUE]  # set config options for this session'              ),
loc('    s reconfigure | save   # reconfigure settings / save current settings'     ),
loc('    s edit                 # open configuration file in editor and reload'     ),
#loc('    /(dis)connect          # (dis)connect to a remote machine running cpanpd'  ),
loc('    /source FILE [FILE ..] # read in commands from the specified file'         ),
loc('    ! EXPR                 # evaluate a perl statement'                        ),
loc('    p [FILE]               # print the error stack (optionally to a file)'     ),
loc('    x                      # reload CPAN indices'                              ),
    ) unless @Help;

    $self->_pager_open if (@Help >= $self->_term_rowcount);
    ### XXX: functional placeholder for actual 'detailed' help.
    print "Detailed help for the command '$input' is not available.\n\n"
      if length $input;
    print map {"$_\n"} @Help;
    $self->_pager_close;
}

### eval some code ###
sub _bang {
    my $self    = shift;
    my $cb      = $self->backend;
    my %hash    = @_;


    my $input;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            input   => { required => 1, store => \$input }
        };

        my $args = check( $tmpl, \%hash ) or return;
    }

    eval $input;
    error( $@ ) if $@;
    print "\n";
    return;
}

sub _search_module {
    my $self    = shift;
    my $cb      = $self->backend;
    my %hash    = @_;

    my $args;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            input   => { required => 1, },
            options => { default => { } },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    my @regexes = map { qr/$_/i } split /\s+/, $args->{'input'};

    ### XXX this is rather slow, because (probably)
    ### of the many method calls
    ### XXX need to profile to speed it up =/

    ### find the modules ###
    my @rv = sort { $a->module cmp $b->module }
                    $cb->search(
                        %{$args->{'options'}},
                        type    => 'module',
                        allow   => \@regexes,
                    );

    ### store the result in the cache ###
    $self->cache([undef,@rv]);

    $self->__display_results;

    return 1;
}

sub _search_author {
    my $self    = shift;
    my $cb      = $self->backend;
    my %hash    = @_;

    my $args;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            input   => { required => 1, },
            options => { default => { } },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    my @regexes = map { qr/$_/i } split /\s+/, $args->{'input'};

    my @rv;
    for my $type (qw[author cpanid]) {
        push @rv, $cb->search(
                        %{$args->{'options'}},
                        type    => $type,
                        allow   => \@regexes,
                    );
    }

    my %seen;
    my @list =  sort { $a->module cmp $b->module }
                grep { defined }
                map  { $_->modules }
                grep { not $seen{$_}++ } @rv;

    $self->cache([undef,@list]);

    $self->__display_results;
    return 1;
}

sub _readme {
    my $self    = shift;
    my $cb      = $self->backend;
    my %hash    = @_;

    my $args; my $mods; my $opts;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            modules => { required => 1,  store => \$mods },
            options => { default => { }, store => \$opts },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    return unless scalar @$mods;

    $self->_pager_open;
    for my $mod ( @$mods ) {
        print $mod->readme( %$opts );
    }

    $self->_pager_close;

    return 1;
}

sub _fetch {
    my $self    = shift;
    my $cb      = $self->backend;
    my %hash    = @_;

    my $args; my $mods; my $opts;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            modules => { required => 1,  store => \$mods },
            options => { default => { }, store => \$opts },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    $self->_pager_open if @$mods >= $self->_term_rowcount;
    for my $mod (@$mods) {
        my $where = $mod->fetch( %$opts );

        print $where
                ? loc("Successfully fetched '%1' to '%2'",
                        $mod->module, $where )
                : loc("Failed to fetch '%1'", $mod->module);
        print "\n";
    }
    $self->_pager_close;

}

sub _shell {
    my $self    = shift;
    my $cb      = $self->backend;
    my $conf    = $cb->configure_object;
    my %hash    = @_;

    my $shell = $conf->get_program('shell');
    unless( $shell ) {
        print   loc("Your config does not specify a subshell!"), "\n",
                loc("Perhaps you need to re-run your setup?"), "\n";
        return;
    }

    my $args; my $mods; my $opts;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            modules => { required => 1,  store => \$mods },
            options => { default => { }, store => \$opts },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    my $cwd = Cwd::cwd();
    for my $mod (@$mods) {
        $mod->fetch(    %$opts )    or next;
        $mod->extract(  %$opts )    or next;

        $cb->_chdir( dir => $mod->status->extract() )   or next;

        local $ENV{PERL5OPT} = CPANPLUS::inc->original_perl5opt;
        if( system($shell) and $! ) {
            print loc("Error executing your subshell '%1': %2",
                        $shell, $!),"\n";
            next;
        }
    }
    $cb->_chdir( dir => $cwd );

    return 1;
}

sub _distributions {
    my $self    = shift;
    my $cb      = $self->backend;
    my $conf    = $cb->configure_object;
    my %hash    = @_;

    my $args; my $mods; my $opts;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            modules => { required => 1,  store => \$mods },
            options => { default => { }, store => \$opts },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    my @list;
    for my $mod (@$mods) {
        push @list, sort { $a->version <=> $b->version }
                    grep { defined } $mod->distributions( %$opts );
    }

    my @rv = sort { $a->module cmp $b->module } @list;

    $self->cache([undef,@rv]);
    $self->__display_results;

    return; 1;
}

sub _reload_indices {
    my $self = shift;
    my $cb   = $self->backend;
    my %hash = @_;

    my $args; my $opts;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            options => { default => { }, store => \$opts },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    return $cb->reload_indices( %$opts );
}

sub _install {
    my $self    = shift;
    my $cb      = $self->backend;
    my $conf    = $cb->configure_object;
    my %hash    = @_;

    my $args; my $mods; my $opts; my $choice;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            modules => { required => 1,     store => \$mods },
            options => { default  => { },   store => \$opts },
            choice  => { required => 1,     store => \$choice,
                         allow    => [qw|i t|] },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    unless( scalar @$mods ) {
        print loc("Nothing done\n");
        return;
    }

    my $target = $choice eq 'i' ? TARGET_INSTALL : TARGET_CREATE;
    my $prompt = $choice eq 'i' ? loc('Installing ') : loc('Testing ');

    my $status = {};
    ### first loop over the mods to install them ###
    for my $mod (@$mods) {
        print $prompt, $mod->module, "\n";

        ### store the status for look up when we're done with all
        ### install calls
        $status->{$mod} = $mod->install( %$opts, target => $target );
    }

    my $flag;
    ### then report whether all this went ok or not ###
    for my $mod (@$mods) {
    #    if( $mod->status->installed ) {
        if( $status->{$mod} ) {
            print loc("Module '%1' %tense(%2,past) successfully\n",
                        $mod->module, $target)
        } else {
            $flag++;
            print loc("Error %tense(%1,present) '%2'\n",
                        $target, $mod->module);
        }
    }



    if( !$flag ) {
        print loc("No errors %tense(%1,present) all modules", $target), "\n";
    } else {
        print loc("Problem %tense(%1,present) one or more modules", $target);
        print "\n";
        print loc("*** You can view the complete error buffer by pressing '%1' ***\n", 'p')
                unless $conf->get_conf('verbose') || $self->noninteractive;
    }
    print "\n";

    return !$flag;
}

sub __ask_about_install {
    my $mod     = shift or return;
    my $prereq  = shift or return;
    my $term    = $Shell->term;

    print "\n";
    print loc(  "Module '%1' requires '%2' to be installed",
                $mod->module, $prereq->module );
    print "\n\n";
    print loc(  "If you don't wish to see this question anymore\n".
                "you can disable it by entering the following ".
                "commands on the prompt:\n    '%1'",
                's conf prereqs 1; s save' );
    print "\n\n";

    my $bool =  $term->ask_yn(
                    prompt  => loc("Should I install this module?"),
                    default => 'y'
                );

    return $bool;
}

sub __ask_about_send_test_report {
    my($mod, $grade) = @_;
    return 1 unless $grade eq GRADE_FAIL;

    my $term    = $Shell->term;

    print "\n";
    print loc(  "Test report prepared for module '%1'\n. Would you like to ".
                "send it? (You can edit it if you like)", $mod->module );
    print "\n\n";
    my $bool =  $term->ask_yn(
                    prompt  => loc("Would you like to send the test report?"),
                    default => 'n'
                );

    return $bool;
}

sub __ask_about_edit_test_report {
    my($mod, $grade) = @_;
    return 0 unless $grade eq GRADE_FAIL;

    my $term    = $Shell->term;

    print "\n";
    print loc(  "Test report prepared for module '%1'. You can edit this ".
                "report if you would like", $mod->module );
    print "\n\n";
    my $bool =  $term->ask_yn(
                    prompt  => loc("Would you like to edit the test report?"),
                    default => 'y'
                );

    return $bool;
}



sub _details {
    my $self    = shift;
    my $cb      = $self->backend;
    my $conf    = $cb->configure_object;
    my %hash    = @_;

    my $args; my $mods; my $opts;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            modules => { required => 1,  store => \$mods },
            options => { default => { }, store => \$opts },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    ### every module has about 10 lines of details
    ### maybe more later with Module::CPANTS etc
    $self->_pager_open if scalar @$mods * 10 > $self->_term_rowcount;


    my $format = "%-30s %-30s\n";
    for my $mod (@$mods) {
        my $href = $mod->details( %$opts );
        my @list = sort { $a->module cmp $b->module } $mod->contains;

        unless( $href ) {
            print loc("No details for %1 - it might be outdated.",
                        $mod->module), "\n";
            next;

        } else {
            print loc( "Details for '%1'\n", $mod->module );
            for my $item ( sort keys %$href ) {
                printf $format, $item, $href->{$item};
            }
            
            my $showed;
            for my $item ( @list ) {
                printf $format, ($showed ? '' : 'Contains:'), $item->module;
                $showed++;
            }
            print "\n";
        }
    }
    $self->_pager_close;
    print "\n";

    return 1;
}

sub _print {
    my $self = shift;
    my %hash = @_;

    my $args; my $opts; my $file;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            options => { default => { }, store => \$opts },
            input   => { default => '',  store => \$file },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    my $old; my $fh;
    if( $file ) {
        $fh = FileHandle->new( ">$file" )
                    or( warn loc("Could not open '%1': '%2'", $file, $!),
                        return
                    );
        $old = select $fh;
    }


    $self->_pager_open if !$file;

    print CPANPLUS::Error->stack_as_string;

    $self->_pager_close;

    select $old if $old;
    print "\n";

    return 1;
}

sub _set_conf {
    my $self    = shift;
    my %hash    = @_;
    my $cb      = $self->backend;
    my $conf    = $cb->configure_object;

    ### possible options
    ### XXX hard coded, not optimal :(
    my @types   = qw[reconfigure save edit program conf];


    my $args; my $opts; my $input;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            options => { default => { }, store => \$opts },
            input   => { default => '',  store => \$input },
        };

        $args = check( $tmpl, \%hash ) or return;
    }

    my ($type,$key,$value) = $input =~ m/(\w+)\s*(\w*)\s*(.*?)\s*$/;
    $type = lc $type;

    if( $type eq 'reconfigure' ) {
        my $setup = CPANPLUS::Configure::Setup->new(
                        conf    => $conf,
                        term    => $self->term,
                        backend => $cb,
                    );
        return $setup->init;

    } elsif ( $type eq 'save' ) {
        my $rv = $cb->configure_object->save();

        print $rv
                ? loc("Configuration successfully saved\n")
                : loc("Failed to save configuration\n" );
        return $rv;

    } elsif ( $type eq 'edit' ) {

        my $editor  = $conf->get_program('editor')
                        or( print(loc("No editor specified")), return );

        my $env     = ENV_CPANPLUS_CONFIG;
        my $where   = $ENV{$env} || $INC{'CPANPLUS/Config.pm'};

        system("$editor $where");

        ### now reload it
        ### disable warnings for this
        {   local $^W;
            delete $INC{'CPANPLUS/Config.pm'};
            $conf->_load_cpanplus_config;
        }

        ### and use the new config ###
        $conf->conf( CPANPLUS::Config->new() );

        return 1;

    } else {

        if ( $type eq 'program' or $type eq 'conf' ) {

            unless( $key ) {
                my @list =  grep { $_ ne 'hosts' }
                            $conf->options( type => $type );

                my $method = 'get_' . $type;

                local $Data::Dumper::Indent = 0;
                for my $name ( @list ) {
                    my $val = $conf->$method($name);
                    ($val)  = ref($val)
                                ? (Data::Dumper::Dumper($val) =~ /= (.*);$/)
                                : "'$val'";
                    printf  "    %-25s %s\n", $name, $val;
                }

            } elsif ( $key eq 'hosts' ) {
                print loc(  "Setting hosts is not trivial.\n" .
                            "It is suggested you use '%1' and edit the " .
                            "configuration file manually", 's edit');
            } else {
                my $method = 'set_' . $type;
                $conf->$method( $key => defined $value ? $value : '' )
                    and print loc("Key '%1' was set to '%2'", $key,
                                  defined $value ? $value : 'EMPTY STRING');
            }

        } else {
            print loc("Unknown type '%1'",$type || 'EMPTY' );
            print $/;
            print loc("Try one of the following:");
            print $/, join $/, map { "\t'$_'" } sort @types;
        }
    }
    print "\n";
    return 1;
}

sub _uptodate {
    my $self = shift;
    my %hash = @_;
    my $cb   = $self->backend;
    my $conf = $cb->configure_object;

    my $opts; my $mods;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            options => { default => { }, store => \$opts },
            modules => { required => 1,  store => \$mods },
        };

        check( $tmpl, \%hash ) or return;
    }

    ### long listing? short is default ###
    my $long = $opts->{'long'} ? 1 : 0;

    my @list = scalar @$mods ? @$mods : @{$cb->_all_installed};

    my @rv; my %seen;
    for my $mod (@list) {
        ### skip this mod if it's up to date ###
        next if $mod->is_uptodate;
        ### skip this mod if it's core ###
        next if $mod->package_is_perl_core;

        if( $long or !$seen{$mod->package}++ ) {
            push @rv, $mod;
        }
    }

    @rv = sort { $a->module cmp $b->module } @rv;

    $self->cache([undef,@rv]);

    $self->_pager_open if scalar @rv >= $self->_term_rowcount;

    my $format = "%5s %10s %10s %-40s %-10s\n";

    my $i = 1;
    for my $mod ( @rv ) {
        printf $format,
                $i,
                $self->_format_version( $mod->installed_version ),
                $self->_format_version( $mod->version ),
                $mod->module,
                $mod->author->cpanid();
        $i++;
    }
    $self->_pager_close;

    return 1;
}

sub _autobundle {
    my $self = shift;
    my %hash = @_;
    my $cb   = $self->backend;
    my $conf = $cb->configure_object;

    my $opts; my $input;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            options => { default => { }, store => \$opts },
            input   => { default => '',  store => \$input },
        };

         check( $tmpl, \%hash ) or return;
    }

    $opts->{'path'} = $input if $input;

    my $where = $cb->autobundle( %$opts );

    print $where
            ? loc("Wrote autobundle to '%1'", $where)
            : loc("Could not create autobundle" );
    print "\n";

    return $where ? 1 : 0;
}

sub _uninstall {
    my $self = shift;
    my %hash = @_;
    my $cb   = $self->backend;
    my $term = $self->term;
    my $conf = $cb->configure_object;

    my $opts; my $mods;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            options => { default => { }, store => \$opts },
            modules => { default => [],  store => \$mods },
        };

         check( $tmpl, \%hash ) or return;
    }

    my $force = $opts->{'force'} || $conf->get_conf('force');

    unless( $force ) {
        my $list = join "\n", map { '    ' . $_->module } @$mods;

        print loc("
This will uninstall the following modules:
%1

Note that if you installed them via a package manager, you probably
should use the same package manager to uninstall them

", $list);

        return unless $term->ask_yn(
                        prompt  => loc("Are you sure you want to continue?"),
                        default => 'n',
                    );
    }

    ### first loop over all the modules to uninstall them ###
    for my $mod (@$mods) {
        print loc("Uninstalling '%1'", $mod->module), "\n";

        $mod->uninstall( %$opts );
    }

    my $flag;
    ### then report whether all this went ok or not ###
    for my $mod (@$mods) {
        if( $mod->status->uninstall ) {
            print loc("Module '%1' %tense(uninstall,past) successfully\n",
                       $mod->module )
        } else {
            $flag++;
            print loc("Error %tense(uninstall,present) '%1'\n", $mod->module);
        }
    }

    if( !$flag ) {
        print loc("All modules %tense(uninstall,past) successfully"), "\n";
    } else {
        print loc("Problem %tense(uninstalling,present) one or more modules" ),
                    "\n";
        print loc("*** You can view the complete error buffer by pressing '%1'".
                    "***\n", 'p') unless $conf->get_conf('verbose');
    }
    print "\n";

    return !$flag;
}

sub _reports {
   my $self = shift;
    my %hash = @_;
    my $cb   = $self->backend;
    my $term = $self->term;
    my $conf = $cb->configure_object;

    my $opts; my $mods;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            options => { default => { }, store => \$opts },
            modules => { default => '',  store => \$mods },
        };

         check( $tmpl, \%hash ) or return;
    }

    ### XXX might need to be conditional ###
    $self->_pager_open;

    for my $mod (@$mods) {
        my @list = $mod->fetch_report( %$opts )
                    or( print(loc("No reports available for this distribution.")),
                        next
                    );

        @list = reverse
                map  { $_->[0] }
                sort { $a->[1] cmp $b->[1] }
                map  { [$_, $_->{'dist'}.':'.$_->{'platform'}] } @list;



        ### XXX this may need to be sorted better somehow ###
        my $url;
        my $format = "%8s %s %s\n";

        my %seen;
        for my $href (@list ) {
            print "[" . $mod->author->cpanid .'/'. $href->{'dist'} . "]\n"
                unless $seen{ $href->{'dist'} }++;

            printf $format, $href->{'grade'}, $href->{'platform'},
                            ($href->{'details'} ? '(*)' : '');

            $url ||= $href->{'details'};
        }

        print "\n==> $url\n" if $url;
        print "\n";
    }
    $self->_pager_close;

    return 1;
}

sub _meta {
    my $self = shift;
    my %hash = @_;
    my $cb   = $self->backend;
    my $term = $self->term;
    my $conf = $cb->configure_object;

    my $opts; my $input;
    {   local $Params::Check::ALLOW_UNKNOWN = 1;

        my $tmpl = {
            options => { default => { }, store => \$opts },
            input   => { default => '',  store => \$input },
        };

         check( $tmpl, \%hash ) or return;
    }

    my @parts   = split /\s+/, $input;
    my $cmd     = lc(shift @parts);

    if( $cmd eq 'connect' ) {
        my $host = shift @parts || 'localhost';
        my $port = shift @parts || $conf->_get_daemon('port');

        load IO::Socket;

        my $remote = IO::Socket::INET->new(
                            Proto       => "tcp",
                            PeerAddr    => $host,
                            PeerPort    => $port,
                        ) or (
                            error( loc( "Cannot connect to port '%1' ".
                                        "on host '%2'", $port, $host ) ),
                            return
                        );
        my $user; my $pass;
        {   local $Params::Check::ALLOW_UNKNOWN = 1;

            my $tmpl = {
                user => { default => $conf->_get_daemon('username'),
                            store => \$user },
                pass => { default => $conf->_get_daemon('password'),
                            store => \$pass },
            };

             check( $tmpl, $opts ) or return;
        }

        my $con = {
            connection  => $remote,
            username    => $user,
            password    => $pass,
        };

        ### store the connection
        $self->remote( $con );

        my($status,$buffer) = $self->__send_remote_command("VERSION=$VERSION");

        if( $status ) {
            print "\n$buffer\n\n";

            print loc(  "Successfully connected to '%1' on port '%2'",
                        $host, $port );
            print "\n\n";
            print loc(  "Note that no output will appear until a command ".
                        "has completed\n-- this may take a while" );
            print "\n\n";

            $self->prompt( $Brand .'@'. $host .'> ' );

        } else {
            print "\n$buffer\n\n";

            print loc(  "Failed to connect to '%1' on port '%2'",
                        $host, $port );
            print "\n\n";

            $self->remote( undef );
        }


    } elsif ( $cmd eq 'disconnect' ) {
        print "\n", ($self->remote
                        ? loc( "Disconnecting from remote host" )
                        : loc( "Not connected to remote host" )
                ), "\n\n";

        $self->remote( undef );
        $self->prompt( $Prompt );

    } elsif ( $cmd eq 'source' ) {
        while( my $file = shift @parts ) {
            my $fh = FileHandle->new("$file")
                        or( error(loc("Could not open file '%1': %2",
                            $file, $!)),
                            return
                        );
            while( my $line = <$fh> ) {
                chomp $line;
                return 1 if $self->dispatch_on_input( input => $line );
            }
        }
    } else {
        error( loc( "Unknown command '%1'", $cmd ) );
        return;
    }
    return 1;
}

### send a command to a remote host, retrieve the answer;
sub __send_remote_command {
    my $self    = shift;
    my $cmd     = shift;
    my $remote  = $self->remote or return;
    my $user    = $remote->{'username'};
    my $pass    = $remote->{'password'};
    my $conn    = $remote->{'connection'};
    my $end     = "\015\012";
    my $answer;

    my $send = join "\0", $user, $pass, $cmd;

    print $conn $send . $end;

    ### XXX why doesn't something like this just work?
    #1 while recv($conn, $answer, 1024, 0);
    while(1) {
        my $buff;
        $conn->recv( $buff, 1024, 0 );
        $answer .= $buff;
        last if $buff =~ /$end$/;
    }

    my($status,$buffer) = split "\0", $answer;

    return ($status, $buffer);
}


sub _read_configuration_from_rc {
    my $rc_file = shift;

    my $href;
    if( can_load( modules => { 'Config::Auto' => '0.0' } ) ) {
        $Config::Auto::DisablePerl = 1;

        eval { $href = Config::Auto::parse( $rc_file, format => 'space' ) };

        print loc(  "Unable to read in config file '%1': %2",
                    $rc_file, $@ ) if $@;
    }

    return $href || {};
}

1;

__END__

=pod

=head1 AUTHOR

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001, 2002, 2003, 2004, Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=head1 SEE ALSO

L<CPANPLUS::Shell::Classic>, L<CPANPLUS::Shell>, L<cpanp>

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:

__END__

TODO:
    e   => "_expand_inc", # scratch it, imho -- not used enough

### free letters: g j k n y ###
