# $File: //depot/cpanplus/dist/lib/CPANPLUS/Internals/System.pm $
# $Revision: #2 $ $Change: 1913 $ $DateTime: 2002/11/04 12:35:28 $

#######################################################
###            CPANPLUS/Internals/System.pm         ###
###      Run-time flags for _run() and other stuff  ###
###         Written 28-05-2002 by Autrijus Tang     ###
#######################################################

### System.pm ###

package CPANPLUS::Internals::System;

use strict;

sub import {
    my $class = shift;
    foreach my $flag (@_) {
        my ($key, $val) = split(/=/, $flag, 2);

        if ($key eq 'autoflush') {
            $| = $val;
        }
    }
}

1;

=pod

=head1 NAME

CPANPLUS::Internals::System - Flags for _run()

=head1 DESCRIPTION

This module is included in every perl invoked by C<_run()> via
C<$ENV{PERL5OPT} .= " -MCPANPLUS::Internals::System=key1=val1,...">.

It then parses each key for ways to override the default behaviour.
Currently, only C<autoflush> is meaningful, which sets C<$|> to the
value.

=head1 AUTHORS

This module by
Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001, 2002 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same 
terms as Perl itself.

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
