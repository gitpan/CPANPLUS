#!/usr/bin/perl
# $File: //depot/cpanplus/dist/Makefile.PL $
# $Revision: #25 $ $Change: 8313 $ $DateTime: 2003/10/02 14:57:49 $

use strict;
BEGIN { require 5.00503; }

use Cwd;
use Config;

# First, make sure we have a good File::Spec.
use lib 't/lib';

use File::Spec;
use File::Copy      qw/copy/;
use File::Basename  qw/dirname/;

use constant LIBS => [ map {
    File::Spec->catdir(File::Spec->rel2abs(dirname($0)), $_)
} ('inc', 'lib') ];

use lib @{+LIBS};

use CPANPLUS::I18N;

# tests that doesn't require setup
use constant BASIC_TESTS => ('t/0-signature.t');

{
    # set up include path to find CPANPLUS::Internals::System
    local $ENV{PERL5LIB} .= join($Config::Config{path_sep}, '', @{+LIBS});

    # not 'use' because we don't want to import it yet
    require ExtUtils::AutoInstall;
}

print loc("
### PLEASE NOTE ###################################################

CPANPLUS will replace CPAN.pm in the 5.10 core. Although you should
*NOT* expect it to work just like CPAN.pm, there is a compatible
shell available. See perldoc CPANPLUS::Shell after installation

You are strongly urged to configure CPANPLUS now, since otherwise
non-privileged (non-root) users may be unable to use CPANPLUS until
you configure it properly.

###################################################################
");

my $AutoInstall; # the flag to really perform autoinstallation
my $ConfigObj;   # the config object

# chdir to the Makefile.PL's directory
chdir dirname($0);

# first, determine the Config.pm's location.
my $has_prev; # flag to signify a configuration file from previous versions
my $config  = load_config($0);
my $has_old = is_configured($config);

# we can't do anything without nmake.
if (nmake_needed()) {
    get_nmake() or die loc("Please follow the instruction in README to install nmake first."), "\n";
}

# next, determine if we should run setup
if (setup_needed()) {
    $ConfigObj = CPANPLUS::Configure->new;

    if ($has_old) {
        unlink $config # remove the old one so we don't end up with Config.pm~
            or warn loc("Cannot unlink old config file '%1', continuing anyway.", $config), "\n"
                unless $has_prev;
        CPANPLUS::Configure::Setup->init(conf => $ConfigObj);
    }
    else {
        unlink "$config~";
    }

    write_makefile();
}
elsif ($has_old) {
    write_makefile();
}
else {
    print loc("Skipping setup; advanced tests will be disabled."), "\n";
    write_makefile(BASIC_TESTS); # with basic tests only
}

exit 0;

# tests whether the config file is different from the original config
sub is_configured {
    my $file = shift;
    return (-e $file and (-s $file != -s "$config-orig"));
}

sub load_config {
    unless (-e (File::Spec->catfile(qw|lib CPANPLUS Config.pm|))) {
        copy(old_configuration(), File::Spec->catfile(qw|lib CPANPLUS Config.pm|))
            or die loc("Cannot write to %1", 'Config.pm');
    }

    require CPANPLUS::Configure::Setup;
    return $INC{'CPANPLUS/Config.pm'};
}

sub old_configuration {
    foreach my $dir (@INC[2..$#INC]) {
        my $file = File::Spec->catfile($dir, qw|CPANPLUS Config.pm|);
        ($has_prev = $file, last) if -e $file;
    }

    if ($has_prev) {
        print loc("A previous installation detected. Use its settings? [Y/n]: ");
        undef $has_prev if <STDIN> =~ /^[Nn]/;
    }

    return $has_prev || File::Spec->catfile(qw|lib CPANPLUS Config.pm-orig|);
}

# returns whether setup is requested by user
sub setup_needed {
    my $run_setup;

    # first, look for SETUP=1 or SETUP=yes in @ARGV
    foreach my $arg (@ARGV) {
        $run_setup   = (($1 =~ /[1yY]/) ? 1 : 0) if $arg =~ /^SETUP=(.)/i;
        $AutoInstall = (($1 =~ /[1yY]/) ? 1 : 0) if $arg =~ /^AUTOINSTALL=(.)/i;
    }

    if (defined $run_setup) {
        # removes the SETUP=* to make MakeMaker happier
        @ARGV = grep { $_ !~ /^(?:SETUP|AUTOINSTALL)=./i } @ARGV;
    }
    else {
        # can't tell from @ARGV, so ask the user instead
        my $prompt = (
            $has_prev ? loc("Manually configure CPANPLUS based on previous settings?") :
            $has_old  ? loc("Old settings detected. Do you want to modify it?")
                      : loc("Do you want to configure CPANPLUS now?")
        );

        my $answer = _get_reply(
            prompt  => $prompt,
            default => (($has_old and not $has_prev) ? 'n' : 'y'),
            choices => [ qw/y n/ ],
        );

        unless ($run_setup = (($answer =~ /^y/i) ? 1 : 0)) {
            print loc("Okay, existing settings are preserved."), "\n";
        }

        if ($has_prev) {
            $CPANPLUS::Configure::Setup::AutoSetup = !$run_setup;
            $CPANPLUS::Configure::Setup::SkipMirrors =
            $CPANPLUS::Configure::Setup::SkipMirrors = 1;
            $run_setup = 1; # have to run setup anyway.
        }
    }

    return $run_setup;
}

# determine if the user needs nmake.
sub nmake_needed {
    return unless (
        $Config{make} =~ /^nmake\b/i and
        $^O eq 'MSWin32'             and
        !_can_run('nmake')
    );

    my $answer = _get_reply(
        prompt  => loc("Required executable 'nmake' not found. Install it?"),
        default => 'y',
        choices => [ qw/y n/ ],
    );

    my $needed = (($answer =~ /^y/i) ? 1 : 0)
        or die loc("Please follow the instruction in README to install nmake manually."), "\n";

    return $needed;
}

# writes makefile. optionally with a arrayref specifying tests to run
sub write_makefile {
    my $tests = shift;

    try_autoinstall() unless $tests;

    my %args = (
        NAME            => 'CPANPLUS',
        AUTHOR          => 'Jos Boumans <kane@cpan.org>',
        ABSTRACT        => 'Ameliorated interface to the CPAN',
        VERSION_FROM    => 'lib/CPANPLUS/Internals.pm',
        DISTNAME        => 'CPANPLUS',
        BINARY_LOCATION => 'x86/CPANPLUS',
        EXE_FILES       => [ <bin/*> ],

        dist            => {
            COMPRESS => 'gzip -9',
            SUFFIX   => '.gz',
        }
    );

    $args{test} = { TESTS => $tests } if $tests;

    ExtUtils::AutoInstall::Write(%args);

    print loc("Now, please type '%1' to test, and '%2' to install.", "$Config{make} test", "$Config{make} install"), "\n";

    # make an educated guess of whether we'll need root permission.
    if (eval '$>' and $AutoInstall) {
        print loc("You may need to do that as the 'root' user to install dependencies."), "\n";
    }

    # warn again, CLEARLY that you MUST set your $ENV var to point to the config
    CPANPLUS::Configure::Setup::_issue_non_default_config_warning();
}

sub try_autoinstall {
    print loc("
### PLEASE NOTE ###################################################

Although the core features of CPANPLUS do not require external
modules, they may depend on other modules to work according to your
configuration.  If you skip the probing, or answer 'n' to questions
that defaults to 'Y', there might be _unpredictable failures_!

###################################################################
");

    if (!defined($AutoInstall)) {
        $AutoInstall = _get_reply(
            prompt  => loc("Let the installer probe for module dependencies?"),
            default => 'y',
            choices => [ qw/y n/ ],
        ) =~ /^y/i;
    }

    return unless $AutoInstall;

    $ConfigObj ||= CPANPLUS::Configure->new;

    my $have_cc  = _can_run($Config::Config{cc});
    my $have_pgp = (_can_run('gpg') or _can_use('Crypt::OpenPGP'));
    my $ipc_ok   = (!_is_win9x()   and ($^O ne 'cygwin'));
    my $term_mod = _is_unix()         ? 'Term::Size'     :
                   ($^O eq 'MSWin32') ? 'Win32::Console' : undef;
    my $shell    = $ConfigObj->get_conf('shell') || '';

    ExtUtils::AutoInstall->import(
        -version                => 0.27,
        -core                   => 'all',
        -config                 => [
            ### Skip all tests to speed up installation.
            ### Also, following modules are particularly bad:
            ### - Archive::Tar is known to fail without zlib.
            ### - LWP takes lots of time to finish.
            ### - Term::ReadLine::Perl's test is interactive.
            ### - Compress::Zlib works but fails tests on Darwin.
            -skiptest           => 1,
            -prereqs            => 1,
            -do_once            => 1,
        ],
        loc('Uncompress .tar files')      => [
            -default            => (!_can_run('tar')),
            'Compress::Zlib'    => 0.01,
            'IO::Zlib'          => 0.01,
            'Archive::Tar'      => 1.05,
        ],
        loc('.zip files support') => [
            -default            => 0,
            'Archive::Zip'      => 0.01,
        ],
    $have_cc ? (
        loc('Uncompress .gz files')       => [
            -default            => !_can_run('gzip'),
            'Compress::Zlib'    => 1.00,
        ],
        loc('Cached metadata')            => [
            -default            => $ConfigObj->get_conf('storable'),
            'Storable'          => 1.00,
        ],
        loc('MD5 checksum')               => [
            -default            => $ConfigObj->get_conf('md5'),
            'Digest::MD5'       => 2.00,
        ],
    ) : (),
    $have_pgp ? (
        loc('PGP signatures')             => [
            -default            => $ConfigObj->get_conf('signature'),
            'Module::Signature' => 0.33,
        ],
    ) : (),
    ($] >= 5.006) ? (
        loc('Module::Build distribution')      => [
            -default            => 0,
            'Module::Build'     => 0.11,
        ],
    ) : (),
(0) ? (
    ($^O eq 'MSWin32') ? (
        loc('PPM distribution') => [
            -default            => 0,
            'Archive::Zip'      => 0.01,
            'PPM'               => 0,
        ],
    ) : (),
    ($^O eq 'freebsd') ? (
        loc('FreeBSD ports distribution') => [
            -default              => 0,
            'ExtUtils::MakeMaker' => 6.00,
        ],
    ) : (),
        loc('PAR distribution') => [
            -default              => 0,
            'PAR::Dist'           => 0,
        ],
) : (),
        loc('Net::FTP support')           => [
            -default            => (!grep {_can_run($_)} qw|wget lynx ncftp ncftp3 ncftpget|),
            'Net::FTP'          => 2.00,
        ],
        loc('File::RsyncP support')       => [
            -default            => 0,
            'File::RsyncP'      => 0,
        ],
        loc('LWP & CPAN test query')      => [
            -default            => 0,
            'URI'               => 1.00,
            'HTML::HeadParser'  => 0,
            'Net::FTP'          => 2.00,
            'MIME::Base64'      => 2.00,
            'Digest::MD5'       => 2.00,
            'LWP'               => 5.60,
        ],
    _can_use('LWP') ? () : (
        loc('Local file support')         => [
            -default            => 0,
            'File::Spec'        => 0.82,
        ]
    ),
    $ipc_ok ? (
        loc('IPC::Run support')           => [
            -default            => (!_is_unix() or ($^O eq 'solaris')),
            'IPC::Run'          => 0.75,
        ],
    ) : (),
        loc('CPAN Test reporting')        => [
            -default            => $ConfigObj->get_conf('cpantest'),
            'Net::SMTP'         => 0.01,
    $ipc_ok ? (
            'IPC::Run'          => 0.75,
    ) : (),
            'Test::Reporter'    => 1.20,
            'YAML'              => 0,
        ],
    _supports_readline() ? (
        loc('ReadLine support')           => [
            -default            => 0,
            'Term::ReadLine'    => 0,
      eval { require Term::ReadLine::Gnu; 1 } ? (
            'Term::ReadLine::Gnu' => 1.00,
      ) : (
            'Term::ReadLine::Perl' => 0.90,
      ),
        ],
    ) : (),
    $term_mod ? (
        loc('Terminal size support')      => [
            -default            => 0,
            $term_mod           => 0.01,
        ]
    ) : (),
        loc('Localized messages')         => [
            -default            => 0,
            'Locale::Maketext'  => 0.20,
            'Locale::Maketext::Lexicon' => 0.28,
        ],
        loc('Curses Shell') => [
            -default            => ($shell eq 'CPANPLUS::Shell::Curses'),
            'CPANPLUS::Shell::Curses'   => 0.02,
        ],
        loc('Tk Shell') => [
            -default            => ($shell eq 'CPANPLUS::Shell::Tk'),
            'CPANPLUS::Shell::Tk'   => 0.02,
        ],
    );

    if (_can_run('gpg')) {
        print "Importing public keys to GnuPG... ";
        system('gpg', '--quiet', '--import', <key/*.pub>);
	print "done!\n";
    }

}

# check if we can run some module
sub _can_use {
    my $module = shift;
    $module =~ s|::|/|g;
    $module .= '.pm';

    return eval { require $module; 1 };
}

# check if we can run some command - lifted from Internals.pm
sub _can_run {
    my $command = shift;

    for my $dir (split /$Config{path_sep}/, $ENV{PATH}) {
        my $abs = File::Spec->catfile($dir, $command);
        return $abs if $abs = MM->maybe_command($abs);
    }

    return;
}

# returns whether a platform is unix enough for Term::Size's use
sub _is_unix {
    # if it's good enough for MakeMaker, it's good enough for us
    return ($MM::ISA[0]           eq 'ExtUtils::MM_Unix'
         || $ExtUtils::MM::ISA[0] eq 'ExtUtils::MM_Unix');
}

# returns whether this is a win9x platform
sub _is_win9x {
    return ($^O eq 'MSWin32' and !Win32::IsWinNT());
}

# just uses the Setup.pm one; let it initiate terminal for us
sub _get_reply {
    local $CPANPLUS::Configure::Setup::AutoSetup = 0; # always interactive
    return CPANPLUS::Configure::Setup::_get_reply(@_);
}

sub _supports_readline {
    # determine whether readline support is potentially available.
    return ( $^O ne 'MSWin32');
}

sub get_nmake {
    my $host = 'ftp.microsoft.com';

    unless (_can_use('Socket') and Socket::inet_aton($host)) {
        print loc("Cannot fetch %1; '%2' resolve failed!", 'nmake', $host), "\n";
        return;
    }

    use Cwd;
    my $dir = getcwd;
    chdir dirname($^X) or return;

    print loc("Fetching '%1' from %2. It may take a few minutes... ", 'nmake', $host);

    if (_can_use('Net::FTP')) {
        # use Net::FTP to get pass firewall
        my $ftp = Net::FTP->new("ftp.microsoft.com", Passive => 1, Timeout => 600);
        $ftp->login("anonymous", 'cpanplus@example.com');
        $ftp->cwd("/Softlib/MSLFILES");
        $ftp->binary;
        $ftp->get("nmake15.exe") or die $!;
        $ftp->quit;
    }
    elsif (_can_run('ftp')) {
        # no Net::FTP, fallback to ftp.exe
        require FileHandle;
        my $fh = FileHandle->new;

        local $SIG{CHLD} = 'IGNORE';
        unless ($fh->open("|ftp.exe -n")) {
            warn "Couldn't open ftp: $!";
            chdir $dir; return;
        }

        my @dialog = split(/\n/, << '.');
open ftp.microsoft.com
user anonymous cpanplus@example.com
cd /Softlib/MSLFILES/
binary
get nmake15.exe nmake15.exe
quit
.

        foreach (@dialog) { $fh->print("$_\n") }
        $fh->close;
    }
    else {
        print loc("Cannot fetch %1 without a working '%2' executable!", 'nmake', 'ftp'), "\n";
        chdir $dir; return;
    }

    system('nmake15.exe /o > nul') if -s 'nmake15.exe' == 51928;
    unlink('nmake15.exe') if -e 'nmake15.exe';

    print (((-e 'nmake.exe') ? loc("done!") : loc("failed! (%1)", $!)), "\n");
    chdir $dir; return !$?;
}

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
