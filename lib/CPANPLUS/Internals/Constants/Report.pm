package CPANPLUS::Internals::Constants::Report;

use strict;
use CPANPLUS::Error;

use File::Spec;
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';

BEGIN {

    require Exporter;
    use vars    qw[$VERSION @ISA @EXPORT];
  
    $VERSION    = 0.01;
    @ISA        = qw[Exporter];
    @EXPORT     = qw[   
                    CPAN_MAIL_ACCOUNT RELEVANT_TEST_RESULT GRADE_FAIL GRADE_NA
                    GRADE_PASS GRADE_UNKNOWN NO_TESTS_DEFINED MAX_REPORT_SEND
                    REPORT_MESSAGE_HEADER REPORT_MESSAGE_FAIL_HEADER
                    TEST_FAIL_STAGE REPORT_MISSING_TESTS CPAN_TESTERS_EMAIL 
                    REPORT_MISSING_PREREQS MISSING_PREREQS_LIST
                ];
}

### OS to regex map ###
my %OS = (
    Amiga       => 'amigaos',
    Atari       => 'mint',
    BSD         => 'bsdos|darwin|freebsd|openbsd|netbsd',
    Be          => 'beos',
    BeOS        => 'beos',
    Darwin      => 'darwin',
    EBCDIC      => 'os390|os400|posix-bc|vmesa',
    HPUX        => 'hpux',
    Linux       => 'linux',
    MSDOS       => 'dos',
    'bin\\d*Mac'=> 'MacOS', # binMac, bin56Mac, bin58Mac...
    Mac         => 'MacOS',
    MacPerl     => 'MacOS',
    MacOS       => 'MacOS',
    MacOSX      => 'darwin',
    MPE         => 'mpeix',
    MPEiX       => 'mpeix',
    OS2         => 'os2',
    Plan9       => 'plan9',
    RISCOS      => 'riscos',
    SGI         => 'irix',
    Solaris     => 'solaris',
    Unix        => 'aix|bsdos|darwin|dgux|dynixptx|freebsd|'.
                   'linux|hpux|machten|netbsd|next|openbsd|dec_osf|'.
                   'svr4|sco_sv|unicos|unicosmk|solaris|sunos',
    VMS         => 'VMS',
    VOS         => 'VOS',
    Win32       => 'MSWin32',
    Win32API    => 'MSWin32',
);

use constant GRADE_FAIL     => 'fail';
use constant GRADE_PASS     => 'pass';
use constant GRADE_NA       => 'na';
use constant GRADE_UNKNOWN  => 'unknown';

use constant MAX_REPORT_SEND
                            => 2;

use constant CPAN_TESTERS_EMAIL
                            => 'cpan-testers@perl.org';

### the cpan mail account for this user ###
use constant CPAN_MAIL_ACCOUNT  
                            => sub {
                                my $username = shift or return;
                                return $username . '@cpan.org'; 
                            };      

### check if this module is platform specific and if we're on that
### specific platform. Alternately, the module is not platform specific
### and we're always OK to send out test results.
use constant RELEVANT_TEST_RESULT 
                            => sub {
                                my $mod  = shift or return;   
                                my $name = $mod->module;
                                my $specific;   
                                for my $platform (keys %OS) {
                                    if( $name =~ /\b$platform\b/i ) {
                                        $specific++;
                                        return 1 if 
                                            $^O =~ /^(?:$OS{$platform})$/
                                    }    
                                };
                                return $specific ? 0 : 1; 
                            };      

use constant NO_TESTS_DEFINED
                            => sub {
                                my $buffer = shift or return;
                                return $buffer =~ 
                                  /^'?No tests defined for .* extension.\s*$/m 
                                  and ( $buffer !~ /\*\.t/m and 
                                        $buffer !~ /test\.pl/m);

                            };

### what stage did the test fail? ###
use constant TEST_FAIL_STAGE
                            => sub {
                                my $buffer = shift or return;
                                return $buffer =~ /(MAKE [A-Z]+).*/ 
                                    ? lc $1 : 
                                    'fetch'; 
                            };

use constant MISSING_PREREQS_LIST
                            => sub {
                                my $buffer = shift; 
                                my @list = map { s/.pm$//; s|/|::|g; $_ } 
                                    ($buffer =~ 
                                        m/\bCan\'t locate (\S+) in \@INC/g);
                                
                                return @list;           
                            };    
                              
use constant REPORT_MESSAGE_HEADER               
                            => sub {
                                my ($author,$email) = @_;
                                return << ".";                                
                                
******************************** NOTE ********************************
The comments below are created mechanically, possibly without manual
checking by the sender.  Also, because many people perform automatic
tests on CPAN, chances are that you will receive identical messages
about the same problem.

If you believe that the message is mistaken, please reply to the first
one with correction and/or additional information, and do not take
it personally.  (We appreciate your patience. :)
**********************************************************************

Hello, $author! Thanks for uploading your works to CPAN.

.
                            };                                       

use constant REPORT_MESSAGE_FAIL_HEADER
                            => sub {
                                my($version, $stage, $buffer) = @_;
                                return << ".";
This is an error report generated automatically by CPANPLUS,
version $version.

Below is the error stack during '$stage':

$buffer

Additional comments:

.
                            };                                

use constant REPORT_MISSING_PREREQS
                            => sub {
                                my @missing = @_;
                                my $modules = join "\n", @missing;
                                my $prereqs = join "\n", map {"\t'$_'\t=> '0',".
                                    " # or a minimum working version"} @missing;
                                
                                return << ".";
I noticed that the test suite seem to fail without these modules:

$modules

As such, adding the prerequisite module(s) to 'PREREQ_PM' in your
Makefile.PL should solve this problem.  For example:

WriteMakefile(
    AUTHOR      => 'Your Name Here',
    ... # other information
    PREREQ_PM   => {
$prereqs
    }
);

If you are interested in making a more flexible Makefile.PL that can
probe for missing dependencies and install them, ExtUtils::AutoInstall
at <http://search.cpan.org/dist/ExtUtils-AutoInstall/> may be
worth a look.

Thanks! 

.
                            };

use constant REPORT_MISSING_TESTS
                            => sub {
                                return << ".";
Would it be too much to ask for a simple test script in the next
release, so people can verify which platforms can successfully
install them, as well as avoid regression bugs?

A simple 't/use.t' that says:

#!/usr/bin/env perl -w
use strict;
use Test;
BEGIN { plan tests => 1 }

use Your::Module::Here; ok(1);
exit;
__END__

would be appreciated.  If you are interested in making a more robust
test suite, please see the Test::Simple, Test::More and Test::Tutorial
manpages at <http://search.cpan.org/dist/Test-Simple/>.

Thanks!                       

.
                            };


1;  

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
