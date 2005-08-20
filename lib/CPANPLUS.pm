package CPANPLUS;

use strict;
use Carp;
use CPANPLUS::inc;
use CPANPLUS::Error;
use CPANPLUS::Backend;

use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';

BEGIN {
    use Exporter    ();
    use vars        qw( @EXPORT @ISA $VERSION );
    @EXPORT     =   qw( shell fetch get install );
    @ISA        =   qw( Exporter );
    $VERSION    =   "0.0562";     #have to hardcode or cpan.org gets unhappy
}

### purely for backward compatibility, so we can call it from the commandline:
### perl -MCPANPLUS -e 'install Net::SMTP'
sub install {
    my $cpan = CPANPLUS::Backend->new;
    my $mod = shift or (
                    cp_error(loc("No module specified!")), return
                );

    if ( ref $mod ) {
        cp_error( loc( "You passed an object. Use %1 for OO style interaction",
                    'CPANPLUS::Backend' ));
        return;

    } else {
        my $obj = $cpan->module_tree($mod) or (
                        cp_error(loc("No such module '%1'", $mod)),
                        return
                    );

        my $ok = $obj->install;

        $ok
            ? cp_msg(loc("Installing of %1 successful", $mod),1)
            : cp_msg(loc("Installing of %1 failed", $mod),1);

        return $ok;
    }
}

### simply downloads a module and stores it
sub fetch {
    my $cpan = CPANPLUS::Backend->new;

    my $mod = shift or (
                    cp_error(loc("No module specified!")), return
                );

    if ( ref $mod ) {
        cp_error( loc( "You passed an object. Use %1 for OO style interaction",
                    'CPANPLUS::Backend' ));
        return;

    } else {
        my $obj = $cpan->module_tree($mod) or (
                        cp_error(loc("No such module '%1'", $mod)),
                        return
                    );

        my $ok = $obj->fetch( fetchdir => '.' );

        $ok
            ? cp_msg(loc("Fetching of %1 successful", $mod),1)
            : cp_msg(loc("Fetching of %1 failed", $mod),1);

        return $ok;
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
    ### of CPANPLUS::Shell so we can set up all the checks properly
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

=head1 SYNOPSIS

    cpanp
    cpanp -i Some::Module

    perl -MCPANPLUS -eshell
    perl -MCPANPLUS -e'fetch Some::Module'

    ### for programmatic interfacing, see below ###

=head1 DESCRIPTION

The C<CPANPLUS> library is an API to the C<CPAN> mirrors and a
collection of interactive shells, commandline programs, daemons, etc,
that use this API.

This documentation will discuss all of these briefly and direct you to
the appropriate tool to use for the job at hand.

=head1 INTERFACES

=head2 COMMAND LINE

The C<CPANPLUS> library comes with several command line tools;

=over 4

=item C<cpanp>

This is the commandline tool to start the default interactive shell
(see C<SHELLS> below), or to do one-off commands. See C<cpanp -h> for
details.

=item C<cpan2dist.pl>

This is a commandline tool to convert any distribution from C<CPAN>
into a package in the format of your choice, like for example C<.deb>
or C<FreeBSD ports>. See C<cpan2dist.pl -h> for details.

=item C<cpanpd.pl>

This is a daemon that acts as a remote backend to your default shell.
This allows you to administrate multiple perl installations on multiple
machines using only one frontend. See C<cpanpd.pl -h> for details.

=back

=head2 SHELLS

Interactive shells are there for when you want to do multiple queries,
browse the C<CPAN> mirrors, consult a distributions C<README>, etc.

The C<CPANPLUS> library comes with a variety of possible shells. You
can install third party shells from the C<CPAN> mirrors if the default
one is not to your liking.

=over 4

=item CPANPLUS::Shell::Default

This is the standard shell shipped with C<CPANPLUS>. The commands

    cpanp

and

    perl -MCPANPLUS -eshell

should fire it up for you. Type C<h> at the prompt to see how to use it.

=item CPANPLUS::Shell::Classic

This is the emulation shell that looks and feels just like the old
C<CPAN.pm> shell.

=back

=head2 API

All the above tools are written using the C<CPANPLUS> API. If you have
any needs that aren't already covered by the above tools, you might
consider writing your own. To do this, use the C<CPANPLUS::Backend>
module. It implements the full C<CPANPLUS> API.

Consult the C<CPANPLUS::Backend> documentation on how to use it.

=head2 PLUGINS

There are various plugins available for C<CPANPLUS>. Below is a short
listing of just a few of these plugins;

=over 4

=item Various shells

As already available in the C<0.04x> series, C<CPANPLUS> provides
various shells (as described in the C<SHELL> section above). There
are also 3rd party shells you might get from a C<cpan> mirror near
you, such as:

=over 8

=item CPANPLUS::Shell::Curses

A shell using C<libcurses>

=item CPANPLUS::Shell::Tk

A shell using the graphical toolkit C<Tk>

=back

=item Various package manager plugins

As already available in the C<0.04x> series, C<CPANPLUS> can provide
a hook to install modules via the package manager of your choice.
Look in the C<CPANPLUS::Dist::> namespace on C<cpan> to see what's
available. Installing such a plugin will allow you to create packages
of that type using the C<cpan2dist> program provided with C<CPANPLUS>
or by saying, to create for example, debian distributions:

    cpanp -i Acme::Bleach --format=debian

There are a few package manager plugins available and/or planned
already; they include, but are not limited to:

=over 8

=item CPANPLUS::Dist::Ports

Allows you to create packages for C<FreeBSD ports>.

=item CPANPLUS::Dist::Deb

Allows you to create C<.deb> packages for C<Debian linux>.

=item CPANPLUS::Dist::MDK

Allows you to create packages for C<MandrakeLinux>.

=item CPANPLUS::Dist::PPM

Allows you to create packages in the C<PPM> format, commonly
used by C<ActiveState Perl>.

=back

=item CPANPLUS Remote Daemon

New in the C<0.05x> series is the C<CPANPLUS Daemon>. This application
allows you to remotely control several machines running the C<CPANPLUS
Daemon>, thus enabling you to update several machines at once, or
updating machines from the comfort of your own desktop. This is done
using C<CPANPLUS::Shell::Default>'s C<dispatch_on_input> method. See
the C<CPANPLUS::Shell::Default> manpage for details on that method.

=item Scriptable Shell

New in the C<0.05x> series is the possibility of scripting the default
shell. This can be done by using its C<dispatch_on_input> method.
See the C<CPANPLUS::Shell::Default> manpage for details on that method.

Also, soon it will be possible to have a C<.rc> file for the default
shell, making aliases for all your commonly used functions. For exmpale,
you could alias 'd' to do this:

    d --fetchdir=/my/downloads

or you could make the re-reading of your sourcefiles force a refetch
of those files at all times:
    x --update_source

=back

=head1 FUNCTIONS

For quick access to common commands, you may use this module,
C<CPANPLUS> rather than the full programmatic API situated in
C<CPANPLUS::Backend>. This module offers the following functions:

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

See L<CPANPLUS::Shell::Default> for instructions on using the default
shell.  Note that if you have changed your default shell in your
configuration, that shell will be used instead. If for some reason
there was an error with your specified shell, you will be given the
default shell.

You may also optionally specify another shell to use for this invocation
(which is a good way to test other shells):
    perl -MCPANPLUS -e 'shell Classic'

Shells are only designed to be used on the command-line; use
of shells for scripting is discouraged and completely unsupported.

=head1 FAQ

For frequently asked questions and answers, please consult the
C<CPANPLUS::FAQ> manual.

=head1 AUTHOR

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001, 2002, 2003, 2004, 2005 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=head1 ACKNOWLEDGEMENTS

Please see the F<AUTHORS> file in the CPANPLUS distribution
for a list of Credits and Contributors.

=head1 SEE ALSO

L<CPANPLUS::Backend>, L<CPANPLUS::Shell::Default>, L<CPANPLUS::FAQ>,
L<cpanp>,  L<cpan2dist.pl>

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
