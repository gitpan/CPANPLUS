# $File: //depot/dist/lib/CPANPLUS/Shell.pm $
# $Revision: #2 $ $Change: 59 $ $DateTime: 2002/06/06 05:24:49 $

###################################################
###               CPANPLUS/Shell.pm             ###
### Module to load the default shell for CPAN++ ###
###      Written 17-08-2001 by Jos Boumans      ###
###################################################

### Shell.pm ###

package CPANPLUS::Shell;

### First BEGIN block:
### make sure we set our global vars, and get the proper shell to use
### from Configure
BEGIN {
    use strict;
    use Exporter ();
    use CPANPLUS::Configure;

    use vars qw(@ISA $SHELL $DEFAULT);

    ### Perhaps this chould be a Config.pm option ###
    $DEFAULT = 'CPANPLUS::Shell::Default';

    my $cp = new CPANPLUS::Configure;

    ### Get the user preferred shell, or the default
    $SHELL  = $cp->get_conf('shell') || $DEFAULT;
}

### Second BEGIN block:
### (just split them out for clarity)
### this is the evil part, where we eval and check.
BEGIN {

    EVAL: {
        ### perlbug - if we use this, the die()'s will be ignored
        ### submitted to p5p Sat Feb  9 23:58:02 2002 -kane
        #local $@;

        ### use is compile time, so no choice but to eval it ###
        eval "use $SHELL";

        ### ok, something went wrong...
        if ($@) {

            ### if we already tried the default shell - which is the shell we ship
            ### with the dist as DEFAULT, something is VERY wrong! -kane
            if( $SHELL eq $DEFAULT ) {
                die qq[Your default shell $DEFAULT isn't available: $@\nCheck your installation!];

            ### otherwise, we just tried the shell the user entered... well, that might
            ### be a broken or even a non-existant one. So, warn the user it didn't work
            ### and we'll try our default shell instead.
            } else {
                warn qq[Failed to use $SHELL: $@\nSwitching to the default shell $DEFAULT];
                $SHELL = $DEFAULT;
                redo EVAL;
            }
        }
    }
    @ISA = ("Exporter", $SHELL);
}

sub which { return $SHELL };

1;

=pod

=head1 NAME

CPANPLUS::Shell - interactive interface launcher for CPAN++

=head1 SYNOPSIS

    perl -MCPANPLUS -e 'shell'
    /perl/bin/cpanp

=head1 DESCRIPTION

CPANPLUS::Shell is used to launch an interactive shell.  What
shell will be launched depends upon what shell was configured to
be the default.  If you did not change the shell during configuration,
the default shell will be CPANPLUS::Shell::Default.

You can start the shell with either the command-line perl, or
by using the C<cpanp> command, which will be installed in your
perl bin.

For information on using your shell, please refer to the documentation
for your default shell.

=head1 AUTHORS

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt>.

This pod text by Ann Barcomb E<lt>kudra@cpan.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001, 2002 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same 
terms as Perl itself.

=head1 SEE ALSO 

L<CPANPLUS::Shell::Default>

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
