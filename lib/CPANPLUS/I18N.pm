# $File: //depot/cpanplus/dist/lib/CPANPLUS/I18N.pm $
# $Revision: #1 $ $Change: 1913 $ $DateTime: 2002/11/04 12:35:28 $

##############################
###    CPANPLUS/I18N.pm    ###
### Localization functions ###
##############################

package CPANPLUS::I18N;

use strict;
use Exporter;
use vars qw( @ISA @EXPORT %Lexicon $LangHandle );

@ISA     = 'Exporter';
@EXPORT  = 'loc';
%Lexicon = ( '_AUTO' => 1 );

if (eval { require Locale::Maketext; require Locale::Maketext::Lexicon; 1 }) {
    push @ISA, 'Locale::Maketext';

    require File::Spec;
    require File::Basename;

    my ($name, $path) = File::Basename::fileparse(__FILE__, '.pm');

    my @languages;
    foreach my $lexicon ( glob( File::Spec->catfile($path, $name, '*.po')) ) {
        File::Basename::basename($lexicon) =~ /^(\w+).po$/ or next;
        push @languages, $1;
    };

    Locale::Maketext::Lexicon->import( {
        i_default       => [
            Gettext => File::Spec->catfile($path, $name, "CPANPLUS.pot")
        ],
        map { lc($_)    => [
            Gettext => File::Spec->catfile($path, $name, "$_.po")
        ] } @languages,
    } );
}

$LangHandle = eval { __PACKAGE__->get_handle };

sub loc {
    my $str = shift;

    local $^W;

    if ($LangHandle) {
        $str =~ s/[\~\[\]]/~$&/g;
        $str =~ s/(^|[^%\\])%([A-Za-z#*]\w*)\(([^\)]*)\)/"$1\[$2,"._unescape($3)."]"/eg;
        $str =~ s/(^|[^%\\])%(\d+|\*)/$1\[_$2]/g;
        return $LangHandle->maketext($str, @_);
    }

    # stub code
    $str =~ s{
	%(?:\d+|(\w+)\(%\d+([^)]*)\))
    }{
	shift(@_) . (($1 and $1 eq 'tense')
	    ? (($2 eq ',present') ? 'ing' : 'ed')
	    : '');
    }egx;

    return $str;
}

sub _unescape {
    my $str = shift;
    $str =~ s/(^|,)%(\d+|\*)(,|$)/$1_$2$3/g;
    return $str;
}

# utility function for maketext
sub tense {
    my ($self, $str, $tense) = @_;
    return $str . (($tense eq 'present') ? 'ing' : 'ed');
}

1;

__END__

=head1 NAME

CPANPLUS::I18N - Localization class

=head1 SYNOPSIS

    use CPANPLUS::I18N;
    print loc("Hello, %1!", 'world');

=head1 DESCRIPTION

This module exports C<loc()> to each module that displays messages
to users, so that these messages may be properly localized.

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
