package CPANPLUS::Configure::Setup;

use strict;
use vars    qw(@ISA);
@ISA    =   qw[CPANPLUS::Internals::Utils];

use CPANPLUS::inc;
use CPANPLUS::Internals::Utils;
use CPANPLUS::Internals::Constants;
use CPANPLUS::Error                 qw[msg error];

use Config;
use Term::UI;
use File::Spec;
use FileHandle;
use Module::Load;
use Term::ReadLine;
use File::Basename;

use Cwd                         qw[cwd];
use IPC::Cmd                    qw[can_run];
use Params::Check               qw[check];
use Module::Load::Conditional   qw[check_install];
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';

$Params::Check::VERBOSE = 1;

#Can't ioctl TIOCGETP: Unknown error
#Consider installing Term::ReadKey from CPAN site nearby
#        at http://www.perl.com/CPAN
#Or use
#        perl -MCPAN -e shell
#to reach CPAN. Falling back to 'stty'.
#        If you do not want to see this warning, set PERL_READLINE_NOWARN
#in your environment.
#'stty' is not recognized as an internal or external command,
#operable program or batch file.
#Cannot call `stty': No such file or directory at C:/Perl/site/lib/Term/ReadLine/

### setting this var in the meantime to avoid this warning ###
$ENV{PERL_READLINE_NOWARN} = 1;

### silence Term::UI
$Term::UI::VERBOSE = 0;

### autogenerate accessors ###
for my $key (qw[configure_object term backend autosetup location
            custom_config skip_mirrors use_previous]
) {
    no strict 'refs';
    *{__PACKAGE__."::$key"} = sub {
        my $self = shift;
        $self->{$key} = $_[0] if @_;
        return $self->{$key};
    }
}

sub new {
    my $class = shift;
    my %hash  = @_;

    my ($cb,$term,$conf,$ar,$sm, $up);
    my $tmpl = {
        configure_object => { store  => \$conf   },
        term             => { store  => \$term   },
        backend          => { store  => \$cb     },
        autoreply        => { store  => \$ar,    default => 0, },
        skip_mirrors     => { store  => \$sm,    default => 0, },
        use_previous     => { store  => \$up,    default => 1, },
    };

    my $args = check( $tmpl, \%hash ) or return;


    ### otherwise there's a circular use ###
    load CPANPLUS::Configure;
    load CPANPLUS::Backend;

    $conf   ||= CPANPLUS::Configure->new();
    $cb     ||= CPANPLUS::Backend->new( $conf );
    $term   ||= Term::ReadLine->new();

    my $setup = {
        backend             => $cb,
        configure_object    => $conf,
        term                => $term,
        autoreply           => $ar,
        skip_mirrors        => $sm,
        use_previous        => $up,
    };

    ### enable autoreply if that was passed ###
    $Term::UI::AUTOREPLY = $ar;

    return bless $setup, $class;
}

sub init {
    my $self = shift;
    my $conf = $self->configure_object;

    my $loc = $self->_save_where or return;
    $self->location($loc);

    my $manual = $self->_manual;

    $Term::UI::AUTOREPLY = 1 if $manual;

    $self->_setup_base            or return;
    $self->_setup_ftp             or return;
    $self->_setup_program         or return;
    $self->_setup_conf            or return;
    ($self->_setup_hosts          or return)
            unless $self->skip_mirrors;
    $conf->save($self->location)  or return;
    $self->_edit                  or return;

    $self->_issue_non_default_config_warning($self->location)
        if $self->custom_config;

    return 1;
}

### looking in the existing config object to get the proper defaults ###
sub _get {
    my $self    = shift;
    my $conf    = $self->configure_object;
    my $key     = shift;
    my $default = shift;
    my @options = qw/n y a b/;

    return $default unless $self->use_previous;

    ### maybe this is a new key the old conf doesn't have yet
    ### don't error, just add the key and return the default
    unless( grep { $key eq $_ } $conf->options(type => 'conf') ) {
        $conf->add_conf( $key => $default );
        return $options[$default];
    }

    my $value   = $conf->get_conf($key);
    return defined  $value
                        ? $value =~ /^\d+$/
                            ? ($options[$value])
                            : $value
                        : $default;
}

######################
###
### Config location
###
######################

### offer a few locations where to save the config ###
sub _save_where {
    my $self = shift;
    my $term = $self->term;
    my $conf = $self->configure_object;

    ### default place, installed along with the rest of cpanplus
    my $default_unix = $INC{'CPANPLUS/Configure.pm'};
    $default_unix    =~ s/ure(\.pm)$/$1/i;

    ### it might be a non-unixy OS that wants a non-unixy path
    my $default = File::Spec->catfile( split('/',$default_unix) );

    ### homedir ###
    my $home = File::Spec->catfile( $self->_home_dir, DOT_CPANPLUS, 'config');

   print loc( q[
Where would you like to save the CPANPLUS Configuration file?

If you wish to use a custom configuration file, or do not have administrator
privileges, you probably can't or don't want to write to the systemwide perl
installation directory. In this case, you must provide an alternate location
(like your home directory) where you do have permissions.

You can override the system wide CPANPLUS Configuration file by setting
   $ENV{%1}
to the path of your personal configuration file.

Note that if you choose to use a custom configuration file you MUST set the
environment variables BEFORE running 'make', or CPANPLUS will be unable to find
your custom location and most likely prompt you for setup again.

If you save your config to your CPANPLUS build directory, it will be installed
along with the rest of CPANPLUS (illustrated by option 1).

If you are unsure what to answer here, just hit ENTER and CPANPLUS will try to
put your Configuration file in the default location.

], ENV_CPANPLUS_CONFIG);

    ### maybe the config we're reading from is somewhere altogether
    ### different. let's check for that.
    my $other   = 'Somewhere else';
    my $choices;
    if( $INC{'CPANPLUS/Config.pm'} and
        $INC{'CPANPLUS/Config.pm'} ne $default_unix
    ) {
        $choices = [$default, $INC{'CPANPLUS/Config.pm'}, $other];

    ### no need to worry, just go with the normal settings ###
    } else {
        $choices = [$default, $other];
    }

    my $loc     = $term->get_reply(
                    prompt  => loc("Location of the Configuration file"),
                    default => $default,
                    choices => $choices,
              );


    $self->custom_config(1) unless $loc eq $default;

    ### custom location ###
    if( $loc eq $other ) {
        CONFIG_FILE: {
            print loc(q[
Where would you like to save the config instead?

A suggestion might be your homedirectory
    %1

or to use the default location anyway
    %2

Note that you will have to set the environment variable
    $ENV{%3}
to point to the chosen location, so it can be found again.

    ].$/, $home, $default, ENV_CPANPLUS_CONFIG );

            $loc = $term->get_reply(
                        prompt  => loc('Configuration file name'),
                        default => $home,
                    );

            if( -e $loc and -w _ ) {
                last CONFIG_FILE if $term->ask_yn(
                                prompt  => loc("I see you already have this file. It is writable. Shall I overwrite it?"),
                                default => 'n',
                            );
            } else {
                my $dir = dirname($loc);
                last CONFIG_FILE if -w $dir;
                $self->_mkdir( dir => $dir )
                    and chmod( 0755, $dir )
                    and last CONFIG_FILE;
            }

            print loc( "I cannot write to %1, I don't have permission.", $loc), "\n";
            redo CONFIG_FILE;
        }
    }

    print "\n", loc("OK, I will save your configuration file to:"),
                "\n\t$loc\n\n";

    unless ($conf->can_save($loc) ) {
        print loc("*** Error: CPANPLUS %1 was not configured properly, and we cannot write to\n    %2",
                    $CPANPLUS::Internals::VERSION, $loc), "\n",
              loc("*** Please check its permission, or contact your administrator."), "\n";
        return;
    }

    $self->_issue_non_default_config_warning($loc) if $self->custom_config;

    return $loc;
}

sub _home_dir {
    return  exists $ENV{APPDATA}        ? $ENV{APPDATA}     :
            exists $ENV{HOME}           ? $ENV{HOME}        :
            exists $ENV{USERPROFILE}    ? $ENV{USERPROFILE} :
            exists $ENV{WINDIR}         ? $ENV{WINDIR}      :  cwd();
}

sub _issue_non_default_config_warning {
    my $self    = shift;
    my $where   = shift;
    my $env     = ENV_CPANPLUS_CONFIG;

    if( not defined $ENV{$env} ) {

        print loc( qq[
### IMPORTANT #####################################################

Since you chose a custom config file location, do not forget to set
the environment variable "%1" to
    "%2"
before running '%3' or your config will not be detected!

###################################################################

        ], ENV_CPANPLUS_CONFIG, $where, 'make');

        sleep 3;

    } elsif ( $ENV{$env} ne $where ) {


        print loc( qq[
### IMPORTANT #####################################################

Since you chose a custom config file location at
    "%1"
your environment variable "%2" should be set to
the same location, but it is currently set to
    "%3"

This means CPANPLUS will use your *old* configuration!

###################################################################
        ], $where, $env, $ENV{$env} );

        sleep 3;
    }
}

####################################
###
### Banner + Auto/Manual setup
###
####################################

sub _manual {
    my $self = shift;
    my $term = $self->term;

    print loc(q[

CPAN is the world-wide archive of perl resources. It consists of about
100 sites that all replicate the same contents all around the globe.
Many countries have at least one CPAN site already. The resources found
on CPAN are easily accessible with CPANPLUS modules. If you want to use
CPANPLUS, you have to configure it properly.

]);

    unless( $self->autosetup ) {
        print loc(q[
Although we recommend an interactive configuration session, you can
also enter 'n' here to use default values for all questions.

]);
        my $ok = $term->ask_yn(
                    prompt  => loc("Are you ready for manual configuration?"),
                    default => 'y',
                );

        $self->autosetup(!$ok);
    }

    return $self->autosetup;
}

#######################################
###
### Setup home dir and rules
###
#######################################

sub _setup_base {
    my $self = shift;
    my $term = $self->term;
    my $conf = $self->configure_object;

    my $home = File::Spec->catdir( $self->_home_dir, DOT_CPANPLUS );

    my $base = $conf->get_conf('base');

    print loc("
The CPAN++ module needs a directory of its own to cache important index
files and maybe keep a temporary mirror of CPAN files.  This may be a
site-wide directory or a personal directory.
");

    my $where;
    ASK_HOME_DIR: {
        my $other = loc('Somewhere else');
        if( $base and ($base ne $home) ) {
            print "\n", loc("You have several choices: "), "\n";

            $where = $term->get_reply(
                        prompt  => loc('Please pick one'),
                        choices => [$home, $base, $other],
                        default => $home,
                    );
        } else {
            $where = $base;
        }

        if( $where and -d $where ) {
            print   "\n", loc("I see you already have a directory:"),
                    "\n\n    $where\n\n";

            my $yn = $term->ask_yn(
                            prompt  => loc('Should I use it?'),
                            default => 'y',
                        );
            $where = '' unless $yn;
        }

        if( $where and ($where ne $other) and not -d $where ) {
            if (!$self->_mkdir( dir => $where ) ) {
                print   "\n", loc("Unable to create directory '%1'", $where);
                redo ASK_HOME_DIR;
            }

        } elsif( not $where or ($where eq $other) ) {
            print   "\n",
                    loc("First of all, I'd like to create this directory."),
                    "\n\n";

            NEW_HOME: {
                $where = $term->get_reply(
                                prompt  => loc('Where shall I create it?'),
                                default => $home,
                            );

                my $again;
                if( -d $where and not -w _ ) {
                    print "\n", loc("I can't seem to write in this directory");
                    $again++;
                } elsif (!$self->_mkdir( dir => $where ) ) {
                    print "\n", loc("Unable to create directory '%1'", $where);
                    $again++;
                }

                if( $again ) {
                    print "\n", loc('Please select another directory'), "\n\n";
                    redo NEW_HOME;
                }
            }
        }
    }

    ### this actually changes path seperators to unixy stuff on win32.
    ### and i don't see a reason not to use File::Spec, so switch here...
    #$where = Cwd::abs_path($where);
    $where = File::Spec->rel2abs($where);

    $conf->set_conf( base => $where );

    ### set default values to _build for upgrading to 0.040+
    {
        my $map = {
            distdir             => 'dist',
            autobundle          => 'autobundle',
            autobundle_prefix   => 'Snapshot',
        };

        while( my($key,$val) = each %$map ) {
            $conf->_set_build( $key => $val )
                    unless $conf->_get_build( $key );
        }
    }

    ### create subdirectories ###
    my @dirs =
        File::Spec->catdir( $where, $self->_perl_version(perl => $^X),
                            $conf->_get_build('moddir') ),
        map {
            File::Spec->catdir( $where, $conf->_get_build($_) )
        } qw[autdir distdir];

    for my $dir ( @dirs ) {
        unless( $self->_mkdir( dir => $dir ) ) {
            warn loc("I wasn't able to create '%1'", $dir), "\n";
        }
    }

    ### clear away old storable images before 0.031
    for my $src (qw[dslip mailrc packages]) {
        unlink File::Spec->catfile( $where, $src );

    }

    print " \n", loc("Your CPAN++ build and cache directory has been set to:"),
            "\n    $where\n";

    return 1;
}


#######################################
###
### Passive FTP? Where to send SPAM?
###
#######################################

sub _setup_ftp {
    my $self = shift;
    my $term = $self->term;
    my $conf = $self->configure_object;

    #########################
    ## are you a pacifist? ##
    #########################

    print loc("
If you are connecting through a firewall or proxy that doesn't handle
FTP all that well you can use passive FTP.

");

    my $yn = $term->ask_yn(
                prompt  => loc("Use passive FTP?"),
                default => $self->_get(passive => 'y'),
            );

    $conf->set_conf(passive => $yn);

    ### set the ENV var as well, else it won't get set till AFTER
    ### the configuration is saved. but we fetch files BEFORE that.
    $ENV{FTP_PASSIVE} = $yn;

    print $yn
            ? loc("I will use passive FTP.")
            : loc("I won't use passive FTP.");
    print "\n\n";

    #############################
    ## should fetches timeout? ##
    #############################

    print loc("
CPANPLUS can specify a network timeout for downloads (in whole seconds).
If none is desired (or to skip this question), enter '0'.

");

    my $timeout = 0 + $term->get_reply(
                prompt  => loc("Network timeout for downloads"),
                default => $conf->get_conf('timeout') || 0,
		### whole numbers only
		allow	=> qr/(?!\D)/,
            );

    $conf->set_conf(timeout => $timeout);

    print $timeout
            ? loc("The network timeout for downloads is %1 seconds.", $timeout)
            : loc("The network timeout for downloads is not set.");
    print "\n\n";

    ############################
    ## where can I reach you? ##
    ############################

    print loc("
What email address should we send as our anonymous password when
fetching modules from CPAN servers?  Some servers will NOT allow you to
connect without a valid email address, or at least something that looks
like one.
Also, if you choose to report test results at some point, a valid email
is required for the 'from' field, so choose wisely.

");

    my $other = 'Something else';
    my @choices = (DEFAULT_EMAIL, $Config{cf_email}, $other);
    my $current = $self->_get(email => DEFAULT_EMAIL);
    unless (grep { $_ eq $current } @choices) {
	unshift @choices, $current;
    }
    my $email = $term->get_reply(
                    prompt  => loc('Which email address shall I use?'),
                    default => $choices[0],
                    choices => \@choices,
                );

    if( $email eq $other ) {
	print "\n";
        EMAIL: {
            $email = $term->get_reply(
                        prompt  => loc('Email address:'),
                    );
            unless( $self->_valid_email($email) ) {
                print loc("You did not enter a valid email address, please try again!"), "\n"
                        if length $email;

                redo EMAIL;
            }
        }
    }

    print "\n", loc("Your 'email' is now:"), "\n    $email\n\n";

    $conf->set_conf(email => $email);

    return 1;
}

{
    my $RFC822PAT; # RFC pattern to match for valid email address

    sub _valid_email {
        my $self = shift;
        if (!$RFC822PAT) {
            my $esc        = '\\\\'; my $Period      = '\.'; my $space      = '\040';
            my $tab         = '\t';  my $OpenBR     = '\[';  my $CloseBR    = '\]';
            my $OpenParen  = '\(';   my $CloseParen  = '\)'; my $NonASCII   = '\x80-\xff';
            my $ctrl        = '\000-\037';                   my $CRlist     = '\012\015';

            my $qtext = qq/[^$esc$NonASCII$CRlist\"]/;
            my $dtext = qq/[^$esc$NonASCII$CRlist$OpenBR$CloseBR]/;
            my $quoted_pair = qq< $esc [^$NonASCII] >; # an escaped character
            my $ctext   = qq< [^$esc$NonASCII$CRlist()] >;
            my $Cnested = qq< $OpenParen $ctext* (?: $quoted_pair $ctext* )* $CloseParen >;
            my $comment = qq< $OpenParen $ctext* (?: (?: $quoted_pair | $Cnested ) $ctext* )* $CloseParen >;
            my $X = qq< [$space$tab]* (?: $comment [$space$tab]* )* >;
            my $atom_char  = qq/[^($space)<>\@,;:\".$esc$OpenBR$CloseBR$ctrl$NonASCII]/;
            my $atom = qq< $atom_char+ (?!$atom_char) >;
            my $quoted_str = qq< \" $qtext * (?: $quoted_pair $qtext * )* \" >;
            my $word = qq< (?: $atom | $quoted_str ) >;
            my $domain_ref  = $atom;
            my $domain_lit  = qq< $OpenBR (?: $dtext | $quoted_pair )* $CloseBR >;
            my $sub_domain  = qq< (?: $domain_ref | $domain_lit) $X >;
            my $domain = qq< $sub_domain (?: $Period $X $sub_domain)* >;
            my $route = qq< \@ $X $domain (?: , $X \@ $X $domain )* : $X >;
            my $local_part = qq< $word $X (?: $Period $X $word $X )* >;
            my $addr_spec  = qq< $local_part \@ $X $domain >;
            my $route_addr = qq[ < $X (?: $route )?  $addr_spec > ];
            my $phrase_ctrl = '\000-\010\012-\037'; # like ctrl, but without tab
            my $phrase_char = qq/[^()<>\@,;:\".$esc$OpenBR$CloseBR$NonASCII$phrase_ctrl]/;
            my $phrase = qq< $word $phrase_char * (?: (?: $comment | $quoted_str ) $phrase_char * )* >;
            $RFC822PAT = qq< $X (?: $addr_spec | $phrase $route_addr) >;
        }

        return scalar ($_[0] =~ /$RFC822PAT/ox);
    }
}

####################################
###
### commandline programs
###
####################################

sub _setup_program {
    my $self = shift;
    my $term = $self->term;
    my $conf = $self->configure_object;

    ### leaving out 'shell' 'pager' and 'sudo'
    my %map;
    $map{'make'} = $conf->get_program('make') ||
		   can_run($Config{'make'}) ||
		   can_run('make');

    ### some additions ###
    $map{'pager'} = $conf->get_program('pager') ||
                    $ENV{'PAGER'}               ||
                    can_run('less')             ||
                    can_run('more');

    ### remove whitespace from windows paths if possible
    ### see below for explenation
    if( $^O eq 'MSWin32' ) {
        for my $pgm (qw[make pager]) {
            $map{$pgm} = Win32::GetShortPathName( $map{$pgm} )
                            if $map{$pgm} =~ /\s+/;
        }
    }

    print loc(q[
Note that the paths you provide should not contain spaces, which is
needed to make a distinction between program name and options to that
program. For Win32 machines, you can use the short name for a path,
like '%1'.

],      'c:\Progra~1\prog.exe');

    if( $^O eq 'MSWin32' ) {
        print loc(q[
If you do not have '%1' yet, you can get it from:
    %2

],      'nmake.exe', 'ftp://ftp.microsoft.com/Softlib/MSLFILES/nmake15.exe');
    }

    while( my($pgm,$default) = each %map ) {
        PROGRAM: {
            my $where = $term->get_reply(
                            prompt  => loc("Where can I find your '%1' program?", $pgm),
                            default => $default,
                        );

            my $full;

            ### empty line -> no answer ###
            unless ( length $where ) {
                if( $pgm eq 'make' ) {
                    warn loc("Without your '%1' executable I can't function!", $pgm), "\n";
                    redo PROGRAM;
                }

            } else {
                my ($prog, @args) = split(/ /, $where);
                ### make sure it's the full path ###
                $full = can_run($prog);


                unless( $full ) {
                    warn loc("No such binary '%1'\n", $prog);

                    $term->ask_yn(
                            prompt  => loc("Are you use you want to use '%1'", $prog),
                            default => 'y',
                    ) or redo PROGRAM;
                    $full = $prog;
                }

                $conf->set_program( $pgm => join(' ', $full, @args) );
            }

            print   "\n", loc("Your '%1' program has been set to:", $pgm),
                    "\n    ", (length $full ? $full : loc('*nothing entered*')),
                    "\n\n";
        }
    }

    #############################################
    ## what commandprompt/editor should we use ##
    #############################################

    {
        my $map = {
            shell   => $conf->get_program('shell') ||
                        ($^O eq 'MSWin32' ? $ENV{COMSPEC} : $ENV{SHELL}),
            editor  => $conf->get_program('editor') ||
                        $ENV{'EDITOR'}  || $ENV{'VISUAL'} ||
                        can_run('vi')   || can_run('pico')
        };

        while( my($pgm, $default) = each %$map ) {
            PROGRAM: {
                my $where = $term->get_reply(
                                prompt  => loc("Your favorite command line %1?", $pgm),
                                default => $default,
                            );

                my $full = can_run($where);
                if( length $where and !$full ) {
                    warn loc("No such binary '%1'\n", $where);
                    $term->ask_yn(
                            prompt  => loc("Are you use you want to use '%1'?", $where),
                            default => 'y',
                    ) or redo PROGRAM;
                    $full = $where;
                }

                print   "\n", loc("Your '%1' program has been set to:", $pgm),
                        "\n    ", (length $full ? $full : loc('*nothing entered*')),
                        "\n\n";

                $conf->set_program($pgm => $full);
            }
        }
    }

    ##############################
    ## does this box have sudo? ##
    ##############################

    {   my $pgm     = 'sudo';
        my $sudo    = $conf->get_program($pgm) || can_run($pgm);

        ### default to 'yes' if you're not root ###
        if($sudo) {
            my $default = $>
                            ? (-w $Config{'installsitelib'} ? 'n' : 'y')
                            : 'y';

            my $yn = $term->ask_yn(
                        prompt  => loc("I found %1 in your path, would you like to use it for '%2'?", $pgm, 'make install' ),
                        default => $default,
                    );
           $sudo = '' unless $yn;

           print $yn
                ? loc("Ok, I will use '%1' for '%2'", $pgm, 'make install')
                : loc("Ok, I won't use '%1' for '%2'", $pgm, 'make install');
           print "\n\n";

           $conf->set_program( $pgm => $sudo );
        }
    }

    return 1;
}

sub _setup_conf {
    my $self = shift;
    my $term = $self->term;
    my $conf = $self->configure_object;

    my $none = 'None';

    {
        print loc("
CPANPLUS uses binary programs as well as Perl modules to accomplish
various tasks. Normally, CPANPLUS will prefer the use of Perl modules
over binary programs.

You can change this setting by making CPANPLUS prefer the use of
certain binary programs if they are available.

");

        my $type = 'prefer_bin';
        my $yn   = $term->ask_yn(
                        prompt  => loc("Should I prefer the use of binary programs?"),
                        default => $self->_get( $type => 'n' ),
                    );

        print $yn
                ? loc("Ok, I will prefer to use binary programs if possible.")
                : loc("Ok, I will prefer to use Perl modules if possible.");
        print "\n\n";


        $conf->set_conf( $type => $yn );
    }

    {
        print loc("
Makefile.PL is run by perl in a separate process, and accepts various
flags that controls the module's installation.  For instance, if you
would like to install modules to your private user directory, set
'makemakerflags' to:

LIB=~/perl/lib INSTALLMAN1DIR=~/perl/man/man1 INSTALLMAN3DIR=~/perl/man/man3

and be sure that you do NOT set UNINST=1 in 'makeflags' below.

Enter a name=value list separated by whitespace, but quote any embedded
spaces that you want to preserve.  (Enter a space to clear any existing
settings.)

If you don't understand this question, just press ENTER.

");

        my $type = 'makemakerflags';
        my $flags = $term->get_reply(
                            prompt  => 'Makefile.PL flags?',
                            default => $self->_get( $type => $none ),
                    );

        $flags = '' if $flags eq $none || $flags !~ /\S/;

        print   "\n", loc("Your '%1' have been set to:", 'Makefile.PL flags'),
                "\n    ", ( $flags ? $flags : loc('*nothing entered*')),
                "\n\n";

        $conf->set_conf( $type => $flags );
    }

    {
        print loc("
Like Makefile.PL, we run 'make' and 'make install' as separate processes.
If you have any parameters (e.g. '-j3' in dual processor systems) you want
to pass to the calls, please specify them here.

In particular, 'UNINST=1' is recommended for root users, unless you have
fine-tuned ideas of where modules should be installed in the \@INC path.

Enter a name=value list separated by whitespace, but quote any embedded
spaces that you want to preserve.  (Enter a space to clear any existing
settings.)

Again, if you don't understand this question, just press ENTER.

");
        my $type        = 'makeflags';
        my $flags   = $term->get_reply(
                                prompt  => 'make flags?',
                                default => $self->_get($type => $none),
                            );

        $flags = '' if $flags eq $none || $flags !~ /\S/;

        print   "\n", loc("Your '%1' have been set to:", $type),
                "\n    ", ( $flags ? $flags : loc('*nothing entered*')),
                "\n\n";

        $conf->set_conf( $type => $flags );
    }

    {
        print loc("
An alternative to ExtUtils::MakeMaker and Makefile.PL there's a module
called Module::Build which uses a Build.PL.

If you would like to specify any flags to pass when executing the
Build.PL (and Build) script, please enter them below.

For instance, if you would like to install modules to your private
user directory, you could enter:

    install_base=/my/private/path

Or to uninstall old copies of modules before updating, you might
want to enter:

    uninst=1

Again, if you don't understand this question, just press ENTER.

");

        my $type    = 'buildflags';
        my $flags   = $term->get_reply(
                                prompt  => 'Build.PL and Build flags?',
                                default => $self->_get($type => $none),
                            );

        $flags = '' if $flags eq $none || $flags !~ /\S/;

        print   "\n", loc("Your '%1' have been set to:",
                            'Build.PL and Build flags'),
                "\n    ", ( $flags ? $flags : loc('*nothing entered*')),
                "\n\n";

        $conf->set_conf( $type => $flags );
    }

    ### use EU::MM or module::build? ###
    {
        print loc("
Some modules provide both a Build.PL (Module::Build) and a Makefile.PL
(ExtUtils::MakeMaker).  By default, CPANPLUS prefers Build.PL when it
is available.

Although Module::Build is a pure perl solution, which means you will
not need a 'make' binary, it does have some limitations. The most
important is that CPANPLUS is unable to uninstall any modules installed
by Module::Build.

Again, if you don't understand this question, just press ENTER.

");
        my $type = 'prefer_makefile';
        my $yn = $term->ask_yn(
                    prompt  => loc("Prefer Makefile.PL over Build.PL?"),
                    default => $self->_get( $type => 1 ),
                 );

        $conf->set_conf( $type => $yn );
    }

    {
        print loc('
If you like, CPANPLUS can add extra directories to your @INC list during
startup. These will just be used by CPANPLUS and will not change your
external environment or perl interpreter.  Enter a space separated list of
pathnames to be added to your @INC, quoting any with embedded whitespace.
(To clear the current value enter a single space.)

');

        my $type    = 'lib';
        my $flags = $term->get_reply(
                            prompt  => loc('Additional @INC directories to add?'),
                            default => (join " ", @{$self->_get($type => [])} ),
                        );

        my $lib;
        unless( $flags =~ /\S/ ) {
            $lib = [];
        } else {
            (@$lib) = $flags =~  m/\s*("[^"]+"|'[^']+'|[^\s]+)/g;
        }

        print "\n", loc("Your additional libs are now:"), "\n";

        print scalar @$lib
                        ? map { "    $_\n" } @$lib
                        : "    ", loc("*nothing entered*"), "\n";
        print "\n\n";

        $conf->set_conf( $type => $lib );
    }

    {
        ############
        ## noisy? ##
        ############

        print loc("
In normal operation I can just give you basic information about what I
am doing, or I can be more verbose and give you every little detail.

");

        my $type = 'verbose';
        my $yn   = $term->ask_yn(
                            prompt  => loc("Should I be verbose?"),
                            default => $self->_get( $type => 'n' ),
                        );

        print "\n";
        print $yn
                ? loc("You asked for it!")
                : loc("I'll try to be quiet");
        print "\n\n";

        $conf->set_conf( $type => $yn );
    }

    {
        #######################
        ## flush you animal! ##
        #######################

        print loc("
In the interest of speed, we keep track of what modules were installed
successfully and which failed in the current session.  We can flush this
data automatically, or you can explicitly issue a 'flush' when you want
to purge it.

");
        my $type = 'flush';
        my $yn   = $term->ask_yn(
                            prompt  => loc("Flush automatically?"),
                            default => $self->_get( $type => 'y' ),
                        );

        print "\n";
        print $yn
                ? loc("I'll flush after every full module install.")
                : loc("I won't flush until you tell me to.");
        print "\n\n";

        $conf->set_conf( $type => $yn );
    }

    {
        #####################
        ## force installs? ##
        #####################

        print loc("
Usually, when a test fails, I won't install the module, but if you
prefer, I can force the install anyway.

");


        my $type = 'force';
        my $yn   = $term->ask_yn(
                        prompt  => loc("Force installs?"),
                        default => $self->_get( $type => 'n' ),
                    );

        print "\n";
        print $yn
                ? loc("I will force installs.")
                : loc("I won't force installs.");
        print "\n\n";

        $conf->set_conf( $type => $yn );
    }

    {
        ###################
        ## about prereqs ##
        ###################

        print loc("
Sometimes a module will require other modules to be installed before it
will work.  CPAN++ can attempt to install these for you automatically
if you like, or you can do the deed yourself.

If you would prefer that we NEVER try to install extra modules
automatically, select NO.  (Usually you will want this set to YES.)

If you would like to build modules to satisfy testing or prerequisites,
but not actually install them, select BUILD.

NOTE: This feature requires you to flush the 'lib' cache for longer
running programs (refer to the CPANPLUS::Backend documentations for
more details).

Otherwise, select ASK to have us ask your permission to install them.

");

        my $type = 'prereqs';
        my $map  = {
                    0   => 'No',
                    1   => 'Yes',
                    2   => 'Ask',
                    3   => 'Build',
                };

        my $default = defined $conf->get_conf($type)
                            ? $map->{ $conf->get_conf($type) }
                            : 'Ask';

        my $reply   = $term->get_reply(
                        prompt  => loc('Follow prerequisites?'),
                        default => $default,
                        choices => [@$map{sort keys %$map}],
                    );
        print "\n";

        while( my($key,$val) = each %$map ) {
            next unless $val eq $reply;

            $conf->set_conf( $type => $key );

            print   $reply eq 'No'      ? loc("I won't install prerequisites") :
                    $reply eq 'Yes'     ? loc("I will install prerequisites") :
                    $reply eq 'Ask'     ? loc("I will ask permission to install prerequisites") :
                    $reply eq 'Build'   ? loc("I will only build, but not install prerequisites") :
                                          loc("You shouldn't get here!");


            last;
        }

        print "\n\n";
    }

    {

        print loc("
Modules in the CPAN archives are protected with md5 checksums.

This requires the Perl module Digest::MD5 to be installed (which
CPANPLUS can do for you later);

");
        my $type    = 'md5';
        my $default = check_install( module => 'Digest::MD5' ) ? 'y' : 'n';

        my $yn = $term->ask_yn(
                    prompt  => loc("Shall I use the MD5 checksums?"),
                    default => $default,
                );

        print $yn
                ? loc("I will use the MD5 checksums if you have it")
                : loc("I won't use the MD5 checksums");

        $conf->set_conf( $type => $yn );

        print "\n\n";
    }

    {
        ###########################################
        ## sally sells seashells by the seashore ##
        ###########################################

        print loc("
By default CPAN++ uses its own shell when invoked.  If you would prefer
a different shell, such as one you have written or otherwise acquired,
please enter the full name for your shell module.

");
        my $type    = 'shell';
        my $other   = 'Other';
        my $default = $self->_get( $type => 'CPANPLUS::Shell::Default' );
        my @choices = (qw|  CPANPLUS::Shell::Default
                            CPANPLUS::Shell::Classic |, # currently unavail.
#                           CPANPLUS::Shell::Curses,
                            $other );

        unshift @choices, $default unless grep { $_ eq $default } @choices;

        my $reply   = $term->get_reply(
                        prompt  => loc('Which CPANPLUS "shell" do you want to use?'),
                        default => $default,
                        choices => \@choices,
                    );

        if( $reply eq $other ) {
            SHELL: {
                $reply = $term->get_reply(
                                prompt  => loc('Please enter the name of the shell you wish to use'),
                            );

                unless( check_install( module => $reply ) ) {
                    print "\n", loc("Could not find '$reply' in your path -- please try again"), "\n";
                    redo SHELL;
                }
            }
        }

        print "\n", loc("Your shell is now:   $reply"), "\n\n";

        $conf->set_conf( $type => $reply );
    }

    {
        ###################
        ## use storable? ##
        ###################

        print loc("
To speed up the start time of CPANPLUS, and maintain a cache over
multiple runs, we can use Storable to freeze some information.
Would you like to do this?

");
        my $type    = 'storable';
        my $default;
        $default      = ($conf->get_conf($type) ? 'y' : 'n') if length $conf->get_conf($type);
        $default    ||= check_install( modules => 'Storable' ) ? 'y' : 'n';
        my $yn      = $term->ask_yn(
                                prompt  => loc("Use Storable?"),
                                default => $default,
                            );
        print "\n";
        print $yn
                ? loc("I will use Storable if you have it")
                : loc("I will not use Storable");
        print "\n\n";

        $conf->set_conf( $type => $yn );
    }

    {
        ###################
        ## use cpantest? ##
        ###################

        print loc("
CPANPLUS has support for the Test::Reporter module, which can be utilized
to report success and failures of modules installed by CPANPLUS.  Would
you like to do this?  Note that you will still be prompted before
sending each report.

If you don't have all the required modules installed yet, you should
consider installing '%1'

This package bundles all the required modules to enable test reporting
and querying from CPANPLUS.
You can do so straight after this installation.

", 'Bundle::CPANPLUS::Test::Reporter');

        my $type = 'cpantest';
        my $yn   = $term->ask_yn(
                        prompt  => loc('Report test results?'),
                        default => $self->_get( $type => 'n' ),
                    );

        print "\n";
        print $yn
                ? loc("I will prompt you to report test results")
                : loc("I won't prompt you to report test results");
        print "\n\n";

        $conf->set_conf( $type => $yn );
    }

    {
        ###################################
        ## use cryptographic signatures? ##
        ###################################

        print loc("
The Module::Signature extension allows CPAN authors to sign their
distributions using PGP signatures.  Would you like to check for
module's cryptographic integrity before attempting to install them?
Note that this requires either the 'gpg' utility or Crypt::OpenPGP
to be installed.

");
        my $type = 'signature';

        my $default;
        $default      = ($conf->get_conf($type) ? 'y' : 'n') if length $conf->get_conf($type);
        $default    ||= can_run( 'gpg' ) || check_install( modules => 'Crypt::OpenPGP' )
                            ? 'y'
                            : 'n';

        my $yn = $term->ask_yn(
                            prompt  => loc('Shall I check module signatures?'),
                            default => $default,
                        );

        print "\n";
        print $yn
                ? loc("Ok, I will attempt to check module signatures.")
                : loc("Ok, I won't attempt to check module signatures.");
        print "\n\n";

        $conf->set_conf( $type => $yn );
    }

    return 1;
}

sub _setup_hosts {
    my $self = shift;
    my $term = $self->term;
    my $conf = $self->configure_object;


    if( scalar @{ $conf->get_conf('hosts') } ) {

        my $hosts;
        for my $href ( @{$conf->get_conf('hosts')} ) {
            $hosts .= "\t$href->{scheme}://$href->{host}$href->{path}\n";
        }

        print loc("
I see you already have some hosts selected:

$hosts

If you'd like to stick with your current settings, just select 'Yes'.
Otherwise, select 'No' and you can reconfigure your hosts

");
        my $yn = $term->ask_yn(
                        prompt  => loc("Would you like to keep your current hosts?"),
                        default => 'y',
                    );
        return 1 if $yn;
    }

    my @hosts;
    MAIN: {

        print loc("

Now we need to know where your favorite CPAN sites are located. Make a
list of a few sites (just in case the first on the array won't work).

If you are mirroring CPAN to your local workstation, specify a file:
URI by picking the CUSTOM option.

Otherwise, let us fetch the official CPAN mirror list and you can pick
the mirror that suits you best from a list by using the MIRROR option;
First, pick a nearby continent and country. Then, you will be presented
with a list of URLs of CPAN mirrors in the country you selected. Select
one or more of those URLs.

Note, the latter option requires a working net connection.

You can select VIEW to see your current selection and QUIT when you
are done.

");

        my $reply = $term->get_reply(
                        prompt  => loc('Please choose an option'),
                        choices => [qw|Mirror Custom View Quit|],
                        default => 'Mirror',
                    );
        print "\n\n";

        goto MIRROR if $reply eq 'Mirror';
        goto CUSTOM if $reply eq 'Custom';
        goto QUIT   if $reply eq 'Quit';

        $self->_view_hosts(@hosts) if $reply eq 'View';
        redo MAIN;
    }

    my $mirror_file;
    my $hosts;
    MIRROR: {
        $mirror_file    ||= $self->_get_mirrored_by               or return;
        $hosts          ||= $self->_parse_mirrored_by($mirror_file) or return;

        my ($continent, $country, $host) = $self->_guess_from_timezone( $hosts );

        CONTINENT: {
            my %seen;
            my @choices =   sort map {
                                $_->{'continent'}
                            } grep {
                                not $seen{$_->{'continent'}}++
                            } values %$hosts;
            push @choices,  qw[Custom Up Quit];

            my $reply   = $term->get_reply(
                                prompt  => loc('Pick a continent'),
                                default => $continent,
                                choices => \@choices,
                            );
            print "\n\n";

            goto MAIN   if $reply eq 'Up';
            goto CUSTOM if $reply eq 'Custom';
            goto QUIT   if $reply eq 'Quit';

            $continent = $reply;
        }

        COUNTRY: {
            my %seen;
            my @choices =   sort map {
                                $_->{'country'}
                            } grep {
                                not $seen{$_->{'country'}}++
                            } grep {
                                ($_->{'continent'} eq $continent)
                            } values %$hosts;
            push @choices,  qw[Custom Up Quit];

            my $reply   = $term->get_reply(
                                prompt  => loc('Pick a country'),
                                default => $country,
                                choices => \@choices,
                            );
            print "\n\n";

            goto CONTINENT  if $reply eq 'Up';
            goto CUSTOM     if $reply eq 'Custom';
            goto QUIT       if $reply eq 'Quit';

            $country = $reply;
        }

        HOST: {
            my @list =  grep {
                            $_->{'continent'}   eq $continent and
                            $_->{'country'}     eq $country
                        } values %$hosts;

            my %map; my $default;
            for my $href (@list) {
                for my $con ( @{$href->{'connections'}} ) {
                    next unless length $con->{'host'};

                    my $entry   = $con->{'scheme'} . '://' . $con->{'host'};
                    $default    = $entry if $con->{'host'} eq $host;

                    $map{$entry} = $con;
                }
            }

            CHOICE: {
                my @reply = $term->get_reply(
                                    prompt  => loc('Please pick a site: '),
                                    choices => [sort(keys %map), qw|Custom View Up Quit|],
                                    default => $default,
                                    multi   => 1,
                            );
                print "\n\n";

                goto COUNTRY    if grep { $_ eq 'Up' }      @reply;
                goto CUSTOM     if grep { $_ eq 'Custom' }  @reply;
                goto QUIT       if grep { $_ eq 'Quit' }    @reply;

                ### add the host, but only if it's not on the stack already ###
                unless(  grep { $_ eq 'View' } @reply ) {
                    for my $reply (@reply) {
                        if( grep { $_ eq $map{$reply} } @hosts ) {
                            print loc("Host '%1' already selected", $reply);
                            print "\n\n";
                        } else {
                            push @hosts, $map{$reply}
                        }
                    }
                }

                $self->_view_hosts(@hosts);

                goto QUIT if $self->autosetup;
                redo CHOICE;
            }
        }
    }

    CUSTOM: {
        print loc("

If there are any additional URLs you would like to use, please add them
now.  You may enter them separately or as a space delimited list.

We provide a default fall-back URL, but you are welcome to override it
with e.g. 'http://www.cpan.org/' if LWP, wget or curl is installed.

(Enter a single space when you are done, or to simply skip this step.)

Note that if you want to use a local depository, you will have to enter
as follows:

file://server/path/to/cpan

if the file is on a server on your local network or as:

file:///path/to/cpan

if the file is on your local disk. Note the three /// after the file: bit

");

        CHOICE: {
            my $reply = $term->get_reply(
                            prompt  => loc("Additionals host(s) to add: "),
                            default => '',
                        );

            last CHOICE unless $reply =~ /\S/;

            my $href = $self->_parse_host($reply);

            if( $href ) {
                push @hosts, $href
                    unless grep {
                        $href->{'scheme'}   eq $_->{'scheme'}   and
                        $href->{'host'}     eq $_->{'host'}     and
                        $href->{'path'}     eq $_->{'path'}
                    } @hosts;

                last CHOICE if $self->autosetup;
            } else {
                print loc("Invalid uri! Please try again!");
            }

            $self->_view_hosts(@hosts);

            redo CHOICE;
        }

        DONE: {

            print loc("
Where would you like to go now?

Please pick one of the following options or Quit when you are done

");
            my $answer = $term->get_reply(
                                    prompt  => loc("Where to now?"),
                                    default => 'Quit',
                                    choices => [qw|Mirror Custom View Quit|],
                                );

            if( $answer eq 'View' ) {
                $self->_view_hosts(@hosts);
                redo DONE;
            }

            goto MIRROR if $answer eq 'Mirror';
            goto CUSTOM if $answer eq 'Custom';
            goto QUIT   if $answer eq 'Quit';
        }
    }

    QUIT: {
        $conf->set_conf( hosts => \@hosts );

        print loc("
Your host configuration has been saved

");
    }

    return 1;
}

sub _view_hosts {
    my $self    = shift;
    my @hosts   = @_;

    print "\n\n";

    if( scalar @hosts ) {
        my $i = 1;
        for my $host (@hosts) {

            ### show full path on file uris, otherwise, just show host
            my $path = join '', (
                            $host->{'scheme'} eq 'file'
                                ? ( ($host->{'host'} || '[localhost]'),
                                    $host->{path} )
                                : $host->{'host'}
                        );

            printf "%-40s %30s\n",
                loc("Selected %1",$host->{'scheme'} . '://' . $path ),
                loc("%quant(%2,host) selected thus far.", $i);
            $i++;
        }
    } else {
        print loc("No hosts selected so far.");
    }

    print "\n\n";

    return 1;
}

sub _get_mirrored_by {
    my $self = shift;
    my $cpan = $self->backend;
    my $conf = $self->configure_object;

    print loc("
Now, we are going to fetch the mirror list for first-time configurations.
This may take a while...

");

    ### use the enew configuratoin ###
    $cpan->configure_object( $conf );

    load CPANPLUS::Module::Fake;
    load CPANPLUS::Module::Author::Fake;

    my $mb = CPANPLUS::Module::Fake->new(
                    module      => $conf->_get_source('hosts'),
                    path        => '',
                    package     => $conf->_get_source('hosts'),
                    author      => CPANPLUS::Module::Author::Fake->new(
                                        _id => $cpan->_id ),
                    _id         => $cpan->_id,
                );

    my $file = $cpan->_fetch(   fetchdir => $conf->get_conf('base'),
                                module   => $mb );

    return $file if $file;
    return;
}

sub _parse_mirrored_by {
    my $self = shift;
    my $file = shift;

    -s $file or return;

    my $fh = new FileHandle;
    $fh->open("$file")
        or (
            warn(loc('Could not open file "%1": %2', $file, $!)),
            return
        );

    ### slurp the file in ###
    { local $/; $file = <$fh> }

    ### remove comments ###
    $file =~ s/#.*$//gm;

    $fh->close;

    ### sample host entry ###
    #     ftp.sun.ac.za:
    #       frequency        = "daily"
    #       dst_ftp          = "ftp://ftp.sun.ac.za/CPAN/CPAN/"
    #       dst_location     = "Stellenbosch, South Africa, Africa (-26.1992 28.0564)"
    #       dst_organisation = "University of Stellenbosch"
    #       dst_timezone     = "+2"
    #       dst_contact      = "ftpadm@ftp.sun.ac.za"
    #       dst_src          = "ftp.funet.fi"
    #
    #     # dst_dst          = "ftp://ftp.sun.ac.za/CPAN/CPAN/"
    #     # dst_contact      = "mailto:ftpadm@ftp.sun.ac.za
    #     # dst_src          = "ftp.funet.fi"

    ### host name as key, rest of the entry as value ###
    my %hosts = $file =~ m/([a-zA-Z0-9\-\.]+):\s+((?:\w+\s+=\s+".*?"\s+)+)/gs;

    while (my($host,$data) = each %hosts) {

        my $href;
        map {
            s/^\s*//;
            my @a = split /\s*=\s*/;
            $a[1] =~ s/^"(.+?)"$/$1/g;
            $href->{ pop @a } = pop @a;
        } grep /\S/, split /\n/, $data;

        ($href->{city_area}, $href->{country}, $href->{continent},
            $href->{latitude}, $href->{longitude} ) =
            $href->{dst_location} =~
                m/
                    #Aizu-Wakamatsu, Tohoku-chiho, Fukushima
                    ^"?(
                         (?:[^,]+?)\s*         # city
                         (?:
                             (?:,\s*[^,]+?)\s* # optional area
                         )*?                   # some have multiple areas listed
                     )

                     #Japan
                     ,\s*([^,]+?)\s*           # country

                     #Asia
                     ,\s*([^,]+?)\s*           # continent

                     # (37.4333 139.9821)
                     \((\S+)\s+(\S+?)\)"?$       # (latitude longitude)
                 /sx;

        ### parse the different hosts, store them in config format ###
        my @list;

        for my $type (qw[dst_ftp dst_rsync dst_http]) {
	    my $path = $href->{$type};
	    next unless $path =~ /\w/;
	    if ($type eq 'dst_rsync' && $path !~ /^rsync:/) {
		$path =~ s{::}{/};
		$path = "rsync://$path/";
	    }
            my $parts = $self->_parse_host($path);
            push @list, $parts;
        }

        $href->{connections}    = \@list;
        $hosts{$host}           = $href;
    }

    return \%hosts;
}

sub _parse_host {
    my $self = shift;
    my $host = shift;

    my @parts = $host =~ m|^(\w*)://([^/]*)(/.*)$|s;

    my $href;
    for my $key (qw[scheme host path]) {
        $href->{$key} = shift @parts;
    }

    return if lc($href->{'scheme'}) ne 'file' and !$href->{'host'};
    return if !$href->{'path'};

    return $href;
}

## tries to figure out close hosts based on your timezone
##
## Currently can only report on unique items for each of zones, countries, and
## sites.  In the future this will be combined with something else (perhaps a
## ping?) to narrow down multiple choices.
##
## Tries to return the best zone, country, and site for your location.  Any non-
## unique items will be set to undef instead.
##
## (takes hashref, returns array)
##
sub _guess_from_timezone {
    my $self  = shift;
    my $hosts = shift;
    my (%zones, %countries, %sites);

    ### autrijus - build time zone table
    my %freq_weight = (
        'hourly'        => 2400,
        '4 times a day' =>  400,
        '4x daily'      =>  400,
        'daily'         =>  100,
        'twice daily'   =>   50,
        'weekly'        =>   15,
    );

    while (my ($site, $host) = each %{$hosts}) {
        my ($zone, $continent, $country, $frequency) =
            @{$host}{qw/dst_timezone continent country frequency/};


        # skip non-well-formed ones
        next unless $continent and $country and $zone =~ /^[-+]?\d+(?::30)?/;
        ### fix style
        chomp $zone;
        $zone =~ s/:30/.5/;
        $zone =~ s/^\+//;
        $zone =~ s/"//g;

        $zones{$zone}{$continent}++;
        $countries{$zone}{$continent}{$country}++;
        $sites{$zone}{$continent}{$country}{$site} = $freq_weight{$frequency};
    }

    use Time::Local;
    my $offset = ((timegm(localtime) - timegm(gmtime)) / 3600);

    local $_;

    ## pick the entry with most country/site/frequency, one level each;
    ## note it has to be sorted -- otherwise we're depending on the hash order.
    ## also, the list context assignment (pick first one) is deliberate.

    my ($continent) = map {
        (sort { ($_->{$b} <=> $_->{$a}) or $b cmp $a } keys(%{$_}))
    } $zones{$offset};

    my ($country) = map {
        (sort { ($_->{$b} <=> $_->{$a}) or $b cmp $a } keys(%{$_}))
    } $countries{$offset}{$continent};

    my ($site) = map {
        (sort { ($_->{$b} <=> $_->{$a}) or $b cmp $a } keys(%{$_}))
    } $sites{$offset}{$continent}{$country};

    return ($continent, $country, $site);
} # _guess_from_timezone

sub _edit {
    my $self    = shift;
    my $conf    = $self->configure_object;
    my $file    = shift || $self->location;
    my $editor  = shift || $conf->get_program('editor');
    my $term    = $self->term;

    unless( $editor ) {
        print loc("
I'm sorry, I can't find a suitable editor, so I can't offer you
post-configuration editing of the config file

");
        return 1;
    }

    print loc("
Your configuration has now been saved. Would you like to inspect the
resulting file and possibly make some manual changes?

This feature should only be used if you are an expert or you think
you made a typo you need to fix.

");

    my $yn = $term->ask_yn(
                    prompt  => loc("Would you like to edit the config file?"),
                    default => 'n'
                );

    return 1 unless $yn;

    return !system("$editor $file");
}

1;
