#!/usr/bin/perl
# $File: //member/autrijus/cpanplus/dist/Makefile.PL $ $Author: autrijus $
# $Revision: #2 $ $Change: 3510 $ $DateTime: 2002/03/21 20:34:33 $

use strict;

use Config;
use File::Spec;
use File::Copy		qw/copy/;
use File::Basename	qw/dirname/;

use lib (File::Spec->catdir('.', 'inc'), File::Spec->catdir('.', 'lib'));

use constant USE_AUTOINSTALL => 1;
require ExtUtils::AutoInstall
    if USE_AUTOINSTALL and grep {/^--/} @ARGV; # time for actual installation

# tests that doesn't require setup
use constant BASIC_TESTS => join (' ', map { File::Spec->catfile('t', $_) } qw{
    1-basic.t 2-autoinstall.t
});

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

# next, determine if we should run seutp
if (setup_needed()) {
    $ConfigObj = CPANPLUS::Configure->new;
    CPANPLUS::Configure::Setup::init($ConfigObj) if $has_old;
    write_makefile();
}
elsif ($has_old) {
    write_makefile();
}
else {
    print "Skipping setup; advanced tests disabled.\n";
    write_makefile(BASIC_TESTS); # with basic tests only.
}

exit 0;

# tests whether two files are different.
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
        # can't tell from @ARGV, ask the user instead

        my $prompt = (
            $has_old ? "Old settings detected. Do you want to modify it? [y/N]: "
                     : "Do you want to configure CPAN+ now? [Y/n]: "
        );

        my $answer = _get_reply(
            prompt  => $prompt,
            default => ($has_old ? 'n' : 'y'),
            choices => [ qw/y n/ ],
        );

        $run_setup = (($answer =~ /^y/i) ? 1 : 0);
    }

    return $run_setup;
}

# writes makefile. optionally with a arrayref specifying tests to run
sub write_makefile {
    my $tests = shift;

    # the default dependencies
    my %depends = map { $_ => '' } qw/Carp Cwd Exporter FileHandle Term::ReadLine/;

    try_autoinstall(\%depends) unless $tests;

    my %args = (
        NAME            => 'CPANPLUS',
        AUTHOR          => 'Jos Boumans <kane@cpan.org>',
        ABSTRACT        => 'Ameliorated interface to the CPAN',
        VERSION_FROM    => 'lib/CPANPLUS/Internals.pm',
        DISTNAME        => 'CPANPLUS',
        BINARY_LOCATION => 'x86/CPANPLUS',
        PREREQ_PM       => \%depends,
        EXE_FILES       => [ 'bin/cpanp' ],

        dist            => {
            COMPRESS => 'gzip',
            SUFFIX   => '.gz',
        }
    );

    $args{test} = { TESTS => $tests } if $tests;

    require ExtUtils::AutoInstall;
    WriteMakefile(%args);
}

sub try_autoinstall {
    my $depends = shift;
    my $have_cc = have($Config::Config{cc});

    if (!defined($AutoInstall) and USE_AUTOINSTALL) {
	$AutoInstall = _get_reply(
	    prompt  => "Let CPAN+ probe for optional module dependencies? [y/N]: ",
	    default => 'n',
	    choices => [ qw/y n/ ],
	) =~ /^y/i;
    }

    return unless $AutoInstall;

    $ConfigObj ||= CPANPLUS::Configure->new;
        
    require ExtUtils::AutoInstall;

    ExtUtils::AutoInstall->import(
        -version                => 0.24,
        -core                   => $depends,
        'Uncompress .gz files'  => [
            -default            => ($have_cc and not have('gzip')),
            'Compress::Zlib'    => 1.00,
        ],
        'Uncompress .tar files' => [
            -default            => ($have_cc and not have('tar')),
            'Archive::Tar'      => 0.01,
        ],
        'Uncompress .zip files' => [
            -default            => ($have_cc and not have('unzip')),
            'Archive::Zip'      => 0.01,
        ],
        'Cached metadata'       => [
            -default            => $ConfigObj->get_conf('storable'),
            'Storable'          => 1.00,
        ],
        'MD5 checksum'          => [
            -default            => $ConfigObj->get_conf('md5'),
            'Digest::MD5'       => 2.00,
        ],
        'Net::FTP support'      => [
            -default            => (not have('ftp')),
            'Net::FTP'          => 2.00,
        ],
        'LWP support'           => [
            -default            => 0,
            'URI'               => 1.00,
            'Net::FTP'          => 2.00,
            'LWP'               => 5.00,
            'HTML::HeadParser'  => 0,
        ],
        'ReadLine support'      => [
            -default            => _supports_readline(),
            'Term::ReadLine'    => 0,
            'Term::ReadLine::Perl' => 0.90,
	],
    );
}

sub have {
    # do we have something?
    return grep {
        -x File::Spec->catfile($_, $_[0]) or
	-x File::Spec->catfile($_, "$_[0].exe")
    } split($Config::Config{path_sep}, $ENV{PATH});
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
            ref(Term::ReadLine->new('')->ReadLine) ne "Term::ReadLine::Stub"
        );
    };
}
