# $File: //depot/cpanplus/dist/lib/CPANPLUS/Configure/Setup.pm $
# $Revision: #20 $ $Change: 7777 $ $DateTime: 2003/08/29 12:53:19 $

##################################################
###        CPANPLUS/Configure/Setup.pm         ###
###     Initial configuration for CPAN++       ###
##################################################

package CPANPLUS::Configure::Setup;

use strict;
use vars qw($AutoSetup $SkipMirrors $CustomConfig $ConfigLocation);

require CPANPLUS::Backend;
use CPANPLUS::I18N;

use Config;
use Cwd qw(getcwd);
use ExtUtils::MakeMaker ();
use File::Path ();
use File::Spec;
use FileHandle ();

use Term::ReadLine;
use CPANPLUS::Tools::Term;

### EVIL WARNING - FIX THIS ASAP ###
### got it on win2k with AS perl 5.6.0

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

my $term;
my $backend;

## gather information needed to initialize CPANPLUS
##
## (takes conf => Configure object and term => Term object, returns no values)
##
sub init {
    my ($self, %args) = @_;

    my $conf    = $args{conf} || CPANPLUS::Configure->new;
    $term       = $args{term}       if exists $args{term};
    $backend    = $args{backend}    if exists $args{backend};


    my $loc;
    ### ask where the user wants to save the config.pm ###
    {
        ### in case we have a loaded, but b0rked version ###
        my $default = $INC{'CPANPLUS/Config.pm'};

        unless( defined $default ) {
            ### nasty hack =(( -kane ###
            my $pm = File::Spec::Unix->catfile(qw|CPANPLUS Configure Setup.pm|);
            $default = File::Spec->catfile( split '/', $INC{$pm} );
            $default =~ s/ure.Setup(\.pm)/$1/ig;
        }

        my $show_default = $default;
	### in build time, config will be installed into sitelib, so show that instead
	if ($0 =~ 'Makefile.PL') {
            $show_default = File::Spec->catfile($Config{sitelib}, "CPANPLUS", "Config.pm");
	}

        my $home_dir = _home_dir();

        my $home_conf = File::Spec->catdir($home_dir, '.cpanplus', 'config');

        print loc( q[
Where would you like to save the CPANPLUS Configuration file?

If you wish to use a custom configuration file, or do not have administrator
privileges, you probably can't or don't want to write to the systemwide perl
installation directory. In this case, you must provide an alternate location
(like your home directory) where you do have permissions.

You can override the system wide CPANPLUS Configuration file by setting
    $ENV{PERL5_CPANPLUS_CONFIG}
to the path of your personal configuration file.

Note that if you choose to use a custom configuration file you MUST set the
environment variables BEFORE running 'make', or CPANPLUS will be unable to find
your custom location and most likely prompt you for setup again.

If you are unsure what to answer here, just hit ENTER and CPANPLUS will try to
put your Configuration file in the default location.

1) %1
2) %2
3) Somewhere else

], $show_default, $home_conf);

        my $prompt = loc("Location of the Configuration file [1]: ");

        my $where = _get_reply(
            prompt  => $prompt,
            default => '1',
            choices => [ qw/1 2 3/ ],
        );

        unless( $where ) {
            $loc = $default;
        } else {
            $loc = $default                         if $where == 1;
            ($loc = $home_conf, ++$CustomConfig)    if $where == 2;
            ($loc = '',         ++$CustomConfig)    if $where == 3;
        }

        unless( $loc ) {
            BLOCK: {
            while ( defined($loc= _readline(loc('Configuration file name: '))) ) {
                $loc ||= $default;
                $term->addhistory($loc);

                if( -e $loc and -w _ ) {
                    my $yn = _get_reply(
                        prompt  => loc("I see you already have this file. It is writable. Shall I overwrite it?"),
                        default => 'n',
                        choices => [ qw/y n/ ],
                    );
                    last BLOCK if $yn =~ /y/i;
                } else {
                    my $dir = File::Basename::dirname($loc);

                    last BLOCK if -w $dir;

                    unless( -d $dir ) {
                        eval { File::Path::mkpath($dir) };
                        if ($@) {
                            warn qq[Could not create dir '$dir'];
                        } else {
                            chmod( 0644, $dir );
                            last BLOCK;
                        }
                    }
                    print loc("I can not write to %1, I don't have permission.", $loc), "\n";
                    redo BLOCK;
                }
            }
            }
        }
    }
    print "\n", loc("OK, I will save your Configure file to:"), "\n\t$loc\n\n";

    my $what = $ConfigLocation = $loc || q[$INC{'CPANPLUS/Config.pm'}];

    unless ($conf->can_save($loc) ) {
        print loc("*** Error: CPANPLUS %1 was not configured properly, and we cannot write to\n    %2", $CPANPLUS::Internals::VERSION, $what), "\n",
              loc("*** Please check its permission, or contact your administrator."), "\n";
        exit 1;
    }

    _issue_non_default_config_warning($loc) if $CustomConfig;


    local $SIG{INT};

    #my ($answer, $prompt, $default);
    print loc("

CPAN is the world-wide archive of perl resources. It consists of about
100 sites that all replicate the same contents all around the globe.
Many countries have at least one CPAN site already. The resources found
on CPAN are easily accessible with CPANPLUS modules. If you want to use
CPANPLUS, you have to configure it properly.

");

    my $answer;

    unless (defined $AutoSetup) {
    print loc("
Although we recommend an interactive configuration session, you can
also enter 'n' here to use default values for all questions.

");

        $answer = _get_reply(
            prompt  => loc("Are you ready for manual configuration?"),
            default => 'y',
            choices => [ qw/y n/ ],
        );
    }

    local $AutoSetup = 1 if $answer =~ /^n/i;

    _setup_ftp($conf);
    _setup_build($conf);
    _setup_conf($conf);
    _setup_hosts($conf);


################################################################################
##
## store it all
##

    print $conf->save($loc)
        ? ("\n", loc("Your CPAN++ configuration info has been saved!"), "\n\n")
        : ("\n", loc("Error saving your configuration"), "\n\n");

    # removes the terminal instance to avoid "Falling back to dumb"
    no strict 'refs';
    undef ${ref($term)."::term"} unless $[ < 5.006; # 5.005 chokes on this


} #init



sub _issue_non_default_config_warning {
    if( $CustomConfig ) {
        print loc( qq[
### IMPORTANT #####################################################

Since you chose a custom config file location, do not forget to set
the environment variable "%1" to
"%2"
before running '%3' or your config will not be detected!

###################################################################

        ], 'PERL5_CPANPLUS_CONFIG', $ConfigLocation, 'make');
    }
}


## gather all info needed for the 'conf' hash
##
## (takes Configure object, returns no values)
##
sub _setup_conf {

    my $conf = shift;

    #####################
    ## makemaker flags ##
    #####################

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

    my $MMflags = _ask_flags(
        MakeMaker => $conf->get_conf('makemakerflags'),
    );

    ################
    ## make flags ##
    ################

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

    my $makeflags = _ask_flags(
        "'make'" => $conf->get_conf('makeflags'),
    );

    #################
    ## shift a lib ##
    #################

    print loc('
If you like, CPAN++ can add extra directories to your @INC list starts
during startup.  Enter a space separated list of list to be added to
your @INC, quoting anything with embedded whitespace.  (To clear the
current value enter a single space.)

');

    my $lib = $conf->get_conf('lib');

    my $answer = _get_reply(
                  prompt  => loc('Additional @INC directories to add? [%1]', "@{$lib}"),
                  default => "@{$lib}",
              );

    if ($answer) {
        if ($answer =~ m/^\s+$/) {
            $lib = [];
        } else {
            (@{$lib}) = $answer =~ m/\s*("[^"]+"|'[^']+'|[^\s]+)/g;
        } #if
    } #if

    printf "\n", loc("Your additional libs are now:"), "\n";

    if (@{$lib}) {
        print map { "    $_\n" } @{$lib};
    } else {
        print "    ", loc("*nothing entered*"), "\n";
    } #if

    print "\n";


    ############
    ## noisy? ##
    ############

    print loc("
In normal operation I can just give you basic information about what I
am doing, or I can be more verbose and give you every little detail.

");

    $answer = _get_reply(
                  prompt  => loc("Should I be verbose?"),
                  default => _get($conf, verbose => 'n'),
                  choices => [ qw/y n/ ],
              );

    my $verbose;
    print "\n";

    if ($answer =~ /^y/i) {
        $verbose = 1;
        print loc("You asked for it!");
    } else {
        $verbose = 0;
        print loc("I'll try to be quiet.");
    } #if

    print "\n\n";


    #######################
    ## flush you animal! ##
    #######################

    print loc("
In the interest of speed, we keep track of what modules were installed
successfully and which failed in the current session.  We can flush this
data automatically, or you can explicitly issue a 'flush' when you want
to purge it.

");

    $answer = _get_reply(
                    prompt  => loc("Flush automatically?"),
                    default => _get($conf, flush => 'y'),
                    choices => [ qw/y n/ ],
              );

    my $flush;
    print "\n";

    if ($answer =~ /^y/i) {
        $flush = 1;
        print loc("I'll flush after every full module install.");
    } else {
        $flush = 0;
        print loc("I won't flush until you tell me to.  (It could get smelly in here! ;o)");
    } #if

    print "\n\n";


    ###################
    ## get in there! ##
    ###################

    print loc("
Usually, when a test fails, I won't install the module, but if you
prefer, I can force the install anyway.

");

    $answer = _get_reply(
                    prompt  => loc("Force installs?"),
                    default => _get($conf, force => 'n'),
                    choices => [ qw/y n/ ],
              );

    my $force;
    print "\n", loc("Ok, ");

    if ($answer =~ /^y/i) {
        $force = 1;
        print loc("I will force installs.");
    } else {
        $force = 0;
        print loc("I won't force installs.");
    } #if

    print "\n\n";


    ################################
    ## follow, follow, follow me! ##
    ################################

    print loc("
Sometimes a module will require other modules to be installed before it
will work.  CPAN++ can attempt to install these for you automatically
if you like, or you can do the deed yourself.

If you would prefer that we NEVER try to install extra modules
automatically, select NO.  (Usually you will want this set to YES.)

If you would like to build modules to satisfy testing or prerequisites,
but not actually install them, select B[uild].

NOTE: This feature requires you to flush the 'lib' cache for longer
running programs (refer to the CPANPLUS::Backend documentations for
more details).

Otherwise, select ASK to have us ask your permission to install them.

");

    $answer = _get_reply(
                    prompt  => loc("Follow prereqs?"),
                    default => _get($conf, prereqs => 'a'),
                    choices => [ qw/y n a b/ ],
              );

    my $prereqs;
    print "\n", loc("Ok, ");

    if ($answer =~ /^y/i) {
        $prereqs = 1;
        print loc("I will install prereqs.");
    } elsif ( $answer =~ /^a/i) {
        $prereqs = 2;
        print loc("I will ask permission to install prereqs.");
    } elsif ( $answer =~ /^b/i) {
        $prereqs = 3;
        print loc("I will only build and not install prereqs.");
    } else {
        $prereqs = 0;
        print loc("I won't install prereqs.");
    } #if

    print "\n\n";


    ####################
    ## safety is good ##
    ####################

    print loc("
The modules in the CPAN archives are protected with md5 checksums.

");

    my $have_md5 = eval { require Digest::MD5; 1 };
    $answer = _get_reply(
                    prompt  => loc("Use the md5 checksums?"),
                    default => _get($conf, md5 => $have_md5 ? 'y' : 'n'),
                    choices => [ qw/y n/ ],
              );

    my $md5;
    print "\n", loc("Ok, ");

    if ($answer =~ /^y/i) {
        $md5 = 1;
        print loc("I will use md5 if you have it.");
    } else {
        $md5 = 0;
        print loc("I won't use md5 if you have it.");
    } #if

    print "\n\n";


    ###########################################
    ## sally sells seashells by the seashore ##
    ###########################################

    my $default = 'CPANPLUS::Shell::Default';
    my $compat  = 'CPANPLUS::Shell::Classic';
    my $curses  = 'CPANPLUS::Shell::Curses';
    my $tk      = 'CPANPLUS::Shell::Tk';
    my $shell   = $conf->get_conf('shell') || $default;

    my @list = ( $default, $compat, $curses, $tk, undef );
    unshift @list, $shell unless grep { $_ eq $shell } @list;

    print loc(qq[
By default CPAN++ uses its own shell when invoked.  If you would prefer
a different shell, such as one you have written or otherwise acquired,
please enter the full name for your shell module.

1) %1
2) %2
3) %3
4) %4
5) other

],@list[0..3]);

    my $prompt = loc("Which CPANPLUS 'shell' do you want to use? " );

    my $pick = _get_reply(
        prompt  => $prompt . q|[1]: |,
        default => '1',
        choices => [ qw/1 2 3 4 5/ ],
    );

    my $which = $list[ $pick - 1 ];

    unless( $which ) {
        while( defined( $which = _readline($prompt) ) ) {

            ### soemthing like this should be added for sanity check
            ### we can use the load tool as of 0.050
            #eval { require $prompt }

            last;
        }
    }

    print "\nYour 'shell' is now:\n    $which\n";
    print "\n";

#die "conf ", Data::Dumper::Dumper( $CPANPLUS::Configure::conf );

    ###################
    ## use storable? ##
    ###################

    print loc("
To speed up the start time of CPAN++ we can use Storable to freeze some
information.  Would you like to do this?

");

    my $have_storable = eval "use Storable; 1";
    $answer = _get_reply(
                    prompt  => loc("Use Storable?"),
                    default => _get($conf, storable => $have_storable ? 'y' : 'n'),
                    choices => [ qw/y n/ ],
              );

    my $storable;
    print "\n";

    if ($answer =~ /^y/i) {
        $storable = 1;
        print loc("I will use Storable if you have it.");
    } else {
        $storable = 0;
        print loc("I am NOT going to use Storable.");
    } #if

    print "\n\n";


    ###################
    ## use cpantest? ##
    ###################

    print loc("
CPANPLUS has support for the Test::Reporter module, which can be utilized
to report success and failures of modules installed by CPANPLUS.  Would
you like to do this?  Note that you will still be prompted before
sending each report.

");

    $answer = _get_reply(
                    prompt  => loc("Report tests results?"),
                    default => _get($conf, cpantest => 'n'),
                    choices => [ qw/y n/ ],
              );

    my $cpantest;
    print "\n", loc("Ok, ");

    if ($answer =~ /^y/i) {
        $cpantest = 1;
        print loc("I will prompt you to report test results.");

    } else {
        $cpantest = 0;
        print loc("I won't prompt you to report test results.");
    } #if

    print "\n\n";


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

    my $have_pgp = `gpg --version` or eval { require Crypt::OpenPGP; 1 };
    $answer = _get_reply(
                    prompt  => loc("Check module signatures?"),
                    default => _get($conf, signature => ($have_pgp ? 'y' : 'n')),
                    choices => [ qw/y n/ ],
              );

    my $signature;
    print "\n", loc("Ok, ");

    if ($answer =~ /^y/i) {
        $signature = 1;
        print loc("I will attempt to check module signatures.");
    } else {
        $signature = 0;
        print loc("I won't attempt to check module signatures.");
    } #if

    print "\n\n";




    ##############
    ## save it! ##
    ##############

    $conf->set_conf(
        cpantest       => $cpantest,
        force          => $force,
        lib            => $lib,
        makeflags      => $makeflags,
        makemakerflags => $MMflags,
        md5            => $md5,
        prereqs        => $prereqs,
        shell          => $which,
        storable       => $storable,
        signature      => $signature,
        verbose        => $verbose,
    );

} #_setup_conf


## getting the $conf to set proper defaults
sub _get {
    my ($conf, $key, $default) = @_;
    my $value = $conf->get_conf($key);
    return (defined $value ? ((qw/n y a b/)[$value]) : $default);
}

## gather all info needed for the '_ftp' hash,
## except 'urilist' is handled in _setup_hosts
##
## (takes Configure object, returns no values)
##
sub _setup_ftp {

    my $conf = shift;
    my ($answer, $prompt, $default);

    #########################
    ## are you a pacifist? ##
    #########################

    print loc("
If you are connecting through a firewall or proxy that doesn't handle
FTP all that well you can use passive FTP.

");

    $answer = _get_reply(
                    prompt  => loc("Use passive FTP?"),
                    default => _get($conf, passive => 'y'),
                    choices => [ qw/y n/ ],
              );

    my $passive;
    print "\n";

    if ($answer =~ /^y/i) {
        $passive = 1;

        ### set the ENV var as well, else it won't get set till AFTER
        ### the configuration is saved. but we fetch files BEFORE that.
        $ENV{FTP_PASSIVE} = 1;

        print loc("I will use passive FTP.");
    } else {
        $passive = 0;
        print loc("I won't use passive FTP.");
    } #if

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

    my $email   = $conf->_get_ftp('email') || 'cpanplus@example.com';
    my $cf_mail = $Config{cf_email};

    $cf_mail = 'cpanplus@example.com' if $cf_mail eq $email; # for variety's sake

    print loc("
You have several choices:

1) %1
2) %2
3) something else

", $email, $cf_mail);

    $prompt = loc('Please pick one [1]: ');
    $default = '1';

    while (defined($answer = _readline($prompt))) {
        $answer ||= $default;
        $term->addhistory($answer);

                           last, if $answer == 1;
        $email = $cf_mail, last, if $answer == 2;
        $email = '',       last, if $answer == 3;

        $prompt  = loc('Please choose 1, 2, or 3 [1]: ');
        next;
    } #while

    until ( _valid_email($email) ) {
        print loc("You did not enter a valid email address, please try again!"), "\n"
            if length $email;

        $email = _get_reply(
            prompt  => loc("Email address: "),
        );
    } #while

    print "\n", loc("Your 'email' is now:"), "\n    $email\n";
    print "\n";


    ##############
    ## save it! ##
    ##############

    $conf->_set_ftp(
        email   => $email,
        passive => $passive,
    );

} #_setup_ftp


## gather all info needed for the '_build' hash
##
## (takes Configure object, returns no values)
##
sub _setup_build {

    my $conf = shift;
    my ($answer, $prompt, $default);

    #################
    ## CPAN++ home ##
    #################

    print loc("
The CPAN++ module needs a directory of its own to cache important index
files and maybe keep a temporary mirror of CPAN files.  This may be a
site-wide directory or a personal directory.
");

    my $new_path;
    my $dot_cpan = '.cpanplus';

    ### add more checks later - good for Win9x/NT4/Win2k and *nix now
    ### this breaks cygwin, thanks -kane
    #if ($^O =~ m/win/i) {

    ### when HOME is set, it is assumed that UNIX behaviour is wanted
    if ( not $ENV{HOME} and $^O eq 'MSWin32' ) {
        #V: {
        #    #$new_path = $ENV{WIN2KTEST},   last V, if exists $ENV{USERPROFILE};
        #    $new_path = $ENV{USERPROFILE}, last V, if exists $ENV{USERPROFILE};
        #    $new_path = $ENV{WINDIR},      last V, if exists $ENV{WINDIR};
        #} #V
        $new_path = File::Spec->catdir(_home_dir(), 'Application Data', $dot_cpan);

        ### this seems a rather dangerous thing -kane ###
        #$new_path =~ s|\\|/|g; # makes everything look better
    } else {
        $new_path = File::Spec->catdir($ENV{HOME}, $dot_cpan);
    } #if

    my $cpan_home = $conf->_get_build('base') || $new_path;
    #$cpan_home =~ s|\\|/|g, if $^O eq 'MSWin32'; # beautify windoze

    if ($cpan_home ne $new_path) {

        print loc("
You have several choices:

1) %1
2) %2
3) something else

", $new_path, $cpan_home);

        $prompt = loc('Please pick one [1]: ');
        $default = '1';

        while (defined($answer = _readline($prompt))) {
            $answer ||= $default;
            $term->addhistory($answer);

            $cpan_home = $new_path, last, if $answer == 1;
                                    last, if $answer == 2;
            $cpan_home = '',        last, if $answer == 3;

            $prompt  = loc('Please choose 1, 2, or 3 [1]: ');
            next;
        } #while

    } #if

    if (-d $cpan_home) {

        print "\n", loc("I see you already have a directory:"), "\n\n    $cpan_home\n\n";

        $prompt  = loc('Should I use it? [Y/n]: ');
        $default = 'y';

    } else {

        print "\n", loc("First of all, I'd like to create this directory.  Where?"), "\n\n";

        $prompt  = loc("[%1]: ", $cpan_home);
        $default = $cpan_home;

    } #if


    while (defined($answer = _readline($prompt))) {
        $answer ||= $default;
        $term->addhistory($answer);

        if ($default eq 'y') {
            if ($answer =~ /^y/i) {
                $answer = $cpan_home;
            } else {
                $prompt  = loc('Where shall I put it then?: ');
                $default = '';
                next;
            } #if
        } #if

        $prompt = loc('Please choose a different location: ');
        $default = '';

        if (-d $answer and not (-w _)) {
            print loc("I can't seem to write in this directory."), "\n";
            $AutoSetup = 0; next;
        } #if

        ### windoze won't make more than one dir at a time :o(
        #unless (mkdir $answer) {

        {
            ### dont use this, it's buggy! -kane
            #local $@;

            unless (-d $answer or eval { File::Path::mkpath($answer) } ) {
                chomp($@);
                warn loc("I wasn't able to create %1.", $answer), "\n",
                     loc("The error I got was %1", $@), "\n\n";
                $AutoSetup = 0; next;
            } #unless
        } #scope

        my $autdir = File::Spec->catdir($answer, $conf->_get_build('autdir'));
        unless (-e $autdir or mkdir($autdir, 0777)) {
            warn loc("I wasn't able to create %1.", $autdir), "\n",
                 loc("The error I got was %1", $!), "\n\n";
            $AutoSetup = 0; next; # XXX: doesn't unlink the current $answer
        }

        my $moddir = File::Spec->catdir($answer, $conf->_get_build('moddir'));
        unless (-e $moddir or mkdir($moddir, 0777)) {
            warn loc("I wasn't able to create %1.", $moddir), "\n",
                 loc("The error I got was %1", $!), "\n\n";
            $AutoSetup = 0; next; # XXX: doesn't unlink the current $answer
        }

        $cpan_home = Cwd::abs_path($answer);

        ### clear away old storable images before 0.031
        unlink File::Spec->catfile($cpan_home, 'dslip');
        unlink File::Spec->catfile($cpan_home, 'mailrc');
        unlink File::Spec->catfile($cpan_home, 'packages');

        ### set default values to _build for upgrading to 0.040+
        $conf->set_build('distdir' => 'dist/')
            unless $conf->get_build('autobundle');
        $conf->set_build('autobundle' => 'autobundle/')
            unless $conf->get_build('autobundle');
        $conf->set_build('autobundle_prefix' => 'Snapshot')
            unless $conf->get_build('autobundle_prefix');

        $conf->_set_build( base => $cpan_home );

        print "\n", loc("Your CPAN++ build and cache directory has been set to:"), "\n";
        print "    $cpan_home\n";
        last;
    } #while

    print "\n\n";

    ######################################
    ## what commandprompt should we use ##
    ######################################

    my (@path) = split /$Config{path_sep}/, $ENV{PATH};

    {
        my $default = $conf->_get_build('shell');

        $default ||= $^O eq 'MSWin32'
            ? $ENV{COMSPEC}
            : $ENV{SHELL};

        my $prog;
        while('not good enough') {
            my $answer = _get_reply(
                            prompt  => loc("Your favorite command line shell? ").
                                       ($default ? " [$default]: " : ": "),
                            default => $default,
                      );

            $prog = ( MM->maybe_command($answer) or _find_exe($answer, [@path]) );

            $prog
                ? print(loc("Your command line shell has been set to:"), "\n    $prog\n\n")
                : print(loc("I'm sorry, '%1' is not a valid option, please try again", $answer), "\n");

            last if $prog;
        }

        $conf->_set_build( shell => $prog );
    }

    ### does this box have sudo ? ###
    my $sudo;
    {
        $sudo = _find_exe('sudo',\@path);
        if( $sudo ) {
            my $ok = $AutoSetup || $term->ask_yn(
                prompt  => loc("I found %1 in your path, would you like to use it for '%2'?", 'sudo', 'make install' ),
                default => 'y',
            );
            $sudo = '' unless $ok;
        }
    }

    ###############################
    ## whereis make/tar/gzip/etc ##
    ###############################

    my ($new_name, $pgm_name);

    my %pgms = (
        ftp      => '',
        gzip     => '',
        lynx     => '',
        make     => '',
        ncftp    => '',
        ncftpget => '',
        pager    => '',
        #perl     => '', # favor finding this at runtime
        #shell    => '',
        tar      => '',
        unzip    => '',
        wget     => '',
        curl     => '',
        rsync    => '',
    );

    for my $pgm (sort keys %pgms) {

        #unless ($pgm eq 'perl') { # favor finding this at runtime
        my $name = $Config{$pgm} || $pgm;

        $name ||= $ENV{PAGER} || 'more' if ($pgm eq 'pager');

        $new_name = (_find_exe($name, [@path]) || MM->maybe_command($name))
                  ? $name
                  : '';

        $new_name ||= 'ncftp3' if $pgm eq 'ncftp' and
            (_find_exe('ncftp3', [@path]) || MM->maybe_command('ncftp3'));

        #} else {
        #    $new_name = $^X; # favor finding this at runtime
        #} #unless

        #$new_name =~ s|\\|/|g, if $^O eq 'MSWin32'; # pretty up windoze

        $name = $conf->_get_build($pgm);
        if ($name) {
            $pgm_name = (_find_exe($name, [@path]) || MM->maybe_command($name))
                      ? $name
                      : $new_name;
            #$pgm_name =~ s|\\|/|g, if $^O eq 'MSWin32'; # pretty up windoze
        } else {
            $pgm_name = $new_name;
        }

        if ($pgm_name ne $new_name) {
            print loc("
Which '%1' executable should I use?

1) %2
2) %3
3) other

", $pgm, $new_name, $pgm_name);

            $prompt = loc('Please pick one [1]: ');
            $default = 1;

        } else {
            $prompt  = loc("Where can I find your '%1' executable? [%2]: ", $pgm, $pgm_name);
            $default = $pgm_name;

        } #if

        while (defined($answer = _readline($prompt))) {
            $answer ||= $default;
            $answer =~ s/^\s+$//;
            $term->addhistory($answer), if $answer;

            if ($default =~ /^[123]$/) {
                unless ($answer == 1 || $answer == 2 || $answer == 3) {
                    $prompt  = loc('Please choose 1, 2, or 3 [1]: ');
                    next;
                } #unless

                $answer = $new_name, if $answer == 1;
                $answer = $pgm_name, if $answer == 2;

                if ($answer == 3) {
                    $prompt  = loc("Where can I find your '%1' executable?: ", $pgm);
                    $default = '';
                    $AutoSetup = 0; next;
                } #if

            } #if

            $pgm_name = $answer;

            # some can be blank, but NOT perl or make
            #last, unless $pgm_name or $pgm =~ m/^make|perl$/;
            unless ($pgm_name) {
                #last, unless $pgm =~ m/^make|perl$/; # favor finding this at runtime
                last, unless $pgm eq 'make';
                warn loc("Without your '%1' executable I can't function!", $pgm), "\n";
                $AutoSetup = 0; next;
            } #unless

            # it better actually be a program!
            last, if File::Spec->file_name_is_absolute($answer)
                  && MM->maybe_command($answer);

            $answer = _find_exe($answer, [@path]);
            unless ($answer) {
                warn loc("I couldn't find '%1' in your PATH.", $pgm_name), "\n";
                $prompt  = loc("Please tell me where I can find it: ");
                $default = '';
                $AutoSetup = 0; next;
            } #unless

            print "\n", loc("Good, I found '%1' in your PATH:", $pgm_name), "\n    $answer\n";
            last;

        } #while

        print "\n", loc("Your '%1' program has been set to:", $pgm),
              "\n    ", (($answer) ? $answer : loc('*nothing entered*')), "\n";

        print "\n\n";

        $pgms{$pgm} = $^O eq 'MSWin32' ? Win32::GetShortPathName($answer) : $answer;

    } #for


    ##############
    ## save it! ##
    ##############

    print $conf->_set_build(
        'base' => $cpan_home,
        'sudo' => $sudo,
        %pgms,
    )
        ? loc("Build options saved\n")
        : loc("Failed to save build options\n");

} #_setup_build


### helper module for makeflags and makemakerflags
sub _ask_flags {
    my ($name, $old) = @_;

    ### do a one-level deep copy of the original value
    my $flags = (UNIVERSAL::isa($old, 'HASH')) ? { %{$old} } : {};

    if (%{$flags}) {
        print loc("Your current %1 flags are:", $name), "\n";
        print map {
            defined($flags->{$_})
                ? "    $_=$flags->{$_}\n"
                : "    $_\n"
        } sort keys %{$flags};
        print "\n\n";
    } #if


    my $current_flags = join(' ', map {
        defined($flags->{$_})
            ? "$_=$flags->{$_}"
            : "$_"
    } sort keys %{$flags});

    my $answer = _get_reply(
                    prompt  => loc("Parameters for %1 [%2]: ", $name, $current_flags),
                    default => $current_flags,
             );

    $flags = CPANPLUS::Backend->_flags_hashref($answer);

    print "\n", loc("Your %1 flags are now:", $name), "\n";

    if (%{$flags}) {
        print map {
            defined($flags->{$_})
                ? "    $_=$flags->{$_}\n"
                : "    $_\n"
        } sort keys %{$flags};
    } else {
        print "    *nothing entered*\n";
    } #if

    print "\n";

    return $flags;
}


## locate a given executable in the given path
##
## (takes scalar and arrayref, returns scalar)
##
sub _find_exe {
    my ($exe, $path) = @_;
    my $param = (($exe =~ s/(\s+.*)//) ? $1 : '');

    for my $dir (@{$path}) {
        my $abs = File::Spec->catfile($dir, $exe);
        return $abs.$param if $abs = MM->maybe_command($abs);
    } #for

} #_find_exe


## gather all info needed for 'urilist' hash inside '_ftp'
##
## (takes Configure object, returns no values)
##
sub _setup_hosts {
    my $conf = shift;

    ### these are the options you have in the varying menus ###
    my $options = {
        continent   => [ qw|c u q| ],
        country     => [ qw|c u q| ],
        host        => [ qw|c v u q| ],
        view        => [ qw|y n| ],
        main        => [ qw|c m v q| ],
    };

    my ($answer, $prompt, $default, $loaded_mirrored_by);
    my (@selected_hosts, $hosts, $host_list, $country, $continent);
    my ($default_continent, $default_country, $default_host);


    my $next = 'main';
    my $came_from;
    LOOP: { while (1) {

        last if $SkipMirrors;

        #print Dumper \@selected_hosts;

        if ( $next eq 'main' ) {
            print loc("

Now we need to know where your favorite CPAN sites are located. Push a
few sites onto the array (just in case the first on the array won't
work).

If you are mirroring CPAN to your local workstation, specify a file:
URI by picking the [c] option.

Otherwise, let us fetch the official CPAN mirror list and you can pick
the mirror that suits you best from a list by using the [m] option;
First, pick a nearby continent and country. Then, you will be presented
with a list of URLs of CPAN mirrors in the country you selected. Select
one or more of those URLs.

Note, the latter option requires a working net connection.
");


            #my $items   = [sort keys %{$hosts->{all}}];
            my $pick    = _pick_item (
                           options => {
                                        q => loc('quit'),
                                        m => loc('official cpan mirror list'),
                                        c => loc('custom host'),
                                        v => (scalar(keys %$host_list)) > 0 ? loc('view list') : '',
                                    },
                           prompt  => loc("Please choose an option "),
                           choices => [ @{$options->{main}} ],
                           default => 'm',
            );

            if (lc $pick->[0] eq 'c') {
                push @selected_hosts, _set_custom_host($conf,$host_list); next;

            } elsif (lc $pick->[0] eq 'm') {
                $next = 'continent'; next;

            } elsif (lc $pick->[0] eq 'v') {
                $came_from = 'main';
                $next = 'view'; next;

            } elsif (lc $pick->[0] eq 'q') {
                unless( scalar @selected_hosts ) {
                    print "\n", loc("You have *NO* hosts selected! This will probably cause problems!"), "\n";
                }
                last;
            }

        } elsif ( lc $next eq 'custom' ) {

            push @selected_hosts, _set_custom_host($conf,$host_list); next;

        } elsif ( lc $next eq 'continent' ) {
            ### if we haven't done so yet:
            ### get mirrored_by, parse it and get all the hosts
            ### also guess what a reasonable default would be

            unless( $loaded_mirrored_by++ ) {
                $hosts = _get_mirrored_by($conf);

                ($default_continent, $default_country, $default_host) =
                    _guess_from_timezone($hosts);
            }

            my $items   = [sort keys %{$hosts->{all}}];
            my $default = _find_seq($items, $default_continent);
            my $pick    = _pick_item (
                           items   => $items,
                           options => {
                                        q => loc('quit'),
                                        u => loc('back to main'),
                                        c => loc('custom host'),
                                    },
                           prompt  => loc("Please choose a continent [%1]: ", $default),
                           choices => [ @{$options->{continent}} ],
                           default => $default,
            );

            if ($pick->[0] =~ /\d/) {
                $continent = $pick->[1];
                $next      = 'country'; next;

            } elsif (lc $pick->[0] eq 'c') {
                push @selected_hosts, _set_custom_host($conf,$host_list); next;

            } elsif (lc $pick->[0] eq 'u') {
                $next = 'main'; next;

            } elsif (lc $pick->[0] eq 'q') {
                last;
            }


        } elsif ( lc $next eq 'country' ) {
            my $items   = [ sort keys %{$hosts->{all}->{$continent}} ];
            my $default = _find_seq($items, $default_country);
            my $pick    = _pick_item (
                           items   => $items,
                           options => {
                                          q => loc('quit'),
                                          u => loc('back to continents'),
                                          c => loc('custom host'),
                                      },
                           prompt  => loc("Please choose a country [%1]: ", $default),
                           choices => [ @{$options->{country}} ],
                           default => $default,
                       );

            if ($pick->[0] =~ /\d/) {
                $country = $pick->[1];
                $next    = 'host';      next;

            } elsif (lc $pick->[0] eq 'c') {
                push @selected_hosts, _set_custom_host($conf,$host_list); next;

            } elsif (lc $pick->[0] eq 'u') {
                $next = 'continent'; next;

            } elsif (lc $pick->[0] eq 'q') {
                last;

            }

        } elsif ( lc $next eq 'host' ) {
            my $sub     = sub { return "[$_[0]] $_[1]" .
                                " ($hosts->{$_[1]}->{frequency}" .
                                ", $hosts->{$_[1]}->{dst_bandwidth})\n";
                            };

            my $items   = [ sort @{$hosts->{all}->{$continent}->{$country}} ];
            my $default = _find_seq($items, $default_host);
            my $pick    = _pick_item (
                           items   => $items,
                           options => {
                                        q => loc('finish'),
                                        u => loc('back to countries'),
                                        v => (scalar(keys %$host_list)) > 0 ? loc('view list') : '',
                                        c => loc('custom host'),

                                    },
                           map_sub => $sub,
                           prompt  => loc("Please choose a host [%1]: ", $default),
                           choices => [ @{$options->{host}} ],
                           default => $default,
                           multi   => 1,
                       );

            if ($pick->[0] =~ /\d/) {
                print "\n";
                for my $host (@{$pick}[1..$#{$pick}]) {
                    if (exists $host_list->{$host}) {
                        print "\n", loc("Host %1 already selected!", $host), "\n";
                        last LOOP if $AutoSetup; next;
                    }

                    push @selected_hosts, $host;
                    $host_list->{$host} = $hosts->{$host};
                    my $total           = scalar(keys %{$host_list});

                    printf "%-30s %30s\n",
                                loc("Selected %1",$host),
                                loc("%quant(%2,host) selected thus far.", $total);
                }

                $next = 'host'; next;

            } elsif (lc $pick->[0] eq 'c') {
                push @selected_hosts, _set_custom_host($conf,$host_list); next;

            } elsif (lc $pick->[0] eq 'q') {
                last;

            } elsif (lc $pick->[0] eq 'u') {
                $next = 'country'; next;

            } elsif (lc $pick->[0] eq 'v') {
                $came_from = 'host';
                $next = 'view'; next;
            }

        } elsif ( lc $next eq 'view' ) {
            print "\n\n", loc("Currently selected hosts:");
            my $pick = _pick_item (
                           items        => [ @selected_hosts ],
                           map_sub      => sub { return "    $_[1]\n" },
                           prompt       => loc('Choose another? [Y/n]: '),
                           default      => 'y',
                           choices      => [ @{$options->{view}} ],
                           add_choices  => 0,
                       );

            if (lc $pick->[0] eq 'n') {
                last
            } else {
                $next = $came_from ? $came_from : 'main'; next;
            }

        } else {

        }

    } } ### end LOOP end WHILE;

    push @selected_hosts, _set_custom_host($conf,$host_list) if $AutoSetup;

    # remove duplicate hosts from the list.
    my %unique_hosts;
    @selected_hosts = grep { !$unique_hosts{$_}++ } @selected_hosts;

    @selected_hosts = map {
        if (!$host_list->{$_}) {
            my ($scheme, $host, $path) = m{^([a-zA-Z]+)://([a-zA-Z0-9\.-]*)(/.*)$};
            $host_list->{$_} = { host => $host, scheme => $scheme, path => $path };
        }
        {
            host   => $host_list->{$_}->{host} ? $host_list->{$_}->{host} : $_,
            path   => $host_list->{$_}->{path},
            scheme => $host_list->{$_}->{scheme},
        }
    } @selected_hosts;

    print "\n", loc("Your current hosts are:"), "\n",
          (
            map { (
                    "$_->{host}",
                    (lc $_->{scheme} eq 'file') ? " ($_->{path})" : '',
                    "\n"
                );
            } @selected_hosts
        ),"\n";

    ### MUST CHANGE THIS - I HATE IT!!! -jmb
    $conf->_set_ftp( urilist => [ @selected_hosts ] );

} #_setup_hosts

sub _get_mirrored_by {
    my $conf = shift;

    print loc("
Now, we are going to fetch the mirror list for first-time configurations.
This may take a while...

");

    my $file = File::Spec->catfile($conf->_get_build('base'), $conf->_get_source('hosts'));

    unless (-e $file) {

        if($backend) {
            $backend->_reconfigure(conf => $conf);
        } else {
            $backend = new CPANPLUS::Backend($conf);
        }

        $backend or die loc("Can't use Backend!"), "\n";

        $backend->_fetch(
            file     => $conf->_get_source('hosts'),
            fetchdir => $conf->_get_build('base'),
        ) or warn loc("Fetch of %1 failed!", $file), "\n";

    } #unless

    my $hosts = _parse_mirrored_by($file);

    return $hosts;
}

sub _set_custom_host {
    my $conf        = shift;
    my $host_list   = shift;

    ## the default fall-back host for unfortunate users
    my $fallback_host;
    {
        use CPANPLUS::Config;
        my $conf = CPANPLUS::Config->new;
        my $uri  = $conf->{_ftp}->{urilist}->[0]; # first URI from CPANPLUS::Config
        $fallback_host = $uri
            ? "$uri->{scheme}://$uri->{host}$uri->{path}"
            : 'http://ftp.cpan.org/pub/CPAN/';
    }

    print loc("

If there are any additional URLs you would like to use, please add them
now.  You may enter them separately or as a space delimited list.

We provide a default fall-back URL, but you are welcome to override it
with e.g. 'http://www.cpan.org/' if LWP, wget or curl is installed.

(Enter an empty string when you are done, or to simply skip this step.)

Note that if you want to use a local depository, you will have to enter
as follows:

file://server/path/to/cpan

if the file is on a server on your local network or as:

file:///path/to/cpan

if the file is on your local disk. Note the three /// after the file: bit

");

    my @hosts;
    while ('kane is happy') {
        my $answer = _get_reply(
                        prompt  => ($fallback_host
                            ? loc("Additional host(s) to add [%1]: ", $fallback_host)
                            : loc("Additional host(s) to add: ")),
                        default => $fallback_host,
                  );

        ## first-time only.
        $fallback_host = '';

        ## oh, you want to quit (_get_reply returns empty string given no input)
        last unless $answer =~ /\S/;

        my @given = split(' ', $answer); #little-documented awk-like behavior

        for my $uri (@given) {
            ## break up into scheme/host/path
            ## cheat here and reject all but full uri's without auth data
            ## (real cheesy basic check - NOT a full URI validation!)
            my ($scheme, $host, $path)
                = $uri =~ m{^([a-zA-Z]+)://([a-zA-Z0-9\.-:]*)(/.*)$};


            ## no schemey, no hosty, no pathy, no worky
            unless ($scheme and $path) {
                print "\n", loc("No valid path or scheme entered!"), "\n";
                next;
            }

            ### only file URI's allowed to leave host blank
            unless($scheme eq 'file') {
                unless( $host ) {
                    print "\n", loc("No valid hostname entered!"), "\n";
                    next;
                }
            }

            ## don't store duplicate items
            ## maybe we don't care or want to override them though? -jmb
            ## need to allow for multiple localhost hosts somehow
            #unless ($host ne 'localhost' and exists $host_list->{$host}) {
            my $flag;
            unless (    $scheme ne 'file' and exists $host_list->{$host}
                        and $path ne $host_list->{$host}->{path}
            ) {
                my $href = {
                                host    => $host,
                                path    => $path,
                                scheme  => $scheme,
                            };

                $host_list->{$uri} = $href;
                push @hosts, $uri;

            } #unless

        } #for

    } #while

    return @hosts;
}

## consolidated picker routine
##
## Displays a picklist and asks for a reply.
##
## You supply:
##     map_sub => subref used to display picklist
##     items   => arrayref with items in picklist
##     options => hashref with options not in picklist
##     multi   => flag to indicate a multiple choice question
## and any additional args for _get_reply
##
## For your trouble you get an arrayref with the user supplied answer and the
## associated item.
##
## (takes hash, returns arrayref)
##
sub _pick_item {
    my %args = @_;

    my ($count, $choices);
    my $sub = $args{map_sub} || sub { return "[$_[0]] $_[1]\n"; };

    ## build main list
    my @list = map {
        $choices->{++$count} = $_;
        $sub->($count, $_);
   } @{$args{items}};

    ## build option list
    push @list, map {
        ("[$_] $args{options}->{$_}\n"), if $args{options}->{$_};
    } sort keys %{$args{options}};

    $args{prompt} =~ s/ \[\]:$/:/; # remove empty defaults

    print "\n\n", @list, "\n";

    ### add generated choices to list if this was requested
    ### it is also the default
    my $add_choices = 1;
    if(defined $args{add_choices} ) {
        $add_choices = $args{add_choices} ? 1 : 0;
    }

    push @{$args{choices}}, keys %{$choices} if $add_choices;

    ## get the reply
    my $answer = _get_reply(%args);
    return [ $answer, @{$choices}{split(/\s+/, $answer)} ];

} #_pick_item


## generic reply processor
##
## Asks for, and stubbornly refuses to accept anything but, a valid reply.
##
## You supply:
##     prompt  => prompt for user display
##     default => default answer, if any
##     choices => list of valid replies
##     multi   => flag to indicate a multiple choice question
##
## For your trouble you get the user supplied answer.
##
## (takes hash, returns scalar)
##
sub _get_reply {
    my %args = @_;

    # On win32, we limit ourselves to the dumb terminal.
    # -autrijus: eventually we'd want CPANPLUS::Term that wraps this up.

    if ($args{default} =~ /^[a-zA-Z]$/ and exists $args{choices}) {
        $args{prompt} .= " [".join('/', map {
            ($_ eq $args{default}) ? uc($_) : $_
        } @{$args{choices}})."]: ";
    }

    LOOP: {
        my $answer = _readline($args{prompt});
        $answer = $args{default}   unless length $answer;
        $answer = ''               unless length $answer;
        $term->addhistory($answer) if length $answer and !$AutoSetup;

        if (exists $args{choices}) {
            my @answers = $args{multi} ? split(/\s+/, $answer) : $answer;
            unless (@answers == grep {
                my $ans = $_; grep { lc($_) eq lc($ans) } @{$args{choices}}
            } @answers) {
                #$args{prompt} = 'Invalid selection, please try again: ';
                warn loc("Invalid selection, please try again."), "\n";
                redo LOOP;
            } #unless
        } #if
        return $answer;
    } #LOOP

} #_get_reply

sub _readline {
    if ($AutoSetup) {
        print @_;
        print "\n";
        return '';
    }

    my $TR = ($^O eq 'MSWin32') ? 'Term::ReadLine::Stub' : 'Term::ReadLine';
    $term ||= $TR->new('CPANPLUS Configuration', *STDIN, *STDOUT);
    return $term->readline(@_);
}

## MIRRORED.BY parser
##
## Converts a given MIRRORED.BY file into usable data without an eval.
##
## (takes scalar, returns hashref)
##
sub _parse_mirrored_by {

    my $file = shift;

    ### file should have a size, else there is a problem ###
    if (-s $file) {
        my $fh = new FileHandle;

        $fh->open("<$file") or die loc("Couldn't open %1: %2", $file, $!);
        {
            local $/ = undef;
            $file    = <$fh>;
        }
        $fh->close;
    }
    else {
        $file = MIRRORED_BY();
    }

    $file =~ s/#.*$//gm; # squash comments

    #open (DEBUG, '>debug.txt') or die $!;

    my $hosts;
    %{$hosts} = $file =~ m/([a-zA-Z0-9\-\.]+):\s+((?:\w+\s+=\s+".*?"\s+)+)/gs;
    #print DEBUG Data::Dumper->Dump([$hosts], ['hosts']);

    for my $h (sort keys %{$hosts}) {
        #print DEBUG "h is $h, ", Data::Dumper->Dump([$hosts->{$h}], ['host1']);

        my $el;
        #%{$el} = $hosts->{$h} =~ m/(\w+)\s+=\s+"(.+?)"\s+/gs;
        %{$el} = $hosts->{$h} =~ m/(\w+)\s+=\s+"(.*?)"\s+/gs;
        #print DEBUG Data::Dumper->Dump([$el], ['host1']);

        ## cripple it to ftp for now
        #next, unless exists $el->{dst_ftp};
        #next, unless $el->{dst_ftp};
        ## can't just go to next, must delete this host
        ## (else _guess_from_timezone chokes)
        unless ($el->{dst_ftp}) {
            delete $hosts->{$h};
            next;
        } #unless

        ($el->{path}) = $el->{dst_ftp} =~ m/$h(.*)$/;
        #print DEBUG "dst_ftp: ", $el->{dst_ftp}, ", path: ", $el->{path}, "\n";
        $el->{scheme} = 'ftp';

        my $lat_long;
        ($el->{city_area}, $el->{country}, $el->{continent}, $lat_long) =
            $el->{dst_location} =~
                #"Aizu-Wakamatsu, Tohoku-chiho, Fukushima, Japan, Asia (37.4333 139.9821)"
                m/
                    #Aizu-Wakamatsu, Tohoku-chiho, Fukushima
                    ^(
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
                     ((?:\(.*)?)$              # (latitude longitude)
                 /sx;

        @{$el->{lat_long}} = $lat_long =~ m/\((\S+)\s+(\S+?)\)/;

        $el->{dst_bandwidth} ||= 'unknown';

        $hosts->{$h} = $el;
        push @{$hosts->{all}->{$el->{continent}}->{$el->{country}}}, $h;

        #print DEBUG Data::Dumper->Dump([$el], ['host2']);

    } #for

    #print DEBUG Data::Dumper->Dump([$hosts], ['hosts']);
    #close DEBUG;

    return $hosts;

} #_parse_mirrored_by


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
    ### autrijus - build time zone table
    my $hosts = shift;
    my (%zones, %countries, %sites);

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


## finds a target's position in a given arrayref
##
## (takes arrayref and scalar, returns scalar)
##
sub _find_seq {
    my ($ref, $target) = @_;

    ### $target will be undef sometimes -jmb
    if ($target) {
        #local $_;
        #($ref->[$_] eq $target) and return ($_ + 1) for (0 .. $#{$ref});
        ### this seems clearer to me -jmb
        for my $count (0 .. $#{$ref}) {
            return ($count + 1) if $ref->[$count] eq $target;
        }
    }

    return '';

} # _find_seq


## Test email validness against RFC 822, using Jeffrey Friedl's optimized
## example in _Mastering Regular Expressions_ (http://www.ora.com/catalog/regex/).
##
## (takes string, returns bolean)
##
{
    my $RFC822PAT; # RFC pattern to match for valid email address

    sub _valid_email {
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

sub _home_dir {
    return  exists $ENV{HOME}           ? $ENV{HOME}        :
            exists $ENV{USERPROFILE}    ? $ENV{USERPROFILE} :
            exists $ENV{WINDIR}         ? $ENV{WINDIR}      :  cwd();
}

use constant MIRRORED_BY => << '__EOF__';
# Explanation of the syntax:
#
# hostname.of.the.CPAN.mirroring.site:
#   frequency        = "daily/bidaily/.../weekly"
#   dst_ftp          = "ftp://the.same.host.name:/CPAN/mirror/directory/"
#   dst_http         = "http://the.same.host.name:/CPAN/mirror/directory/"
#   dst_rsync        = "the.same.host.name::CPAN"
#   dst_location     = "city, (area?, )country, continent (lat long)"
#   dst_organisation = "full organisation name"
#   dst_timezone     = "GMT[+-]n"
#   dst_bandwidth    = "Approximate connection speed,e.g. T1, E3, etc."
#   dst_contact      = "email.address.to.contact@for.this.mirror"
#   dst_src          = "host.that.you.mirror.from"
#   dst_loadbal	     = "Y" or "N" Join the load balancing pool for ftp.cpan.org
#   dst_notes        = "(optional field) access restrictions, for example?"
#
# Notes:
# - The "area" in dst_location is optional.
#   It is the state (United States), county, prefecture, district.
# - The "lon,lat" in dst_location are required.
#   They are the latitude, longtitude, in degrees.minutes_IN_DECIMAL
#   (45 minutes = 0.75).
# - The dst_organisation tries to be correct but in some cases it
#   cannot be because the format is so simple:
#   - Greek/Cyrillic/Kanji/Hanzi/... cannot be rendered in ISO Latin 1
#   - the format is usually "native (english)"
#     but for example in Canada, well, is native English or French?
#   - sometimes the name of the organisation is already
#     in English (funet, sunet, arnes, math.ncu, ...)
#


ftp.rucus.ru.ac.za:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.rucus.ru.ac.za/pub/perl/CPAN/"
  dst_http         = "http://ftp.rucus.ru.ac.za/pub/perl/CPAN/"
  dst_location     = "Grahamstown, Eastern Cape, South Africa, Africa (-33.313028 26.519528)"
  dst_organisation = "Rhodes University Computer Users' Society"
  dst_timezone     = "+2"
  dst_bandwidth    = "T3"
  dst_contact      = "webteam@rucus.ru.ac.za"
  dst_src          = "cont1.lhx.teleglobe.net"

# dst_dst          = "ftp://ftp.rucus.ru.ac.za/pub/perl/CPAN/"
# dst_contact      = "mailto:webteam@rucus.ru.ac.za
# dst_src          = "cont1.lhx.teleglobe.net"

ftp.is.co.za:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.is.co.za/programming/perl/CPAN/"
  dst_location     = "Johannesburg, South Africa, Africa (-26.1992 28.0564)"
  dst_organisation = "Internet Solution"
  dst_timezone     = "+2"
  dst_contact      = "ftp-admin@is.co.za"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.is.co.za/programming/perl/CPAN/"
# dst_contact      = "mailto:ftp-admin@is.co.za
# dst_src          = "ftp.funet.fi"

ftp.saix.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.saix.net/pub/CPAN/"
  dst_location     = "Parow, Western Cape, South Africa, Africa (-33.9064 18.5631)"
  dst_organisation = "South African Internet eXchange (SAIX)"
  dst_timezone     = "+2"
  dst_bandwidth    = "T3"
  dst_contact      = "ftp@saix.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.saix.net/pub/CPAN/"
# dst_contact      = "mailto:ftp@saix.net
# dst_src          = "ftp.funet.fi"

ftp.sun.ac.za:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.sun.ac.za/CPAN/CPAN/"
  dst_location     = "Stellenbosch, South Africa, Africa (-26.1992 28.0564)"
  dst_organisation = "University of Stellenbosch"
  dst_timezone     = "+2"
  dst_contact      = "ftpadm@ftp.sun.ac.za"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.sun.ac.za/CPAN/CPAN/"
# dst_contact      = "mailto:ftpadm@ftp.sun.ac.za
# dst_src          = "ftp.funet.fi"

cpan.linuxforum.net:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.linuxforum.net/"
  dst_location     = "Beijing, Zhonghua, China, Asia (39.9118 116.3792)"
  dst_organisation = "China GNU/Linux Forum"
  dst_timezone     = "+8"
  dst_contact      = "mirror@linuxforum.net yusun@atwell.co.jp"
  dst_src          = "ftp.pacific.net.hk"

# dst_dst          = "http://cpan.linuxforum.net/"
# dst_contact      = "mailto:mirror@linuxforum.net yusun@atwell.co.jp
# dst_src          = "ftp.pacific.net.hk"

shellhung.org:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.shellhung.org/pub/CPAN"
  dst_http         = "http://cpan.shellhung.org/"
  dst_rsync        = "ftp.shellhung.org::CPAN"
  dst_location     = "Hong Kong, Xianggang, China, Asia (22.4438 114.0955)"
  dst_organisation = "Shell Hung"
  dst_timezone     = "+8"
  dst_contact      = "ftp@shellhung.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.shellhung.org/pub/CPAN"
# dst_contact      = "mailto:ftp@shellhung.org
# dst_src          = "ftp.funet.fi"

mirrors.hknet.com:
  frequency        = "daily"
  dst_ftp          = "ftp://mirrors.hknet.com/CPAN"
  dst_location     = "Hong Kong SAR, China, Asia (22.3866 114.124)"
  dst_organisation = "HKNet Company Limited"
  dst_timezone     = "+8"
  dst_bandwidth    = "200M"
  dst_contact      = "stephen@hknet.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirrors.hknet.com/CPAN"
# dst_contact      = "mailto:stephen@hknet.com
# dst_src          = "ftp.funet.fi"

mirrors.tf.itb.ac.id:
  frequency        = "weekly"
  dst_ftp          = ""
  dst_http         = "http://mirrors.tf.itb.ac.id/cpan/"
  dst_location     = "Bandung, West Java, Indonesia, Asia (-6.9161 107.615)"
  dst_organisation = "Engineering Physics Dept. - Institut Teknologi Bandung"
  dst_timezone     = "+7"
  dst_bandwidth    = "T1"
  dst_contact      = "fadly@tf.itb.ac.id"
  dst_src          = "ftp.ayamura.org"

# dst_dst          = "http://mirrors.tf.itb.ac.id/cpan/"
# dst_contact      = "mailto:fadly@tf.itb.ac.id
# dst_src          = "ftp.ayamura.org"

cpan.cbn.net.id:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.cbn.net.id/mirror/CPAN"
  dst_http         = "http://cpan.cbn.net.id/"
  dst_rsync        = "ftp.cbn.net.id::CPAN"
  dst_location     = "Jakarta, Indonesia, Asia (-6.133 106.750)"
  dst_organisation = "PT. Cyberindo Aditama"
  dst_timezone     = "+7"
  dst_contact      = "sysadm@cbn.net.id"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.cbn.net.id/mirror/CPAN"
# dst_contact      = "mailto:sysadm@cbn.net.id
# dst_src          = "ftp.funet.fi"

ftp.iglu.org.il:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.iglu.org.il/pub/CPAN/"
  dst_rsync        = "ftp.iglu.org.il::CPAN"
  dst_location     = "Haifa, Hefa, Mehoz, Israel, Asia (32.8153 34.989)"
  dst_organisation = "Israeli Group of Linux Users"
  dst_timezone     = "+2"
  dst_contact      = "mirrors@iglu.org.il"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.iglu.org.il/pub/CPAN/"
# dst_contact      = "mailto:mirrors@iglu.org.il
# dst_src          = "ftp.funet.fi"

cpan.lerner.co.il:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.lerner.co.il/"
  dst_location     = "Modi'in, Israel, Asia (31.783 35.233)"
  dst_organisation = "Lerner Communications Consulting"
  dst_timezone     = "+2"
  dst_bandwidth    = "Frame relay [ 56k ]"
  dst_contact      = "cpan@lerner.co.il"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://cpan.lerner.co.il/"
# dst_contact      = "mailto:cpan@lerner.co.il
# dst_src          = "ftp.funet.fi"

bioinfo.weizmann.ac.il:
  frequency        = "daily"
  dst_ftp          = "ftp://bioinfo.weizmann.ac.il/pub/software/perl/CPAN/"
  dst_http         = "http://bioinfo.weizmann.ac.il/pub/software/perl/CPAN/"
  dst_location     = "Rehovot, HaMerkaz, Mehoz, Israel, Asia (31.9008 34.8053)"
  dst_organisation = "Weizmann Institute of Science"
  dst_timezone     = "+2"
  dst_contact      = "ftpmaster@bioinfo.weizmann.ac.il"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://bioinfo.weizmann.ac.il/pub/software/perl/CPAN/"
# dst_contact      = "mailto:ftpmaster@bioinfo.weizmann.ac.il
# dst_src          = "ftp.funet.fi"

ftp.u-aizu.ac.jp:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.u-aizu.ac.jp/pub/CPAN"
  dst_location     = "Aizu-Wakamatsu, Tohoku-chiho, Fukushima, Japan, Asia (37.4333 139.9821)"
  dst_organisation = "University of Aizu"
  dst_timezone     = "+9"
  dst_bandwidth    = "T2(6Mbps)"
  dst_contact      = "ftp-admin@u-aizu.ac.jp"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.u-aizu.ac.jp/pub/CPAN"
# dst_contact      = "mailto:ftp-admin@u-aizu.ac.jp
# dst_src          = "ftp.funet.fi"

ftp.kddlabs.co.jp:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.kddlabs.co.jp/CPAN/"
  dst_rsync        = "ftp.kddlabs.co.jp::cpan"
  dst_location     = "Kamifukuoka, Kanto, Saitama-ken, Japan, Asia (35.8746 139.5304)"
  dst_organisation = "KDD R&D Labs, Inc."
  dst_timezone     = "+9"
  dst_contact      = "ftpadmin@kddlabs.co.jp"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.kddlabs.co.jp/CPAN/"
# dst_contact      = "mailto:ftpadmin@kddlabs.co.jp
# dst_src          = "ftp.funet.fi"

ftp.ayamura.org:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ayamura.org/pub/CPAN/"
  dst_rsync        = "ftp.ayamura.org::pub/CPAN/"
  dst_location     = "Shinagawa-ku, Tokyo, Japan, Asia (35.750 139.500)"
  dst_organisation = "AYAMURA"
  dst_timezone     = "+9"
  dst_bandwidth    = "OC3"
  dst_contact      = "ayamura@ayamura.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ayamura.org/pub/CPAN/"
# dst_contact      = "mailto:ayamura@ayamura.org
# dst_src          = "ftp.funet.fi"

ftp.jaist.ac.jp:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.jaist.ac.jp/pub/lang/perl/CPAN/"
  dst_location     = "Tatsunokuchi, Nomi, Ishikawa, Japan, Asia (36.4251 136.5739)"
  dst_organisation = "Japan Advanced Institute of Science and Technology"
  dst_timezone     = "+9"
  dst_contact      = "ftp-admin@jaist.ac.jp"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.jaist.ac.jp/pub/lang/perl/CPAN/"
# dst_contact      = "mailto:ftp-admin@jaist.ac.jp
# dst_src          = "ftp.funet.fi"

ftp.cpan.jp:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.cpan.jp/CPAN/"
  dst_http         = "http://ftp.cpan.jp/"
  dst_location     = "Tokyo, Shibuya-ward, Japan, Asia (35.667 139.700)"
  dst_organisation = "IFT Co., Ltd."
  dst_timezone     = "+9"
  dst_bandwidth    = "1Gbit"
  dst_contact      = "info@cpan.jp"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.cpan.jp/CPAN/"
# dst_contact      = "mailto:info@cpan.jp
# dst_src          = "ftp.funet.fi"

ftp.dti.ad.jp:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.dti.ad.jp/pub/lang/CPAN/"
  dst_location     = "Tokyo, Minato-ku, Japan, Asia (35.6754 139.7694)"
  dst_organisation = "Dream Train Internet Inc."
  dst_timezone     = "+9"
  dst_contact      = "ftp-admin@dti.ad.jp"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.dti.ad.jp/pub/lang/CPAN/"
# dst_contact      = "mailto:ftp-admin@dti.ad.jp
# dst_src          = "ftp.funet.fi"

ftp.ring.gr.jp:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ring.gr.jp/pub/lang/perl/CPAN/"
  dst_location     = "Tsukuba, Ibaraki, Kanto, Ibaraki-ken, Japan, Asia (36.2793 140.4408)"
  dst_organisation = "Ring Server Project"
  dst_timezone     = "+9"
  dst_contact      = "ftpadmin@ring.gr.jp"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ring.gr.jp/pub/lang/perl/CPAN/"
# dst_contact      = "mailto:ftpadmin@ring.gr.jp
# dst_src          = "ftp.funet.fi"

cpan.MyBSD.org.my:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.MyBSD.org.my"
  dst_location     = "Gombak, Selangor, Malaysia, Asia (3.2496 101.5496)"
  dst_organisation = "MyBSD Malaysia Project (http://www.MyBSD.org.my)"
  dst_timezone     = "+8"
  dst_bandwidth    = "T3"
  dst_contact      = "mirror-adm@MyBSD.org.my"
  dst_src          = "rsync.nic.funet.fi"
  dst_notes        = "The intention of this mirror is to serve for Malaysia and the South East Asia region."

# dst_dst          = "http://cpan.MyBSD.org.my"
# dst_contact      = "mailto:mirror-adm@MyBSD.org.my
# dst_src          = "rsync.nic.funet.fi"

mirror.leafbug.org:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://mirror.leafbug.org/pub/CPAN"
  dst_rsync        = "mirror.leafbug.org::CPAN"
  dst_location     = "Kuala Lumpur, Malaysia, Asia (3.167 101.700)"
  dst_organisation = "Leafbug Opensource Research Group"
  dst_timezone     = "+8"
  dst_bandwidth    = "T1"
  dst_contact      = "sysadmin@leafbug.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://mirror.leafbug.org/pub/CPAN"
# dst_contact      = "mailto:sysadmin@leafbug.org
# dst_src          = "ftp.funet.fi"

ossig.mncc.com.my:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://ossig.mncc.com.my/mirror/pub/CPAN"
  dst_location     = "Kuala Lumpur, Malaysia, Asia (3.8 101.42)"
  dst_organisation = "Malaysian National Computer Confederation"
  dst_timezone     = "+8"
  dst_bandwidth    = "T1"
  dst_contact      = "admin@mncc.com.my"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://ossig.mncc.com.my/mirror/pub/CPAN"
# dst_contact      = "mailto:admin@mncc.com.my
# dst_src          = "ftp.funet.fi"

cpan.tomsk.ru:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.tomsk.ru/"
  dst_http         = "http://cpan.tomsk.ru"
  dst_location     = "Tomsk, Siberia, Russian Federation, Asia (56.5 84.9667)"
  dst_organisation = "TLUG"
  dst_timezone     = "+7"
  dst_bandwidth    = "T2"
  dst_contact      = "andrew@grob.ru"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://cpan.tomsk.ru/"
# dst_contact      = "mailto:andrew@grob.ru
# dst_src          = "ftp.cpan.org"

ftp.isu.net.sa:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.isu.net.sa/pub/CPAN/"
  dst_location     = "Riyadh, al-Wusta, Saudi Arabia, Asia (24.6439 46.7406)"
  dst_organisation = "King Abdulaziz City for Science and Technology / Internet Services Unit"
  dst_timezone     = "+3"
  dst_contact      = "mirrors@isu.net.sa"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://ftp.isu.net.sa/pub/CPAN/"
# dst_contact      = "mailto:mirrors@isu.net.sa
# dst_src          = "ftp.cpan.org"

cpan.en.com.sg:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.en.com.sg/"
  dst_http         = "http://CPAN.en.com.sg/"
  dst_rsync        = "rsync.en.com.sg::CPAN"
  dst_location     = "Singapore, Singapore, Asia (1.283 103.85)"
  dst_organisation = "EN Singapore"
  dst_timezone     = "+8"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "slash@en.com.sg"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "ftp://cpan.en.com.sg/"
# dst_contact      = "mailto:slash@en.com.sg
# dst_src          = "rsync.nic.funet.fi"

mirror.averse.net:
  frequency        = "daily"
  dst_ftp          = "ftp://mirror.averse.net/pub/CPAN"
  dst_http         = "http://mirror.averse.net/pub/CPAN"
  dst_rsync        = "mirror.averse.net::cpan"
  dst_location     = "Singapore, Singapore, Asia (1.283 103.85)"
  dst_organisation = "averse.net"
  dst_timezone     = "+8"
  dst_bandwidth    = "T3"
  dst_contact      = "mirror-maintainer@mirror.averse.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirror.averse.net/pub/CPAN"
# dst_contact      = "mailto:mirror-maintainer@mirror.averse.net
# dst_src          = "ftp.funet.fi"

www.oss.eznetsols.org:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.oss.eznetsols.org/cpan"
  dst_http         = "http://cpan.oss.eznetsols.org"
  dst_rsync        = "rsync.oss.eznetsols.org"
  dst_location     = "Singapore, Singapore, Asia (1.283 103.85)"
  dst_organisation = "ezNetworking Solutions Pte Ltd"
  dst_timezone     = "+8"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "noc@eznetsols.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.oss.eznetsols.org/cpan"
# dst_contact      = "mailto:noc@eznetsols.com
# dst_src          = "ftp.funet.fi"

ftp.bora.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.bora.net/pub/CPAN/"
  dst_http         = "http://CPAN.bora.net/"
  dst_location     = "Seoul, South Korea, Asia (37.5631 126.9769)"
  dst_organisation = "Dacom Corporation"
  dst_timezone     = "+9"
  dst_contact      = "ftpadm@bora.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.bora.net/pub/CPAN/"
# dst_contact      = "mailto:ftpadm@bora.net
# dst_src          = "ftp.funet.fi"

ftp.kr.FreeBSD.org:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.kr.FreeBSD.org/pub/CPAN"
  dst_http         = "http://mirror.kr.FreeBSD.org/CPAN"
  dst_rsync        = "ftp.kr.FreeBSD.org::CPAN"
  dst_location     = "Seoul, South Korea, Asia (37.56 126.98)"
  dst_organisation = "Korea FreeBSD Users Group"
  dst_timezone     = "+9"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "admin@kr.FreeBSD.org"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "ftp://ftp.kr.FreeBSD.org/pub/CPAN"
# dst_contact      = "mailto:admin@kr.FreeBSD.org
# dst_src          = "rsync.nic.funet.fi"

ftp.nctu.edu.tw:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.nctu.edu.tw/UNIX/perl/CPAN"
  dst_location     = "HsinChu, Taiwan, Asia (24.4719 120.5950)"
  dst_organisation = "National Chiao Tung University"
  dst_timezone     = "+8"
  dst_contact      = "ftpadm@ftp.nctu.edu.tw"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.nctu.edu.tw/UNIX/perl/CPAN"
# dst_contact      = "mailto:ftpadm@ftp.nctu.edu.tw
# dst_src          = "ftp.funet.fi"

cpan.cdpa.nsysu.edu.tw:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.cdpa.nsysu.edu.tw/pub/CPAN"
  dst_http         = "http://cpan.cdpa.nsysu.edu.tw/"
  dst_rsync        = "cpan.cdpa.nsysu.edu.tw::CPAN"
  dst_location     = "Kao-hsiung, Taiwan, Asia (22.38 120.17)"
  dst_organisation = "CDPA National Sun Yat-Sen University"
  dst_timezone     = "+8"
  dst_bandwidth    = "GBE"
  dst_contact      = "tjs@cdpa.nsysu.edu.tw"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.cdpa.nsysu.edu.tw/pub/CPAN"
# dst_contact      = "mailto:tjs@cdpa.nsysu.edu.tw
# dst_src          = "ftp.funet.fi"

ftp.isu.edu.tw:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.isu.edu.tw/pub/CPAN"
  dst_http         = "http://ftp.isu.edu.tw/pub/CPAN"
  dst_location     = "Kao-hsiung, Taiwan, Asia (22.600 120.283)"
  dst_organisation = "I-SHOU University"
  dst_timezone     = "+8"
  dst_bandwidth    = "GBE"
  dst_contact      = "ftpadm@ftp.isu.edu.tw"
  dst_src          = "ftp.isu.edu.tw"

# dst_dst          = "ftp://ftp.isu.edu.tw/pub/CPAN"
# dst_contact      = "mailto:ftpadm@ftp.isu.edu.tw
# dst_src          = "ftp.isu.edu.tw"

ftp1.sinica.edu.tw:
  frequency        = "weekly"
  dst_ftp          = "ftp://ftp1.sinica.edu.tw/pub1/perl/CPAN/"
  dst_location     = "Taipei, Taiwan, Asia (25.0439 121.4972)"
  dst_organisation = "Academia Sinica Computing Centre"
  dst_timezone     = "+8"
  dst_contact      = "tyuan@sinica.edu.tw"
  dst_src          = "ftp.perl.org"

# dst_dst          = "ftp://ftp1.sinica.edu.tw/pub1/perl/CPAN/"
# dst_contact      = "mailto:tyuan@sinica.edu.tw
# dst_src          = "ftp.perl.org"

ftp.tku.edu.tw:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.tku.edu.tw/pub/CPAN/"
  dst_http         = "http://ftp.tku.edu.tw/pub/CPAN/"
  dst_location     = "TamSui, T'ai-pei Hsien, Taiwan, Asia (25.217 121.483)"
  dst_organisation = "TamKang University"
  dst_timezone     = "+8"
  dst_bandwidth    = "T3"
  dst_contact      = "tkuftp@ftp.tku.edu.tw"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.tku.edu.tw/pub/CPAN/"
# dst_contact      = "mailto:tkuftp@ftp.tku.edu.tw
# dst_src          = "ftp.funet.fi"

ftp.loxinfo.co.th:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.loxinfo.co.th/pub/cpan/"
  dst_location     = "Bangkok, Thailand, Asia (13.733 100.500)"
  dst_organisation = "Loxley Information Services Co., Ltd."
  dst_timezone     = "+7"
  dst_bandwidth    = "T3"
  dst_contact      = "sysadmin@loxinfo.co.th"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.loxinfo.co.th/pub/cpan/"
# dst_contact      = "mailto:sysadmin@loxinfo.co.th
# dst_src          = "ftp.funet.fi"

ftp.cs.riubon.ac.th:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.cs.riubon.ac.th/pub/mirrors/CPAN/"
  dst_location     = "Ubon Ratchathani, Thailand, Asia (15.2342 104.8636)"
  dst_organisation = "Rajabhat Institute Ubonratchathani"
  dst_timezone     = "+7"
  dst_contact      = "admin@cs.riubon.ac.th"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.cs.riubon.ac.th/pub/mirrors/CPAN/"
# dst_contact      = "mailto:admin@cs.riubon.ac.th
# dst_src          = "ftp.funet.fi"

ftp.ucr.ac.cr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ucr.ac.cr/pub/Unix/CPAN/"
  dst_http         = "http://ftp.ucr.ac.cr/Unix/CPAN/"
  dst_location     = "San Jose, Costa Rica, Central America (9.93 -84.079)"
  dst_organisation = "Centro de Informatica, Universidad de Costa Rica (Computing Center, University of Costa Rica)"
  dst_timezone     = "-6"
  dst_contact      = "mguerra@ns.ucr.ac.cr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ucr.ac.cr/pub/Unix/CPAN/"
# dst_contact      = "mailto:mguerra@ns.ucr.ac.cr
# dst_src          = "ftp.funet.fi"

ftp.tuwien.ac.at:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.tuwien.ac.at/pub/CPAN/"
  dst_location     = "Vienna, Austria, Europe (48.20234 16.36958)"
  dst_organisation = "Technische Universität Wien (Vienna University of Technology)"
  dst_timezone     = "+2"
  dst_bandwidth    = "T1"
  dst_contact      = "Antonin.Sprinzl@tuwien.ac.at"
  dst_src          = "ftp.funet.fi"
  dst_notes        = "a.k.a. at.cpan.org"

# dst_dst          = "ftp://ftp.tuwien.ac.at/pub/CPAN/"
# dst_contact      = "mailto:Antonin.Sprinzl@tuwien.ac.at
# dst_src          = "ftp.funet.fi"

ftp.easynet.be:
  frequency        = "twice daily"
  dst_ftp          = "ftp://ftp.easynet.be/pub/CPAN/"
  dst_http         = "http://ftp.easynet.be/pub/CPAN/"
  dst_location     = "Brussels, Belgium, Europe (50.50 4.20)"
  dst_organisation = "Easynet Belgium SA/NV; Part of Easynet Group"
  dst_timezone     = "+1"
  dst_bandwidth    = "OC3"
  dst_contact      = "ftp@be.easynet.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.easynet.be/pub/CPAN/"
# dst_contact      = "mailto:ftp@be.easynet.net
# dst_src          = "ftp.funet.fi"

ftp.skynet.be:
  frequency        = "hourly"
  dst_ftp          = "ftp://ftp.cpan.skynet.be/pub/CPAN"
  dst_http         = "http://cpan.skynet.be"
  dst_location     = "Brussels, Belgium, Europe (50.833 4.333)"
  dst_organisation = "Belgacom Skynet S.A."
  dst_timezone     = "+1"
  dst_bandwidth    = "T3"
  dst_contact      = "ftp@skynet.be"
  dst_src          = "ftp.funet.fi"
  dst_notes        = "other contact: cedric.gavage@skynet.be"

# dst_dst          = "ftp://ftp.cpan.skynet.be/pub/CPAN"
# dst_contact      = "mailto:ftp@skynet.be
# dst_src          = "ftp.funet.fi"

ftp.kulnet.kuleuven.ac.be:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.kulnet.kuleuven.ac.be/pub/mirror/CPAN/"
  dst_location     = "Leuven, Vlaanderen, Belgium, Europe (50.8793 4.70333)"
  dst_organisation = "Katholieke Universiteit Leuven (The Catholic University of Leuven)"
  dst_timezone     = "+1"
  dst_contact      = "operations@kulnet.kuleuven.ac.be"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.kulnet.kuleuven.ac.be/pub/mirror/CPAN/"
# dst_contact      = "mailto:operations@kulnet.kuleuven.ac.be
# dst_src          = "ftp.funet.fi"

cpan.blic.net:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.blic.net/"
  dst_location     = "Banja Luka, Bosnia and Herzegovina, Europe (44.776 17.186)"
  dst_organisation = "BLIC.NET ISP"
  dst_timezone     = "+1"
  dst_bandwidth    = "10Mbps"
  dst_contact      = "pmalic@blic.net"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "http://cpan.blic.net/"
# dst_contact      = "mailto:pmalic@blic.net
# dst_src          = "rsync.nic.funet.fi"

cpan.online.bg:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.online.bg/cpan"
  dst_http         = "http://cpan.online.bg"
  dst_location     = "Sofia, Bulgaria, Europe (42.667 23.300)"
  dst_organisation = "Bulgaria Online PLC"
  dst_timezone     = "+2"
  dst_bandwidth    = "T1"
  dst_contact      = "support@online.bg"
  dst_src          = "ftp.funet.fi"
  dst_notes        = "The mirror is intended to mainly serve domestic visitors due to company's excellent local connectivity. The mirror is a part of a project named mirrors.online.bg, which now includes also PHP and MySQL mirrors."

# dst_dst          = "ftp://cpan.online.bg/cpan"
# dst_contact      = "mailto:support@online.bg
# dst_src          = "ftp.funet.fi"

cpan.zadnik.org:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.zadnik.org/mirrors/CPAN/"
  dst_http         = "http://cpan.zadnik.org"
  dst_location     = "Sofia, Bulgaria, Europe (42.39 23.22)"
  dst_organisation = "zadnik.org"
  dst_timezone     = "+2"
  dst_bandwidth    = "T1"
  dst_contact      = "velin@zadnik.org"
  dst_src          = "ftp.gwdg.de"

# dst_dst          = "ftp://ftp.zadnik.org/mirrors/CPAN/"
# dst_contact      = "mailto:velin@zadnik.org
# dst_src          = "ftp.gwdg.de"

ftp.lirex.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.lirex.net/pub/mirrors/CPAN"
  dst_http         = "http://cpan.lirex.net/"
  dst_location     = "Sofia, Sofiya-Grad, Bulgaria, Europe (42.6864 23.334)"
  dst_organisation = "Naturella Agency"
  dst_timezone     = "+2"
  dst_contact      = "delian@lirex.bg"
  dst_src          = "ftp.perl.org"

# dst_dst          = "ftp://ftp.lirex.net/pub/mirrors/CPAN"
# dst_contact      = "mailto:delian@lirex.bg
# dst_src          = "ftp.perl.org"

ftp.linux.hr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.linux.hr/pub/CPAN/"
  dst_http         = "http://ftp.linux.hr/pub/CPAN/"
  dst_location     = "Rijeka, Croatia, Europe (45.333 14.450)"
  dst_organisation = "HULK (Croatian Linux Users Group)"
  dst_timezone     = "+1/+2"
  dst_bandwidth    = "100Mbit"
  dst_contact      = "ftpadmin@linux.hr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.linux.hr/pub/CPAN/"
# dst_contact      = "mailto:ftpadmin@linux.hr
# dst_src          = "ftp.funet.fi"

ftp.fi.muni.cz:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.fi.muni.cz/pub/CPAN/"
  dst_location     = "Brno, Jihomoravsky´, Czech Republic, Europe (49.1942 16.6085)"
  dst_organisation = "Fakulta Informatiky Masarykovy Univerzity (Faculty of Informatics, Masaryk University)"
  dst_timezone     = "+1"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "ftp-admin@fi.muni.cz"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.fi.muni.cz/pub/CPAN/"
# dst_contact      = "mailto:ftp-admin@fi.muni.cz
# dst_src          = "ftp.funet.fi"

sunsite.mff.cuni.cz:
  frequency        = "daily"
  dst_ftp          = "ftp://sunsite.mff.cuni.cz/MIRRORS/ftp.funet.fi/pub/languages/perl/CPAN/"
  dst_location     = "Prague, Stredocesky´, Czech Republic, Europe (50.0703 14.445)"
  dst_organisation = "Matematicko-fyzikalni fakulty Univerzity Karlovy (Faculty of Mathematics and Physics, Charles University of Prague)"
  dst_timezone     = "+1"
  dst_contact      = "ftpadm@sunsite.mff.cuni.cz"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://sunsite.mff.cuni.cz/MIRRORS/ftp.funet.fi/pub/languages/perl/CPAN/"
# dst_contact      = "mailto:ftpadm@sunsite.mff.cuni.cz
# dst_src          = "ftp.funet.fi"

sunsite.dk:
  frequency        = "daily"
  dst_ftp          = "ftp://sunsite.dk/mirrors/cpan/"
  dst_http         = "http://mirrors.sunsite.dk/cpan/"
  dst_location     = "Aalborg, Denmark, Europe (57.04923 9.91623)"
  dst_organisation = "SunSITE.dk"
  dst_timezone     = "+1"
  dst_contact      = "mirror@sunsite.dk"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://sunsite.dk/mirrors/cpan/"
# dst_contact      = "mailto:mirror@sunsite.dk
# dst_src          = "ftp.funet.fi"

cpan.cybercity.dk:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.cybercity.dk"
  dst_location     = "Copenhagen, Denmark, Europe (55.68748 12.59118)"
  dst_organisation = "Cybercity"
  dst_timezone     = "+1"
  dst_bandwidth    = "STM-4"
  dst_contact      = "jdn@cybercity.dk"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://cpan.cybercity.dk"
# dst_contact      = "mailto:jdn@cybercity.dk
# dst_src          = "ftp.funet.fi"

www.cpan.dk:
  frequency        = "daily"
  dst_ftp          = "ftp://www.cpan.dk/ftp.cpan.org/CPAN/"
  dst_http         = "http://www.cpan.dk/CPAN/"
  dst_location     = "Copenhagen, Denmark, Europe (55.67621 12.56951)"
  dst_organisation = "World Online Denmark A/S"
  dst_timezone     = "+1"
  dst_bandwidth    = "OC3"
  dst_contact      = "apj@wol.dk"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://www.cpan.dk/ftp.cpan.org/CPAN/"
# dst_contact      = "mailto:apj@wol.dk
# dst_src          = "ftp.funet.fi"

ftp.ut.ee:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ut.ee/pub/languages/perl/CPAN/"
  dst_location     = "Tartu, Estonia, Europe (58.3711 26.7206)"
  dst_organisation = "Tartu Ülikool (Tartu University)"
  dst_timezone     = "+2"
  dst_contact      = "ftp-service@ut.ee"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ut.ee/pub/languages/perl/CPAN/"
# dst_contact      = "mailto:ftp-service@ut.ee
# dst_src          = "ftp.funet.fi"

ftp.funet.fi:
  frequency        = "hourly"
  dst_ftp          = "ftp://ftp.funet.fi/pub/languages/perl/CPAN/"
  dst_rsync        = "rsync.nic.funet.fi::CPAN"
  dst_location     = "Espoo, Etelä-Suomen Lääni, Finland, Europe (60.2099 24.6568)"
  dst_organisation = "Finnish University NETwork"
  dst_timezone     = "+2"
  dst_contact      = "cpan@perl.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.funet.fi/pub/languages/perl/CPAN/"
# dst_contact      = "mailto:cpan@perl.org
# dst_src          = "ftp.funet.fi"

mirror.eunet.fi:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://mirror.eunet.fi/CPAN"
  dst_location     = "Helsinki, Etelä-Suomen Lääni, Finland, Europe (60.2099 24.6568)"
  dst_organisation = "Eunet Finland"
  dst_timezone     = "+2"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "helpdesk@eunet.fi"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://mirror.eunet.fi/CPAN"
# dst_contact      = "mailto:helpdesk@eunet.fi
# dst_src          = "ftp.funet.fi"

www.enstimac.fr:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://www.enstimac.fr/Perl/CPAN"
  dst_location     = "Albi, France, Europe (43.933 2.133)"
  dst_organisation = "Ecole des Mines d'Albi-Carmaux"
  dst_timezone     = "+1"
  dst_bandwidth    = "T1"
  dst_contact      = "paul.gaborit@enstimac.fr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://www.enstimac.fr/Perl/CPAN"
# dst_contact      = "mailto:paul.gaborit@enstimac.fr
# dst_src          = "ftp.funet.fi"

ftp.u-paris10.fr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.u-paris10.fr/perl/CPAN"
  dst_http         = "http://ftp.u-paris10.fr/perl/CPAN"
  dst_rsync        = "ftp.u-paris10.fr::CPAN"
  dst_location     = "Nanterre, Hauts de Seine, France, Europe (48.905 2.21)"
  dst_organisation = "Universitie Paris 10"
  dst_timezone     = "+1"
  dst_bandwidth    = "34Mo"
  dst_contact      = "ftpmaster@u-paris10.fr"
  dst_src          = "ftp.sunet.se"

# dst_dst          = "ftp://ftp.u-paris10.fr/perl/CPAN"
# dst_contact      = "mailto:ftpmaster@u-paris10.fr
# dst_src          = "ftp.sunet.se"

cpan.mirrors.easynet.fr:
  frequency        = "weekly"
  dst_ftp          = "ftp://cpan.mirrors.easynet.fr/pub/ftp.cpan.org/"
  dst_http         = "http://cpan.mirrors.easynet.fr/"
  dst_location     = "Paris, Ile-de-France, France, Europe (48.85424 2.34486)"
  dst_organisation = "Easynet France SA, Part of Easynet Group"
  dst_timezone     = "+1"
  dst_bandwidth    = "OC3"
  dst_contact      = "ftpmaster@easynet.fr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.mirrors.easynet.fr/pub/ftp.cpan.org/"
# dst_contact      = "mailto:ftpmaster@easynet.fr
# dst_src          = "ftp.funet.fi"

ftp.club-internet.fr:
  frequency        = "twice daily"
  dst_ftp          = "ftp://ftp.club-internet.fr/pub/perl/CPAN/"
  dst_location     = "Paris, Ile-de-France, France, Europe (48.85424 2.34486)"
  dst_organisation = "Club Internet / T-Online France"
  dst_timezone     = "+1"
  dst_contact      = "ftpmaster@t-online.fr"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://ftp.club-internet.fr/pub/perl/CPAN/"
# dst_contact      = "mailto:ftpmaster@t-online.fr
# dst_src          = "ftp.cpan.org"

ftp.lip6.fr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.lip6.fr/pub/perl/CPAN/"
  dst_http         = "http://fr.cpan.org/"
  dst_location     = "Paris, Ile-de-France, France, Europe (48.85424 2.34486)"
  dst_organisation = "Laboratoire d'Informatique de Paris 6 (Informatics Laboratory of Paris 6)"
  dst_timezone     = "+1"
  dst_contact      = "ftpmaint@lip6.fr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.lip6.fr/pub/perl/CPAN/"
# dst_contact      = "mailto:ftpmaint@lip6.fr
# dst_src          = "ftp.funet.fi"

ftp.oleane.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.oleane.net/pub/mirrors/CPAN/"
  dst_location     = "Paris, Ile-de-France, France, Europe (48.85424 2.34486)"
  dst_organisation = "France Telecom Transpac"
  dst_timezone     = "+1"
  dst_contact      = "ftpmaint@oleane.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.oleane.net/pub/mirrors/CPAN/"
# dst_contact      = "mailto:ftpmaint@oleane.net
# dst_src          = "ftp.funet.fi"

ftp.pasteur.fr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.pasteur.fr/pub/computing/CPAN/"
  dst_location     = "Paris, Ile-de-France, France, Europe (48.85424 2.34486)"
  dst_organisation = "l'Institut Pasteur (Pasteur Institute)"
  dst_timezone     = "+1"
  dst_bandwidth    = "E1"
  dst_contact      = "ftpmaint@pasteur.fr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.pasteur.fr/pub/computing/CPAN/"
# dst_contact      = "mailto:ftpmaint@pasteur.fr
# dst_src          = "ftp.funet.fi"

mir2.ovh.net:
  frequency        = "daily"
  dst_ftp          = "ftp://mir1.ovh.net/ftp.cpan.org"
  dst_http         = "http://mir2.ovh.net/ftp.cpan.org"
  dst_rsync        = "mir1.ovh.net::CPAN"
  dst_location     = "Paris, Ile-de-France, France, Europe (48.867 2.333)"
  dst_organisation = "OVH"
  dst_timezone     = "+1"
  dst_bandwidth    = "200Mbs"
  dst_contact      = "oles@ovh.net"
  dst_src          = "cpan.teleglobe.net"

# dst_dst          = "ftp://mir1.ovh.net/ftp.cpan.org"
# dst_contact      = "mailto:oles@ovh.net
# dst_src          = "cpan.teleglobe.net"

ftp.crihan.fr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.crihan.fr/mirrors/ftp.cpan.org/"
  dst_http         = "http://ftp.crihan.fr/mirrors/ftp.cpan.org/"
  dst_rsync        = "rsync://ftp.crihan.fr::CPAN"
  dst_location     = "Rouen, France, Europe (49.26 1.05)"
  dst_organisation = "Centre de Ressources Informatiques de Haute-Normandie (CRIHAN)"
  dst_timezone     = "+1"
  dst_bandwidth    = "100Mbit"
  dst_contact      = "ab@crihan.fr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.crihan.fr/mirrors/ftp.cpan.org/"
# dst_contact      = "mailto:ab@crihan.fr
# dst_src          = "ftp.funet.fi"

ftp.u-strasbg.fr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.u-strasbg.fr/CPAN"
  dst_http         = "http://ftp.u-strasbg.fr/CPAN"
  dst_location     = "Strasbourg, France, Europe (48.583 7.750)"
  dst_organisation = "ULP"
  dst_timezone     = "+1"
  dst_bandwidth    = "T3+"
  dst_contact      = "ftpmaint@ftp.u-strasbg.fr"
  dst_src          = "ftp.lip6.fr"

# dst_dst          = "ftp://ftp.u-strasbg.fr/CPAN"
# dst_contact      = "mailto:ftpmaint@ftp.u-strasbg.fr
# dst_src          = "ftp.lip6.fr"

cpan.cict.fr:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.cict.fr/pub/CPAN/"
  dst_location     = "Toulouse, Midi-Pyrénées, France, Europe (43.60385 1.44305)"
  dst_organisation = "Centre Interuniversitaire de Calcul de Toulouse (Université Paul Sabatier); Academic Computing Centre"
  dst_timezone     = "+1"
  dst_bandwidth    = "T1"
  dst_contact      = "baque@cict.fr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.cict.fr/pub/CPAN/"
# dst_contact      = "mailto:baque@cict.fr
# dst_src          = "ftp.funet.fi"

ftp.uvsq.fr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.uvsq.fr/pub/perl/CPAN/"
  dst_location     = "Versailles, Ile-de-France, France, Europe (48.80187 2.13139)"
  dst_organisation = "Universite de Versailles Saint-Quentin en Yvelines (University of Versailles Saint-Quentin en Yvelines)"
  dst_timezone     = "+1"
  dst_contact      = "ftpmaint@uvsq.fr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.uvsq.fr/pub/perl/CPAN/"
# dst_contact      = "mailto:ftpmaint@uvsq.fr
# dst_src          = "ftp.funet.fi"

ftp.rub.de:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.rub.de/pub/CPAN/"
  dst_location     = "Bochum, Nordrhein-Westfalen, Germany, Europe (51.47909 7.22223)"
  dst_organisation = "Die Ruhr-Universität Bochum (Ruhr-University at Bochum)"
  dst_timezone     = "+1"
  dst_bandwidth    = "OC3"
  dst_contact      = "ftp-bugs@rub.de"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.rub.de/pub/CPAN/"
# dst_contact      = "mailto:ftp-bugs@rub.de
# dst_src          = "ftp.funet.fi"

ftp.freenet.de:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.freenet.de/pub/ftp.cpan.org/pub/CPAN/"
  dst_location     = "Düsseldorf, Nordrhein-Westfalen, Germany, Europe (51.2264 6.77679)"
  dst_organisation = "freenet.de AG"
  dst_timezone     = "+1"
  dst_bandwidth    = "OC-48"
  dst_contact      = "ftpmaster@freenet.de"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://ftp.freenet.de/pub/ftp.cpan.org/pub/CPAN/"
# dst_contact      = "mailto:ftpmaster@freenet.de
# dst_src          = "ftp.cpan.org"

ftp.uni-erlangen.de:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.uni-erlangen.de/pub/source/CPAN/"
  dst_location     = "Erlangen, Bayern, Germany, Europe (49.59792 11.00329)"
  dst_organisation = "Friedrich Alexander Universität Erlangen-Nürnberg (Friedrich Alexander University of Erlangen-Nürnberg)"
  dst_timezone     = "+1"
  dst_contact      = "ftpsrc@rrze.uni-erlangen.de"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.uni-erlangen.de/pub/source/CPAN/"
# dst_contact      = "mailto:ftpsrc@rrze.uni-erlangen.de
# dst_src          = "ftp.funet.fi"

ftp-stud.fht-esslingen.de:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp-stud.fht-esslingen.de/pub/Mirrors/CPAN"
  dst_location     = "Esslingen am Neckar, Baden-Württemberg, Germany, Europe (48.45 9.16)"
  dst_organisation = "Rechenzentrum, Fachhochschule Esslingen, Hochschule für Technik (Computing Center, University of Applied Sciences)"
  dst_timezone     = "+1"
  dst_contact      = "webmaster@www.fht-esslingen.de"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp-stud.fht-esslingen.de/pub/Mirrors/CPAN"
# dst_contact      = "mailto:webmaster@www.fht-esslingen.de
# dst_src          = "ftp.funet.fi"

pandemonium.tiscali.de:
  frequency        = "daily"
  dst_ftp          = "ftp://pandemonium.tiscali.de/pub/CPAN/"
  dst_http         = "http://pandemonium.tiscali.de/pub/CPAN/"
  dst_location     = "Frankfurt am Main, Hessen, Germany, Europe (50.120509 8.73574)"
  dst_organisation = "Tiscali"
  dst_timezone     = "+1"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "reflector@nacamar.de"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://pandemonium.tiscali.de/pub/CPAN/"
# dst_contact      = "mailto:reflector@nacamar.de
# dst_src          = "ftp.funet.fi"

ftp.gwdg.de:
  frequency        = "twice daily"
  dst_ftp          = "ftp://ftp.gwdg.de/pub/languages/perl/CPAN/"
  dst_http         = "http://ftp.gwdg.de/pub/languages/perl/CPAN/"
  dst_rsync        = "ftp.gwdg.de::FTP/languages/perl/CPAN/"
  dst_location     = "Göttingen, Niedersachsen, Germany, Europe (51.53098 9.93825)"
  dst_organisation = "Gesellschaft für wissenschaftliche Datenverarbeitung (Society for Scientific Data Processing)"
  dst_timezone     = "+1"
  dst_contact      = "emoenke@gwdg.de"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.gwdg.de/pub/languages/perl/CPAN/"
# dst_contact      = "mailto:emoenke@gwdg.de
# dst_src          = "ftp.funet.fi"

ftp.uni-hamburg.de:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.uni-hamburg.de/pub/soft/lang/perl/CPAN/"
  dst_location     = "Hamburg, Germany, Europe (53.55453 9.9903)"
  dst_organisation = "Universität Hamburg (University of Hamburg)"
  dst_timezone     = "+1"
  dst_contact      = "ftpadmin@ftp.uni-hamburg.de"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.uni-hamburg.de/pub/soft/lang/perl/CPAN/"
# dst_contact      = "mailto:ftpadmin@ftp.uni-hamburg.de
# dst_src          = "ftp.funet.fi"

ftp.leo.org:
  frequency        = "hourly"
  dst_ftp          = "ftp://ftp.leo.org/pub/CPAN/"
  dst_rsync        = "ftp.leo.org::CPAN"
  dst_location     = "Munich, Bayern, Germany, Europe (48.13333 11.57138)"
  dst_organisation = "Link Everything Online"
  dst_timezone     = "+1"
  dst_bandwidth    = "OC-12"
  dst_contact      = "leo-admin@leo.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.leo.org/pub/CPAN/"
# dst_contact      = "mailto:leo-admin@leo.org
# dst_src          = "ftp.funet.fi"

cpan.noris.de:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.noris.de/pub/CPAN/"
  dst_http         = "http://cpan.noris.de/"
  dst_location     = "Nuremburg, Bavaria, Germany, Europe (49.4541 11.0634)"
  dst_organisation = "Noris Network AG"
  dst_timezone     = "+1"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "cpan@noris.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.noris.de/pub/CPAN/"
# dst_contact      = "mailto:cpan@noris.net
# dst_src          = "ftp.funet.fi"

ftp.mpi-sb.mpg.de:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.mpi-sb.mpg.de/pub/perl/CPAN/"
  dst_location     = "Saarbrücken, Saarland, Germany, Europe (49.23109 6.99801)"
  dst_organisation = "Max-Planck-Institut für Informatik (Max-Planck Institute for Information Science)"
  dst_timezone     = "+1"
  dst_contact      = "ftpadmin@mpi-sb.mpg.de"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.mpi-sb.mpg.de/pub/perl/CPAN/"
# dst_contact      = "mailto:ftpadmin@mpi-sb.mpg.de
# dst_src          = "ftp.funet.fi"

ftp.gmd.de:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.gmd.de/mirrors/CPAN/"
  dst_location     = "Sankt Augustin, Nordrhein-Westfalen, Germany, Europe (50.77667 7.18528)"
  dst_organisation = "GMD - Forschungszentrum Informationstechnik GmbH"
  dst_timezone     = "+1"
  dst_bandwidth    = "155Mbps"
  dst_contact      = "ftpmaster@gmd.de"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.gmd.de/mirrors/CPAN/"
# dst_contact      = "mailto:ftpmaster@gmd.de
# dst_src          = "ftp.funet.fi"

ftp.acn.gr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.acn.gr/pub/lang/perl"
  dst_location     = "Athens, Greece, Europe (38.000 23.733)"
  dst_organisation = "ACN S.A."
  dst_timezone     = "+2"
  dst_bandwidth    = "T1"
  dst_contact      = "ftpmaster@hq.acn.gr"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://ftp.acn.gr/pub/lang/perl"
# dst_contact      = "mailto:ftpmaster@hq.acn.gr
# dst_src          = "ftp.cpan.org"

ftp.forthnet.gr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.forthnet.gr/pub/languages/perl/CPAN"
  dst_location     = "Athens, Greece, Europe (37.97 23.72)"
  dst_organisation = "Hellenic Telecommunications & Telematics Applications Company"
  dst_timezone     = "+2"
  dst_bandwidth    = "T1"
  dst_contact      = "ftpadmin@forthnet.gr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.forthnet.gr/pub/languages/perl/CPAN"
# dst_contact      = "mailto:ftpadmin@forthnet.gr
# dst_src          = "ftp.funet.fi"

ftp.ntua.gr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ntua.gr/pub/lang/perl/"
  dst_location     = "Athens, Greece, Europe (37.97 23.72)"
  dst_organisation = "Ethnikon Metsovion Polytechnion (National Technical University of Athens)"
  dst_timezone     = "+2"
  dst_contact      = "ftpadm@ntua.gr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ntua.gr/pub/lang/perl/"
# dst_contact      = "mailto:ftpadm@ntua.gr
# dst_src          = "ftp.funet.fi"

ftp.kfki.hu:
  frequency        = "weekly"
  dst_ftp          = "ftp://ftp.kfki.hu/pub/packages/perl/CPAN/"
  dst_http         = "http://ftp.kfki.hu/packages/perl/CPAN/"
  dst_location     = "Budapest, Hungary, Europe (47.5105 19.0711)"
  dst_organisation = "Központi Fizikai Kutató Intézet (Central Research Institute for Physics)"
  dst_timezone     = "+1"
  dst_bandwidth    = "155Mbps"
  dst_contact      = "ftpadm@sunserv.kfki.hu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.kfki.hu/pub/packages/perl/CPAN/"
# dst_contact      = "mailto:ftpadm@sunserv.kfki.hu
# dst_src          = "ftp.funet.fi"

ftp.rhnet.is:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.rhnet.is/pub/CPAN/"
  dst_http         = "http://ftp.rhnet.is/pub/CPAN/"
  dst_location     = "Reykjavik, Iceland, Europe (64.1333 -21.95)"
  dst_organisation = "Icelandic University Research Network"
  dst_timezone     = "0"
  dst_bandwidth    = "T3"
  dst_contact      = "ftpadm@rhnet.is"
  dst_src          = "ftp.funet.fi"
  dst_notes        = "Peering inside Iceland from 100-1000Mb/s"

# dst_dst          = "ftp://ftp.rhnet.is/pub/CPAN/"
# dst_contact      = "mailto:ftpadm@rhnet.is
# dst_src          = "ftp.funet.fi"

cpan.indigo.ie:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.indigo.ie/pub/CPAN/"
  dst_http         = "http://cpan.indigo.ie/"
  dst_location     = "Dublin, Ireland, Europe (53.3443 -6.270899)"
  dst_organisation = "Indigo Services Limited, Dublin, Ireland"
  dst_timezone     = "-1"
  dst_bandwidth    = "STM-1"
  dst_contact      = "cpan@indigo.ie"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.indigo.ie/pub/CPAN/"
# dst_contact      = "mailto:cpan@indigo.ie
# dst_src          = "ftp.funet.fi"

ftp.heanet.ie:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.heanet.ie/mirrors/ftp.perl.org/pub/CPAN"
  dst_http         = "http://ftp.heanet.ie/mirrors/ftp.perl.org/pub/CPAN"
  dst_rsync        = "rsync://ftp.heanet.ie/mirrors/ftp.perl.org/pub/CPAN"
  dst_location     = "Dublin, Ireland, Europe (53.333 -6.250)"
  dst_organisation = "HEAnet"
  dst_timezone     = "0"
  dst_bandwidth    = "Gigabit"
  dst_contact      = "mirrors@heanet.ie"
  dst_src          = "ftp.perl.org"
  dst_notes        = "See http://ftp.heanet.ie/about and http://www.hea.net/ for details of server and connectivity."

# dst_dst          = "ftp://ftp.heanet.ie/mirrors/ftp.perl.org/pub/CPAN"
# dst_contact      = "mailto:mirrors@heanet.ie
# dst_src          = "ftp.perl.org"

sunsite.compapp.dcu.ie:
  frequency        = "daily"
  dst_ftp          = "ftp://sunsite.compapp.dcu.ie/pub/perl/"
  dst_http         = "http://sunsite.compapp.dcu.ie/pub/perl/"
  dst_location     = "Dublin, Ireland, Europe (53.3443 -6.270899)"
  dst_organisation = "School of Computer Applications, Dublin City University"
  dst_timezone     = "-1"
  dst_contact      = "SS@compapp.DCU.ie"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://sunsite.compapp.dcu.ie/pub/perl/"
# dst_contact      = "mailto:SS@compapp.DCU.ie
# dst_src          = "ftp.funet.fi"

cpan.nettuno.it:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.nettuno.it/"
  dst_location     = "Bologna, Emilia-Romagna, Italy, Europe (44.50477 11.34547)"
  dst_organisation = "Nextra"
  dst_timezone     = "+1"
  dst_bandwidth    = "E3"
  dst_contact      = "ftp-admin@nettuno.it"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://cpan.nettuno.it/"
# dst_contact      = "mailto:ftp-admin@nettuno.it
# dst_src          = "ftp.funet.fi"

gusp.dyndns.org:
  frequency        = "daily"
  dst_ftp          = "ftp://gusp.dyndns.org/pub/CPAN"
  dst_http         = "http://gusp.dyndns.org/CPAN/"
  dst_rsync        = "gusp.dyndns.org::cpan"
  dst_location     = "Firenze, Toscana, Italy, Europe (43.75 11.25)"
  dst_organisation = "GUSP"
  dst_timezone     = "+1"
  dst_bandwidth    = "DSL"
  dst_contact      = "pf@gusp.dyndns.org"
  dst_src          = "download.sourceforge.net"

# dst_dst          = "ftp://gusp.dyndns.org/pub/CPAN"
# dst_contact      = "mailto:pf@gusp.dyndns.org
# dst_src          = "download.sourceforge.net"

softcity.iol.it:
  frequency        = "daily"
  dst_ftp          = "ftp://softcity.iol.it/pub/cpan"
  dst_http         = "http://softcity.iol.it/cpan"
  dst_location     = "Milano, Lombardia, Italy, Europe (45.464 9.189)"
  dst_organisation = "Italia OnLine"
  dst_timezone     = "+1"
  dst_contact      = "dino.uras@iol.it"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://softcity.iol.it/pub/cpan"
# dst_contact      = "mailto:dino.uras@iol.it
# dst_src          = "ftp.funet.fi"

ftp.unina.it:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.unina.it/pub/Other/CPAN/CPAN/"
  dst_location     = "Napoli, Campania, Italy, Europe (40.84074 14.25219)"
  dst_organisation = "Universitá di Napoli - Federico II"
  dst_timezone     = "+1"
  dst_contact      = "ftpadmin@ftp.unina.it"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.unina.it/pub/Other/CPAN/CPAN/"
# dst_contact      = "mailto:ftpadmin@ftp.unina.it
# dst_src          = "ftp.funet.fi"

ftp.unipi.it:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.unipi.it/pub/mirror/perl/CPAN/"
  dst_location     = "Pisa, Toscana, Italy, Europe (43.70996 10.39903)"
  dst_organisation = "Centro di Servizi per la Rete di Ateneo, University of Pisa"
  dst_timezone     = "+1"
  dst_contact      = "ftp-admin@unipi.it"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.unipi.it/pub/mirror/perl/CPAN/"
# dst_contact      = "mailto:ftp-admin@unipi.it
# dst_src          = "ftp.funet.fi"

cis.uniRoma2.it:
  frequency        = "daily"
  dst_ftp          = "ftp://cis.uniRoma2.it/CPAN/"
  dst_location     = "Roma, Lazio, Italy, Europe (41.90293 12.49593)"
  dst_organisation = "Università di Roma Tor Vergata (Tor Vergata University of Rome)"
  dst_timezone     = "+1"
  dst_contact      = ""
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cis.uniRoma2.it/CPAN/"
# dst_contact      = "mailto:
# dst_src          = "ftp.funet.fi"

ftp.edisontel.it:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.edisontel.it/pub/CPAN_Mirror/"
  dst_location     = "Roma, Lazio, Italy, Europe (41.90293 12.49593)"
  dst_organisation = "Edisontel S.p.A."
  dst_timezone     = "+1"
  dst_contact      = "ftpadmin@edisontel.it"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.edisontel.it/pub/CPAN_Mirror/"
# dst_contact      = "mailto:ftpadmin@edisontel.it
# dst_src          = "ftp.funet.fi"

ftp.flashnet.it:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.flashnet.it/pub/CPAN/"
  dst_http         = "http://cpan.flashnet.it/"
  dst_location     = "Roma, Lazio, Italy, Europe (41.90293 12.49593)"
  dst_organisation = "Cybernet Italia S.p.A."
  dst_timezone     = "+1"
  dst_bandwidth    = "T1"
  dst_contact      = "ftpadmin@flashnet.it"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.flashnet.it/pub/CPAN/"
# dst_contact      = "mailto:ftpadmin@flashnet.it
# dst_src          = "ftp.funet.fi"

kvin.lv:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://kvin.lv/pub/CPAN/"
  dst_location     = "Riga, Latvia, Europe (56.9498 24.1148)"
  dst_organisation = "Kvant-Interkom"
  dst_timezone     = "+2"
  dst_bandwidth    = "11Mbps"
  dst_contact      = "arkadi@kvin.lv"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://kvin.lv/pub/CPAN/"
# dst_contact      = "mailto:arkadi@kvin.lv
# dst_src          = "ftp.funet.fi"

ftp.unix.lt:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.unix.lt/pub/CPAN/"
  dst_location     = "Vilnius, Lithuania, Europe (54.683 25.283)"
  dst_organisation = "DELFI Internet"
  dst_timezone     = "+2"
  dst_bandwidth    = "ISP"
  dst_contact      = "domas.mituzas@delfi.lt"
  dst_src          = "ftp.funet.fi"
  dst_notes        = "Bandwidth restrictions for international users but fast and wide access for .lt netizens. Site a.k.a. ftp.lt.freebsd.org and ocean.delfi.lt"

# dst_dst          = "ftp://ftp.unix.lt/pub/CPAN/"
# dst_contact      = "mailto:domas.mituzas@delfi.lt
# dst_src          = "ftp.funet.fi"

download.xs4all.nl:
  frequency        = "daily"
  dst_ftp          = "ftp://download.xs4all.nl/pub/mirror/CPAN/"
  dst_location     = "Amsterdam, Noord-Holland, Netherlands, Europe (52.37269 4.89296)"
  dst_organisation = "XS4ALL"
  dst_timezone     = "+1"
  dst_contact      = "unixbeheer@xs4all.nl"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://download.xs4all.nl/pub/mirror/CPAN/"
# dst_contact      = "mailto:unixbeheer@xs4all.nl
# dst_src          = "ftp.funet.fi"

ftp.nl.uu.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.nl.uu.net/pub/CPAN/"
  dst_location     = "Amsterdam, Netherlands, Europe (52.3289910 4.9650350)"
  dst_organisation = "UUNET NL"
  dst_timezone     = "+1"
  dst_contact      = "ftpadm@nl.uu.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.nl.uu.net/pub/CPAN/"
# dst_contact      = "mailto:ftpadm@nl.uu.net
# dst_src          = "ftp.funet.fi"

ftp.nluug.nl:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.nluug.nl/pub/languages/perl/CPAN/"
  dst_location     = "Amsterdam, Noord-Holland, Netherlands, Europe (52.37269 4.89296)"
  dst_organisation = "Dutch Unix Users Group NLUUG"
  dst_timezone     = "+1"
  dst_contact      = "ftp-admin@nluug.nl"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.nluug.nl/pub/languages/perl/CPAN/"
# dst_contact      = "mailto:ftp-admin@nluug.nl
# dst_src          = "ftp.funet.fi"

mirror.cybercomm.nl:
  frequency        = "hourly"
  dst_ftp          = "ftp://mirror.cybercomm.nl/pub/CPAN"
  dst_http         = "http://cpan.cybercomm.nl/"
  dst_location     = "Amsterdam, Noord-Holland, Netherlands, Europe (52.37269 4.89296)"
  dst_organisation = "Cybercomm Internet"
  dst_timezone     = "+1"
  dst_bandwidth    = "100Mbit"
  dst_contact      = "marcel@cybercomm.nl"
  dst_src          = "cpan.teleglobe.net"

# dst_dst          = "ftp://mirror.cybercomm.nl/pub/CPAN"
# dst_contact      = "mailto:marcel@cybercomm.nl
# dst_src          = "cpan.teleglobe.net"

mirror.vuurwerk.nl:
  frequency        = "daily"
  dst_ftp          = "ftp://mirror.vuurwerk.nl/pub/CPAN/"
  dst_location     = "Amsterdam, Netherlands, Europe (52.37269 4.89296)"
  dst_organisation = "VuurWerk Internet"
  dst_timezone     = "+1"
  dst_bandwidth    = "100MBit"
  dst_contact      = "mirror@vuurwerk.nl"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirror.vuurwerk.nl/pub/CPAN/"
# dst_contact      = "mailto:mirror@vuurwerk.nl
# dst_src          = "ftp.funet.fi"

ftp.cpan.nl:
  frequency        = "hourly"
  dst_ftp          = "ftp://ftp.cpan.nl/pub/CPAN/"
  dst_location     = "Hoofddorp, Netherlands, Europe (52.30315 4.69719)"
  dst_organisation = "Widexs Internet"
  dst_timezone     = "+1"
  dst_contact      = "cpan@widexs.nl"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.cpan.nl/pub/CPAN/"
# dst_contact      = "mailto:cpan@widexs.nl
# dst_src          = "ftp.funet.fi"

ftp.easynet.nl:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.easynet.nl/mirror/CPAN"
  dst_http         = "http://ftp.easynet.nl/mirror/CPAN"
  dst_location     = "Rotterdam Zuid-Holland, Netherlands, Europe (51.917 4.483)"
  dst_organisation = "Easynet-Group Netherlands"
  dst_timezone     = "+1
"
  dst_bandwidth    = "STM1"
  dst_contact      = "diederik@nl.easynet.net"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "ftp://ftp.easynet.nl/mirror/CPAN"
# dst_contact      = "mailto:diederik@nl.easynet.net
# dst_src          = "rsync.nic.funet.fi"

ftp.cs.uu.nl:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.cs.uu.nl/mirror/CPAN/"
  dst_http         = "http://archive.cs.uu.nl/mirror/CPAN/"
  dst_location     = "Utrecht, Netherlands, Europe (52.08787 5.11637)"
  dst_organisation = "de Universiteit Utrecht (Utrecht University)"
  dst_timezone     = "+1"
  dst_contact      = "archivist@cs.uu.nl"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.cs.uu.nl/mirror/CPAN/"
# dst_contact      = "mailto:archivist@cs.uu.nl
# dst_src          = "ftp.funet.fi"

ftp.uninett.no:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.uninett.no/pub/languages/perl/CPAN"
  dst_location     = "Oslo, Norway, Europe (59.9104 10.7524)"
  dst_organisation = "University of Oslo / Uninett"
  dst_timezone     = "+1"
  dst_contact      = "ftp-drift@uio.no"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.uninett.no/pub/languages/perl/CPAN"
# dst_contact      = "mailto:ftp-drift@uio.no
# dst_src          = "ftp.funet.fi"

ftp.uit.no:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.uit.no/pub/languages/perl/cpan/"
  dst_location     = "Tromsø, Troms, Norway, Europe (69.6529 18.962)"
  dst_organisation = "Universitetet i Tromsø (University of Tromsø)"
  dst_timezone     = "+1"
  dst_contact      = "ftp@uit.no"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.uit.no/pub/languages/perl/cpan/"
# dst_contact      = "mailto:ftp@uit.no
# dst_src          = "ftp.funet.fi"

ftp.mega.net.pl:
  frequency        = "daily"
  dst_ftp          = "ftp.mega.net.pl/CPAN"
  dst_location     = "Swinoujscie, Zachodniopomorskie, Poland, Europe (53.9068 14.2484)"
  dst_organisation = "MegaNET ISP"
  dst_timezone     = "+1"
  dst_bandwidth    = "E1"
  dst_contact      = "marcel@mega.net.pl"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp.mega.net.pl/CPAN"
# dst_contact      = "mailto:marcel@mega.net.pl
# dst_src          = "ftp.funet.fi"

ftp.man.torun.pl:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.man.torun.pl/pub/doc/CPAN/"
  dst_location     = "Torun, Kujawsko-Pomorskie, Poland, Europe (53.0217 18.6107)"
  dst_organisation = "Nicholas Copernicus University, Torun Metropolitan Area Network"
  dst_timezone     = "+1"
  dst_contact      = "ftpadmin@man.torun.pl"
  dst_src          = "ftp.icm.edu.pl"

# dst_dst          = "ftp://ftp.man.torun.pl/pub/doc/CPAN/"
# dst_contact      = "mailto:ftpadmin@man.torun.pl
# dst_src          = "ftp.icm.edu.pl"

sunsite.icm.edu.pl:
  frequency        = "daily"
  dst_ftp          = "ftp://sunsite.icm.edu.pl/pub/CPAN/"
  dst_location     = "Warsaw, Mazowieckie, Poland, Europe (52.2478 21.0208)"
  dst_organisation = "Interdyscyplinarne Centrum Modelowania Matematycznego i Komputerowego Uniwersytet Warszawski (Interdisciplinary Centre for Mathematical and Computational Modeling)"
  dst_timezone     = "+1"
  dst_bandwidth    = "E3"
  dst_contact      = "mirror@icm.edu.pl"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://sunsite.icm.edu.pl/pub/CPAN/"
# dst_contact      = "mailto:mirror@icm.edu.pl
# dst_src          = "ftp.cpan.org"

ftp.ua.pt:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ua.pt/pub/CPAN/"
  dst_location     = "Aveiro, Portugal, Europe (40.6352 -8.653099)"
  dst_organisation = "Centro de Informática e Comunicações da Universidade de Aveiro (Computer and Comunications Center, University of Aveiro)"
  dst_timezone     = "0"
  dst_contact      = "ftp-adm@ua.pt"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ua.pt/pub/CPAN/"
# dst_contact      = "mailto:ftp-adm@ua.pt
# dst_src          = "ftp.funet.fi"

perl.di.uminho.pt:
  frequency        = "daily"
  dst_ftp          = "ftp://perl.di.uminho.pt/pub/CPAN/"
  dst_location     = "Braga, Portugal, Europe (41.5396 -8.418)"
  dst_organisation = "Departamento de Informática, Universidade do Minho (Department of Informatics, University of Minho)"
  dst_timezone     = "0"
  dst_contact      = "jpo@di.uminho.pt"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://perl.di.uminho.pt/pub/CPAN/"
# dst_contact      = "mailto:jpo@di.uminho.pt
# dst_src          = "ftp.funet.fi"

ftp.dei.uc.pt:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.dei.uc.pt/pub/CPAN"
  dst_http         = "http://cpan.dei.uc.pt/"
  dst_location     = "Coimbra, Portugal, Europe (40.2000 -8.4167)"
  dst_organisation = "Departamento de Engenharia Informatica da Universidade de Coimbra (Department of Informatics Engineering, University of Coimbra)"
  dst_timezone     = "0"
  dst_bandwidth    = "T3"
  dst_contact      = "ftpadmin@dei.uc.pt"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.dei.uc.pt/pub/CPAN"
# dst_contact      = "mailto:ftpadmin@dei.uc.pt
# dst_src          = "ftp.funet.fi"

ftp.nfsi.pt:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.nfsi.pt/pub/CPAN"
  dst_location     = "Leiria, Portugal, Europe (39.7500 -8.8000)"
  dst_organisation = "NFSi - Solucoes Internet Lda"
  dst_timezone     = "0
"
  dst_bandwidth    = "STM-1"
  dst_contact      = "nuno.vieira@nfsi.pt"
  dst_src          = "rsync.nic.funet.fi"
  dst_notes        = "Anonymous User Limit 10"

# dst_dst          = "ftp://ftp.nfsi.pt/pub/CPAN"
# dst_contact      = "mailto:nuno.vieira@nfsi.pt
# dst_src          = "rsync.nic.funet.fi"

ftp.linux.pt:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.linux.pt/pub/mirrors/CPAN"
  dst_http         = "http://ftp.linux.pt/pub/mirrors/CPAN"
  dst_location     = "Lisboa, Portugal, Europe (38.7134 -9.2334)"
  dst_organisation = "Linux.pt"
  dst_timezone     = "0"
  dst_bandwidth    = "T3"
  dst_contact      = "mirror@linux.pt"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.linux.pt/pub/mirrors/CPAN"
# dst_contact      = "mailto:mirror@linux.pt
# dst_src          = "ftp.funet.fi"

cpan.ip.pt:
  frequency        = "4 times daily"
  dst_ftp          = "ftp://cpan.ip.pt/pub/cpan/"
  dst_http         = "http://cpan.ip.pt/"
  dst_location     = "Lisbon, Portugal, Europe (38.7341 -9.1446)"
  dst_organisation = "Novis Telecom, SA"
  dst_timezone     = "0"
  dst_bandwidth    = "OC3"
  dst_contact      = "ftpadmin@ip.pt"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.ip.pt/pub/cpan/"
# dst_contact      = "mailto:ftpadmin@ip.pt
# dst_src          = "ftp.funet.fi"

cpan.telepac.pt:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.telepac.pt/pub/cpan/"
  dst_http         = "http://cpan.telepac.pt/"
  dst_location     = "Lisbon, Portugal, Europe (38.733 -9.133)"
  dst_organisation = "Telepac"
  dst_timezone     = "0"
  dst_bandwidth    = "T3"
  dst_contact      = "mramos@tp.telepac.pt"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.telepac.pt/pub/cpan/"
# dst_contact      = "mailto:mramos@tp.telepac.pt
# dst_src          = "ftp.funet.fi"

ftp.bio-net.ro:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.bio-net.ro/pub/CPAN"
  dst_location     = "Bucharest, Romania, Europe (44.26 26.06)"
  dst_organisation = "EDVAL Trading SRL"
  dst_timezone     = "+2"
  dst_bandwidth    = "T1"
  dst_contact      = "admin@bio-net.ro"
  dst_src          = "ftp.tuwien.ac.at"
  dst_notes        = "2002-12-12 13:55:00"

# dst_dst          = "ftp://ftp.bio-net.ro/pub/CPAN"
# dst_contact      = "mailto:admin@bio-net.ro
# dst_src          = "ftp.tuwien.ac.at"

ftp.kappa.ro:
  frequency        = "twice daily"
  dst_ftp          = "ftp://ftp.kappa.ro/pub/mirrors/ftp.perl.org/pub/CPAN/"
  dst_location     = "Bucharest, Romania, Europe (44.4333 26.1)"
  dst_organisation = "Astral Telecom"
  dst_timezone     = "+2"
  dst_bandwidth    = "E1"
  dst_contact      = "ftpadm@kappa.ro"
  dst_src          = "ftp.perl.org"

# dst_dst          = "ftp://ftp.kappa.ro/pub/mirrors/ftp.perl.org/pub/CPAN/"
# dst_contact      = "mailto:ftpadm@kappa.ro
# dst_src          = "ftp.perl.org"

ftp.lug.ro:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.lug.ro/CPAN"
  dst_location     = "Bucharest, Romania, Europe (44.4333 26.1000)"
  dst_organisation = "KPNQwest/GTS Romania -- Romanian Linux Users Group"
  dst_timezone     = "+2"
  dst_bandwidth    = "STM1"
  dst_contact      = "cpan@lug.ro"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "ftp://ftp.lug.ro/CPAN"
# dst_contact      = "mailto:cpan@lug.ro
# dst_src          = "rsync.nic.funet.fi"

ftp.roedu.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.roedu.net/pub/CPAN/"
  dst_location     = "Bucharest, Romania, Europe (44.4 26.1)"
  dst_organisation = "Romanian Educational Network - RoEduNet"
  dst_timezone     = "+2"
  dst_bandwidth    = "STM1"
  dst_contact      = "keeper@roedu.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.roedu.net/pub/CPAN/"
# dst_contact      = "mailto:keeper@roedu.net
# dst_src          = "ftp.funet.fi"

ftp.dntis.ro:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.dntis.ro/pub/cpan/"
  dst_location     = "Iasi, Romania, Europe (47.1559 27.5822)"
  dst_organisation = "Dynamic Network Technologies Romania"
  dst_timezone     = "+2"
  dst_contact      = "ftpadmin@dntis.ro"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.dntis.ro/pub/cpan/"
# dst_contact      = "mailto:ftpadmin@dntis.ro
# dst_src          = "ftp.funet.fi"

ftp.iasi.roedu.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.iasi.roedu.net/pub/mirrors/ftp.cpan.org/"
  dst_location     = "Iasi, Romania, Europe (47.1559 27.5822)"
  dst_organisation = "RoEduNet Iasi Branch"
  dst_timezone     = "+2"
  dst_bandwidth    = "6Mbps"
  dst_contact      = "sysadmin@iasi.roedu.net"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://ftp.iasi.roedu.net/pub/mirrors/ftp.cpan.org/"
# dst_contact      = "mailto:sysadmin@iasi.roedu.net
# dst_src          = "ftp.cpan.org"

ftp.ambra.ro:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ambra.ro/pub/CPAN"
  dst_http         = "http://cpan.ambra.ro/"
  dst_location     = "Piatra Neamt, Romania, Europe (46.933 26.367)"
  dst_organisation = "Ambra srl"
  dst_timezone     = "+2"
  dst_bandwidth    = "DSL"
  dst_contact      = "mihai@ambra.ro"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ambra.ro/pub/CPAN"
# dst_contact      = "mailto:mihai@ambra.ro
# dst_src          = "ftp.funet.fi"

ftp.dnttm.ro:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.dnttm.ro/pub/CPAN/"
  dst_location     = "Timisoara, Romania, Europe (45.753 21.2183)"
  dst_organisation = "Dynamic Network Technologies Romania"
  dst_timezone     = "+2"
  dst_contact      = "ftp@dnttm.ro"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.dnttm.ro/pub/CPAN/"
# dst_contact      = "mailto:ftp@dnttm.ro
# dst_src          = "ftp.funet.fi"

ftp.lasting.ro:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.lasting.ro/pub/CPAN"
  dst_location     = "Timisoara, Romania, Europe (45.753 21.2183)"
  dst_organisation = "LASTING Net"
  dst_timezone     = "+2"
  dst_bandwidth    = "DSL"
  dst_contact      = "noc@lasting.ro"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://ftp.lasting.ro/pub/CPAN"
# dst_contact      = "mailto:noc@lasting.ro
# dst_src          = "ftp.cpan.org"

ftp.timisoara.roedu.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.timisoara.roedu.net/mirrors/CPAN/"
  dst_location     = "Timisoara, Romania, Europe (45.753 21.2183)"
  dst_organisation = "RoEduNet Timisoara"
  dst_timezone     = "+2"
  dst_contact      = "support@timisoara.roedu.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.timisoara.roedu.net/mirrors/CPAN/"
# dst_contact      = "mailto:support@timisoara.roedu.net
# dst_src          = "ftp.funet.fi"

ftp.chg.ru:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.chg.ru/pub/lang/perl/CPAN/"
  dst_location     = "Chernogolovka, Russia, Europe (56.000 38.367)"
  dst_organisation = "Landau Institute for Theoretical Physics"
  dst_timezone     = "+3"
  dst_contact      = "ftpadm@chg.ru"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.chg.ru/pub/lang/perl/CPAN/"
# dst_contact      = "mailto:ftpadm@chg.ru
# dst_src          = "ftp.funet.fi"

cpan.rinet.ru:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.rinet.ru/pub/mirror/CPAN/"
  dst_http         = "http://cpan.rinet.ru/"
  dst_location     = "Moscow, Russia, Europe (55.75 37.5833)"
  dst_organisation = "Cronyx Plus Ltd. (RiNet ISP)"
  dst_timezone     = "+3"
  dst_bandwidth    = "10Mbps"
  dst_contact      = "mirroradm@rinet.ru"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.rinet.ru/pub/mirror/CPAN/"
# dst_contact      = "mailto:mirroradm@rinet.ru
# dst_src          = "ftp.funet.fi"

ftp.aha.ru:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.aha.ru/pub/CPAN/"
  dst_location     = "Moscow, Russia, Europe (55.75 37.5833)"
  dst_organisation = "Zenon N.S.P."
  dst_timezone     = "+3"
  dst_contact      = "sysadm@zenon.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.aha.ru/pub/CPAN/"
# dst_contact      = "mailto:sysadm@zenon.net
# dst_src          = "ftp.funet.fi"

ftp.corbina.ru:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.corbina.ru/pub/CPAN/"
  dst_location     = "Moscow, Russia, Europe (55.75 37.5833)"
  dst_organisation = "Corbina Telecom"
  dst_timezone     = "+3"
  dst_bandwidth    = "1Gbps"
  dst_contact      = "support@corbina.ru"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "ftp://ftp.corbina.ru/pub/CPAN/"
# dst_contact      = "mailto:support@corbina.ru
# dst_src          = "rsync.nic.funet.fi"

ftp.sai.msu.su:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.sai.msu.su/pub/lang/perl/CPAN/"
  dst_http         = "http://cpan.sai.msu.ru/"
  dst_location     = "Moscow, Russia, Europe (55.75 37.5833)"
  dst_organisation = "Sternberg Astronomical Institute, Moscow University"
  dst_timezone     = "+3"
  dst_bandwidth    = "10Mbps"
  dst_contact      = "oleg@sai.msu.su"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.sai.msu.su/pub/lang/perl/CPAN/"
# dst_contact      = "mailto:oleg@sai.msu.su
# dst_src          = "ftp.funet.fi"

ftp.cvt.stuba.sk:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.cvt.stuba.sk/pub/CPAN/"
  dst_location     = "Bratislava, Slovakia, Europe (48.1376 17.1043)"
  dst_organisation = "Slovak University Of Technology"
  dst_timezone     = "+2"
  dst_bandwidth    = "100Mbit"
  dst_contact      = "ftpadmin@cvt.stuba.sk"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.cvt.stuba.sk/pub/CPAN/"
# dst_contact      = "mailto:ftpadmin@cvt.stuba.sk
# dst_src          = "ftp.funet.fi"

ftp.arnes.si:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.arnes.si/software/perl/CPAN/"
  dst_location     = "Ljubljana, Slovenia, Europe (46.058 14.5049)"
  dst_organisation = "Academic and Research Network in Slovenia"
  dst_timezone     = "+1"
  dst_contact      = "ftpadmin@arnes.si"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.arnes.si/software/perl/CPAN/"
# dst_contact      = "mailto:ftpadmin@arnes.si
# dst_src          = "ftp.funet.fi"

cpan.imasd.elmundo.es:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.imasd.elmundo.es/"
  dst_location     = "Madrid, Spain, Europe (40.417 -3.717)"
  dst_organisation = "elmundo.es"
  dst_timezone     = "+1"
  dst_bandwidth    = "100Mb"
  dst_contact      = "admin@el-mundo.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://cpan.imasd.elmundo.es/"
# dst_contact      = "mailto:admin@el-mundo.net
# dst_src          = "ftp.funet.fi"

ftp.rediris.es:
  frequency        = "twice daily"
  dst_ftp          = "ftp://ftp.rediris.es/mirror/CPAN/"
  dst_location     = "Madrid, Spain, Europe (40.42031 -3.70562)"
  dst_organisation = "Red Académica y de Investigación Nacional Española (Spanish Academic Network for Research and Development)"
  dst_timezone     = "+1"
  dst_contact      = "ftp@rediris.es"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.rediris.es/mirror/CPAN/"
# dst_contact      = "mailto:ftp@rediris.es
# dst_src          = "ftp.funet.fi"

ftp.ri.telefonica-data.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ri.telefonica-data.net/"
  dst_location     = "Madrid, Spain, Europe (40.4167 -3.7167)"
  dst_organisation = "Telefonica Data Corp"
  dst_timezone     = "+1"
  dst_bandwidth    = "100Mbit"
  dst_contact      = "carlos.oleaortigosa@telefonica-data.com"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "ftp://ftp.ri.telefonica-data.net/"
# dst_contact      = "mailto:carlos.oleaortigosa@telefonica-data.com
# dst_src          = "rsync.nic.funet.fi"

ftp.etse.urv.es:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.etse.urv.es/pub/perl/"
  dst_location     = "Tarragona, Catalonia, Spain, Europe (41.11617 1.25561)"
  dst_organisation = "Escola Tècnica Superior d'Enginyeria Universitat Rovira i Virgili (Advanced Engineering Technical School Rovira i Virgili University)"
  dst_timezone     = "+1"
  dst_contact      = "ftpmanager@etse.urv.es"
  dst_src          = "ftp.rediris.es"

# dst_dst          = "ftp://ftp.etse.urv.es/pub/perl/"
# dst_contact      = "mailto:ftpmanager@etse.urv.es
# dst_src          = "ftp.rediris.es"

ftp.du.se:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.du.se/pub/CPAN/"
  dst_http         = "http://ftp.du.se/CPAN/"
  dst_location     = "Borlänge, Sweden, Europe (60.48349 15.43365)"
  dst_organisation = "Dalarna University College"
  dst_timezone     = "+1"
  dst_bandwidth    = "OC3"
  dst_contact      = "ftpadmin@du.se"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.du.se/pub/CPAN/"
# dst_contact      = "mailto:ftpadmin@du.se
# dst_src          = "ftp.funet.fi"

mirror.dataphone.se:
  frequency        = "daily"
  dst_ftp          = "ftp://mirror.dataphone.se/pub/CPAN"
  dst_http         = "http://mirror.dataphone.se/CPAN"
  dst_location     = "Solna, Sweden, Europe (59.367 17.983)"
  dst_organisation = "Dataphone Communication Networks"
  dst_timezone     = "+1"
  dst_bandwidth    = "OC3"
  dst_contact      = "mikael.hugo@dataphone.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirror.dataphone.se/pub/CPAN"
# dst_contact      = "mailto:mikael.hugo@dataphone.net
# dst_src          = "ftp.funet.fi"

ftp.sunet.se:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.sunet.se/pub/lang/perl/CPAN/"
  dst_location     = "Uppsala, Sweden, Europe (59.85814 17.64458)"
  dst_organisation = "Swedish University NETwork"
  dst_timezone     = "+1"
  dst_contact      = "ftp-admin@ftp.sunet.se"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.sunet.se/pub/lang/perl/CPAN/"
# dst_contact      = "mailto:ftp-admin@ftp.sunet.se
# dst_src          = "ftp.funet.fi"

ftp.solnet.ch:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.solnet.ch/mirror/CPAN/"
  dst_http         = "http://cpan.mirror.solnet.ch/"
  dst_rsync        = "ftp.solnet.ch::CPAN"
  dst_location     = "Solothurn, Switzerland, Europe (47.2167 7.5333)"
  dst_organisation = "SolNet"
  dst_timezone     = "+1"
  dst_bandwidth    = "T3"
  dst_contact      = "mirrormaster@solnet.ch"
  dst_src          = "ftp.leo.org"

# dst_dst          = "ftp://ftp.solnet.ch/mirror/CPAN/"
# dst_contact      = "mailto:mirrormaster@solnet.ch
# dst_src          = "ftp.leo.org"

ftp.danyk.ch:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.danyk.ch/CPAN/"
  dst_location     = "Zürich, Switzerland, Europe (47.37704 8.53951)"
  dst_organisation = "K-Informatik"
  dst_timezone     = "+1"
  dst_contact      = "dkuebler@k-informatik.ch"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.danyk.ch/CPAN/"
# dst_contact      = "mailto:dkuebler@k-informatik.ch
# dst_src          = "ftp.funet.fi"

sunsite.cnlab-switch.ch:
  frequency        = "daily"
  dst_ftp          = "ftp://sunsite.cnlab-switch.ch/mirror/CPAN/"
  dst_location     = "Zürich, Switzerland, Europe (47.37704 8.53951)"
  dst_organisation = "Swiss Academic and Research Network"
  dst_timezone     = "+1"
  dst_contact      = "archive@sunsite.cnlab-switch.ch"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://sunsite.cnlab-switch.ch/mirror/CPAN/"
# dst_contact      = "mailto:archive@sunsite.cnlab-switch.ch
# dst_src          = "ftp.funet.fi"

ftp.ulak.net.tr:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ulak.net.tr/perl/CPAN"
  dst_http         = "http://ftp.ulak.net.tr/perl/CPAN/"
  dst_location     = "Ankara, Turkey, Europe (39.0871001 34.430400)"
  dst_organisation = "Turkish Academic Network and Information Center"
  dst_timezone     = "+2"
  dst_bandwidth    = "E3"
  dst_contact      = "noc@ulakbim.gov.tr"
  dst_src          = "cpan.teleglobe.net"

# dst_dst          = "ftp://ftp.ulak.net.tr/perl/CPAN"
# dst_contact      = "mailto:noc@ulakbim.gov.tr
# dst_src          = "cpan.teleglobe.net"

sunsite.bilkent.edu.tr:
  frequency        = "twice daily"
  dst_ftp          = "ftp://sunsite.bilkent.edu.tr/pub/languages/CPAN/"
  dst_location     = "Ankara, Turkey, Europe (39.9366 32.8543)"
  dst_organisation = "Bilkent University"
  dst_timezone     = "+2"
  dst_contact      = "akgul@bilkent.edu.tr"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://sunsite.bilkent.edu.tr/pub/languages/CPAN/"
# dst_contact      = "mailto:akgul@bilkent.edu.tr
# dst_src          = "ftp.funet.fi"

cpan.org.ua:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.org.ua/"
  dst_http         = "http://cpan.org.ua/"
  dst_location     = "Kiev, Ukraine, Europe (50.4333 30.5167)"
  dst_organisation = "K27"
  dst_timezone     = "+2"
  dst_bandwidth    = "1Mb"
  dst_contact      = "hostmaster@cpan.org.ua"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.org.ua/"
# dst_contact      = "mailto:hostmaster@cpan.org.ua
# dst_src          = "ftp.funet.fi"

ftp.perl.org.ua:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.perl.org.ua/pub/CPAN/"
  dst_location     = "Kiev, Ukraine, Europe (50.4333 30.5167)"
  dst_organisation = "LoGiN Organisation"
  dst_timezone     = "+2"
  dst_bandwidth    = "HDSL 64K"
  dst_contact      = "admin@perl.org.ua"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.perl.org.ua/pub/CPAN/"
# dst_contact      = "mailto:admin@perl.org.ua
# dst_src          = "ftp.funet.fi"

no-more.kiev.ua:
  frequency        = "daily"
  dst_ftp          = "ftp://no-more.kiev.ua/pub/CPAN/"
  dst_http         = "http://no-more.kiev.ua/CPAN/"
  dst_location     = "Kiev, Ukraine, Europe (50.4333 30.5167)"
  dst_organisation = "No More BBS"
  dst_timezone     = "+2"
  dst_bandwidth    = "512Kb"
  dst_contact      = "cpan@no-more.kiev.ua"
  dst_src          = "ftp.funet.fi"
  dst_notes        = "2003-01-08 08:46:00"

# dst_dst          = "ftp://no-more.kiev.ua/pub/CPAN/"
# dst_contact      = "mailto:cpan@no-more.kiev.ua
# dst_src          = "ftp.funet.fi"

ftp.mirror.ac.uk:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.mirror.ac.uk/sites/ftp.funet.fi/pub/languages/perl/CPAN/"
  dst_http         = "http://www.mirror.ac.uk/sites/ftp.funet.fi/pub/languages/perl/CPAN"
  dst_location     = "Canterbury and Lancaster, England, United Kingdom, Europe (51.27561 1.07514)"
  dst_organisation = "UK Mirror Service"
  dst_timezone     = "0"
  dst_contact      = "mirror-admin@mirror.ac.uk"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.mirror.ac.uk/sites/ftp.funet.fi/pub/languages/perl/CPAN/"
# dst_contact      = "mailto:mirror-admin@mirror.ac.uk
# dst_src          = "ftp.funet.fi"

cont1.lhx.teleglobe.net:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.teleglobe.net/pub/CPAN"
  dst_http         = "http://cpan.teleglobe.net/"
  dst_rsync        = "cpan.teleglobe.net::CPAN"
  dst_location     = "London, England, United Kingdom, Europe (51.50595 -0.12689)"
  dst_organisation = "Teleglobe"
  dst_timezone     = "0"
  dst_bandwidth    = "OC48"
  dst_contact      = "mirror@teleglobe.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.teleglobe.net/pub/CPAN"
# dst_contact      = "mailto:mirror@teleglobe.net
# dst_src          = "ftp.funet.fi"

cpan.crazygreek.co.uk:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.mirror.anlx.net/CPAN/"
  dst_http         = "http://cpan.mirror.anlx.net/"
  dst_rsync        = "rsync://rsync.mirror.anlx.net::CPAN"
  dst_location     = "London, England, United Kingdom, Europe (51.50595 -0.12689)"
  dst_organisation = "Associated Networks Limited"
  dst_timezone     = "0"
  dst_bandwidth    = "DS3"
  dst_contact      = "Theo Zourzouvillys theo@anlx.net"
  dst_src          = "ftp.funet.fi"
  dst_notes        = "Server is load balanced over 2 machines using an Arrowpoint CS-800"

# dst_dst          = "ftp://ftp.mirror.anlx.net/CPAN/"
# dst_contact      = "mailto:Theo Zourzouvillys theo@anlx.net
# dst_src          = "ftp.funet.fi"

cpan.etla.org:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.etla.org/pub/CPAN"
  dst_http         = "http://cpan.etla.org/"
  dst_location     = "London, United Kingdom, Europe (51.512078 -0.002035)"
  dst_organisation = ""
  dst_timezone     = "0"
  dst_bandwidth    = "10Mbit"
  dst_contact      = "mstevens@etla.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.etla.org/pub/CPAN"
# dst_contact      = "mailto:mstevens@etla.org
# dst_src          = "ftp.funet.fi"

ftp.demon.co.uk:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.demon.co.uk/pub/CPAN/"
  dst_location     = "London, England, United Kingdom, Europe (51.50595 -0.12689)"
  dst_organisation = "Demon Internet Limited"
  dst_timezone     = "0"
  dst_bandwidth    = "DS3"
  dst_contact      = "malcolm@thokk.demon.co.uk"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.demon.co.uk/pub/CPAN/"
# dst_contact      = "mailto:malcolm@thokk.demon.co.uk
# dst_src          = "ftp.funet.fi"

ftp.flirble.org:
  frequency        = "4 times daily"
  dst_ftp          = "ftp://ftp.flirble.org/pub/languages/perl/CPAN/"
  dst_http         = "http://cpan.m.flirble.org/"
  dst_location     = "London, England, United Kingdom, Europe (51.50595 -0.12689)"
  dst_organisation = "The Flirble Organisation"
  dst_timezone     = "0"
  dst_bandwidth    = "100mb"
  dst_contact      = "cpan-mirror@flirble.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.flirble.org/pub/languages/perl/CPAN/"
# dst_contact      = "mailto:cpan-mirror@flirble.org
# dst_src          = "ftp.funet.fi"

ftp.plig.org:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.plig.org/pub/CPAN/"
  dst_location     = "London, England, United Kingdom, Europe (51.50595 -0.12689)"
  dst_organisation = "PLiG"
  dst_timezone     = ""
  dst_contact      = "ftp-admin@plig.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.plig.org/pub/CPAN/"
# dst_contact      = "mailto:ftp-admin@plig.org
# dst_src          = "ftp.funet.fi"

cpan.hambule.co.uk:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.hambule.co.uk/"
  dst_location     = "Nottingham, England, United Kingdom, Europe (52.967 -1.167)"
  dst_organisation = "Hambule"
  dst_timezone     = "0"
  dst_bandwidth    = "100Mbit"
  dst_contact      = "cpan@hambule.co.uk"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://cpan.hambule.co.uk/"
# dst_contact      = "mailto:cpan@hambule.co.uk
# dst_src          = "ftp.funet.fi"

ftp.clockerz.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.clockerz.net/pub/CPAN/"
  dst_http         = "http://cpan.mirrors.clockerz.net/"
  dst_location     = "Nottingham, England, United Kingdom, Europe (52.95519 -1.147518)"
  dst_organisation = "clockerz.net"
  dst_timezone     = "0"
  dst_contact      = "ftp-admin@clockerz.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.clockerz.net/pub/CPAN/"
# dst_contact      = "mailto:ftp-admin@clockerz.net
# dst_src          = "ftp.funet.fi"

usit.shef.ac.uk:
  frequency        = "daily"
  dst_ftp          = "ftp://usit.shef.ac.uk/pub/packages/CPAN/"
  dst_location     = "Sheffield, England, United Kingdom, Europe (53.38311 -1.464879)"
  dst_organisation = "University of Sheffield, Union of Students, IT committee"
  dst_timezone     = "0"
  dst_contact      = "tony@usit.shef.ac.uk"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://usit.shef.ac.uk/pub/packages/CPAN/"
# dst_contact      = "mailto:tony@usit.shef.ac.uk
# dst_src          = "ftp.funet.fi"

sunsite.ualberta.ca:
  frequency        = "twice daily"
  dst_ftp          = "ftp://cpan.sunsite.ualberta.ca/pub/CPAN/"
  dst_http         = "http://cpan.sunsite.ualberta.ca/"
  dst_location     = "Edmonton, Alberta, Canada, North America (53.5262 -113.5294)"
  dst_organisation = "University of Alberta"
  dst_timezone     = "-7"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "ftpadmin@sunsite.ualberta.ca"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.sunsite.ualberta.ca/pub/CPAN/"
# dst_contact      = "mailto:ftpadmin@sunsite.ualberta.ca
# dst_src          = "ftp.funet.fi"

cpan.chebucto.ns.ca:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.chebucto.ns.ca/pub/CPAN/"
  dst_location     = "Halifax, Nova Scotia, Canada, North America (44.637 -63.5935)"
  dst_organisation = "Chebucto Community Net Department of Information Warfare"
  dst_timezone     = ""
  dst_bandwidth    = "3Mbps"
  dst_contact      = "jeffw@chebucto.ns.ca ccn-tech@chebucto.ns.ca"
  dst_src          = "sunsite.ualberta.ca"

# dst_dst          = "ftp://cpan.chebucto.ns.ca/pub/CPAN/"
# dst_contact      = "mailto:jeffw@chebucto.ns.ca ccn-tech@chebucto.ns.ca
# dst_src          = "sunsite.ualberta.ca"

ftp.nrc.ca:
  frequency        = "twice daily"
  dst_ftp          = "ftp://ftp.nrc.ca/pub/CPAN/"
  dst_location     = "Ottawa, Ontario, Canada, North America (45.2030 -75.5259)"
  dst_organisation = "National Research Council"
  dst_timezone     = "-5"
  dst_bandwidth    = "1Gb/s"
  dst_contact      = "wmaton@ryouko.imsb.nrc.ca"
  dst_src          = "ftp.funet.fi"
  dst_notes        = "Limit 500 users for CA*Net 4 and Internet2."

# dst_dst          = "ftp://ftp.nrc.ca/pub/CPAN/"
# dst_contact      = "mailto:wmaton@ryouko.imsb.nrc.ca
# dst_src          = "ftp.funet.fi"

theoryx5.uwinnipeg.ca:
  frequency        = "daily"
  dst_ftp          = "ftp://theoryx5.uwinnipeg.ca/pub/CPAN/"
  dst_http         = "http://theoryx5.uwinnipeg.ca/pub/CPAN/"
  dst_rsync        = "theoryx5.uwinnipeg.ca::CPAN"
  dst_location     = "Winnipeg, Manitoba, Canada, North America (49.8807 -97.1378)"
  dst_organisation = "Physics Department, University of Winnipeg"
  dst_timezone     = "-6"
  dst_bandwidth    = "T1"
  dst_contact      = "ftp-admin@theory.uwinnipeg.ca"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://theoryx5.uwinnipeg.ca/pub/CPAN/"
# dst_contact      = "mailto:ftp-admin@theory.uwinnipeg.ca
# dst_src          = "ftp.funet.fi"

cpan.azc.uam.mx:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.azc.uam.mx/mirrors/CPAN"
  dst_http         = "http://cpan.azc.uam.mx"
  dst_location     = "Ciudad de México, Mexico, North America (19 -98)"
  dst_organisation = "Universidad Autónoma Metropolitana Azcapotzalco"
  dst_timezone     = "-6"
  dst_bandwidth    = "E3"
  dst_contact      = "jpedral@correo.azc.uam.mx"
  dst_src          = "ftp.sunet.se"
  dst_notes        = "Limit 500 users. InternetII"

# dst_dst          = "ftp://cpan.azc.uam.mx/mirrors/CPAN"
# dst_contact      = "mailto:jpedral@correo.azc.uam.mx
# dst_src          = "ftp.sunet.se"

ftp.unam.mx:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.unam.mx/pub/CPAN"
  dst_http         = "http://www.cpan.unam.mx/"
  dst_location     = "Ciudad de Mexico, Mexico, North America (19 -98)"
  dst_organisation = "Universidad Nacional Autonoma de Mexico"
  dst_timezone     = "-6"
  dst_bandwidth    = "T1"
  dst_contact      = "mirrors@servidores.unam.mx"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.unam.mx/pub/CPAN"
# dst_contact      = "mailto:mirrors@servidores.unam.mx
# dst_src          = "ftp.funet.fi"

ftp.msg.com.mx:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.msg.com.mx/pub/CPAN/"
  dst_http         = "http://www.msg.com.mx/CPAN/"
  dst_location     = "Mexico City, Distrito Federál, Mexico, North America (19.4547 -99.1433)"
  dst_organisation = "Matias Software Group"
  dst_timezone     = "-6"
  dst_contact      = "ftpadmin@msg.com.mx"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.msg.com.mx/pub/CPAN/"
# dst_contact      = "mailto:ftpadmin@msg.com.mx
# dst_src          = "ftp.funet.fi"

mirrors.towardex.com:
  frequency        = "daily"
  dst_ftp          = "ftp://mirrors.towardex.com/pub/CPAN"
  dst_http         = "http://mirrors.towardex.com/CPAN"
  dst_location     = "Acton, Massachusetts, United States, North America (42.4841 -71.4379)"
  dst_organisation = "TowardEX Technologies"
  dst_timezone     = "-5"
  dst_bandwidth    = "T1"
  dst_contact      = "mirrors-maint@towardex.com"
  dst_src          = ""
  dst_notes        = "max ftp users = 50"

# dst_dst          = "ftp://mirrors.towardex.com/pub/CPAN"
# dst_contact      = "mailto:mirrors-maint@towardex.com
# dst_src          = ""

ftp.sedl.org:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://ftp.sedl.org/pub/mirrors/CPAN/"
  dst_rsync        = "ftp.sedl.org::cpan"
  dst_location     = "Austin, Texas, United States, North America (30.26847 -97.74014)"
  dst_organisation = "Southwest Educational Development Laboratory"
  dst_timezone     = "-6"
  dst_bandwidth    = "T1"
  dst_contact      = "ftp@sedl.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://ftp.sedl.org/pub/mirrors/CPAN/"
# dst_contact      = "mailto:ftp@sedl.org
# dst_src          = "ftp.funet.fi"

ftp.uwsg.iu.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.uwsg.iu.edu/pub/perl/CPAN/"
  dst_location     = "Bloomington, Indiana, United States, North America (39.166 -86.521)"
  dst_organisation = "Unix Workstation Support Group, Indiana University Bloomington"
  dst_timezone     = "-5"
  dst_contact      = "uwsg@indiana.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.uwsg.iu.edu/pub/perl/CPAN/"
# dst_contact      = "mailto:uwsg@indiana.edu
# dst_src          = "ftp.funet.fi"

ftp.ccs.neu.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ccs.neu.edu/net/mirrors/ftp.funet.fi/pub/languages/perl/CPAN/"
  dst_location     = "Boston, Massachusetts, United States, North America (42.362 -71.058)"
  dst_organisation = "College of Computer Science, Northeastern University"
  dst_timezone     = "-5"
  dst_bandwidth    = "T3"
  dst_contact      = "ftp@ccs.neu.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ccs.neu.edu/net/mirrors/ftp.funet.fi/pub/languages/perl/CPAN/"
# dst_contact      = "mailto:ftp@ccs.neu.edu
# dst_src          = "ftp.funet.fi"

ftp.cs.colorado.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.cs.colorado.edu/pub/perl/CPAN/"
  dst_location     = "Boulder, Colorado, United States, North America (40.026 -105.251)"
  dst_organisation = "Computer Science, Colorado University"
  dst_timezone     = "-7"
  dst_contact      = "trouble@cs.colorado.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.cs.colorado.edu/pub/perl/CPAN/"
# dst_contact      = "mailto:trouble@cs.colorado.edu
# dst_src          = "ftp.funet.fi"

www.ibiblio.org:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ibiblio.org/pub/languages/perl/CPAN"
  dst_http         = "http://www.ibiblio.org/pub/languages/perl/CPAN"
  dst_rsync        = "ibiblio.org::CPAN"
  dst_location     = "Chapel Hill, North Carolina, United States, North America (35.92 -79.03)"
  dst_organisation = "ibiblio.org"
  dst_timezone     = "-5"
  dst_bandwidth    = "T3"
  dst_contact      = "admin@ibiblio.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ibiblio.org/pub/languages/perl/CPAN"
# dst_contact      = "mailto:admin@ibiblio.org
# dst_src          = "ftp.funet.fi"

ftp.cpanel.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.cpanel.net/pub/CPAN/"
  dst_http         = "http://ftp.cpanel.net/pub/CPAN/"
  dst_location     = "Clifton, New Jersey, United States, North America (40.863 -74.157)"
  dst_organisation = "cPanel, Inc."
  dst_timezone     = "-5"
  dst_bandwidth    = "OC3"
  dst_contact      = "nick@cpanel.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.cpanel.net/pub/CPAN/"
# dst_contact      = "mailto:nick@cpanel.net
# dst_src          = "ftp.funet.fi"

ftp.orst.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.orst.edu/pub/CPAN"
  dst_location     = "Corvallis, Oregon, United States, North America (44.570 -123.275)"
  dst_organisation = "Oregon State University"
  dst_timezone     = "-8"
  dst_contact      = ""
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.orst.edu/pub/CPAN"
# dst_contact      = "mailto:
# dst_src          = "ftp.funet.fi"

ftp.epix.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.epix.net/pub/languages/perl/"
  dst_http         = "http://ftp.epix.net/CPAN/"
  dst_location     = "Dallas, Pennsylvania, United States, North America (41.331 -75.972)"
  dst_organisation = "EPIX Internet Services"
  dst_timezone     = "-5"
  dst_bandwidth    = "DS3"
  dst_contact      = "archive@epix.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.epix.net/pub/languages/perl/"
# dst_contact      = "mailto:archive@epix.net
# dst_src          = "ftp.funet.fi"

cpan.tarchive.com:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.four10.com"
  dst_location     = "Denver, Colorado, United States, North America (39.7333 -104.9833)"
  dst_organisation = "Four10.com"
  dst_timezone     = "-7"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "admin@four10.com"
  dst_src          = "mirrors.kernel.org"

# dst_dst          = "http://cpan.four10.com"
# dst_contact      = "mailto:admin@four10.com
# dst_src          = "mirrors.kernel.org"

cpan-du.viaverio.com:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan-du.viaverio.com/pub/CPAN/"
  dst_http         = "http://cpan-du.viaverio.com/"
  dst_rsync        = "cpan-du.viaverio.com::CPAN"
  dst_location     = "Dulles, Virginia, United States, North America (38.98806 -77.52844)"
  dst_organisation = "viaVerio (NTT/Verio)"
  dst_timezone     = "-5"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "cpan@perlcode.org"
  dst_src          = "rsync.nic.funet.fi"
  dst_notes        = "https also available"

# dst_dst          = "ftp://cpan-du.viaverio.com/pub/CPAN/"
# dst_contact      = "mailto:cpan@perlcode.org
# dst_src          = "rsync.nic.funet.fi"

ftp.duke.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.duke.edu/pub/perl/"
  dst_location     = "Durham, North Carolina, United States, North America (35.999 -78.907)"
  dst_organisation = "Duke University"
  dst_timezone     = "-5"
  dst_contact      = "ftpadmin@ftp.duke.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.duke.edu/pub/perl/"
# dst_contact      = "mailto:ftpadmin@ftp.duke.edu
# dst_src          = "ftp.funet.fi"

cpan.cse.msu.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.cse.msu.edu/"
  dst_location     = "East Lansing, Michigan, United States, North America (42.7262 -84.48)"
  dst_organisation = "Computer Science and Engineering, Michigan State University"
  dst_timezone     = "-5"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "manager@cse.msu.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.cse.msu.edu/"
# dst_contact      = "mailto:manager@cse.msu.edu
# dst_src          = "ftp.funet.fi"

mirrors.rcn.net:
  frequency        = "daily"
  dst_ftp          = "ftp://mirrors.rcn.net/pub/lang/CPAN/"
  dst_http         = "http://mirrors.rcn.net/pub/lang/CPAN/"
  dst_location     = "Fairfax, Virginia, United States, North America (38.853 -77.298)"
  dst_organisation = "RCN Corporation"
  dst_timezone     = "-5"
  dst_contact      = "mirrors@rcn.com"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://mirrors.rcn.net/pub/lang/CPAN/"
# dst_contact      = "mailto:mirrors@rcn.com
# dst_src          = "ftp.cpan.org"

perl.secsup.org:
  frequency        = "daily"
  dst_ftp          = "ftp://perl.secsup.org/pub/perl/"
  dst_http         = "http://perl.secsup.org/"
  dst_location     = "Fairfax, Virginia, United States, North America (38.867584 -77.233474)"
  dst_organisation = "UUNET Technologies"
  dst_timezone     = "-5"
  dst_bandwidth    = "OC-12"
  dst_contact      = "chris@uu.net brian@uu.net"
  dst_src          = "mirrors.rcn.net"

# dst_dst          = "ftp://perl.secsup.org/pub/perl/"
# dst_contact      = "mailto:chris@uu.net brian@uu.net
# dst_src          = "mirrors.rcn.net"

noc.cvaix.com:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://noc.cvaix.com/mirrors/CPAN/"
  dst_location     = "Fredericksburg, Virginia, United States, North America (38.300 -77.450)"
  dst_organisation = "Central Virginia Internet eXchange"
  dst_timezone     = "-5"
  dst_bandwidth    = "Multiple T1"
  dst_contact      = "support@cvaix.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://noc.cvaix.com/mirrors/CPAN/"
# dst_contact      = "mailto:support@cvaix.com
# dst_src          = "ftp.funet.fi"

ftp.cise.ufl.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.cise.ufl.edu/pub/mirrors/CPAN/"
  dst_location     = "Gainesville, Florida, United States, North America (29.674 -82.336)"
  dst_organisation = "Computer and Information Science and Engineering Department, University of Florida"
  dst_timezone     = "-5"
  dst_contact      = "mirror@cise.ufl.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.cise.ufl.edu/pub/mirrors/CPAN/"
# dst_contact      = "mailto:mirror@cise.ufl.edu
# dst_src          = "ftp.funet.fi"

cpan.netnitco.net:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.netnitco.net/pub/mirrors/CPAN/"
  dst_http         = "http://cpan.netnitco.net/"
  dst_location     = "Hebron, Indiana, United States, North America (41.322 -87.202)"
  dst_organisation = "NetNITCO Internet Services"
  dst_timezone     = "-6"
  dst_bandwidth    = "DS3"
  dst_contact      = "mirrors@netnitco.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.netnitco.net/pub/mirrors/CPAN/"
# dst_contact      = "mailto:mirrors@netnitco.net
# dst_src          = "ftp.funet.fi"

binarycode.org:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://www.binarycode.org/cpan"
  dst_location     = "Houston, Texas, United States, North America (33.891 -89.023)"
  dst_organisation = "A. P. Andrews"
  dst_timezone     = "-6"
  dst_bandwidth    = "DS3"
  dst_contact      = "stephan.jau@apandrews.com"
  dst_src          = "cpan.teleglobe.net"

# dst_dst          = "http://www.binarycode.org/cpan"
# dst_contact      = "mailto:stephan.jau@apandrews.com
# dst_src          = "cpan.teleglobe.net"

mirror.telentente.com:
  frequency        = "daily"
  dst_ftp          = "ftp://mirror.telentente.com/pub/CPAN"
  dst_location     = "Houston, Texas, United States, North America (29.9405 -95.4139)"
  dst_organisation = "Telentente, Inc."
  dst_timezone     = "-6"
  dst_bandwidth    = "OC12"
  dst_contact      = "ftp@telentente.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirror.telentente.com/pub/CPAN"
# dst_contact      = "mailto:ftp@telentente.com
# dst_src          = "ftp.funet.fi"

mirrrors.theonlinerecordstore.com:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://mirrors.theonlinerecordstore.com/CPAN"
  dst_location     = "Houston, Texas, United States, North America (29.9806 -95.3397)"
  dst_organisation = "The Online Record Store"
  dst_timezone     = "-5"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "mitch@theonlinerecordstore.com"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "http://mirrors.theonlinerecordstore.com/CPAN"
# dst_contact      = "mailto:mitch@theonlinerecordstore.com
# dst_src          = "rsync.nic.funet.fi"

mirror.hiwaay.net:
  frequency        = "daily"
  dst_ftp          = "ftp://mirror.hiwaay.net/CPAN/"
  dst_http         = "http://mirror.hiwaay.net/CPAN/"
  dst_location     = "Huntsville, Alabama, United States, North America (34.725961 -86.596365)"
  dst_organisation = "HiWAAY Information Services"
  dst_timezone     = "-6"
  dst_contact      = "mirror@hiwaay.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirror.hiwaay.net/CPAN/"
# dst_contact      = "mailto:mirror@hiwaay.net
# dst_src          = "ftp.funet.fi"

archive.progeny.com:
  frequency        = "twice daily"
  dst_ftp          = "ftp://archive.progeny.com/CPAN/"
  dst_http         = "http://archive.progeny.com/CPAN/"
  dst_rsync        = "archive.progeny.com::CPAN"
  dst_location     = "Indianapolis, Indiana, United States, North America (39.9119 -86.0747)"
  dst_organisation = "Progeny Linux Systems, Inc."
  dst_timezone     = "-6"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "archive@progeny.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://archive.progeny.com/CPAN/"
# dst_contact      = "mailto:archive@progeny.com
# dst_src          = "ftp.funet.fi"

ftp.sunsite.utk.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.sunsite.utk.edu/pub/CPAN/"
  dst_location     = "Knoxville, Tennessee, United States, North America (35.970 -83.918)"
  dst_organisation = "SunSITE@UTK, University of Tennessee, Knoxville"
  dst_timezone     = "-5"
  dst_contact      = "mirrormgr@sunsite.utk.edu"
  dst_src          = "www.cpan.org"

# dst_dst          = "ftp://ftp.sunsite.utk.edu/pub/CPAN/"
# dst_contact      = "mailto:mirrormgr@sunsite.utk.edu
# dst_src          = "www.cpan.org"

cpan.uky.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.uky.edu/pub/CPAN/"
  dst_http         = "http://cpan.uky.edu/"
  dst_location     = "Lexington, Kentucky, United States, North America (38.0488 -84.4996)"
  dst_organisation = "University of Kentucky"
  dst_timezone     = "-5"
  dst_bandwidth    = "DS3"
  dst_contact      = "soward@uky.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.uky.edu/pub/CPAN/"
# dst_contact      = "mailto:soward@uky.edu
# dst_src          = "ftp.funet.fi"

cpan.develooper.com:
  frequency        = "hourly"
  dst_ftp          = ""
  dst_http         = "http://cpan.develooper.com/"
  dst_location     = "Los Angeles, California, United States, North America (34.050 -118.233)"
  dst_organisation = "Develooper LLC"
  dst_timezone     = "-8"
  dst_bandwidth    = "100Mbit"
  dst_contact      = "ask@develooper.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://cpan.develooper.com/"
# dst_contact      = "mailto:ask@develooper.com
# dst_src          = "ftp.funet.fi"

cpan.valueclick.com:
  frequency        = "hourly"
  dst_ftp          = "ftp://cpan.valueclick.com/pub/CPAN/"
  dst_http         = "http://www.cpan.org/"
  dst_location     = "Los Angeles, California, United States, North America (33.977876 -118.452475)"
  dst_organisation = "ValueClick"
  dst_timezone     = "-8"
  dst_contact      = "ask-mirror@perl.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.valueclick.com/pub/CPAN/"
# dst_contact      = "mailto:ask-mirror@perl.org
# dst_src          = "ftp.funet.fi"

mednor.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.mednor.net/pub/mirrors/CPAN/"
  dst_http         = "http://www.mednor.net/ftp/pub/mirrors/CPAN/"
  dst_location     = "Los Angeles, California, United States, North America (34.052 -118.243)"
  dst_organisation = "Mednor, Inc."
  dst_timezone     = "-8"
  dst_bandwidth    = "OC48"
  dst_contact      = "webmaster@mednor.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.mednor.net/pub/mirrors/CPAN/"
# dst_contact      = "mailto:webmaster@mednor.net
# dst_src          = "ftp.funet.fi"

mirrors.gossamer-threads.com:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://mirrors.gossamer-threads.com/CPAN"
  dst_location     = "Los Angeles, California, United States, North America (34.0522 -118.2434)"
  dst_organisation = "Gossamer Threads Inc."
  dst_timezone     = "-8"
  dst_bandwidth    = "T3"
  dst_contact      = "mirrors@gossamer-threads.com"
  dst_src          = "cpan.valueclick.com"

# dst_dst          = "http://mirrors.gossamer-threads.com/CPAN"
# dst_contact      = "mailto:mirrors@gossamer-threads.com
# dst_src          = "cpan.valueclick.com"

slugsite.louisville.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://slugsite.louisville.edu/CPAN"
  dst_http         = "http://slugsite.louisville.edu/cpan"
  dst_rsync        = "rsync://slugsite.louisville.edu::CPAN"
  dst_location     = "Louisville, Kentucky, United States, North America (38.15 -85.46)"
  dst_organisation = "University of Louisville ACM"
  dst_timezone     = "-5"
  dst_bandwidth    = "T3"
  dst_contact      = "Greg Leffler greg.leffler@louisville.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://slugsite.louisville.edu/CPAN"
# dst_contact      = "mailto:Greg Leffler greg.leffler@louisville.edu
# dst_src          = "ftp.funet.fi"

mirror.doit.wisc.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://mirror.sit.wisc.edu/pub/CPAN/"
  dst_http         = "http://mirror.sit.wisc.edu/pub/CPAN/"
  dst_location     = "Madison, Wisconsin, United States, North America (43.04 -89.24)"
  dst_organisation = "University of Wisconsin - Madison"
  dst_timezone     = "-6"
  dst_bandwidth    = "T3"
  dst_contact      = "ftpkeeper@mirror.doit.wisc.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirror.sit.wisc.edu/pub/CPAN/"
# dst_contact      = "mailto:ftpkeeper@mirror.doit.wisc.edu
# dst_src          = "ftp.funet.fi"

mirror.aphix.com:
  frequency        = "daily"
  dst_ftp          = "ftp://mirror.aphix.com/pub/CPAN"
  dst_http         = "http://mirror.aphix.com/CPAN"
  dst_rsync        = "mirror.aphix.com::CPAN"
  dst_location     = "Milwaukee, Wisconsin, United States, North America (43.039 -87.906)"
  dst_organisation = "Aphix Networks, Ltd."
  dst_timezone     = "-6"
  dst_bandwidth    = "100Mbit"
  dst_contact      = "mirror@aphix.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirror.aphix.com/pub/CPAN"
# dst_contact      = "mailto:mirror@aphix.com
# dst_src          = "ftp.funet.fi"

cpan.nas.nasa.gov:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.nas.nasa.gov/pub/perl/CPAN/"
  dst_location     = "Moffett Field, California, United States, North America (37.26 -122.08)"
  dst_organisation = "NASA Ames Research Center/Numerical Aerospace Simulation Facility"
  dst_timezone     = "-8"
  dst_contact      = ""
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.nas.nasa.gov/pub/perl/CPAN/"
# dst_contact      = "mailto:
# dst_src          = "ftp.funet.fi"

cpan.belfry.net:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.belfry.net/"
  dst_location     = "New York, New York, United States, North America (40.741891 -73.994778)"
  dst_organisation = "The Belfry(!)"
  dst_timezone     = "-5"
  dst_bandwidth    = "T1"
  dst_contact      = "jerlbaum@cpan.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://cpan.belfry.net/"
# dst_contact      = "mailto:jerlbaum@cpan.org
# dst_src          = "ftp.funet.fi"

cpan.erlbaum.net:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.erlbaum.net/"
  dst_http         = "http://cpan.erlbaum.net/"
  dst_location     = "New York, New York, United States, North America (40.7418 -73.9947)"
  dst_organisation = "The Erlbaum Group"
  dst_timezone     = "-5"
  dst_bandwidth    = "T1"
  dst_contact      = "jerlbaum@cpan.org"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "ftp://cpan.erlbaum.net/"
# dst_contact      = "mailto:jerlbaum@cpan.org
# dst_src          = "rsync.nic.funet.fi"

cpan.thepirtgroup.com:
  frequency        = "twice daily"
  dst_ftp          = "ftp://cpan.thepirtgroup.com/"
  dst_http         = "http://cpan.thepirtgroup.com/"
  dst_location     = "New York, New York, United States, North America (40.75461 -73.986625)"
  dst_organisation = "The PIRT Group"
  dst_timezone     = "-5"
  dst_bandwidth    = "T3"
  dst_contact      = "stregar@about-inc.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.thepirtgroup.com/"
# dst_contact      = "mailto:stregar@about-inc.com
# dst_src          = "ftp.funet.fi"

ftp.stealth.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.stealth.net/pub/CPAN/"
  dst_location     = "New York, New York, United States, North America (40.755 -73.986)"
  dst_organisation = "Stealth Communications, Inc."
  dst_timezone     = "-5"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "ftp@stealth.net"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://ftp.stealth.net/pub/CPAN/"
# dst_contact      = "mailto:ftp@stealth.net
# dst_src          = "ftp.cpan.org"

cont1.njy.teleglobe.net:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.teleglobe.net/pub/CPAN"
  dst_http         = "http://cpan.teleglobe.net/"
  dst_rsync        = "cpan.teleglobe.net::CPAN"
  dst_location     = "Newark, New Jersey, United States, North America (40.735559 -74.172703)"
  dst_organisation = "Teleglobe"
  dst_timezone     = "-5"
  dst_bandwidth    = "OC48"
  dst_contact      = "mirror@teleglobe.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.teleglobe.net/pub/CPAN"
# dst_contact      = "mailto:mirror@teleglobe.net
# dst_src          = "ftp.funet.fi"

ftp.lug.udel.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.lug.udel.edu/pub/CPAN"
  dst_http         = "http://ftp.lug.udel.edu/pub/CPAN"
  dst_rsync        = "ftp.lug.udel.edu::cpan"
  dst_location     = "Newark, Delaware, United States, North America (39.683 -75.750)"
  dst_organisation = "University of Delaware Linux Users Group"
  dst_timezone     = "-5"
  dst_bandwidth    = "OC3"
  dst_contact      = "seitz@lug.udel.edu"
  dst_src          = "carroll.cac.psu.edu"

# dst_dst          = "ftp://ftp.lug.udel.edu/pub/CPAN"
# dst_contact      = "mailto:seitz@lug.udel.edu
# dst_src          = "carroll.cac.psu.edu"

ftp.ou.edu:
  frequency        = "twice daily"
  dst_ftp          = "ftp://ftp.ou.edu/mirrors/CPAN/"
  dst_location     = "Norman, Oklahoma, United States, North America (35.225 -97.343)"
  dst_organisation = "University of Oklahoma"
  dst_timezone     = "-6"
  dst_contact      = "ftp@ou.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ou.edu/mirrors/CPAN/"
# dst_contact      = "mailto:ftp@ou.edu
# dst_src          = "ftp.funet.fi"

mirrors.kernel.org:
  frequency        = "hourly"
  dst_ftp          = "ftp://mirrors.kernel.org/pub/CPAN"
  dst_http         = "http://mirrors.kernel.org/cpan/"
  dst_rsync        = "mirrors.kernel.org::mirrors/CPAN"
  dst_location     = "Palo Alto, California, United States, North America (37.445698 -122.161077)"
  dst_organisation = "The Linux Kernel Archives"
  dst_timezone     = "-8"
  dst_bandwidth    = "100Mbit/s"
  dst_contact      = "mirroradmin@kernel.org"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirrors.kernel.org/pub/CPAN"
# dst_contact      = "mailto:mirroradmin@kernel.org
# dst_src          = "ftp.funet.fi"

mirrors.phenominet.com:
  frequency        = "daily"
  dst_ftp          = "ftp://mirrors.phenominet.com/pub/CPAN/"
  dst_http         = "http://mirrors.phenominet.com/pub/CPAN/"
  dst_rsync        = "mirrors.phenominet.com::CPAN"
  dst_location     = "Philadelphia, Pennsylvania, United States, North America (39.9616 -75.1995)"
  dst_organisation = "Phenomenal Internet Solutions"
  dst_timezone     = "-5"
  dst_bandwidth    = "30Mbps"
  dst_contact      = "webmaster@phenominet.com"
  dst_src          = "archive.progeny.com"
  dst_notes        = "Limit 500 users"

# dst_dst          = "ftp://mirrors.phenominet.com/pub/CPAN/"
# dst_contact      = "mailto:webmaster@phenominet.com
# dst_src          = "archive.progeny.com"

cpan.pair.com:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.pair.com/pub/CPAN/"
  dst_http         = "http://cpan.pair.com/"
  dst_rsync        = "cpan.pair.com::CPAN"
  dst_location     = "Pittsburgh, Pennsylvania, United States, North America (40.437 -80.000)"
  dst_organisation = "pair Networks, Inc."
  dst_timezone     = "-5"
  dst_bandwidth    = "multiple OC-12s and Gigabit Ethernet"
  dst_contact      = "CPAN@pair.com"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "ftp://cpan.pair.com/pub/CPAN/"
# dst_contact      = "mailto:CPAN@pair.com
# dst_src          = "rsync.nic.funet.fi"

ftp.ncsu.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.ncsu.edu/pub/mirror/CPAN/"
  dst_location     = "Raleigh, North Carolina, United States, North America (35.4730 -78.4025)"
  dst_organisation = "North Carolina State University"
  dst_timezone     = "-5"
  dst_bandwidth    = "OC48"
  dst_contact      = "ftp@unity.ncsu.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.ncsu.edu/pub/mirror/CPAN/"
# dst_contact      = "mailto:ftp@unity.ncsu.edu
# dst_src          = "ftp.funet.fi"

oss.redundant.com:
  frequency        = "daily"
  dst_ftp          = "ftp://www.oss.redundant.com/pub/CPAN"
  dst_http         = "http://www.oss.redundant.com/pub/CPAN"
  dst_location     = "Reno, Nevada, United States, North America (39.5167 -119.8000)"
  dst_organisation = "Redundant Networks"
  dst_timezone     = "-8"
  dst_bandwidth    = "Dual OC3"
  dst_contact      = "cpan@redundant.com"
  dst_src          = "mirrors.kernel.org"

# dst_dst          = "ftp://www.oss.redundant.com/pub/CPAN"
# dst_contact      = "mailto:cpan@redundant.com
# dst_src          = "mirrors.kernel.org"

fx.saintjoe.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.saintjoe.edu/pub/CPAN"
  dst_http         = "http://fx.saintjoe.edu/pub/CPAN"
  dst_location     = "Rensselar, Indiana, United States, North America (40.9202 -871573)"
  dst_organisation = "Saint Joseph's College"
  dst_timezone     = "-5"
  dst_bandwidth    = "T1"
  dst_contact      = "ftp@saintjoe.edu"
  dst_src          = "ftp.cpan.org"
  dst_notes        = "Limit 50 anonymous ftp users."

# dst_dst          = "ftp://ftp.saintjoe.edu/pub/CPAN"
# dst_contact      = "mailto:ftp@saintjoe.edu
# dst_src          = "ftp.cpan.org"

ftp.rge.com:
  frequency        = "twice daily"
  dst_ftp          = "ftp://ftp.rge.com/pub/languages/perl/"
  dst_http         = "http://www.rge.com/pub/languages/perl/"
  dst_location     = "Rochester, New York, United States, North America (43.157 -77.606)"
  dst_organisation = "Rochester Gas and Electric"
  dst_timezone     = "-5"
  dst_contact      = "ftp@rge.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.rge.com/pub/languages/perl/"
# dst_contact      = "mailto:ftp@rge.com
# dst_src          = "ftp.funet.fi"

mirror.xmission.com:
  frequency        = "daily"
  dst_ftp          = "ftp://mirror.xmission.com/CPAN/"
  dst_location     = "Salt Lake City, Utah, United States, North America (40.771 -111.891)"
  dst_organisation = "XMission Internet"
  dst_timezone     = ""
  dst_contact      = "mirror@xmission.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirror.xmission.com/CPAN/"
# dst_contact      = "mailto:mirror@xmission.com
# dst_src          = "ftp.funet.fi"

cpan-sj.viaverio.com:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan-sj.viaverio.com/pub/CPAN/"
  dst_http         = "http://cpan-sj.viaverio.com/"
  dst_rsync        = "cpan-sj.viaverio.com::CPAN"
  dst_location     = "San Jose, California, United States, North America (37.30400 -121.84978)"
  dst_organisation = "viaVerio (NTT/Verio)"
  dst_timezone     = "-8"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "cpan@perlcode.org"
  dst_src          = "rsync.nic.funet.fi"
  dst_notes        = "https also available (same URL as http)"

# dst_dst          = "ftp://cpan-sj.viaverio.com/pub/CPAN/"
# dst_contact      = "mailto:cpan@perlcode.org
# dst_src          = "rsync.nic.funet.fi"

cpan.digisle.net:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.digisle.net/pub/CPAN"
  dst_http         = "http://cpan.digisle.net/"
  dst_location     = "San Jose, California, United States, North America (37.21 -121.54)"
  dst_organisation = "Digital Island"
  dst_timezone     = "-8"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "cpan-mirror-admin@digisle.net"
  dst_src          = "onion.valueclick.com"

# dst_dst          = "ftp://cpan.digisle.net/pub/CPAN"
# dst_contact      = "mailto:cpan-mirror-admin@digisle.net
# dst_src          = "onion.valueclick.com"

cpan.llarian.net:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.llarian.net/pub/CPAN/"
  dst_http         = "http://cpan.llarian.net/"
  dst_location     = "Seattle, Washington, United States, North America (47.612 -122.338)"
  dst_organisation = "Semaphore Corporation"
  dst_timezone     = "-8"
  dst_bandwidth    = "GigE"
  dst_contact      = "llarian@llarian.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.llarian.net/pub/CPAN/"
# dst_contact      = "mailto:llarian@llarian.net
# dst_src          = "ftp.funet.fi"

cpan.mirrorcentral.com:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.mirrorcentral.com/pub/CPAN/"
  dst_http         = "http://cpan.mirrorcentral.com/"
  dst_location     = "Seattle, Washington, United States, North America (47.6115 -122.3343)"
  dst_organisation = "F5 Networks & MirrorCentral.com"
  dst_timezone     = "-8"
  dst_bandwidth    = "T3"
  dst_contact      = "steve@mirrorcentral.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.mirrorcentral.com/pub/CPAN/"
# dst_contact      = "mailto:steve@mirrorcentral.com
# dst_src          = "ftp.funet.fi"

ftp-mirror.internap.com:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp-mirror.internap.com/pub/CPAN/"
  dst_location     = "Seattle, Washington, United States, North America (47.612 -122.338)"
  dst_organisation = "InterNAP Network Services"
  dst_timezone     = "-8"
  dst_bandwidth    = "OC-12"
  dst_contact      = "ftpadmin@internap.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp-mirror.internap.com/pub/CPAN/"
# dst_contact      = "mailto:ftpadmin@internap.com
# dst_src          = "ftp.funet.fi"

www.perl.com:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://www.perl.com/CPAN/"
  dst_location     = "Sebastopol, California, United States, North America (38.4030 -122.8188)"
  dst_organisation = "The O'Reilly Network's perl.com"
  dst_timezone     = "-8"
  dst_contact      = "cpan@www.perl.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://www.perl.com/CPAN/"
# dst_contact      = "mailto:cpan@www.perl.com
# dst_src          = "ftp.funet.fi"

mirror.csit.fsu.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://mirror.csit.fsu.edu/pub/CPAN/"
  dst_http         = "http://mirror.csit.fsu.edu/pub/CPAN/"
  dst_rsync        = "mirror.csit.fsu.edu::CPAN"
  dst_location     = "Tallahassee, Florida, United States, North America (30.38 -84.37)"
  dst_organisation = "Computational Science & Information Technology at FSU"
  dst_timezone     = "-6"
  dst_bandwidth    = "T3"
  dst_contact      = "merlin@ophelan.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirror.csit.fsu.edu/pub/CPAN/"
# dst_contact      = "mailto:merlin@ophelan.com
# dst_src          = "ftp.funet.fi"

shai.nks.net:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.mirrors.nks.net/"
  dst_location     = "Tampa, Florida, United States, North America (27.9754722 -82.5332500)"
  dst_organisation = "NKS (Networked Knowledge Systems, Inc.)"
  dst_timezone     = "-5"
  dst_bandwidth    = "T3"
  dst_contact      = "ebravick@nks.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "http://cpan.mirrors.nks.net/"
# dst_contact      = "mailto:ebravick@nks.net
# dst_src          = "ftp.funet.fi"

carroll.cac.psu.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://carroll.cac.psu.edu/pub/CPAN/"
  dst_location     = "University Park, Pennsylvania, United States, North America (40.801 -77.856)"
  dst_organisation = "The Pennsylvania State University"
  dst_timezone     = "-5"
  dst_bandwidth    = "OC3"
  dst_contact      = "ftpkeeper@carroll.cac.psu.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://carroll.cac.psu.edu/pub/CPAN/"
# dst_contact      = "mailto:ftpkeeper@carroll.cac.psu.edu
# dst_src          = "ftp.funet.fi"

www.uberian.net:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://www.uberlan.net/CPAN"
  dst_location     = "Vallejo, California, United States, North America (38.40 -122.8188)"
  dst_organisation = "uberLAN Technologies"
  dst_timezone     = "-8"
  dst_bandwidth    = "T3"
  dst_contact      = "sys-admin@uberian.net"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "http://www.uberlan.net/CPAN"
# dst_contact      = "mailto:sys-admin@uberian.net
# dst_src          = "rsync.nic.funet.fi"

ftp.dc.aleron.net:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.dc.aleron.net/pub/CPAN/"
  dst_location     = "Washington, District of Columbia, United States, North America (39.0239 -77.2911)"
  dst_organisation = "Aleron"
  dst_timezone     = "-5"
  dst_bandwidth    = "100Mbps"
  dst_contact      = "ftp@aleron.net"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.dc.aleron.net/pub/CPAN/"
# dst_contact      = "mailto:ftp@aleron.net
# dst_src          = "ftp.funet.fi"

csociety-ftp.ecn.purdue.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://csociety-ftp.ecn.purdue.edu/pub/CPAN"
  dst_http         = "http://csociety-ftp.ecn.purdue.edu/pub/CPAN"
  dst_rsync        = "csociety-ftp.ecn.purdue.edu::CPAN"
  dst_location     = "West Lafayette, Indiana, United States, North America (40.444 -86.911)"
  dst_organisation = "Purdue University IEEE Computer Society"
  dst_timezone     = "-5"
  dst_bandwidth    = "10Mbps"
  dst_contact      = "ftp@csociety.purdue.edu"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://csociety-ftp.ecn.purdue.edu/pub/CPAN"
# dst_contact      = "mailto:ftp@csociety.purdue.edu
# dst_src          = "ftp.funet.fi"

ftp.planetmirror.com:
  frequency        = "twice daily"
  dst_ftp          = "ftp://ftp.planetmirror.com/pub/CPAN/"
  dst_http         = "http://ftp.planetmirror.com/pub/CPAN/"
  dst_location     = "Brisbane, Queensland, Australia, Oceania (-27.500 153.000)"
  dst_organisation = "PlanetMirror.com"
  dst_timezone     = "+10"
  dst_bandwidth    = "155Mbps"
  dst_contact      = "mirror@planetmirror.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.planetmirror.com/pub/CPAN/"
# dst_contact      = "mailto:mirror@planetmirror.com
# dst_src          = "ftp.funet.fi"

mirror.aarnet.edu.au:
  frequency        = "daily"
  dst_ftp          = "ftp://mirror.aarnet.edu.au/pub/perl/CPAN/"
  dst_location     = "Brisbane, Queensland, Australia, Oceania (-27.5306 153.0286)"
  dst_organisation = "AARNet"
  dst_timezone     = "+10"
  dst_bandwidth    = "45Mbps"
  dst_contact      = "mirror@mirror.aarnet.edu.au"
  dst_src          = "ftp.digital.com"

# dst_dst          = "ftp://mirror.aarnet.edu.au/pub/perl/CPAN/"
# dst_contact      = "mailto:mirror@mirror.aarnet.edu.au
# dst_src          = "ftp.digital.com"

cpan.topend.com.au:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.topend.com.au/pub/CPAN/"
  dst_location     = "Darwin, Northern Territory, Australia, Oceania (-12.4336 130.8581)"
  dst_organisation = "Topend"
  dst_timezone     = "+9:30"
  dst_contact      = "nagy@topend.com.au"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://cpan.topend.com.au/pub/CPAN/"
# dst_contact      = "mailto:nagy@topend.com.au
# dst_src          = "ftp.funet.fi"

cpan.mirrors.ilisys.com.au:
  frequency        = "daily"
  dst_ftp          = ""
  dst_http         = "http://cpan.mirrors.ilisys.com.au"
  dst_location     = "Perth, Western Australia, Australia, Oceania (-31.9667 115.8167)"
  dst_organisation = "Ilisys Web Hosting"
  dst_timezone     = "+8"
  dst_bandwidth    = "34Mbit"
  dst_contact      = "mirrors@ilisys.com.au"
  dst_src          = "rsync.nic.funet.fi"
  dst_notes        = "please direct any questions to mirrors@ilisys.com.au"

# dst_dst          = "http://cpan.mirrors.ilisys.com.au"
# dst_contact      = "mailto:mirrors@ilisys.com.au
# dst_src          = "rsync.nic.funet.fi"

ftp.auckland.ac.nz:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.auckland.ac.nz/pub/perl/CPAN/"
  dst_location     = "Auckland, New Zealand, Oceania (-36.917 174.783)"
  dst_organisation = "Auckland University"
  dst_timezone     = "+12"
  dst_contact      = "webmaster@auckland.ac.nz"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.auckland.ac.nz/pub/perl/CPAN/"
# dst_contact      = "mailto:webmaster@auckland.ac.nz
# dst_src          = "ftp.funet.fi"

aniani.ifa.hawaii.edu:
  frequency        = "daily"
  dst_ftp          = "ftp://aniani.ifa.hawaii.edu/CPAN/"
  dst_http         = "http://aniani.ifa.hawaii.edu/CPAN/"
  dst_rsync        = "aniani.ifa.hawaii.edu::CPAN"
  dst_location     = "Hilo, Hawaii, United States, Oceania (19.7 -155.1)"
  dst_organisation = "Institute for Astronomy"
  dst_timezone     = "-10"
  dst_bandwidth    = "DS3"
  dst_contact      = "jhoblitt@ifa.hawaii.edu"
  dst_src          = "ftp.funet.fi"
  dst_notes        = "64 ftp/64 rsync/unlim. http"

# dst_dst          = "ftp://aniani.ifa.hawaii.edu/CPAN/"
# dst_contact      = "mailto:jhoblitt@ifa.hawaii.edu
# dst_src          = "ftp.funet.fi"

mirrors.bannerlandia.com.ar:
  frequency        = "twice daily"
  dst_ftp          = "ftp://mirrors.bannerlandia.com.ar/mirrors/CPAN/"
  dst_location     = "Buenos Aires, Argentina, South America (-34.6 -58.45)"
  dst_organisation = "Bannerlandia.com"
  dst_timezone     = "-3"
  dst_contact      = "mirrors@bannerlandia.com"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://mirrors.bannerlandia.com.ar/mirrors/CPAN/"
# dst_contact      = "mailto:mirrors@bannerlandia.com
# dst_src          = "ftp.funet.fi"

www.linux.org.ar:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.linux.org.ar/mirrors/cpan"
  dst_http         = "http://www.linux.org.ar/mirrors/cpan"
  dst_rsync        = "www.linux.org.ar::cpan"
  dst_location     = "Buenos Aires, Argentina, South America (-34.867 -57.917)"
  dst_organisation = "Linux Users Group Argentina"
  dst_timezone     = "-3"
  dst_bandwidth    = "T1"
  dst_contact      = "dcoletti@linux.org.ar"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.linux.org.ar/mirrors/cpan"
# dst_contact      = "mailto:dcoletti@linux.org.ar
# dst_src          = "ftp.funet.fi"

cpan.pop-mg.com.br:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.pop-mg.com.br/pub/CPAN/"
  dst_location     = "Belo Horizonte, Minas Gerais, Brazil, South America (-19.916 -43.933)"
  dst_organisation = "POP-MG"
  dst_timezone     = "-3"
  dst_contact      = "ftpadmin@pop-mg.com.br"
  dst_src          = "ftp.cpan.org"

# dst_dst          = "ftp://cpan.pop-mg.com.br/pub/CPAN/"
# dst_contact      = "mailto:ftpadmin@pop-mg.com.br
# dst_src          = "ftp.cpan.org"

ftp.matrix.com.br:
  frequency        = "daily"
  dst_ftp          = "ftp://ftp.matrix.com.br/pub/perl/CPAN/"
  dst_location     = "Florianopolis, Brazil, South America (-27.588 -48.575)"
  dst_organisation = "Matrix Internet"
  dst_timezone     = "-3"
  dst_bandwidth    = "E3"
  dst_contact      = "camposr@matrix.com.br"
  dst_src          = "ftp.funet.fi"

# dst_dst          = "ftp://ftp.matrix.com.br/pub/perl/CPAN/"
# dst_contact      = "mailto:camposr@matrix.com.br
# dst_src          = "ftp.funet.fi"

cpan.hostsul.com.br:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.hostsul.com.br/"
  dst_http         = "http://cpan.hostsul.com.br/"
  dst_location     = "Rio de Janeiro, Brazil, South America (-22.54 -43.14)"
  dst_organisation = "HostSul"
  dst_timezone     = "-3"
  dst_bandwidth    = "T3"
  dst_contact      = "cpan@hostsul.com.br"
  dst_src          = "rsync.nic.funet.fi"

# dst_dst          = "ftp://cpan.hostsul.com.br/"
# dst_contact      = "mailto:cpan@hostsul.com.br
# dst_src          = "rsync.nic.funet.fi"

cpan.netglobalis.net:
  frequency        = "daily"
  dst_ftp          = "ftp://cpan.netglobalis.net/pub/CPAN/"
  dst_http         = "http://cpan.netglobalis.net/"
  dst_location     = "Santiago, Chile, South America (-33.45 -70.666)"
  dst_organisation = "Comunicaciones Netglobalis S.A."
  dst_timezone     = "-4"
  dst_bandwidth    = "10Mbps"
  dst_contact      = "ftp-admin@netglobalis.net"
  dst_src          = "ftp.funet.fi"
  dst_notes        = "Bandwith is limited to international users to 2Mbps, national users to 10Mbps and local users to 100Mbps."

# dst_dst          = "ftp://cpan.netglobalis.net/pub/CPAN/"
# dst_contact      = "mailto:ftp-admin@netglobalis.net
# dst_src          = "ftp.funet.fi"


# here endeth MIRRORED.BY
__EOF__

1;

=pod

=head1 NAME

CPANPLUS::Configure::Setup - Configuration setup for CPAN++

=head1 SYNOPSIS

You will be automatically thrown to Setup when you install
CPANPLUS, or whenever your saved Config is corrupt.

You can run Setup explicitly (which will replace your existing Config) with:

    perl -MCPANPLUS::Configure::Setup -e 'CPANPLUS::Configure::Setup->init()'

=head1 DESCRIPTION

CPANPLUS::Configure::Setup prompts the user to enter information
that will be used by CPANPLUS.  The text accompanying the questions
should be sufficient to guide the user through the configuration.
The result of this inquiry is stored in Config.pm.  By default, this
information will be used by all CPANPLUS modules.  However, it is
possible to change some configuration options at runtime with

CPANPLUS::Configure (which will probably be accessed through
CPANPLUS::Backend).

=head1 AUTHORS

This module by
Joshua Boschert E<lt>jambe@cpan.orgE<gt>.

This pod text by Ann Barcomb E<lt>kudra@cpan.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001, 2002 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=head1 SEE ALSO

L<CPANPLUS::Configure>, L<CPANPLUS::Backend>

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
