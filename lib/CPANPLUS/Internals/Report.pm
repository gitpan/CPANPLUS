# $File: //depot/dist/lib/CPANPLUS/Internals/Report.pm $
# $Revision: #5 $ $Change: 77 $ $DateTime: 2002/07/02 10:33:55 $

####################################################
###          CPANPLUS/Internals/Report.pm        ###
###    Subclass for testing reports for cpanplus ###
###      Written 29-03-2002 by Autrijus Tang     ###
####################################################

### Report.pm ###

package CPANPLUS::Internals::Report;

use strict;
use File::Spec;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use Data::Dumper;
use File::Basename;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
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
        $buffer !~ /^All tests successful\b/m
    ) {
        $grade = 'unknown';
    }
    else {
        $grade = 'pass';
    }

    $dist =~ s/(?:\.tar\.(?:gz|Z|bz2)|\.t[gb]z|\.zip)$//i;

    my $cpantest = (File::Spec->catfile(File::Basename::dirname($^X), 'cpantest'));

    return unless length $dist
              and (-e $cpantest or $self->_can_run('cpantest'))
              and $self->{_shell}
              and $self->{_shell}->_ask_report(dist => $dist, grade => $grade);

    my ($fh, $filename, @inform);

    if ($grade eq 'fail') {
        return unless $self->_can_use( modules => { 'File::Temp' => '0.0' } );
        ($fh, $filename) = File::Temp::tempfile( UNLINK => 1 );

        my $stage = lc($self->{_error}->stack);
        $stage =~ s/ failed.*//;

        return if $self->{_conf}->get_conf('cpantest') =~ /\bmaketest_only\b/i
                  and ($stage !~ /\btest\b/);

        print $fh '' . << ".";
This is an error report generated automatically by CPANPLUS.
Below is the error stack during '$stage':

$buffer

Additional comments:
.

        if (my @missing = $buffer =~ m/\bCan't locate (\S+) in \@INC/g) {
            my $missing = join("\n", map {
                s/.pm$//; s|/|::|g; $_
            } @missing);

            my $prereq  = join("\n", map {
                s/.pm$//; s|/|::|g; "\t'$_'\t=> '0', # or a minimum workable version"
            } @missing);

            print $fh '' . << ".";

Hello, $author! Thanks for uploading your works to CPAN.

I noticed that the test suite seem to fail without these modules:

$missing

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
at <http://search.cpan.org/search?dist=ExtUtils-AutoInstall> may be
worth a look.

Thanks! :-)
.
        }

        push @inform, "$module->{author}\@cpan.org";
    }
    elsif ($grade eq 'unknown') {
        if ($name =~ /\bBundle\b/) {
            print "UNKNOWN grades for Bundles are normal; skipped.\n";
            return;
        }

        return unless $self->_can_use( modules => { 'File::Temp' => '0.0' } );

        ($fh, $filename) = File::Temp::tempfile( UNLINK => 1 );

        my $stage = 'make test';

        print $fh '' . << ".";
This is an error report generated automatically by CPANPLUS.
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
manpages at <http://search.cpan.org/search?dist=Test-Simple>.

Thanks! :-)
.

        push @inform, "$module->{author}\@cpan.org";
    }
    elsif ($self->{_conf}->get_conf('cpantest') =~ /\balways_cc\b/i) {
        push @inform, "$module->{author}\@cpan.org";
    }

    close $fh if $fh;

    my @cmd = $self->_report_command(
        dist     => $dist,
        module   => $module,
        grade    => $grade,
        filename => $filename,
        inform   => \@inform,
    );

    print $self->_run(command => \@cmd, verbose => 1) ? "done.\n" : "failed ($!)!\n";
}


### Determine additional parameters to pass to 'cpantest'
sub _report_command {
    my ($self, %args) = @_;
    my $conf = $self->{_conf};
    my ($dist, $module, $grade, $filename, $inform) =
        @args{qw|dist module grade filename inform|};

    my $cpantest = (File::Spec->catfile(File::Basename::dirname($^X), 'cpantest'));
    my @cmd = (-e $cpantest ? ($^X, $cpantest) : 'cpantest');
    push @cmd, ('-g', $grade, qw|-auto -p|, $dist);
    push @cmd, ('-f', $filename) if defined $filename;
    push @cmd, @{$inform};

    return @cmd;
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
    my $url = "http://testers.cpan.org/search?request=dist&dist=$name";
    my $request = HTTP::Request->new( GET => $url );

    $err->inform(
        msg   => "Fetching: $url",
        quiet => !$conf->get_conf('verbose'),
    );

    ### and start using the LWP::UserAgent object again...
    my $response = $ua->request( $request );

    unless ($response->is_success) {
        $err->trap( error => "Fetch report failed: ". $response->message);
        return 0;
    }

    ### got the report, start parsing
    my ($result) = ($response->content =~ /\n<dl>(.*?)\n<\/dl>\n/s);

    unless (defined $result) {
        $err->trap( error => "Error parsing testers.cpan.org results" );
        return 0;
    }

    while ($result =~ s/<dt>\n.*<B>([^<\n]+)<\/B>\n([\d\D]*?)(?:\n<p>|$)//) {
        my ($key, $val) = ($1, $2);
        next unless $dist eq $key or $args{all_versions};

        while ($val =~ s/<dd>(?:<a href="(.*?)">)?.*? ALT="([^"]+)"[^\n]*\n[^>]*>([^<]+)<//s) {
            push @ret, {
                platform => $3,
                grade    => $2,
                dist     => $key,
                $1 ? (details => "$url$1") : (),
	    };
        }
    }

    return @ret ? \@ret : 0;
}

1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
