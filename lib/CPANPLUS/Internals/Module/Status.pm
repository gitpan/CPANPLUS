# $File: //depot/cpanplus/devel/lib/CPANPLUS/Internals/Module.pm $
# $Revision: #13 $ $Change: 3693 $ $DateTime: 2003/01/20 12:29:29 $

#######################################################
###     CPANPLUS/Internals/Module/Status.pm         ###
###   Hold status information for Module objects    ###
###         Written 20-01-2003 by Jos Boumans       ###
#######################################################

package CPANPLUS::Internals::Module::Status;

use strict;
use CPANPLUS::I18N;
use CPANPLUS::Tools::Check qw[check];

use Data::Dumper;

use vars qw[$AUTOLOAD];

sub new { return bless {}, shift }

my $map = {
    dist            => 'dist',
    dist_ppm        => 'dist-ppm',
    dist_ports	    => 'dist-ports',
    dist_par	    => 'dist-par',
    make            => 'make-make',
    makefile        => 'make-makefile',
    make_test       => 'make-test',
    prereq          => 'make-prereq',
    make_overall    => 'make-overall',
    make_dir        => 'make-dir',
    signature       => 'signature',
    install         => 'install',
    extract         => 'extract',
    md5             => 'md5',
    fetch           => 'fetch',
    bundle          => 'bundle',
    readme          => 'readme',
    uninstall       => 'uninstall',
};

sub AUTOLOAD {
    my $self = shift;

    $AUTOLOAD =~ s/.+:://g;

    my @where = split( '-', $map->{ lc $AUTOLOAD } )
                    or die loc("No such method %1",$AUTOLOAD);

    if ( scalar @where == 1 ) {
        $self->{$where[0]} = $_[0] if @_;
        return $self->{$where[0]};
    } elsif ( scalar @where == 2 ) {
        $self->{$where[0]}->{$where[1]} = $_[0] if @_;
        return $self->{$where[0]}->{$where[1]};
    }
}

sub DESTROY { 1 }

1;
