package CPANPLUS::Configure;
use strict;

use CPANPLUS::inc;
use CPANPLUS::Internals::Constants;
use CPANPLUS::Error;

use Log::Message;
use Module::Load                qw[load];
use Params::Check               qw[check];
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';

use vars                        qw[$AUTOLOAD $VERSION $MIN_CONFIG_VERSION];

local $Params::Check::VERBOSE = 1;

### require, avoid circular use ###
require CPANPLUS::Internals;
$VERSION = $CPANPLUS::Internals::VERSION = $CPANPLUS::Internals::VERSION;

### The minimum required config version
### Update this if we have incompatible config changes
#$MIN_CONFIG_VERSION = $VERSION;
$MIN_CONFIG_VERSION = '0.050_04';


=pod

=head1 NAME

CPANPLUS::Configure

=head1 SYNOPSIS

    $conf   = CPANPLUS::Configure->new( options => { ... } );

    $bool   = $conf->can_save;
    $bool   = $conf->save( $where );

    @opts   = $conf->options( $type );

    $make       = $conf->get_program('make');
    $verbose    = $conf->set_conf( verbose => 1 );

=head1 DESCRIPTION

This module deals with all the configuration issues for CPANPLUS.
Users can use objects created by this module to alter the behaviour
of CPANPLUS.

Please refer to the C<CPANPLUS::Backend> documentation on how to
obtain a C<CPANPLUS::Configure> object.

=head1 METHODS

=head2 new( [options => HASHREF] )

This method returns a new object. Normal users will never need to
invoke the C<new> method, but instead retrieve the desired object via
a method call on a C<CPANPLUS::Backend> object.

=cut

sub new {
    my $class = shift;
    my %hash  = @_;

    ### ok, we need to find your config now ###
    $class->_load_cpanplus_config() or return;

    ### minimum version requirement.
    ### this code may change between releases, depending on
    ### compatibillity with previous versions.
    unless( $class->_config_version_sufficient ) {
        cp_error(loc(  "Your config is of version '%1' but '%2' requires ".
                    "a config of '%3' or higher. Your '%4' is of " .
                    "version '%5', but your config requires a version ".
                    "of '%6' or higher. You will need to reconfigure",
                    $CPANPLUS::Config::VERSION, 'CPANPLUS',
                    $MIN_CONFIG_VERSION, 'CPANPLUS', $VERSION,
                    ($CPANPLUS::Config::MIN_CPANPLUS_VERSION || 0) ));
        return;
    }

    my $self = bless {
                    _conf   => CPANPLUS::Config->new(),
                    _error  => Log::Message->new(),
                }, $class;

    unless( $self->_load_args( options => \%hash ) ) {
        cp_error(loc(qq[Unable to initialize configuration!]));
        return;
    }

    return $self;
}


### allow loading of an alternate configuration file ###
sub _load_cpanplus_config {
    my $class = shift;

    ### apparently we loaded it already ###
    return 1 if $INC{'CPANPLUS/Config.pm'};

    my $tried;
    my $env = ENV_CPANPLUS_CONFIG;

    ### check it has length, and is an actual file ###
    if ( defined $ENV{$env} and length $ENV{$env} and
        -f $ENV{$env} and -s _
    ) {
        eval{ load $ENV{$env} };
        $tried++;
        $INC{'CPANPLUS/Config.pm'} = $ENV{$env} unless $@;
    }

    my $ok;
    $@
        ? cp_error( loc("Could not load your personal config: %1: %2",
                    $ENV{$env}, "$@"), "\n",
                loc("Falling back to system-wide config."), "\n" )
        : ($ok = 1) if $tried;

    unless($ok) {
        eval { load CPANPLUS::Config };
        cp_error("$@"), return if $@;
    }

    return 1;
}

### this code may change between releases, depending on backwards
### compatibility between configs.
### if this is returning false, you can also not just use your
### old config as base for your new config -- sorry :(
sub _config_version_sufficient {

    my $fail;

    ### first check if the config is good enough for this version of CPANPLUS
    CONFIG: {
        ### If they're the same, we're done already.
        last CONFIG if $CPANPLUS::Config::VERSION eq $VERSION;

        ### Split the version numbers into a major part and a devel part.
        my $config_version = $CPANPLUS::Config::VERSION;
        $config_version =~ s/_(\d+)$//;
        my $config_devel = $1 || 0;

        my $version = $MIN_CONFIG_VERSION;
        $version =~ s/_(\d+)$//;
        my $devel = $1 || 0;

        ### If the configuration has a newer major version than us,
        ### it's sufficient.
        last CONFIG if $config_version > $version;

        ### If the configuration has the same major version and a newer devel
        ### version than us, it's sufficient.
        last CONFIG if $config_version == $version && $config_devel >= $devel;

        ### ok, the versions are no good, it's WRONG
        $fail++

    }

    ### now check if CPANPLUS is good enough for the config we've loaded
    CPANPLUS: {
        ### we know it failed already...
        last CPANPLUS if $fail;

        ### no minversion specified? that's also too old
        ++$fail && last CPANPLUS 
            unless $CPANPLUS::Config::MIN_CPANPLUS_VERSION;;

        ### If they're the same, we're done already.
        last CPANPLUS if $CPANPLUS::Config::VERSION eq $VERSION;

        ### Split the version numbers into a major part and a devel part.
        my $cp_version = $VERSION;
        $cp_version =~ s/_(\d+)$//;
        my $cp_devel = $1 || 0;

        my $version = $CPANPLUS::Config::MIN_CPANPLUS_VERSION;
        $version =~ s/_(\d+)$//;
        my $devel = $1 || 0;

        ### If cpanplus has a newer major version than what we minimally
        ### require, it's enough
        last CPANPLUS if $cp_version > $version;

        ### If cpanplus has the same major version and a newer devel
        ### version than what we minimally require, it's enough
        last CPANPLUS if $cp_version == $version && $cp_devel >= $devel;

        ### ok, the versions are no good, it's WRONG
        $fail++
    }

    ### Otherwise, the configuration does not have a newer version than us;
    ### it's insufficient.
    return if $fail;

    return 1;
}



=pod

=head2 can_save( [$config_location] )

Check if we can save the configuration to the specified file.
If no file is provided, defaults to your personal config, or
failing that, C<$INC{'CPANPLUS/Config.pm'}>.

Returns true if the file can be saved, false otherwise.

=cut

sub can_save {
    my $self = shift;
    my $env  = ENV_CPANPLUS_CONFIG;
    my $file = shift || $ENV{$env} || $INC{'CPANPLUS/Config.pm'};
    return 1 unless -e $file;

    chmod 0644, $file;
    return (-w $file);
}

=pod

=head2 save( [$config_location] )

Saves the configuration to the location you provided.
If no file is provided, defaults to your personal config, or
failing that, C<$INC{'CPANPLUS/Config.pm'}>.

Returns true if the file was saved, false otherwise.

=cut

sub save {
    my $self = shift;
    my $env  = ENV_CPANPLUS_CONFIG;
    my $file = shift || $ENV{$env} || $INC{'CPANPLUS/Config.pm'};

    return unless $self->can_save($file);

    my $time = gmtime;

    load Data::Dumper;
    local $Data::Dumper::Sortkeys = 1; 
    
    my $data = Data::Dumper->Dump([$self->conf], ['conf']);

    ## get rid of the bless'ing
    $data =~ s/=\s*bless\s*\(\s*\{/= {/;
    $data =~ s/\s*},\s*'[A-Za-z0-9:]+'\s*\);/\n    };/;

    ### use a variable to make sure the pod parser doesn't snag it
    my $is = '=';

    my $msg = <<_END_OF_CONFIG_;
###############################################
###           CPANPLUS::Config              ###
###  Configuration structure for CPANPLUS   ###
###############################################

#last changed: $time GMT

### minimal pod, so you can find it with perldoc -l, etc
${is}pod

${is}head1 NAME

CPANPLUS::Config

${is}head1 DESCRIPTION

This is your CPANPLUS configuration file. Editing this
config changes the way CPANPLUS will behave

${is}cut

package CPANPLUS::Config;

\$VERSION = "$MIN_CONFIG_VERSION";

\$MIN_CPANPLUS_VERSION = "$CPANPLUS::Config::MIN_CPANPLUS_VERSION";

use strict;

sub new {
    my \$class = shift;

    my $data
    bless(\$conf, \$class);
    return \$conf;

} #new


1;

_END_OF_CONFIG_

    ### make a backup ###
    rename $file, "$file~", if -f $file;

    my $fh = new FileHandle;
    $fh->open(">$file")
        or (cp_error(loc("Could not open '%1' for writing: %2", $file, $!)),
            return );

    $fh->print($msg);
    $fh->close;

    return 1;
}

=pod

=head2 conf()

Return the C<CPANPLUS::Config> object.  For internal use only.

=cut

sub conf {
    my $self = shift;
    $self->{_conf} = shift if $_[0];
    return $self->{_conf};
}

=pod

=head2 _load_args( [options => HASHREF] );

Called by C<new> to do the actual altering of options.

Returns true on success, false on failure.

=cut

sub _load_args {
    my $self = shift;
    my %hash = @_;

    my $opts;
    my $tmpl = {
        options => { default => {}, strict_type => 1, store => \$opts },
    };

    my $args = check( $tmpl, \%hash ) or return;

    for my $option ( keys %$opts ) {

        # translate to calling syntax
        my $method;
        if( $option =~ /^_/) {
            ($method = $option) =~ s/^(_)?/$1set_/;
        } else {
            $method = 'set_' . $option;
        }

        $self->$method( %{$opts->{$option}} );
    }

    ### XXX return values?? where does this GO? ###
    #CPANPLUS::Configure->Setup->init( conf => $self )
    #    unless $self->_get_build('make');

    return 1;
}

=pod

=head2 options( type => TYPE )

Returns a list of all valid config options given a specific type
(like for example C<conf> of C<program>) or false if the type does
not exist

=cut

sub options {
    my $self = shift;
    my $conf = $self->conf;
    my %hash = @_;

    my $type;
    my $tmpl = {
        type    => { required       => 1, default   => '',
                     strict_type    => 1, store     => \$type },
    };

    check($tmpl, \%hash) or return;

    return sort keys %{$conf->{$type}} if $conf->{$type};
    return;
}

=pod

=head1 ACCESSORS

Accessors that start with a C<_> are marked private -- regular users
should never need to use these.

=head2 get_SOMETHING( ITEM, [ITEM, ITEM, ... ] );

The C<get_*> style accessors merely retrieves one or more desired
config options.

=head2 set_SOMETHING( ITEM => VAL, [ITEM => VAL, ITEM => VAL, ... ] );

The C<set_*> style accessors set the current value for one
or more config options and will return true upon success, false on
failure.

=head2 add_SOMETHING( ITEM => VAL, [ITEM => VAL, ITEM => VAL, ... ] );

The C<add_*> style accessor adds a new key to a config key.

Currently, the following accessors exist:

=over 4

=item set|get_conf

Simple configuration directives like verbosity and favourite shell.

=item set|get_program

Location of helper programs.

=item _set|_get_build

Locations of where to put what files for CPANPLUS.

=item _set|_get_source

Locations and names of source files locally.

=item _set|_get_mirror

Locations and names of source files remotely.

=item _set|_get_dist

Mapping of distribution format names to modules.

=item _set|_get_fetch

Special settings pertaining to the fetching of files.

=item _set|_get_daemon

Settings for C<cpanpd>, the CPANPLUS daemon.

=back

=cut

sub AUTOLOAD {
    my $self = shift;
    my $conf = $self->conf;

    unless( scalar @_ ) {
        cp_error( loc("No arguments provided!") );
        return;
    }

    my $name = $AUTOLOAD;
    $name =~ s/.+:://;

    my ($private, $action, $field) =
                $name =~ m/^(_)?((?:[gs]et|add))_([a-z]+)$/;

    my $type = '';
    $type .= '_'    if $private;
    $type .= $field if $field;

    unless ( exists $conf->{$type} ) {
        cp_error( loc("Invalid method type: '%1'", $name) );
        return;
    }

    ### retrieve a current value for an existing key ###
    if( $action eq 'get' ) {
        for my $key (@_) {
            my @list = ();

            if( exists $conf->{$type}->{$key} ) {
                push @list, $conf->{$type}->{$key};

            ### XXX EU::AI compatibility hack to provide lookups like in
            ### cpanplus 0.04x; we renamed ->_get_build('base') to
            ### ->get_conf('base')
            } elsif ( $type eq '_build' and $key eq 'base' ) {
                return $self->get_conf($key);  
                
            } else {     
                cp_error( loc(q[No such key '%1' in field '%2'], $key, $type) );
                return;
            }

            return wantarray ? @list : $list[0];
        }

    ### set an existing key to a new value ###
    } elsif ( $action eq 'set' ) {
        my %args = @_;

        while( my($key,$val) = each %args ) {

            if( exists $conf->{$type}->{$key} ) {
                $conf->{$type}->{$key} = $val;

            } else {
                cp_error( loc(q[No such key '%1' in field '%2'], $key, $type) );
                return;
            }
        }

        return 1;

    ### add a new key to the config ###
    } elsif ( $action eq 'add' ) {
        my %args = @_;

        while( my($key,$val) = each %args ) {

            if( exists $conf->{$type}->{$key} ) {
                cp_error( loc( q[Key '%1' already exists for field '%2'],
                            $key, $type));
                return;
            } else {
                $conf->{$type}->{$key} = $val;
            }
        }
        return 1;
    } else {

        cp_error( loc(q[Unknown action '%1'], $action) );
        return;
    }
}

sub DESTROY { 1 };

1;

=pod

=head1 AUTHOR

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001, 2002, 2003, 2004, Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=head1 SEE ALSO

L<CPANPLUS::Backend>, L<CPANPLUS::Configure::Setup>

=cut

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:

