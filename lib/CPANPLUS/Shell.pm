# $File: //depot/cpanplus/dist/lib/CPANPLUS/Shell.pm $
# $Revision: #2 $ $Change: 1913 $ $DateTime: 2002/11/04 12:35:28 $

###################################################
###               CPANPLUS/Shell.pm             ###
### Module to load the default shell for CPAN++ ###
###      Written 17-08-2001 by Jos Boumans      ###
###################################################

### Shell.pm ###

package CPANPLUS::Shell;

use strict;
use CPANPLUS::Configure;
use CPANPLUS::I18N;

use vars qw(@ISA $SHELL $DEFAULT);


### First BEGIN block:
### make sure we set our global vars, and get the proper shell to use
### from Configure
sub import {

    my ($pkg, $option) = @_;
    my $user_choice = $option ? 'CPANPLUS::Shell::' . $option : undef ;

    ### Perhaps this chould be a Config.pm option ###
    $DEFAULT = 'CPANPLUS::Shell::Default';

    my $cp = new CPANPLUS::Configure;

    ### Get the user preferred shell, or the default
    $SHELL  = $user_choice || $cp->get_conf('shell') || $DEFAULT;

    ### this is the evil part, where we eval and check.
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
                die loc("Your default shell %1 is not available: %2", $DEFAULT, $@), "\n",
                    loc("Check your installation!"), "\n";

            ### otherwise, we just tried the shell the user entered... well, that might
            ### be a broken or even a non-existant one. So, warn the user it didn't work
            ### and we'll try our default shell instead.
            } else {
                warn loc("Failed to use %1: %2", $SHELL, $@), "\n",
                     loc("Switching to the default shell %1", $DEFAULT), "\n";
                $SHELL = $DEFAULT;
                redo EVAL;
            }
        }
    }
    @ISA = ($SHELL);
}

sub which { return $SHELL };


###########################################################################
### abstracted out subroutines available to programmers of other shells ###
###########################################################################

package CPANPLUS::Shell::_Base;
use strict;
use vars qw($AUTOLOAD);

use File::Path;
use CPANPLUS::I18N;

### CPANPLUS::Shell::Default needs it's own constructor, seeing it will just access
### CPANPLUS::Backend anyway
sub _init {
    my $class   = shift;
    my %args    = @_;

    my $self    = { };

    ### signal handler ###
    $SIG{INT} = $self->{_signals}{INT}{handler} =
        sub {
            unless ($self->{_signals}{INT}{count}++) {
                warn loc("Caught SIGINT"), "\n";
            } else {
                warn loc("Got another SIGINT"), "\n"; die;
            }
        };

    ### initialise these attributes so that AUTOLOAD will
    ### recognize them
    for my $what ( qw[brand old_sigpipe old_outfh pager backend term format] ) {
        $self->{"_$what"} = '';
    }

    ### store arguments as attributes ###
    while ( my ($k,$v) = each %args ) { $self->{"_$k"} = $v }

    $self->{_signals}{INT}{count} = 0; # count of sigint calls

    return bless $self, $class;
}


### display shell's banner, takes the Backend object as argument
sub _show_banner {
    my ($self, $cpan) = @_;
    my $term = $self->term();

    ### Tries to probe for our ReadLine support status
    # a) under an interactive shell?
    my $rl_avail = (!$term->isa('CPANPLUS::Shell::_Faked'))
        # b) do we have a tty terminal?
        ? (-t STDIN)
            # c) should we enable the term?
            ? (!$self->_is_bad_terminal($term))
                # d) external modules available?
                ? ($term->ReadLine ne "Term::ReadLine::Stub")
                    # a+b+c+d => "Smart" terminal
                    ? loc("enabled")
                    # a+b+c => "Stub" terminal
                    : loc("available (try 'i Term::ReadLine::Perl')")
                # a+b => "Bad" terminal
                : loc("disabled")
            # a => "Dumb" terminal
            : loc("suppressed")
        # none    => "Faked" terminal
        : loc("suppressed in batch mode");

    $rl_avail = loc("ReadLine support %1.", $rl_avail);
    $rl_avail = "\n*** $rl_avail" if (length($rl_avail) > 45);

    print loc("%1 -- CPAN exploration and modules installation (v%2)", $self->which, $self->which->VERSION), "\n",
          loc("*** Please report bugs to <cpanplus-bugs\@lists.sourceforge.net>."), "\n",
          loc("*** Using CPANPLUS::Backend v%1.  %2", $cpan->VERSION, $rl_avail), "\n\n";
}


### checks whether the Term::ReadLine is broken and needs to fallback to Stub
sub _is_bad_terminal {
    my $self = shift;

    return unless $^O eq 'MSWin32';

    ### replace the term with the default (stub) one
    $_[0] = Term::ReadLine::Stub->new( $self->brand );

    return $self->term( $_[0] );
}


{
    my $win32_console;

    ### determines row count of current terminal; defaults to 25.
    sub _term_rowcount {
        my ($self, %args) = @_;
        my $cpan    = $self->backend;
        my $default = $args{default} || 25;

        if ( $^O eq 'MSWin32' ) {
            if ($cpan->_can_use( modules => { 'Win32::Console' => '0.0' } )) {
                $win32_console ||= Win32::Console->new;
                my $rows = ($win32_console->Info)[-1];
                return $rows;
            }

        } else {

            if ($cpan->_can_use( modules => { 'Term::Size' => '0.0' } )) {
                my ($cols, $rows) = Term::Size::chars();
                return $rows;
            }
        }

        return $default;
    }
}

### open a pager handle
sub _pager_open {
    my $self  = shift;
    my $cpan  = $self->backend;
    my $cmd   = $cpan->configure_object->_get_build('pager') or return;

    $self->old_sigpipe( $SIG{PIPE} );
    $SIG{PIPE} = 'IGNORE';

    my $fh = new FileHandle;
    unless ( $fh->open("| $cmd") ) {
        $cpan->error_object->trap( error => loc("could not pipe to %1: %2\n", $cmd, $!) );
        return 0;
    }

    $fh->autoflush(1);

    $self->pager( $fh );
    $self->old_outfh( select $fh );

    return $fh;
}


### print to the current pager handle, or STDOUT if it's not opened
sub _pager_close {
    my $self  = shift;
    my $pager = $self->pager or return;

    $pager->close if (ref($pager) and $pager->can('close'));

    $self->pager( undef );;

    select $self->old_outfh;
    $SIG{PIPE} = $self->old_sigpipe;
}

### parse and set configuration options: $method should be 'set_conf'
sub _set_config {
    my ($self, %args) = @_;

    my ($key, $value, $method) = @args{qw|key value method|};

    my $cpan = $self->backend;

    # determine the reference type of the original value
    my $type = ref($cpan->get_conf($key)->rv->{$key});

    if ($type eq 'HASH') {
        $value = $cpan->_flags_hashref($value);
    }
    elsif ($type eq 'ARRAY') {
        $value = [ $value =~ m/\s*("[^"]+"|'[^']+'|[^\s]+)/g ]
    }

    my $set = $cpan->$method( $key => $value )->rv;

    for my $key (sort keys %$set) {
        my $val = $set->{$key};
        $type = ref($val);

        if ($type eq 'HASH') {
            print loc("%1 was set to:", $key), "\n";
            print map {
                defined($value->{$_})
                    ? "    $_=$value->{$_}\n"
                    : "    $_\n"
            } sort keys %{$value};
        }
        elsif ($type eq 'ARRAY') {
            print loc("%1 was set to:", $key), "\n";
            print map { "    $_\n" } @{$value};
        }
        else {
            print loc("%1 was set to %2", $key, $set->{$key}), "\n";
        }
    }
}

sub _ask_prereq {
    my $obj     = shift;
    my %args    = @_;

    ### either it's called from Internals, or from the shell directly
    ### although the latter is unlikely...
    my $self = $obj->{_shell} || $obj;

    my $mod = $args{mod};

    print "\n", loc("%1 is a required module for this install.", $mod), "\n";

    return $self->_ask_yn(
        prompt  => loc("Would you like me to install it? [Y/n]: "),
        default => 'y',
    ) ? $mod : 0;
}


### generic yes/no question interface
sub _ask_yn {
    my ($self, %args) = @_;
    my $prompt  = $args{prompt};
    my $default = $args{default};

    while ( defined (my $input = $self->term->readline($prompt)) ) {
        $input = $default unless length $input;

        if ( $input =~ /^y/i ) {
            return 1;
        } elsif ( $input =~ /^n/i ) {
            return 0;
        } else {
            print loc("Improper answer, please reply 'y[es]' or 'n[o]'"), "\n";
        }
    }
}

sub AUTOLOAD {
    my $self = shift;

    $AUTOLOAD =~ s/.+:://;

    ### some debug code ###
    #print "\n----------------\nmethod: $AUTOLOAD\n";
    #while( my($k,$v) = each %$self ) {
    #    print "$k => $v\n";
    #}
    #print "\n----------------\n\n";

    unless ( ref($self) ) {
        require Carp;
        Carp::cluck($self);
    }

    unless ( exists $self->{"_$AUTOLOAD"} ) {
        warn loc("No such method %1", $AUTOLOAD), "\n";
        return 0;
    }

    if(@_) { $self->{"_$AUTOLOAD"} = shift; }

    return $self->{"_$AUTOLOAD"};
}

sub DESTROY { 1 }


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

=head1 AVAILABLE SHELLS

CPANPLUS ships with two shells: 

=over 4

=item I<Default> 

Consists of single-character commands.

=item I<Classic>

Emulates the shell interface of CPAN.pm.

=back

To see what other shells are available for CPANPLUS, try a search
of the CPAN.  In the Default shell, you can do this with:

    m cpanplus::shell::

=head1 CHANGING YOUR SHELL

During installation you should have been prompted to select a shell.
After installation there are two ways to set a shell.

=head2 CHANGING THE SHELL FOR THIS INVOCATION

The shell can be changed for this instance by specifying a shell
when starting CPANPLUS:

    perl -MCPANPLUS -e 'shell Classic'

=head2 PERMANENTLY CHANGING THE SHELL

To change the shell permanently, change your configuration.  This
can be done with the I<Backend> method I<set_conf>.  In the
I<Default> shell, the I<s> command allows configuration modifications.

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

L<CPANPLUS::Shell::Default>, L<CPANPLUS::Backend>,
L<CPANPLUS::Shell::Classic>

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
