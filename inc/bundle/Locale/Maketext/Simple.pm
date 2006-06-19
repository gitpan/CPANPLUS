# $File: //member/autrijus/Locale-Maketext-Simple/lib/Locale/Maketext/Simple.pm $ $Author: autrijus $
# $Revision: #17 $ $Change: 9922 $ $DateTime: 2004/02/06 11:13:31 $

package Locale::Maketext::Simple;
$Locale::Maketext::Simple::VERSION = "-1";

use strict;

=head1 NAME

Locale::Maketext::Simple - Simple interface to Locale::Maketext::Lexicon

=head1 VERSION

This document describes version 0.11 of Locale::Maketext::Simple,
released February 6, 2004.

=head1 SYNOPSIS

Minimal setup (looks for F<auto/Foo/*.po> and F<auto/Foo/*.mo>):

    package Foo;
    use Locale::Maketext::Simple;	# exports 'loc'
    loc_lang('fr');			# set language to French
    sub hello {
	print loc("Hello, [_1]!", "World");
    }

More sophisticated example:

    package Foo::Bar;
    use Locale::Maketext::Simple (
	Class	    => 'Foo',		# search in auto/Foo/
	Style	    => 'gettext',	# %1 instead of [_1]
	Export	    => 'maketext',	# maketext() instead of loc()
	Subclass    => 'L10N',		# Foo::L10N instead of Foo::I18N
	Decode	    => 1,		# decode entries to unicode-strings
    );
    sub japh {
	print maketext("Just another %1 hacker", "Perl");
    }

=head1 DESCRIPTION

This module is a simple wrapper around B<Locale::Maketext::Lexicon>,
designed to alleviate the need of creating I<Language Classes> for
module authors.

If B<Locale::Maketext::Lexicon> is not present, it implements a
minimal localization function by simply interpolating C<[_1]> with
the first argument, C<[_2]> with the second, etc.  Interpolated
function like C<[quant,_1]> are treated as C<[_1]>, with the sole
exception of C<[tense,_1,X]>, which will append C<ing> to C<_1> when
X is C<present>, or appending C<ed> to <_1> otherwise.

=head1 OPTIONS

All options are passed either via the C<use> statement, or via an
explicit C<import>.

=head2 Class

By default, B<Locale::Maketext::Simple> draws its source from the
calling package's F<auto/> directory; you can override this behaviour
by explicitly specifying another package as C<Class>.

=head2 Path

If your PO and MO files are under a path elsewhere than C<auto/>,
you may specify it using the C<Path> option.

=head2 Style

By default, this module uses the C<maketext> style of C<[_1]> and
C<[quant,_1]> for interpolation.  Alternatively, you can specify the
C<gettext> style, which uses C<%1> and C<%quant(%1)> for interpolation.

This option is case-insensitive.

=head2 Export

By default, this module exports a single function, C<loc>, into its
caller's namespace.  You can set it to another name, or set it to
an empty string to disable exporting.

=head2 Subclass

By default, this module creates an C<::I18N> subclass under the
caller's package (or the package specified by C<Class>), and stores
lexicon data in its subclasses.  You can assign a name other than
C<I18N> via this option.

=cut

sub import {
    my ($class, %args) = @_;

    $args{Class}    ||= caller;
    $args{Style}    ||= 'maketext';
    $args{Export}   ||= 'loc';
    $args{Subclass} ||= 'I18N';

    my ($loc, $loc_lang) = $class->load_loc(%args);
    $loc ||= $class->default_loc(%args);

    no strict 'refs';
    *{caller(0) . "::$args{Export}"} = $loc if $args{Export};
    *{caller(0) . "::$args{Export}_lang"} = $loc_lang || sub { 1 };
}

my %Loc;

sub reload_loc { %Loc = () }

sub load_loc {
    my ($class, %args) = @_;

    my $pkg = join('::', $args{Class}, $args{Subclass});
    return $Loc{$pkg} if exists $Loc{$pkg};

    eval { require Locale::Maketext::Lexicon; 1 }   or return;
    $Locale::Maketext::Lexicon::VERSION > 0.20	    or return;
    eval { require File::Spec; 1 }		    or return;

    my $path = $args{Path} || $class->auto_path($args{Class}) or return;
    my $pattern = File::Spec->catfile($path, '*.[pm]o');
    my $decode = $args{Decode} || 0;

    $pattern =~ s{\\}{/}g; # to counter win32 paths

    eval "
	package $pkg;
	use base 'Locale::Maketext';
        %${pkg}::Lexicon = ( '_AUTO' => 1 );
	Locale::Maketext::Lexicon->import({
	    'i-default' => [ 'Auto' ],
	    '*'	=> [ Gettext => \$pattern ],
	    _decode => \$decode,
	});
	*tense = sub { \$_[1] . ((\$_[2] eq 'present') ? 'ing' : 'ed') }
	    unless defined &tense;

	1;
    " or die $@;
    
    my $lh = eval { $pkg->get_handle } or return;
    my $style = lc($args{Style});
    if ($style eq 'maketext') {
	$Loc{$pkg} = sub {
	    $lh->maketext(@_)
	};
    }
    elsif ($style eq 'gettext') {
	$Loc{$pkg} = sub {
	    my $str = shift;
	    $str =~ s/[\~\[\]]/~$&/g;
	    $str =~ s{(^|[^%\\])%([A-Za-z#*]\w*)\(([^\)]*)\)}
		     {"$1\[$2,"._unescape($3)."]"}eg;
	    $str =~ s/(^|[^%\\])%(\d+|\*)/$1\[_$2]/g;
	    return $lh->maketext($str, @_);
	};
    }
    else {
	die "Unknown Style: $style";
    }

    return $Loc{$pkg}, sub {
	$lh = $pkg->get_handle(@_);
	$lh = $pkg->get_handle(@_);
    };
}

sub default_loc {
    my ($self, %args) = @_;
    my $style = lc($args{Style});
    if ($style eq 'maketext') {
	return sub {
	    my $str = shift;
	    $str =~ s/((?<!~)(?:~~)*)\[_(\d+)\]/$1%$2/g;
	    $str =~ s{((?<!~)(?:~~)*)\[([A-Za-z#*]\w*),([^\]]+)\]}
		     {"$1%$2("._escape($3).")"}eg;
	    $str =~ s/~([\[\]])/$1/g;
	    _default_gettext($str, @_);
	};
    }
    elsif ($style eq 'gettext') {
	return \&_default_gettext;
    }
    else {
	die "Unknown Style: $style";
    }
}

sub _default_gettext {
    my $str = shift;
    $str =~ s{
	%			# leading symbol
	(?:			# either one of
	    \d+			#   a digit, like %1
	    |			#     or
	    (\w+)\(		#   a function call -- 1
		(?:		#     either
		    %\d+	#	an interpolation
		    |		#     or
		    ([^,]*)	#	some string -- 2
		)		#     end either
		(?:		#     maybe followed
		    ,		#       by a comma
		    ([^),]*)	#       and a param -- 3
		)?		#     end maybe
		(?:		#     maybe followed
		    ,		#       by another comma
		    ([^),]*)	#       and a param -- 4
		)?		#     end maybe
		[^)]*		#     and other ignorable params
	    \)			#   closing function call
	)			# closing either one of
    }{
	my $digit = $2 || shift;
	$digit . (
	    $1 ? (
		($1 eq 'tense') ? (($3 eq 'present') ? 'ing' : 'ed') :
		($1 eq 'quant') ? ' ' . (($digit > 1) ? ($4 || "$3s") : $3) :
		''
	    ) : ''
	);
    }egx;
    return $str;
};

sub _escape {
    my $text = shift;
    $text =~ s/\b_(\d+)/%$1/;
    return $text;
}

sub _unescape {
    my $str = shift;
    $str =~ s/(^|,)%(\d+|\*)(,|$)/$1_$2$3/g;
    return $str;
}

sub auto_path {
    my ($self, $calldir) = @_;
    $calldir =~ s#::#/#g;
    my $path = $INC{$calldir . '.pm'} or return;

    # Try absolute path name.
    if ($^O eq 'MacOS') {
	(my $malldir = $calldir) =~ tr#/#:#;
	$path =~ s#^(.*)$malldir\.pm\z#$1auto:$malldir:#s;
    } else {
	$path =~ s#^(.*)$calldir\.pm\z#$1auto/$calldir/#;
    }

    return $path if -d $path;

    # If that failed, try relative path with normal @INC searching.
    $path = "auto/$calldir/";
    foreach my $inc (@INC) {
	return "$inc/$path" if -d "$inc/$path";
    }

    return;
}

1;

=head1 ACKNOWLEDGMENTS

Thanks to Jos I. Boumans for suggesting this module to be written.

Thanks to Chia-Liang Kao for suggesting C<Path> and C<loc_lang>.

=head1 SEE ALSO

L<Locale::Maketext>, L<Locale::Maketext::Lexicon>

=head1 AUTHORS

Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>

=head1 COPYRIGHT

Copyright 2003, 2004 by Autrijus Tang E<lt>autrijus@autrijus.orgE<gt>.

This program is free software; you can redistribute it and/or 
modify it under the same terms as Perl itself.

See L<http://www.perl.com/perl/misc/Artistic.html>

=cut
