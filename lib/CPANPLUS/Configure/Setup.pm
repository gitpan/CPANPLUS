# $File: //depot/cpanplus/dist/lib/CPANPLUS/Configure/Setup.pm $
# $Revision: #11 $ $Change: 3441 $ $DateTime: 2003/01/12 11:00:46 $

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
use Data::Dumper;
use Term::ReadLine;

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

    my $conf    = $args{conf};
    $term       = $args{term}       if exists $args{term};
    $backend    = $args{backend}    if exists $args{backend};


    my $loc;
    ### ask where the user wants to save the config.pm ###
    {
        ### nasty hack =(( -kane ###
        my $pm = File::Spec::Unix->catfile(qw|CPANPLUS Configure Setup.pm|);
        my $default = File::Spec->catfile( split '/', $INC{$pm} );
        $default =~ s/ure.Setup(\.pm)/$1/ig;

        my $home_conf = File::Spec->catdir($ENV{HOME}, '.cpanplus', 'config');

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

], $default, $home_conf);

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

    $conf->save($loc);

    print "\n", loc("Your CPAN++ configuration info has been saved!"), "\n\n";

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
Note this feature requires you to flush the 'lib' cache for longer
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
    my $shell   = $conf->get_conf('shell') || $default;

    my @list = ( $shell, $default, $compat, undef );

    print loc(qq[
By default CPAN++ uses its own shell when invoked.  If you would prefer
a different shell, such as one you have written or otherwise acquired,
please enter the full name for your shell module.

1) %1
2) %2
3) %3
4) other

],@list[0..2]);

    my $prompt = loc("Which CPANPLUS 'shell' do you want to use? " );

    my $pick = _get_reply(
        prompt  => $prompt . q|[1]: |,
        default => '1',
        choices => [ qw/1 2 3 4/ ],
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
        V: {
            #$new_path = $ENV{WIN2KTEST},   last V, if exists $ENV{USERPROFILE};
            $new_path = $ENV{USERPROFILE}, last V, if exists $ENV{USERPROFILE};
            $new_path = $ENV{WINDIR},      last V, if exists $ENV{WINDIR};
        } #V
        $new_path = File::Spec->catdir($new_path, 'Application Data', $dot_cpan);

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
                ? print loc("Your command line shell has been set to:\n    $prog\n\n")
                : print loc("I'm sorry, '%1' is not a valid option, please try again", $answer), "\n";

            last if $prog;
        }

        $conf->_set_build( shell => $prog );
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

        $pgms{$pgm} = $answer;

    } #for


    ##############
    ## save it! ##
    ##############

    $conf->_set_build(
        'base' => $cpan_home,
        %pgms,
    );

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
        ) or die loc("Fetch of %1 failed!", $file), "\n";

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
                = $uri =~ m{^([a-zA-Z]+)://([a-zA-Z0-9\.-]*)(/.*)$};


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

    my $fh = new FileHandle;

    ### file should have a size, else there is a problem ###
    -s $file or die loc("%1 has no size!", $file);

    $fh->open("<$file") or die loc("Couldn't open %1: %2", $file, $!);
    {
        local $/ = undef;
        $file    = <$fh>;
    }
    $fh->close;

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
