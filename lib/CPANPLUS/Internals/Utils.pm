#######################################################
###         CPANPLUS/Internals/Utils.pm             ###
###         Utility functions to CPANPLUS           ###
###         Written 11-03-2002 by Jos Boumans       ###
#######################################################

package CPANPLUS::Internals::Utils;

use strict;
use Data::Dumper;
use CPANPLUS::I18N;

BEGIN {
    use vars        qw( $VERSION );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

sub _mkdir {
    my $self = shift;
    my %args = @_;

    my $err  = $self->error_object;

    unless( $self->_can_use( modules => { 'File::Path' => 0.0 } ) ) {
        $err->trap( error => loc("Could not use File::Path! This module should be core!") );
        return 0;
    }

    eval { File::Path::mkpath($args{dir}) };

    my $flag;
    if($@) {
        chomp($@);
        $err->trap(
            error => loc( qq[Could not create directory '%1': %2], $args{dir}. $@ )
        );
        $flag = 1;
    }

    return !$flag;
}

1;