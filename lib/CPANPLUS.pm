# $File: //member/autrijus/cpanplus/dist/lib/CPANPLUS.pm $
# $Revision: #4 $ $Change: 3540 $ $DateTime: 2002/03/26 04:28:49 $

###################################################################
###                         CPANPLUS.pm                         ###
### Module to provide a commandline interface to the CPAN++     ###
###              Written 17-08-2001 by Jos Boumans              ###
###################################################################

### CPANPLUS.pm ###

package CPANPLUS;

use strict;
use Carp;
use CPANPLUS::Backend;
use CPANPLUS::Shell;
#use CPANPLUS::Classic::Module;

BEGIN {
    use Exporter    ();
    use vars        qw( @EXPORT @ISA $VERSION );
    @EXPORT     =   qw( shell fetch get install );
    @ISA        =   qw( Exporter );
    $VERSION    =   $CPANPLUS::Backend::VERSION;
}

### purely for backward compatibility, so we can call it from the commandline:
### perl -MCPANPLUS -e 'install Net::SMTP'
sub install {
    my $cpan = new CPANPLUS::Backend;

    my $mod = shift or (
                        $cpan->{_error}->trap( error => "No module specified!" ),
                        return 0
                    );

    if ( ref $mod ) {
        $cpan->{_error}->trap(
                    error => "You passed an object. Use CPANPLUS::Backend for OO style interaction"
                );
        return 0;

    } else {
        return $cpan->install( modules => [ $mod ] );
    }
}

### simply downloads a module and stores it
sub fetch {
    my $cpan = new CPANPLUS::Backend;

    my $mod = shift or (
                        $cpan->{_error}->trap( error => "No module specified!" ),
                        return 0
                    );

    if ( ref $mod ) {
        $cpan->{_error}->trap(
                    error => "You passed an object. Use CPANPLUS::Backend for OO style interaction"
                );
        return 0;
    } elsif ( !$cpan->{_modtree}->{$mod} ) {
        $cpan->{_error}->trap(
                    error => "No such module: $mod"
                );
        return 0;

    } else {
        return $cpan->fetch(
            modules     => [ $mod ],
            fetchdir   => $cpan->{_conf}->_get_build('startdir')
        );
    }
}

### alias to fetch() due to compatibility with cpan.pm ###
sub get { fetch(@_) }


### purely for backwards compatibility, so we can call it from the commandline:
### perl -MCPANPLUS -e 'shell'
sub shell {
    my $cpan = new CPANPLUS::Shell;

    $cpan->shell();
}

1;

__END__

=pod

=head1 NAME

CPANPLUS - Command-line access to the CPAN interface

=head1 NOTICE

Please note that CPANPLUS is intended to eventually be a full drop-in
replacement for CPAN.pm.  However, in early releases you should
B<NOT> expect complete compatibility.

=head1 SYNOPSIS

Command line:

    perl -MCPANPLUS -e 'install Net::SMTP'

    perl -MCPANPLUS -e 'fetch /K/KA/KANE/Acme-POE-Knee-1.10.zip'
    perl -MCPANPLUS -e 'get /K/KA/KANE/Acme-POE-Knee-1.10.zip'

    perl -MCPANPLUS -e 'shell'
    /perl/bin/cpanp

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

=head2 install(NAME);

This function requires the full name of the module, which is case
sensitive.  The module name can also be provided as a fully
qualified file name, beginning with a I</>, relative to
the /authors/id directory on a CPAN mirror.

It will download, extract and install the module.

=head2 fetch(NAME);

Like install, fetch needs the full name of a module or the fully
qualified file name, and is case sensitive.

It will download the specified module to the current directory.

=head2 get(NAME);

Get is provided as an alias for fetch for compatibility with
CPAN.pm.

=head2 shell

Shell starts the default CPAN shell.  You can also start the shell
by using the C<cpanp> command, which will be installed in your
perl bin.

See L<CPANPLUS::Shell::Default> for
instructions on using the default shell.  Note that if you have changed
your default shell in your configuration, that shell will be used instead.

The default shell is only designed to be used on the command-line; its use
in a script is completely unsupported.

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

Andreas Koenig E<lt>andreas.koenig@anima.deE<gt> authored
the original CPAN.pm module.

=head1 SEE ALSO

L<CPANPLUS::Backend>, L<CPANPLUS::Shell::Default>

=cut
