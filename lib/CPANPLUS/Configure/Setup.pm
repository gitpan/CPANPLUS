# $File: //depot/dist/lib/CPANPLUS/Configure/Setup.pm $
# $Revision: #4 $ $Change: 60 $ $DateTime: 2002/06/06 05:42:54 $

##################################################
###        CPANPLUS/Configure/Setup.pm         ###
###     Initial configuration for CPAN++       ###
##################################################

package CPANPLUS::Configure::Setup;

use strict;
use vars '$AutoSetup';
#use Exporter;
#use CPANPLUS::Configure;
#our @ISA = qw(Exporter);

use CPANPLUS::Backend;

use Config;
use Cwd qw(getcwd);
use ExtUtils::MakeMaker ();
use File::Path ();
use File::Spec;
use FileHandle ();
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


## gather information needed to initialize CPANPLUS
##
## (takes conf => Configure object and term => Term object, returns no values)
##
sub init {
    my ($self, %args) = @_;

    my $conf = $args{conf};
    $term = $args{term} if exists $args{term};

    unless ($conf->can_save) {
        print "*** Error: CPANPLUS $CPANPLUS::Internals::VERSION was not ",
              "configured properly, and we cannot write to\n",
              "    '$INC{'CPANPLUS/Config.pm'}'.\n".
              "*** Please check its permission, or contact your administrator.\n";
        exit 1;
    }

    local $SIG{INT};

    #my ($answer, $prompt, $default);
    print qq[

CPAN is the world-wide archive of perl resources. It consists of about
100 sites that all replicate the same contents all around the globe.
Many countries have at least one CPAN site already. The resources found
on CPAN are easily accessible with CPANPLUS modules. If you want to use
CPANPLUS, you have to configure it properly.

];

    my $answer;

    unless (defined $AutoSetup) {
        print qq[
Although we recommend an interactive configuration session, you can
also enter 'n' here to use default values for all questions.

];

        $answer = _get_reply(
            prompt  => "Are you ready for manual configuration? [Y/n]: ",
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

    $conf->save;

    print "\nYour CPAN++ configuration info has been saved!\n\n";

    # removes the terminal instance to avoid "Falling back to dumb"
    no strict 'refs';
    undef ${ref($term)."::term"} unless $[ < 5.006; # 5.005 chokes on this

} #init


## gather all info needed for the 'conf' hash
##
## (takes Configure object, returns no values)
##
sub _setup_conf {

    my $conf = shift;
    my ($answer, $prompt, $default);

    #####################
    ## makemaker flags ##
    #####################

    print qq[
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

];

    my $MMflags = _ask_flags(
        MakeMaker => $conf->get_conf('makemakerflags'),
    );

    ################
    ## make flags ##
    ################

    print qq[
Like Makefile.PL, we run 'make' and 'make install' as separate processes.
If you have any parameters (e.g. '-j3' in dual processor systems) you want
to pass to the calls, please specify them here.

In particular, 'UNINST=1' is recommended for root users, unless you have
fine-tuned ideas of where modules should be installed in the \@INC path.

Enter a name=value list separated by whitespace, but quote any embedded
spaces that you want to preserve.  (Enter a space to clear any existing
settings.)

Again, if you don't understand this question, just press ENTER.

];

    my $makeflags = _ask_flags(
        "'make'" => $conf->get_conf('makeflags'),
    );

    #################
    ## shift a lib ##
    #################

    print q[
If you like, CPAN++ can add extra directories to your @INC list starts
during startup.  Enter a space separated list of list to be added to
your @INC, quoting anything with embedded whitespace.  (To clear the
current value enter a single space.)

];

    my $lib = $conf->get_conf('lib');

    $answer = _get_reply(
                  prompt  => "Additional \@INC directories to add? [@{$lib}]: ",
                  default => "@{$lib}",
              );

    if ($answer) {
        if ($answer =~ m/^\s+$/) {
            $lib = [];
        } else {
            (@{$lib}) = $answer =~ m/\s*("[^"]+"|'[^']+'|[^\s]+)/g;
        } #if
    } #if

    printf "\nYour additional libs are now:\n";

    if (@{$lib}) {
        print map { "    $_\n" } @{$lib};
    } else {
        print "    *nothing entered*\n";
    } #if

    print "\n";


    ############
    ## noisy? ##
    ############

    print q[
In normal operation I can just give you basic information about what I
am doing, or I can be more verbose and give you every little detail.

];

    $answer = _get_reply(
                  prompt  => "Should I be verbose? [N/y]: ",
                  default => 'n',
                  choices => [ qw/y n/ ],
              );

    my $verbose;
    print "\n";

    if ($answer =~ /^y/i) {
        $verbose = 1;
        print "You asked for it!";
    } else {
        $verbose = 0;
        print "I'll try to be quiet.";
    } #if

    print "\n\n";


    #######################
    ## flush you animal! ##
    #######################

    print q[
In the interest of speed, we keep track of what modules were installed
successfully and which failed in the current session.  We can flush this
data automatically, or you can explicitly issue a 'flush' when you want
to purge it.

];

    $answer = _get_reply(
                    prompt  => "Flush automatically? [Y/n]: ",
                    default => 'Y',
                    choices => [ qw/y n/ ],
              );

    my $flush;
    print "\n";

    if ($answer =~ /^y/i) {
        $flush = 1;
        print "I'll flush after every full module install.";
    } else {
        $flush = 0;
        print "I won't flush until you tell me to.  (It could get smelly in here! ;o)";
    } #if

    print "\n\n";


    ###################
    ## get in there! ##
    ###################

    print q[
Usually, when a test fails, I won't install the module, but if you
prefer, I can force the install anyway.

];

    $answer = _get_reply(
                    prompt  => "Force installs? [N/y]: ",
                    default => 'n',
                    choices => [ qw/y n/ ],
              );

    my $force;
    print "\nOk, ";

    if ($answer =~ /^y/i) {
        $force = 1;
        print "I will";
    } else {
        $force = 0;
        print "I won't";
    } #if

    print " force installs.\n\n";


    ################################
    ## follow, follow, follow me! ##
    ################################

    print q[
Sometimes a module will require other modules to be installed before it
will work.  CPAN++ can attempt to install these for you automatically
if you like, or you can do the deed yourself.

If you would prefer that we NEVER try to install extra modules
automatically, select NO.  (Usually you will want this set to YES.)
Otherwise, select ASK to have us ask your permission to install them.

];

    $answer = _get_reply(
                    prompt  => "Follow prereqs? [A/y/n]: ",
                    default => 'a',
                    choices => [ qw/y n a/ ],
              );

    my $prereqs;
    print "\nOk, ";

    if ($answer =~ /^y/i) {
        $prereqs = 1;
        print "I will";
    } elsif ( $answer =~ /^a/i) {
        $prereqs = 2;
        print "I will ask permission to";
    } else {
        $prereqs = 0;
        print "I won't";
    } #if

    print " follow prereqs.\n\n";


    ####################
    ## safety is good ##
    ####################

    print q[
The modules in the CPAN archives are protected with md5 checksums.

];

    my $have_md5 = eval "use Digest::MD5; 1";
    $answer = _get_reply(
                    prompt  => "Use the md5 checksums? "._yn($have_md5),
                    default => $have_md5 ? 'y' : 'n',
                    choices => [ qw/y n/ ],
              );

    my $md5;
    print "\nOk, ";

    if ($answer =~ /^y/i) {
        $md5 = 1;
        print "I will";
    } else {
        $md5 = 0;
        print "I won't";
    } #if

    print " use md5 if you have it.\n\n";


    ###########################################
    ## sally sells seashells by the seashore ##
    ###########################################

    print q[
By default CPAN++ uses it's own shell when invoked.  If you would prefer
a different shell, such as one you have written or otherwise acquired,
please enter the full name for your shell module.

];

    my $shell = $conf->get_conf('shell') || '';

    $shell = _get_reply(
                    prompt  => "CPAN++ 'shell' you want to use? [$shell]: ",
                    default => $shell,
                 );

    print "\nYour 'shell' is now:\n    $shell\n", if ($shell);
    print "\n";


    ###################
    ## use storable? ##
    ###################

    print q[
To speed up the start time of CPAN++ we can use Storable to freeze some
information.  Would you like to do this?

];

    my $have_storable = eval "use Storable; 1";
    $answer = _get_reply(
                    prompt  => "Use Storable? "._yn($have_storable),
                    default => $have_storable ? 'y' : 'n',
                    choices => [ qw/y n/ ],
              );

    my $storable;
    print "\n";

    if ($answer =~ /^y/i) {
        $storable = 1;
        print "I will use Storable if you have it.";
    } else {
        $storable = 0;
        print "I am NOT going to use Storable.";
    } #if

    print "\n\n";


    ###################
    ## use cpantest? ##
    ###################

    print q[
CPANPLUS comes with the "cpantest" utility, which can be utilized to
report success and failures of modules installed by CPANPLUS.  Would
you like to do this?  Note that you will still be prompted before
sending each report.

];

    $answer = _get_reply(
                    prompt  => "Report tests results? [y/N]: ",
                    default => 'n',
                    choices => [ qw/y n/ ],
              );

    my $cpantest;
    print "\nOk, ";

    if ($answer =~ /^y/i) {
        $cpantest = 1;
        print "I will prompt you to";
    } else {
        $cpantest = 0;
        print "I won't";
    } #if

    print " report test results.\n\n";

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
        shell          => $shell,
        storable       => $storable,
        verbose        => $verbose,
    );

} #_setup_conf


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

    print q[
If you are connecting through a firewall or proxy that doesn't handle
FTP all that well you can use passive FTP.

];

    $answer = _get_reply(
                    prompt  => "Use passive FTP? [Y/n]: ",
                    default => 'y',
                    choices => [ qw/y n/ ],
              );

    my $passive;
    print "\n";

    if ($answer =~ /^y/i) {
        $passive = 1;

        ### set the ENV var as well, else it won't get set till AFTER
        ### the configuration is saved. but we fetch files BEFORE that.
        $ENV{FTP_PASSIVE} = 1;

        print "I will";
    } else {
        $passive = 0;
        print "I won't";
    } #if

    print " use passive FTP.\n\n";


    ############################
    ## where can I reach you? ##
    ############################

    print q[
What email address should we send as our anonymous password when
fetching modules from CPAN servers?  Some servers will NOT allow you to
connect without a valid email address, or at least something that looks
like one.

];

    my $email   = $conf->_get_ftp('email') || 'cpanplus@example.com';
    my $cf_mail = $Config{cf_email};

    $cf_mail = 'cpanplus@example.com' if $cf_mail eq $email; # for variety's sake

    print qq|
You have several choices:

1) $email
2) $cf_mail
3) something else

|;

    $prompt = 'Please pick one [1]: ';
    $default = '1';

    while (defined($answer = _readline($prompt))) {
        $answer ||= $default;
        $term->addhistory($answer);

                           last, if $answer == 1;
        $email = $cf_mail, last, if $answer == 2;
        $email = '',       last, if $answer == 3;

        $prompt  = 'Please choose 1, 2, or 3 [1]: ';
        next;
    } #while

    until ( _valid_email($email) ) {
        print "You did not enter a valid email address, please try again!\n"
            if length $email;

        $email = _get_reply(
            prompt  => "Email address: ",
        );
    } #while

    print "\nYour 'email' is now:\n    $email\n";
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

    print qq[
The CPAN++ module needs a directory of its own to cache important index
files and maybe keep a temporary mirror of CPAN files.  This may be a
site-wide directory or a personal directory.
];

    my $new_path;
    my $dot_cpan = '.cpanplus';

    ### add more checks later - good for Win9x/NT4/Win2k and *nix now
    ### this breaks cygwin, thanks -kane
    #if ($^O =~ m/win/i) {
    if ( $^O eq 'MSWin32' ) {
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

        print qq|
You have several choices:

1) $new_path
2) $cpan_home
3) somewhere else

|;

        $prompt = 'Please pick one [1]: ';
        $default = '1';

        while (defined($answer = _readline($prompt))) {
            $answer ||= $default;
            $term->addhistory($answer);

            $cpan_home = $new_path, last, if $answer == 1;
                                    last, if $answer == 2;
            $cpan_home = '',        last, if $answer == 3;

            $prompt  = 'Please choose 1, 2, or 3 [1]: ';
            next;
        } #while

    } #if

    if (-d $cpan_home) {

        print qq{
I see you already have a directory:

    $cpan_home

};

        $prompt  = 'Should I use it? [Y/n]: ';
        $default = 'y';

    } else {

        print qq{
First of all, I'd like to create this directory.  Where?

};

        $prompt  = "[$cpan_home]: ";
        $default = $cpan_home;

    } #if


    while (defined($answer = _readline($prompt))) {
        $answer ||= $default;
        $term->addhistory($answer);

        if ($default eq 'y') {
            if ($answer =~ /^y/i) {
                $answer = $cpan_home;
            } else {
                $prompt  = 'Where shall I put it then?: ';
                $default = '';
                next;
            } #if
        } #if

        $prompt = 'Please choose a different location: ';
        $default = '';

        if (-d $answer and not (-w _)) {
            print "I can't seem to write in this directory.\n";
            $AutoSetup = 0; next;
        } #if

        ### windoze won't make more than one dir at a time :o(
        #unless (mkdir $answer) {

        {
            local $@;
            unless (-d $answer or eval { File::Path::mkpath($answer) } ) {
                chomp($@);
                warn "I wasn't able to create this directory.\n(The error I got was $@)\n\n";
                $AutoSetup = 0; next;
            } #unless
        } #scope

        my $autdir = File::Spec->catdir($answer, $conf->_get_build('autdir'));
        unless (-e $autdir or mkdir($autdir, 0777)) {
            warn "I wasn't able to create $autdir.\n(The error I got was $!)\n\n";
            $AutoSetup = 0; next; # XXX: doesn't unlink the current $answer
        }

        my $moddir = File::Spec->catdir($answer, $conf->_get_build('moddir'));
        unless (-e $moddir or mkdir($moddir, 0777)) {
            warn "I wasn't able to create $moddir.\n(The error I got was $!)\n\n";
            $AutoSetup = 0; next; # XXX: doesn't unlink the current $answer
        }

        $cpan_home = Cwd::abs_path($answer);

        ### clear away old storable images before 0.031
        unlink File::Spec->catfile($cpan_home, 'dslip');
        unlink File::Spec->catfile($cpan_home, 'mailrc');
        unlink File::Spec->catfile($cpan_home, 'packages');

        print "\nYour CPAN++ build and cache directory has been set to:\n";
        print "    $cpan_home\n";
        last;
    } #while

    print "\n\n";


    ###############################
    ## whereis make/tar/gzip/etc ##
    ###############################

    my (@path) = split /$Config{path_sep}/, $ENV{PATH};
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
            print qq|
Which '$pgm' executable should I use?

1) $new_name
2) $pgm_name
3) other

|;

            $prompt = 'Please pick one [1]: ';
            $default = 1;

        } else {
            $prompt  = "Where can I find your '$pgm' executable? [$pgm_name]: ";
            $default = $pgm_name;

        } #if

        while (defined($answer = _readline($prompt))) {
            $answer ||= $default;
            $answer =~ s/^\s+$//;
            $term->addhistory($answer), if $answer;

            if ($default =~ /^[123]$/) {
                unless ($answer == 1 || $answer == 2 || $answer == 3) {
                    $prompt  = 'Please choose 1, 2, or 3 [1]: ';
                    next;
                } #unless

                $answer = $new_name, if $answer == 1;
                $answer = $pgm_name, if $answer == 2;

                if ($answer == 3) {
                    $prompt  = "Where can I find your '$pgm' executable?: ";
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
                warn "Without your '$pgm' executable I can't function!\n";
                $AutoSetup = 0; next;
            } #unless

            # it better actually be a program!
            last, if File::Spec->file_name_is_absolute($answer)
                  && MM->maybe_command($answer);

            $answer = _find_exe($answer, [@path]);
            unless ($answer) {
                warn "I couldn't find '$pgm_name' in your PATH.\n";
                $prompt  = "Please tell me where I can find it: ";
                $default = '';
                $AutoSetup = 0; next;
            } #unless

            print "\nGood, I found '$pgm_name' in your PATH:\n    $answer\n";
            last;

        } #while

        printf "\nYour '$pgm' program has been set to:\n    %s\n",
            ($answer) ? $answer : '*nothing entered*';

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
        print "Your current $name flags are:\n";
        print map {
            defined($flags->{$_})
                ? "    $_=$flags->{$_}\n"
                : "    $_\n"
        } sort keys %{$flags};
        print "\n\n";
    } #if

    my $answer = _get_reply( prompt  => "Parameters for $name?: " );

    $flags = CPANPLUS::Backend->_flags_hashref($answer);

    print "\nYour $name flags are now:\n";

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
    my ($answer, $prompt, $default);

    print q[
Now, we are going to fetch the mirror list for first-time configurations.
This may take a while...

];

    #my $file = '/tmp/MIRRORED.BY';
    my $file = File::Spec->catfile($conf->_get_build('base'), $conf->_get_source('hosts'));

    unless (-e $file) {
        my $cpan = new CPANPLUS::Backend($conf) or die "can't use Backend!\n";

        $cpan->_fetch(
            file     => $conf->_get_source('hosts'),
            fetchdir => $conf->_get_build('base'),
        ) or die "Fetch of $file failed!\n";
    } #unless

    my $hosts = _parse_mirrored_by($file);

    my ($default_continent, $default_country, $default_host) =
        _guess_from_timezone($hosts);

    print qq{

Now we need to know where your favorite CPAN sites are located. Push a
few sites onto the array (just in case the first on the array won't
work). If you are mirroring CPAN to your local workstation, specify a
file: URL.

First, pick a nearby continent and country. Then, you will be presented
with a list of URLs of CPAN mirrors in the country you selected. Select
some of those URLs.  Finally, you will be prompted for any extra URLs --
file:, ftp:, or http: -- that host a CPAN mirror.
};

    my $choices;

    my $count;
    $default = '';

    my ($continent, $country, $last, $next, $host_list, @hosts);
    my @answers;
    $next = 'continent';

    my $options = {
        continent => [ qw/q/ ],
        country   => [ qw/q u/ ],
        host      => [ qw/q u v/ ],
        view      => [ qw/y n/ ],
    };

    LOOP: {
        if ($next eq 'continent') {
            my $items = [sort keys %{$hosts->{all}}];
            my $default = _find_seq($items, $default_continent);

            my $pick = _pick_item (
                           #items   => [sort keys %{$hosts->{all}}],
                           items   => $items,
                           options => { q => 'quit', },
                           #prompt  => 'Please choose a continent: ',
                           prompt  => "Please choose a continent [$default]: ",
                           choices => [ @{$options->{continent}} ],
                           default => $default,

                       );

            if ($pick->[0] =~ /\d/) {
                $continent = $pick->[1];
                $next      = 'country';
            } elsif ($pick->[0] eq 'q') {
                last LOOP;
            } #if

            redo LOOP;

        } elsif ($next eq 'country') {
            my $items = [ sort keys %{$hosts->{all}->{$continent}} ];
            my $default = _find_seq($items, $default_country);

            my $pick = _pick_item (
                           #items   => [sort keys %{$hosts->{all}->{$continent}}],
                           items   => $items,
                           options => {
                                          q => 'quit',
                                          u => 'back to continents',
                                      },
                           #prompt  => 'Please choose a country: ',
                           prompt  => "Please choose a country [$default]: ",
                           choices => [ @{$options->{country}} ],
                           default => $default,
                       );

            if ($pick->[0] =~ /\d/) {
                $country = $pick->[1];
                $next    = 'host';

            } elsif ($pick->[0] eq 'q') {
                last LOOP;

            } elsif ($pick->[0] eq 'u') {
                $next = 'continent';
            } #if

            redo LOOP;

        } elsif ($next eq 'host') {

            my $opts = {
                   q => 'finish',
                   u => 'back to countries',
                   v => (scalar(keys %$host_list)) > 0 ? 'view list' : '',
                   #v => (defined($host_list) && scalar @{$host_list}) > 0 ? 'view list' : '',
               };

            my $sub = sub {
                   return "[$_[0]] $_[1]"
                        . " ($hosts->{$_[1]}->{frequency}"
                        . ", $hosts->{$_[1]}->{dst_bandwidth})\n";
               };

            my $items = [ sort @{$hosts->{all}->{$continent}->{$country}} ];
            my $default = _find_seq($items, $default_host);

            my $pick = _pick_item (
                           #items   => [ sort @{$hosts->{all}->{$continent}->{$country}} ],
                           items   => $items,
                           options => $opts,
                           map_sub => $sub,
                           #prompt  => 'Please choose a host: ',
                           prompt  => "Please choose a host [$default]: ",
                           choices => [ @{$options->{host}} ],
                           default => $default,
                           multi   => 1,
                       );

            if ($pick->[0] =~ /\d/) {
                for my $host (@{$pick}[1..$#{$pick}]) {
                    if (exists $host_list->{$host}) {
                        print "\nHost $host already selected!\n";
                        last LOOP if $AutoSetup;
                        next;
                    }

                    push @hosts, $host;
                    $host_list->{$host} = $hosts->{$host};
                    my $total           = scalar(keys %{$host_list});
                    printf "\nSelected %s, %d host%s selected thus far.\n",
                        $host, $total, ($total == 1) ? '' : 's';
                }

                $next = 'host';

            } elsif ($pick->[0] eq 'q') {
                last LOOP;

            } elsif ($pick->[0] eq 'u') {
                $next = 'country';

            } elsif ($pick->[0] eq 'v') {
                $next = 'view';
            } #if

            redo LOOP;

        } elsif ($next eq 'view') {

            print "\n\nCurrently selected hosts:";
            my $pick = _pick_item (
                           #items   => [ @{$host_list} ],
                           #items   => [ sort keys %{$host_list} ],
                           items   => [ @hosts ],
                           map_sub => sub { return "    $_[1]\n" },
                           prompt  => 'Choose another? [Y/n]: ',
                           default => 'y',
                           choices => [ @{$options->{view}} ],
                       );

            if ($pick->[0] eq 'n') {
                last LOOP;
            } else {
                $next = 'host';
            } #if

            redo LOOP;
        } #if
    } #LOOP

    #my @list = map {
    @hosts = map {
        #my ($scheme, $path) = split /$_/, $host_list->{$_}->{dst_ftp};
        #my ($path) = $host_list->{$_}->{dst_ftp} =~ m/$_(.*)$/;

        {
            host   => $_,
            #path   => $path,
            path   => $host_list->{$_}->{path},
            #scheme => $scheme,
            scheme => $host_list->{$_}->{scheme},
        }

    #} sort keys %{$host_list};
    } @hosts;

    ## the default fall-back host for unfortunate users
    my $fallback_host = 'ftp://ftp.cpan.org/pub/CPAN/';

    print qq{

If there are any additional URLs you would like to use, please add them
now.  You may enter them separately or as a space delimited list.

We provide a default fall-back URL, but you are welcome to override it
with e.g. 'http://www.cpan.org/' if LWP, wget or lynx is installed.

(Enter an empty string when you are done, or to simply skip this step.)

Note that if you want to use a local depository, you will have to enter
as follows:

file://server/path/to/cpan

if the file is on a server on your local network or as:

file:///path/to/cpan

if the file is on your local disk. Note the three /// after the file: bit

};

    while ('kane is happy') {
        $answer = _get_reply(
                        prompt  => "Additional host(s) to add".
                                   ($fallback_host ? " [$fallback_host]: " : ": "),
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

            ## only file URI's allowed to leave host blank (localhost assumed)
            $host = 'localhost' if $scheme eq 'file' and $host eq '';

            ## no schemey, no hosty, no pathy, no worky
            next unless $scheme and $host and $path;

            #my $item = {
            #               host   => $host,
            #               path   => $path,
            #               scheme => $scheme,
            #           };

            ## don't store duplicate items
            #push (@hosts, $item) unless exists $host_list->{$host};

            ## don't store duplicate items
            ## maybe we don't care or want to override them though? -jmb
            ## need to allow for multiple localhost hosts somehow
            #unless ($host ne 'localhost' and exists $host_list->{$host}) {
            unless ($scheme ne 'file' and exists $host_list->{$host}
                and $path ne $host_list->{$host}->{path}) {
                push @hosts, {
                                 host   => $host,
                                 path   => $path,
                                 scheme => $scheme,
                             };
                $host_list->{$host} = 1; ## keep track of these
            } #unless
        } #for
    } #while

    print "\nYour current hosts are:\n",
          (
              map {
                      (
                          "$_->{host}",
                          #($_->{host} eq 'localhost') ? " ($_->{path})" : '',
                          ($_->{scheme} eq 'file') ? " ($_->{path})" : '',
                          "\n"
                      );
                  } @hosts
          ),
          "\n";

    ### MUST CHANGE THIS - I HATE IT!!! -jmb
    $conf->_set_ftp(
        #urilist => [ @list ],
        urilist => [ @hosts ],
    );

    #$conf->_set_hosts(
    #    #order => [ sort keys %{$host_list} ],
    #    #list => $host_list,
    #    #list => [ @list ],
    #);

} #_setup_hosts


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

    ## add generated choices to list
    push @{$args{choices}}, keys %{$choices};

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
                warn "Invalid selection, please try again.\n";
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
    -s $file or die "$file has no size!";

    $fh->open("<$file") or die "Couldn't open $file: $!";
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

sub _yn {
    return $_[0] ? '[Y/n]: ' : '[y/N]';
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
