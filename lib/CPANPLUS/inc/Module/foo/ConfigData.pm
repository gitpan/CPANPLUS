package Module::Build::ConfigData;
use strict;
my $arrayref = eval do {local $/; <DATA>}
  or die "Couldn't load ConfigData data: $@";
close DATA;
my ($config, $features) = @$arrayref;

sub config { $config->{$_[1]} }
sub feature { $features->{$_[1]} }

sub set_config { $config->{$_[1]} = $_[2] }
sub set_feature { $features->{$_[1]} = 0+!!$_[2] }

sub feature_names { keys %$features }
sub config_names  { keys %$config }

sub write {
  my $me = __FILE__;
  require IO::File;
  require Data::Dumper;

  my $mode_orig = (stat $me)[2] & 07777;
  chmod($mode_orig | 0222, $me); # Make it writeable
  my $fh = IO::File->new($me, 'r+') or die "Can't rewrite $me: $!";
  seek($fh, 0, 0);
  while (<$fh>) {
    last if /^__DATA__$/;
  }
  die "Couldn't find __DATA__ token in $me" if eof($fh);

  local $Data::Dumper::Terse = 1;
  seek($fh, tell($fh), 0);
  $fh->print( Data::Dumper::Dumper([$config, $features]) );
  truncate($fh, tell($fh));
  $fh->close;

  chmod($mode_orig, $me)
    or warn "Couldn't restore permissions on $me: $!";
}


=head1 NAME

Module::Build::ConfigData - Configuration for Module::Build

=head1 SYNOPSIS

  use Module::Build::ConfigData;
  $value = Module::Build::ConfigData->config('foo');
  $value = Module::Build::ConfigData->feature('bar');
  
  @names = Module::Build::ConfigData->config_names;
  @names = Module::Build::ConfigData->feature_names;
  
  Module::Build::ConfigData->set_config(foo => $new_value);
  Module::Build::ConfigData->set_feature(bar => $new_value);
  Module::Build::ConfigData->write;  # Save changes

=head1 DESCRIPTION

This module holds the configuration data for the C<Module::Build>
module.  It also provides a programmatic interface for getting or
setting that configuration data.  Note that in order to actually make
changes, you'll have to have write access to the C<Module::Build::ConfigData>
module, and you should attempt to understand the repercussions of your
actions.

=head1 METHODS

=over 4

=item config($name)

Given a string argument, returns the value of the configuration item
by that name, or C<undef> if no such item exists.

=item feature($name)

Given a string argument, returns the value of the feature by that
name, or C<undef> if no such feature exists.

=item set_config($name, $value)

Sets the configuration item with the given name to the given value.
The value may be any Perl scalar that will serialize correctly using
C<Data::Dumper>.  This includes references, objects (usually), and
complex data structures.  It probably does not include transient
things like filehandles or sockets.

=item set_feature($name, $value)

Sets the feature with the given name to the given boolean value.  The
value will be converted to 0 or 1 automatically.

=item config_names()

Returns a list of all the names of config items currently defined in
C<Module::Build::ConfigData>, or in scalar context the number of items.

=item feature_names()

Returns a list of all the names of features currently defined in
C<Module::Build::ConfigData>, or in scalar context the number of features.

=item write()

Commits any changes from C<set_config()> and C<set_feature()> to disk.
Requires write access to the C<Module::Build::ConfigData> module.

=back

=head1 AUTHOR

C<Module::Build::ConfigData> was automatically created using C<Module::Build>.
C<Module::Build> was written by Ken Williams, but he holds no
authorship claim or copyright claim to the contents of C<Module::Build::ConfigData>.

=cut

__DATA__

[
          {},
          {
            'YAML_support' => 1
          }
        ]
