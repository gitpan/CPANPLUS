# $File: //depot/cpanplus/dist/lib/CPANPLUS/Internals/Report.pm $
# $Revision: #14 $ $Change: 8342 $ $DateTime: 2003/10/05 17:16:08 $

####################################################
###          CPANPLUS/Internals/Report.pm        ###
###    Subclass for testing reports for cpanplus ###
###      Written 29-03-2002 by Autrijus Tang     ###
####################################################

### Report.pm ###

package CPANPLUS::Internals::Report;

use strict;
use File::Spec;
use Data::Dumper;
use File::Basename;
use CPANPLUS::I18N;
use CPANPLUS::Tools::Cmd qw[can_run];
use Fcntl;
use AnyDBM_File;

BEGIN {
    use vars        qw( $VERSION );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

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

### Send out testing reports
sub _send_report {
    my ($self, %args) = @_;
    my ($module, $buffer, $failed) = @args{qw|module buffer failed|};

    my $err    = $self->{_error};
    my $conf   = $self->{_conf};
    my $name   = $module->{module};
    my $dist   = $module->{package};
    my $author = $self->_author_tree->{$module->{author}}{name}
                 || $module->{author};
    my $email  = $self->_author_tree->{$module->{author}}{email}
                 || "$module->{author}\@cpan.org";
    my $grade;

    if ($self->{_todo}{failed}{$name} or $failed) {
        foreach my $platform (keys %OS) {
            if ($name =~ /\b$platform\b/i) {
                # a platform-specific module
                $grade = 'na' unless ($^O =~ /^(?:$OS{$platform})$/);
                last;
            }
        }
        $grade ||= 'fail';
    }
    elsif (
        $buffer =~ /^No tests defined for .* extension.\s*$/m and
        ($buffer !~ /\*\.t/m and $buffer !~ /test\.pl/m)
    ) {
        $grade = 'unknown';
    }
    else {
        $grade = 'pass';
    }

    $dist =~ s/(?:\.tar\.(?:gz|Z|bz2)|\.t[gb]z|\.zip)$//i;

    return unless length $dist
              and $self->_can_use( modules => { 'Test::Reporter' => '1.13' } )
              and $self->{_shell}
              and $self->_not_already_sent($dist)
              and $self->{_shell}->_ask_report(dist => $dist, grade => $grade);

    my ($already_sent, $nb_send, $max_send) = (0, 0, 2);
    my @inform;
    my $text = ''; 

    if ($grade eq 'fail') {
        # Check if somebody have already sent FAIL status about this release
        if ($self->{_conf}->get_conf('cpantest') =~ /\bdont_cc\b/i) {
            $already_sent = $self->_query_report('package' => $dist);
            if ($already_sent) {
                foreach my $k (@$already_sent) {
                    $nb_send++ if ($k->{grade} eq 'FAIL');
                }

                $err->inform( msg => loc("FAIL status already reported. I won't cc the author.") )
                    if ($nb_send >= $max_send);
            }
        }

        my $stage = $self->{_error}->stack;
        $stage = 'fetch' unless $stage =~ s/^(MAKE [A-Z]+).*/\L$1\E/;

        return if $self->{_conf}->get_conf('cpantest') =~ /\bmaketest_only\b/i
                  and ($stage !~ /\btest\b/);

        $text = << ".";
This is an error report generated automatically by CPANPLUS,
version $VERSION.

Below is the error stack during '$stage':

$buffer

Additional comments:
.

        my %missing;
        $missing{$_} = 1 foreach ($buffer =~ m/\bCan\'t locate (\S+) in \@INC/g);
        if (%missing) {
            my $modules = join("\n", map {
                s/.pm$//; s|/|::|g; $_
            } sort keys %missing);

            my $prereq  = join("\n", map {
                s/.pm$//; s|/|::|g; "\t'$_'\t=> '0', # or a minimum workable version"
            } sort keys %missing);

            $text .= << ".";

Hello, $author! Thanks for uploading your works to CPAN.

I noticed that the test suite seem to fail without these modules:

$modules

As such, adding the prerequisite module(s) to 'PREREQ_PM' in your
Makefile.PL should solve this problem.  For example:

WriteMakefile(
    AUTHOR      => '$author ($email)',
    ... # other information
    PREREQ_PM   => {
$prereq
    }
);

If you are interested in making a more flexible Makefile.PL that can
probe for missing dependencies and install them, ExtUtils::AutoInstall
at <http://search.cpan.org/dist/ExtUtils-AutoInstall/> may be
worth a look.

Thanks! :-)

******************************** NOTE ********************************
The comments above are created mechanically, possibly without manual
checking by the sender.  Also, because many people perform automatic
tests on CPAN, chances are that you will receive identical messages
about the same problem.

If you believe that the message is mistaken, please reply to the first
one with correction and/or additional information, and do not take
it personally.  We appreciate your patience. :)
**********************************************************************

.
        }

        push @inform, "$module->{author}\@cpan.org"
            if (!$already_sent or $nb_send < $max_send);
    }
    elsif ($grade eq 'unknown') {
        if ($name =~ /\bBundle\b/) {
            $err->inform( msg => loc("UNKNOWN grades for Bundles are normal; skipped.") );
            return;
        }

        my $stage = 'make test';

        $text = << ".";
This is an error report generated automatically by CPANPLUS,
version $VERSION.

Below is the error stack during '$stage':

$buffer

Additional comments:

Hello, $author! Thanks for uploading your works to CPAN.

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

Thanks! :-)

******************************** NOTE ********************************
The comments above are created mechanically, possibly without manual
checking by the sender.  Also, because many people performs automatic
tests on CPAN, chances are that you will receive identical messages
about the same problem.

If you believe that the message is mistaken, please reply to the first
one with correction and/or additional informations, and do not take
it personally.  We appreciate your patience. :)
**********************************************************************

.

        push @inform, "$module->{author}\@cpan.org"
            if (!$already_sent or $nb_send < $max_send);
    }
    elsif ($self->configure_object->get_conf('cpantest') =~ /\balways_cc\b/i) {
        push @inform, "$module->{author}\@cpan.org"
            if (!$already_sent or $nb_send < $max_send);
    }

    my $reporter = Test::Reporter->new(
        grade           => $grade,
        distribution    => $dist,
        via             => "CPANPLUS $CPANPLUS::Internals::VERSION",
    );

    my $from = $self->configure_object->_get_ftp('email');
    $reporter->from($from)      if $from !~ /\@example\.\w+$/;
    $reporter->comments($text)  if length $text;
    $reporter->edit_comments    if $grade eq 'fail';

    $err->inform(
        msg   => loc("Sending report for %1", $dist),
        quiet => !$conf->get_conf('verbose'),
    );

    if ($reporter->send(@inform)) {
        $err->inform( msg => loc("Successfully sent report for %1.", $dist) );
    }
    else {
        $err->trap( error => loc("Can't send report: %1", $reporter->errstr) );
    }
}


### Query a report. Currently cpan-testers only, but could be extend to RT
### Expects an array reference containing distribution names
### Returns a two-level hash reference with dist and version as keys
sub _query_report {
    my ($self, %args) = @_;
    my $err  = $self->{_error};
    my $conf = $self->{_conf};
    my @ret;

    my $use_list = {
        LWP              => '0.0',
        'LWP::UserAgent' => '0.0',
        'HTTP::Request'  => '0.0',
        URI              => '0.0',
        YAML             => '0.0',
    };

    return 0 unless $self->_can_use( modules => $use_list, complain => 1 );

    my $dist = $args{package};
    $dist =~ s/(?:\.tar\.(?:gz|Z|bz2)|\.t[gb]z|\.zip)$//i;
    $dist =~ s/.*\///;

    my $name = $dist;
    my $ver  = $name =~ s/-([\d\._]+)$// ? $1 : '';

    ### fetch the report from cpan testers website
    my $ua = LWP::UserAgent->new;
    $ua->agent("CPANPLUS/$CPANPLUS::Internals::VERSION");
    $ua->env_proxy();

    ### older version of LWP::UserAgent do not know the 'get' method yet
    ### it wasn't available yet in 5.51 but it was in 5.64...
    ### it's just a convenience method anyway (read: wrapper) for the
    ### following:
    my $url = "http://testers.cpan.org/show/".$name.".yaml";
    my $request = HTTP::Request->new( GET => $url );

    $err->inform(
        msg   => loc("Fetching: %1", $url),
        quiet => !$conf->get_conf('verbose'),
    );

    ### and start using the LWP::UserAgent object again...
    my $response = $ua->request( $request );

    unless ($response->is_success) {
        $err->trap( error => loc("Fetch report failed on %2: %1", $response->message, $url) );
        return 0;
    }

    ### got the report, start parsing
    my $result = YAML::Load($response->content);

    unless (defined $result) {
        $err->trap( error => loc("Error parsing testers.cpan.org results") );
        return 0;
    }
    
    foreach my $ref (@$result) {
        next unless $dist eq $ref->{distversion} or $args{all_versions};
        push @ret, {
            platform => $ref->{platform},
            grade    => $ref->{action},
            dist     => $ref->{distversion},
            ($ref->{action} eq 'FAIL') ? (
                details => "http://nntp.x.perl.org/group/perl.cpan.testers/".$ref->{id}
            ) : (),
        };
    }

    return @ret ? \@ret : 0;
}

## Add to DBM database $dist if not exist and return 1, else return 0;
sub _not_already_sent {
    my ($self, $dist, $set) = @_;

    ### if --force is set to true, send duplicated reports anyway.
    return 1 if ($self->{_conf}->get_conf('force'));

    my $sdbm = $self->{_conf}->_get_build("base")."/reports_send.dbm";
    my $perlversion = $self->_perl_version(perl => $^X);
    my $osversion   = $self->_os_version(perl => $^X);

    my $rv = 0;
    my %myreports;

    # Initialize DBM hash with report send by user
    tie (%myreports, 'AnyDBM_File', $sdbm, O_RDWR|O_CREAT, 0640)
        or die loc("Can't open %1: %2", $sdbm, $!);

    unless ($myreports{"$dist|$perlversion|$osversion"}) {
        $myreports{"$dist|$perlversion|$osversion"} = localtime unless $set;
        $rv = 1;
    }

    untie %myreports;

    print loc("You have already sent a report for %1, skipping.\n", $dist)
        unless $rv;

    return $rv;
}

1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
