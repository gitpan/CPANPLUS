# $File: //member/autrijus/cpanplus/dist/lib/CPANPLUS/Internals/Report.pm $
# $Revision: #5 $ $Change: 3772 $ $DateTime: 2002/04/08 06:25:14 $

####################################################
###          CPANPLUS/Internals/Report.pm        ###
###    Subclass for testing reports for cpanplus ###
###      Written 29-03-2002 by Autirjus Tang     ###
####################################################

### Report.pm ###

package CPANPLUS::Internals::Report;

use strict;
use File::Spec;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use Data::Dumper;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

### Send out testing reports
sub _send_report {
    my ($self, %args) = @_;
    my ($module, $buffer) = @args{qw|module buffer|};
    my $name   = $module->{module};
    my $dist   = $module->{package};
    my $grade  = 'pass';

    if ($self->{_todo}{failed}{$name}) {
        $grade = 'fail';
    }
    elsif ($buffer =~ /^No tests defined for .* extension.\s*$/) {
        $grade = 'unknown';
    }

    $dist =~ s/(?:\.tar\.(?:gz|Z|bz2)|\.t[gb]z|\.zip)$//i;

    return unless length $dist
              and $self->_can_run('cpantest')
              and $self->{_shell}
              and $self->{_shell}->_ask_report(dist => $dist, grade => $grade);

    my ($fh, $filename, @inform);

    if ($grade eq 'fail') {
        print $self->_can_use( modules => { 'File::Temp' => '0.0' } );
        ($fh, $filename) = File::Temp::tempfile( UNLINK => 1 );

        my $stage = lc($self->{_error}->stack);
        $stage =~ s/ failed.*//;

        print $fh '' . << ".";
This is an error report generated automatically by CPANPLUS.
Below is the error stack during '$stage':

$buffer

Additional comments:
.

        @inform = "$module->{author}\@cpan.org";
    }

    my @cmd = $self->_report_command(
        dist     => $dist,
        module   => $module,
        grade    => $grade,
        filename => $filename,
    );

    print "Running [@cmd]... ";
    system @cmd;
    print "done.\n";
}


### Determine additional parameters to pass to 'cpantest'
sub _report_command {
    my ($self, %args) = @_;
    my $conf = $self->{_conf};
    my ($dist, $module, $grade, $filename) =
        @args{qw|dist module grade filename|};

    my @cmd = (qw|cpantest -g|, $grade, qw|-auto -p|, $dist);
    push @cmd, ('-f', $filename) if defined $filename;
    push @cmd, "$module->{author}\@cpan.org"
        if $grade eq 'fail' or $conf->get_conf('cpantest') =~ /\balways_cc\b/i;

    return @cmd;
}

### Query a report. Currently cpan-testers only, but could be extend to RT
### Expects an array reference containing distribution names
### Returns a two-level hash reference with dist and version as keys
sub _query_report {
    my ($self, %args) = @_;
    my $err  = $self->{_error};
    my $conf = $self->{_conf};
    my %ret;

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
    my $request = HTTP::Request->new(
                            'GET',
                            'http://testers.cpan.org/search?request=dist&dist='.$name
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

    while ($result =~ s/<dt>\n.*<B>([^<\n]+)<\/B>\n([\d\D]*?)\n<p>//) {
        my ($key, $val) = ($1, $2);
        next unless $dist eq $key or $args{all_versions};

        while ($val =~ s/<dd>.*? ALT="([^"]+)"[^\n]*\n[^>]*>([^<]+)<//s) {
            $ret{$key}{$2} = $1;
        }
    }

    unless ($ret{$dist}) {
        my $unit = (%ret ? 'version' : 'distribution');
        $err->inform( msg => "No reports available for this $unit." );
    }

    return \%ret;
}

1;
