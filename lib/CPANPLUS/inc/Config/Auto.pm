package Config::Auto;

use strict;
use warnings;
use File::Spec::Functions;
use File::Basename;
#use XML::Simple;   # this is now optional
use Config::IniFiles;
use Carp;

use vars qw[$VERSION $DisablePerl];

$VERSION = '0.11';
$DisablePerl = 0;

my %methods = (
    perl   => \&eval_perl,
    colon  => \&colon_sep,
    space  => \&space_sep,
    equal  => \&equal_sep,
    bind   => \&bind_style,
    irssi  => \&irssi_style,
    xml    => \&parse_xml,
    ini    => \&parse_ini,
    list   => \&return_list,
);

delete $methods{'xml'} 
    unless eval { require XML::Simple; XML::Simple->import; 1 };

sub parse {
    my $file = shift;
    my %args = @_;
    
    $file = find_file($file)                if not defined $file or 
                                               not -e $file;
    croak "No config file found!"           if not defined $file;
    croak "Config file $file not readable!" if not -e $file; 

    return if -B $file;

    my $method;
    my @data;

    if (!defined $args{format}) {
        # OK, let's take a look at you.
        my @data;
        open CONFIG, $file or croak "$file: $!";
        if (-s $file > 1024*100) {
            # Just read in a bit.
            while (<CONFIG>) {
                push @data, $_;
                last if $. >= 50;
            }
        } else {
            @data = <CONFIG>;
        }
        my %scores = score(\@data);
        delete $scores{perl} if exists $scores{perl} and $DisablePerl;
        croak "Unparsable file format!" if !keys %scores;
        # Clear winner?
        my @methods = sort { $scores{$b} <=> $scores{$a} } keys %scores;
        if (@methods > 1) {
            croak "File format unclear! ".join ",", map { "$_ => $scores{$_}"} @methods
               if $scores{$methods[0]} == $scores{$methods[1]};
        }
        $method = $methods[0];
    } else {
        croak "Unknown format $args{format}: use one of @{[ keys %methods ]}"
            if not exists $methods{$args{format}};
        $method = $args{format};
    }
    return $methods{$method}->($file);
}

sub score {
    my $data_r = shift;
    return (xml => 100)     if $data_r->[0] =~ /^\s*<\?xml/;
    return (perl => 100)    if $data_r->[0] =~ /^#!.*perl/;
    my %score;
    
    for (@$data_r) {
        # Easy to comment out foo=bar syntax
        $score{equal}++                 if /^\s*#\s*\w+\s*=/;
        next if /^\s*#/;
        
        $score{xml}++                   for /(<\w+.*?>)/g;
        $score{xml}+= 2                 for m|(</\w+.*?>)|g;
        $score{xml}+= 5                 for m|(/>)|g;
        next unless /\S/;
        
        $score{equal}++, $score{ini}++  if m|^.*=.*$|;
        $score{equal}++, $score{ini}++  if m|^\S+\s+=\s+|;
        $score{colon}++                 if /^[^:]+:[^:=]+/;
        $score{colon}+=2                if /^\s*\w+\s*:[^:]+$/;
        $score{colonequal}+= 3          if /^\s*\w+\s*:=[^:]+$/; # Debian foo.
        $score{perl}+= 10               if /^\s*\$\w+(\{.*?\})*\s*=.*/;
        $score{space}++                 if m|^[^\s:]+\s+\S+$|;
        
        # mtab, fstab, etc.
        $score{space}++                 if m|^(\S+)\s+(\S+\s*)+|;
        $score{bind}+= 5                if /\s*\S+\s*{$/;
        $score{list}++                  if /^[\w\/\-\+]+$/;
        $score{bind}+= 5                if /^\s*}\s*$/  and exists $score{bind};
        $score{irssi}+= 5               if /^\s*};\s*$/ and exists $score{irssi};
        $score{irssi}+= 10              if /(\s*|^)\w+\s*=\s*{/;
        $score{perl}++                  if /\b([@%\$]\w+)/g;
        $score{perl}+= 2                if /;\s*$/;
        $score{perl}+=10                if /(if|for|while|until|unless)\s*\(/;
        $score{perl}++                  for /([\{\}])/g;
        $score{equal}++, $score{ini}++  if m|^\s*\w+\s*=.*$|;
        $score{ini} += 10               if /^\s*\[[\s\w]+\]\s*$/;
    }

    # Choose between Win INI format and foo = bar
    if (exists $score{ini}) {
        $score{ini} > $score{equal}
            ? delete $score{equal}
            : delete $score{ini};
    }

    # Some general sanity checks
    if (exists $score{perl}) {
        $score{perl} /= 2   unless ("@$data_r" =~ /;/) > 3 or $#$data_r < 3;
        delete $score{perl} unless ("@$data_r" =~ /;/);
        delete $score{perl} unless ("@$data_r" =~ /([\$\@\%]\w+)/);
    }

    return %score;
}

sub find_file {
    my $x;
    my $whoami = basename($0);
    my $bindir = dirname($0);
    $whoami =~ s/\.pl$//;

    my @options = shift ||
                    ("${whoami}config", "${whoami}.config", 
                     "${whoami}rc", ".${whoami}rc");

    for (@options) {
        return $_                   if -e $_;
        return $x                   if -e ($x=catfile($bindir,$_));
        return $x                   if -e ($x=catfile($ENV{HOME},$_));
        return "/etc/$_"            if -e "/etc/$_";
        return "/usr/local/etc/$_"  if -e "/usr/local/etc/$_";
    }
    return undef;
}

sub eval_perl   { do $_[0]; }
sub parse_xml   { return XMLin(shift); }
sub parse_ini   { tie my %ini, 'Config::IniFiles', (-file=>$_[0]); return \%ini; }
sub return_list { open my $fh, shift or die $!; return [<$fh>]; }

sub bind_style  { croak "BIND8-style config not supported in this release" }
sub irssi_style { croak "irssi-style config not supported in this release" }

# BUG: These functions are too similar. How can they be unified?

sub colon_sep {

    my $file = shift;
    open IN, $file or die $!;
    my %config;
    while (<IN>) {
        next if /^\s*#/;   
        /^\s*(.*?)\s*:\s*(.*)/ or next;
        my ($k, $v) = ($1, $2);
        my @v;
        if ($v =~ /:/) {
            @v =  split /:/, $v;
        } elsif ($v =~ /, /) { 
            @v = split /\s*,\s*/, $v;
        } elsif ($v =~ / /) {
            @v = split /\s+/, $v;
        } elsif ($v =~ /,/) { # Order is important
            @v = split /\s*,\s*/, $v;
        } else {
            @v = $v;
        }
        check_hash_and_assign(\%config, $k, @v);
    }
    return \%config;
}

sub check_hash_and_assign {
    my ($c, $k, @v) = @_;
    if (exists $c->{$k} and !ref $c->{$k}) {
        $c->{$k} = [$c->{$k}];
    }
    
    if (grep /=/, @v) { # Bugger, it's really a hash
        for (@v) {
            my ($subkey, $subvalue);
            if (/(.*)=(.*)/) { ($subkey, $subvalue) = ($1,$2); }
            else { $subkey = $1; $subvalue = 1; }

            if (exists $c->{$k} and ref $c->{$k} ne "HASH") { 
                # Can we find a hash in here?
                my $h=undef;
                for (@{$c->{$k}}) {
                    last if ref ($h = $_) eq "hash";
                }
                if ($h) { $h->{$subkey} = $subvalue; }
                else { push @{$c->{$k}}, { $subkey => $subvalue } }
            } else {
                $c->{$k}{$subkey} = $subvalue; 
            } 
        }
    } elsif (@v == 1) {
        if (exists $c->{$k}) { 
            if (ref $c->{$k} eq "HASH") { $c->{$k}{$v[0]} = 1; }
            else {push @{$c->{$k}}, @v}
        } else { $c->{$k} = $v[0]; }
    } else {
        if (exists $c->{$k}) { 
            if (ref $c->{$k} eq "HASH") { $c->{$k}{$_} = 1 for @v }
            else {push @{$c->{$k}}, @v }
        }
        else { $c->{$k} = [@v]; }
    }
}


sub equal_sep {
    my $file = shift;
    open IN, $file or die $!;
    my %config;
    while (<IN>) {
        next if /^\s*#/;
        /^\s*(.*?)\s*=\s*(.*)\s*$/ or next; 
        my ($k, $v) = ($1, $2);
        my @v;
        if ($v=~ /,/) {
            $config{$k} = [ split /\s*,\s*/, $v ];
        } elsif ($v =~ / /) { # XXX: Foo = "Bar baz"
            $config{$k} = [ split /\s+/, $v ];
        } else {
            $config{$k} = $v;
        }
    }
    
    return \%config;
}

sub space_sep {
    my $file = shift;
    open IN, $file or die $!;
    my %config;
    while (<IN>) {
        next if /^\s*#/;
        /\s*(\S+)\s+(.*)/ or next; 
        my ($k, $v) = ($1, $2);
        my @v;
        if ($v=~ /,/) {
            @v = split /\s*,\s*/, $v;
        } elsif ($v =~ / /) { # XXX: Foo = "Bar baz"
            @v = split /\s+/, $v;
        } else {
            @v = $v;
        }
        check_hash_and_assign(\%config, $k, @v);
    }
    return \%config;

}

1;
__END__
# Below is stub documentation for your module. You better edit it!

=head1 NAME

Config::Auto - Magical config file parser

=head1 SYNOPSIS

  use Config::Auto;

  # Not very magical at all.
  my $config = Config::Auto::parse("myprogram.conf", format => "colon");

  # Considerably more magical.
  my $config = Config::Auto::parse("myprogram.conf");

  # Highly magical.
  my $config = Config::Auto::parse();

=head1 DESCRIPTION

This module was written after having to write Yet Another Config File Parser
for some variety of colon-separated config. I decided "never again". 

When you call C<Config::Auto::parse> with no arguments, we first look at
C<$0> to determine the program's name. Let's assume that's C<snerk>. We
look for the following files:

    snerkconfig
    ~/snerkconfig
    /etc/snerkconfig
    /usr/local/etc/snerkconfig
    snerk.config
    ~/snerk.config
    /etc/snerk.config
    /usr/local/etc/snerk.config
    snerkrc
    ~/snerkrc
    /etc/snerkrc
    /usr/local/etc/snerkrc    
    .snerkrc
    ~/.snerkrc
    /etc/.snerkrc
    /usr/local/etc/.snerkrc
    
We take the first one we find, and examine it to determine what format
it's in. The algorithm used is a heuristic "which is a fancy way of
saying that it doesn't work." (Mark Dominus.) We know about colon
separated, space separated, equals separated, XML, Perl code, Windows
INI, BIND9 and irssi style config files. If it chooses the wrong one,
you can force it with the C<format> option.

If you don't want it ever to detect and execute config files which are made
up of Perl code, set C<$Config::Auto::DisablePerl = 1>.

Then the file is parsed and a data structure is returned. Since we're
working magic, we have to do the best we can under the circumstances -
"You rush a miracle man, you get rotten miracles." (Miracle Max) So
there are no guarantees about the structure that's returned. If you have
a fairly regular config file format, you'll get a regular data
structure back. If your config file is confusing, so will the return
structure be. Isn't life tragic?

Here's what we make of some common Unix config files:

F</etc/resolv.conf>:

    $VAR1 = {
          'nameserver' => [ '163.1.2.1', '129.67.1.1', '129.67.1.180' ],
          'search' => [ 'oucs.ox.ac.uk', 'ox.ac.uk' ]
        };

F</etc/passwd>:

    $VAR1 = {
          'root' => [ 'x', '0', '0', 'root', '/root', '/bin/bash' ],
          ...
        };

F</etc/gpm.conf>:

    $VAR1 = {
          'append' => '""',
          'responsiveness' => '',
          'device' => '/dev/psaux',
          'type' => 'ps2',
          'repeat_type' => 'ms3'
        };

F</etc/nsswitch.conf>:

    $VAR1 = {
          'netgroup' => 'nis',
          'passwd' => 'compat',
          'hosts' => [ 'files', 'dns' ],
          ...
    };

=head1 PARAMETERS

Although C<Config::Auto> is at its most magical when called with no parameters,
its behavior can be reigned in by use of one or two arguments.

If a filename is passed as the first argument to C<parse>, the same paths are
checked, but C<Config::Auto> will look for a file with the passed name instead
of the C<$0>-based names.

 use Config::Auto;

 my $config = Config::Auto::parse("obscure.conf");

The above call will cause C<Config::Auto> to look for:

 obscure.conf
 ~/obscure.conf
 /etc/obscure.conf

Parameters after the first are named, and the only recognize named parameter is
C<format>, which forces C<Config::Auto> to interpret the contents of the
configuration file in the given format without trying to guess.

=head1 TODO

BIND9 and irssi file format parsers currently don't exist. It would be
good to add support for C<mutt> and C<vim> style C<set>-based RCs.

=head1 AUTHOR

This module by Jos Boumans, C<kane@cpan.org>.

=head1 LICENSE

This module is
copyright (c) 2003 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=cut
