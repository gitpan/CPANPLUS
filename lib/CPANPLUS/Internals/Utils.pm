#######################################################
###         CPANPLUS/Internals/Utils.pm             ###
###         Utility functions to CPANPLUS           ###
###         Written 11-03-2002 by Jos Boumans       ###
#######################################################

package CPANPLUS::Internals::Utils;

use strict;
use Data::Dumper;
use CPANPLUS::I18N;
use CPANPLUS::Tools::Check qw[check];

BEGIN {
    use vars        qw( $VERSION );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

sub _mkdir {
    my $self = shift;
    my %hash = @_;
    my $err  = $self->error_object;
    my $conf = $self->configure_object;

    my $tmpl = {
        dir     => { required => 1 },
        verbose => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    unless( $self->_can_use( modules => { 'File::Path' => 0.0 } ) ) {
        $err->trap( error => loc("Could not use File::Path! This module should be core!") );
        return undef;
    }

    eval { File::Path::mkpath($args->{dir}) };

    my $flag;
    if($@) {
        chomp($@);
        $err->trap(
            error => loc( qq[Could not create directory '%1': %2], $args->{dir}. $@ )
        );
        $flag = 1;
    }

    return $flag ? undef : 1;
}

sub _chdir {
    my $self = shift;
    my %hash = @_;
    my $err  = $self->error_object;
    my $conf = $self->configure_object;

    my $tmpl = {
        dir     => { required => 1, allow => sub { -d pop() } },
        verbose => { default => $conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    unless( chdir $args->{dir} ) {
        $err->trap( error => loc(q[Could not chdir into '%1'], $args->{dir}) );
        return undef;
    }

    return 1;
}
1;