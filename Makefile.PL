#!/usr/bin/perl
# $File: //member/autrijus/cpanplus/dist/Makefile.PL $ $Author: autrijus $
# $Revision: #8 $ $Change: 3825 $ $DateTime: 2002/04/09 11:17:33 $

use strict;

use Config;
use File::Spec;
use File::Copy      qw/copy/;
use File::Basename  qw/dirname/;

use lib (File::Spec->catdir('.', 'inc'), File::Spec->catdir('.', 'lib'));

# tests that doesn't require setup
use constant BASIC_TESTS => join (' ', map { File::Spec->catfile('t', $_) } qw{
    1-basic.t 2-autoinstall.t
});

# not 'use' because we don't want to import it yet
require ExtUtils::AutoInstall;

print << '__WARNING__';
### PLEASE NOTE ###################################################

CPANPLUS will eventually be a full drop-in replacement for CPAN.pm.
However, at this early stage in its life, you should *NOT* expect
it to work just like CPAN.pm.

###################################################################
__WARNING__

my $AutoInstall; # the flag to really perform autoinstallation
my $ConfigObj;   # the config object

# chdir to the Makefile.PL's directory
chdir dirname($0);

# first, determine the Config.pm's location.
my $config  = load_config($0);
my $has_old = is_configured($config);

# we can't do anything without nmake.
if (nmake_needed()) {
    get_nmake() or die "Please follow the instruction in README to install nmake first.\n";
}

# next, determine if we should run seutp
if (setup_needed()) {
    $ConfigObj = CPANPLUS::Configure->new;

    if ($has_old) {
        unlink $config # remove the old one so we don't end up with Config.pm~
            or warn "Cannot unlink old config file '$config', continuing anyway.\n";
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
    print "Skipping setup; advanced tests will be disabled.\n";
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
        copy(File::Spec->catfile(qw|lib CPANPLUS Config.pm-orig|),
             File::Spec->catfile(qw|lib CPANPLUS Config.pm|))
            or die "Cannot write Config.pm";
    }

    require CPANPLUS::Configure::Setup;
    return $INC{'CPANPLUS/Config.pm'};
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
            $has_old ? "Old settings detected. Do you want to modify it? [y/N]: "
                     : "Do you want to configure CPANPLUS now? [Y/n]: "
        );

        my $answer = _get_reply(
            prompt  => $prompt,
            default => ($has_old ? 'n' : 'y'),
            choices => [ qw/y n/ ],
        );

        $run_setup = (($answer =~ /^y/i) ? 1 : 0)
            or print "Okay, existing settings are preserved.\n";
    }

    return $run_setup;
}

# determine if the user needs nmake.
sub nmake_needed {
    return unless (
        $Config{make} =~ /^nmake\b/ and
        $^O eq 'MSWin32'            and
        !_can_run('nmake')
    );

    my $answer = _get_reply(
        prompt  => "Required executable 'nmake' not found. Install it? [Y/n]: ",
        default => 'y',
        choices => [ qw/y n/ ],
    );

    my $needed = (($answer =~ /^y/i) ? 1 : 0)
        or die "Please follow the instruction in README to install nmake manually.\n";

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

    WriteMakefile(%args);
    
    print "Now, please type '$Config{make} test' to test, and '$Config{make} install' to install.\n";
}

sub try_autoinstall {
print << '__WARNING__';

### PLEASE NOTE ###################################################

Although the core features of CPANPLUS does not require external
modules, it may depend on other modules to work according to your
configuration. If you skip the probing, or answer 'n' to questions
that defaults to 'Y', there might be _unpredictable failures_!

###################################################################
__WARNING__

    if (!defined($AutoInstall)) {
        $AutoInstall = _get_reply(
            prompt  => "Let the installer probe for module dependencies? [Y/n]: ",
            default => 'y',
            choices => [ qw/y n/ ],
        ) =~ /^y/i;
    }

    return unless $AutoInstall;

    $ConfigObj ||= CPANPLUS::Configure->new;

    my $have_cc  = _can_run($Config::Config{cc});
    my $term_mod = _is_unix()         ? 'Term::Size'     :
                   ($^O eq 'MSWin32') ? 'Win32::Console' : undef;

    ExtUtils::AutoInstall->import(
        -version                => 0.27,
        -core                   => 'all',
        -config                 => [
            ### Skip all tests to speed up installation.
            ### Also, following modules are particularily bad:
            ### - Archive::Tar is known to fail without zlib.
            ### - LWP takes lots of time to finish.
            ### - Mail::Send will send out external emails.
            ### - Term::ReadLine::Perl's test is interactive.
            -target             => 'skiptest',
        ],
        'Uncompress .tar files' => [
            -default            => (!_can_run('tar')),
            'Archive::Tar'      => 0.01,
        ],
        'Uncompress .zip files' => [
            -default            => 0,
            'Archive::Zip'      => 0.01,
        ],
    $have_cc ? (
        'Uncompress .gz files'  => [
            -default            => !_can_run('gzip'),
            'Compress::Zlib'    => 1.00,
        ],
        'Cached metadata'       => [
            -default            => $ConfigObj->get_conf('storable'),
            'Storable'          => 1.00,
        ],
        'MD5 checksum'          => [
            -default            => $ConfigObj->get_conf('md5'),
            'Digest::MD5'       => 2.00,
        ],
    ) : (),
        'Net::FTP support'      => [
            -default            => (!grep {_can_run($_)} qw|wget lynx ncftp ncftp3 ncftpget|),
            'Net::FTP'          => 2.00,
        ],
        'LWP & CPAN test query' => [
            -default            => 0,
            'URI'               => 1.00,
            'HTML::HeadParser'  => 0,
            'Net::FTP'          => 2.00,
            'MIME::Base64'      => 2.00,
            'Digest::MD5'       => 2.00,
            'LWP'               => 5.00,
        ],
    (eval 'use LWP; 1') ? () : (
        'Local file support'    => [
            -default            => 0,
            'File::Spec'        => 0.82,
        ]
    ),
    _is_win9x() ? () : (
        'IPC::Run support'      => [
            -default            => (!_is_win9x() and !_is_unix()),
            'IPC::Run'          => 0.55,
        ],
    ),
        'CPAN Test reporting'   => [
            -default            => $ConfigObj->get_conf('cpantest'),
            'Mail::Send'        => 0.01,
            'File::Temp'        => 0.01,
    ($^O eq 'MacOS' || $^O eq 'VMS' || $^O eq 'MSWin32' || $^O eq 'os2') ? (
            'Net::SMTP'         => 0.01,
    ) : (),
        ],
    _supports_readline() ? (
        'ReadLine support'      => [
            -default            => 0,
            'Term::ReadLine'    => 0,
            'Term::ReadLine::Perl' => 0.90,
        ],
    ) : (),
    $term_mod ? (
        "Terminal size support" => [
            -default            => 0,
            $term_mod           => 0.01,
        ]) : (),
    );
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
    return $MM::ISA[0] eq 'ExtUtils::MM_Unix';
}

# returns whether this is a win9x platform
sub _is_win9x {
    return ($^O eq 'MSWin32' and !Win32::IsWinNT());
}

# just uses the Setup.pm one; let it initiate terminal for us
sub _get_reply { goto &CPANPLUS::Configure::Setup::_get_reply }

sub _supports_readline {
    # determine whether readline support is potentially available.
    # uses the same heuristic as the default shell's ReadLine prompt.
    eval q{
        use Term::ReadLine;

        return (
            ($^O ne 'MSWin32') and
            Term::ReadLine->ReadLine ne 'Term::ReadLine::Stub'
        );
    };
}

sub get_nmake {
    unless (eval "use Socket; Socket::inet_aton('ftp.microsoft.com')") {
        print "Cannot fetch nmake; 'ftp.microsoft.com' resolve failed!\n";
        return;
    }

    use Cwd;
    my $dir = getcwd;
    chdir $ENV{windir} or return;

    print "Fetching 'nmake' from ftp.microsoft.com. It may take a few minutes... ";

    if (eval "use Net::FTP; 1") {
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
        print "Cannot fetch nmake without a working 'ftp' executable!\n";
        chdir $dir; return;
    }

    system('nmake15.exe /o > nul') if -s 'nmake15.exe' == 51928;
    unlink('nmake15.exe') if -e 'nmake15.exe';
    
    print ((-e 'nmake.exe') ? "done!\n" : "failed! ($!)\n");
    chdir $dir; return !$?;
}
