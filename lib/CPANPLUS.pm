# $File: //depot/cpanplus/dist/lib/CPANPLUS.pm $
# $Revision: #4 $ $Change: 2930 $ $DateTime: 2002/12/25 16:03:28 $

###################################################################
###                         CPANPLUS.pm                         ###
### Module to provide a commandline interface to the CPAN++     ###
###              Written 17-08-2001 by Jos Boumans              ###
###################################################################

### CPANPLUS.pm ###

package CPANPLUS;

use strict;
use Carp;
use CPANPLUS::I18N;
use CPANPLUS::Backend;

BEGIN {
    use Exporter    ();
    use vars        qw( @EXPORT @ISA $VERSION );
    @EXPORT     =   qw( shell fetch get install );
    @ISA        =   qw( Exporter );
    $VERSION    =   '0.041';    #have to hardcode or cpan.org gets unhappy
}

### purely for backward compatibility, so we can call it from the commandline:
### perl -MCPANPLUS -e 'install Net::SMTP'
sub install {
    my $cpan = new CPANPLUS::Backend;
    my $err  = $cpan->error_object;

    my $mod = shift or (
                        $cpan->{_error}->trap( error => "No module specified!" ),
                        return 0
                    );

    if ( ref $mod ) {
        $err->trap( error => loc("You passed an object. Use CPANPLUS::Backend for OO style interaction") );
        return 0;

    } else {

        ### input checker disabled and moved to backend instead
        ### with having autobundle's enabled it's easier to have the
        ### validity checker in one central place, namely backend's
        ### install method
        #unless( $cpan->module_tree->{$mod} ) {
        #    $err->trap( error => loc("Unknown module '%1'", $mod) );
        #    return 0;
        #}

        my $rv = $cpan->install( modules => [ $mod ] );


        my $msg = $rv->ok
                    ? loc("Installing of %1 successful", $mod)
                    : loc("Installing of %1 failed", $mod);

        $err->inform( msg => $msg, quiet => 0 );

        return $rv->ok;
    }
}

### simply downloads a module and stores it
sub fetch {
    my $cpan = new CPANPLUS::Backend;

    my $mod = shift or (
                        $cpan->{_error}->trap( error => loc("No module specified!") ),
                        return 0
                    );

    if ( ref $mod ) {
        $cpan->{_error}->trap(
                    error => loc("You passed an object. Use CPANPLUS::Backend for OO style interaction")
                );
        return 0;
    } else {
        unless( $cpan->module_tree->{$mod} ) {
            $cpan->{_error}->trap( error => loc("Unknown module '%1'", $mod) );
            return 0;
        }

        my $rv = $cpan->fetch(
            modules     => [ $mod ],
            fetchdir   => $cpan->{_conf}->_get_build('startdir')
        );

        my $msg = $rv->ok
                    ? loc("Fetching of %1 successful", $mod)
                    : loc("Fetching of %1 failed", $mod);

        $cpan->{_error}->inform( msg => $msg, quiet => 0 );

        return $rv->ok;
    }
}

### alias to fetch() due to compatibility with cpan.pm ###
sub get { fetch(@_) }


### purely for backwards compatibility, so we can call it from the commandline:
### perl -MCPANPLUS -e 'shell'
sub shell {
    my $option  = shift;

    ### since the user can specify the type of shell they wish to start
    ### when they call the shell() function, we have to eval the usage
    ### of CPANPLUS::Shell so we an set up all the checks properly
    eval { require CPANPLUS::Shell; CPANPLUS::Shell->import($option) };
    die $@ if $@;

    my $cpan = CPANPLUS::Shell->new();

    $cpan->shell();
}

1;

__END__

=pod

=head1 NAME

CPANPLUS - Command-line access to the CPAN interface

=head1 NOTICE

CPANPLUS will appear in Perl core in version 5.10, under an
as-yet undetermined name.  CPAN.pm will be deprecated.  CPANPLUS
is B<not> a drop-in replacement for CPAN.pm.

A shell interface which resembles the shell aspects (and not
the programming interface) of CPAN.pm is available.  Refer
to L<CPANPLUS::Shell> for information on switching to the
Classic shell.

=head1 SYNOPSIS

Command line:

    /perl/bin/cpanp
    perl -MCPANPLUS -e 'shell'

    perl5.6.1 -MCPANPLUS -e 'install Net::SMTP'

    perl -MCPANPLUS -e 'fetch /K/KA/KANE/Acme-POE-Knee-1.10.zip'
    perl5.00503 -MCPANPLUS -e 'get /K/KA/KANE/Acme-POE-Knee-1.10.zip'

Note that one CPANPLUS installation can be used for multiple versions
of Perl.  If no version is specified, the Perl version used to install
CPANPLUS will be used.

Scripts:

    use CPANPLUS;
    # This use is not recommended; use
    # CPANPLUS::Backend instead!

    install('Net::SMTP');
    get('Acme::POE::Knee');

=head1 DESCRIPTION

CPANPLUS provides command-line access to the CPAN interface.   Three
functions, I<fetch>, I<install> and I<shell>
are imported in to your namespace.  I<get>--an alias for
I<fetch>--is also provided.

Although CPANPLUS can also be used within scripts,
it is B<highly> recommended
that you use L<CPANPLUS::Backend> in such situations.  In addition to
providing an OO interface, CPANPLUS::Backend is more efficient than
CPANPLUS for multiple operations.
CPANPLUS is provided primarily for
the command-line, in order to be backwards compatible with CPAN.pm.

The first time you run CPANPLUS you should be prompted to
adjust your settings, if you haven't already done so.  Your
settings will determine treatment of dependencies, handling
of errors, and so on.

=head1 FUNCTIONS

=head2 install(NAME)

This function requires the full name of the module, which is case
sensitive.  The module name can also be provided as a fully
qualified file name, beginning with a I</>, relative to
the /authors/id directory on a CPAN mirror.

It will download, extract and install the module.

=head2 fetch(NAME)

Like install, fetch needs the full name of a module or the fully
qualified file name, and is case sensitive.

It will download the specified module to the current directory.

=head2 get(NAME)

Get is provided as an alias for fetch for compatibility with
CPAN.pm.

=head2 shell

Shell starts the default CPAN shell.  You can also start the shell
by using the C<cpanp> command, which will be installed in your
perl bin.

See L<CPANPLUS::Shell::Default> for
instructions on using the default shell.  Note that if you have changed
your default shell in your configuration, that shell will be used instead.
If for some reason there was an error with your specified shell, you
will be given the default shell.

You may also optionally specify another shell to use for this invocation
(which is a good way to test other shells):
    perl -MCPANPLUS -e 'shell Classic'

Shells are only designed to be used on the command-line; use
of shells for scripting is discouraged and completely unsupported.

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

=head1 ACKNOWLEDGMENTS

Please see the F<AUTHORS> file in the CPANPLUS distribution
for a list of Credits and Contributors.

=head1 SEE ALSO

L<CPANPLUS::Backend>, L<CPANPLUS::Shell::Default>

=head1 CONTACT INFORMATION

=over 4

=item * General suggestions:
I<cpanplus-info@lists.sourceforge.net>

=item * Bug reporting:
I<cpanplus-bugs@lists.sourceforge.net>

=item * Development list:
I<cpanplus-devel@lists.sourceforge.net>

=back


=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
