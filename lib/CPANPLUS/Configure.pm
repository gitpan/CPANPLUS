# $File: //member/autrijus/cpanplus/devel/lib/CPANPLUS/Configure.pm
# $Revision: #9 $ $Change: 3808 $ $DateTime: 2002/04/09 06:44:56 $

##################################################
###           CPANPLUS/Configure.pm            ###
###     Configuration structure for CPAN++     ###
##################################################

### Configure.pm ###

### CHANGE LOG ###
#
# 2001-09-28 jmb
# Changed AUTOLOAD'd get methods to accept list input.
# get_conf(qw[storable verbose]) will return both values as an array.
#
# 2001-10-02 jmb
# When returning @list in scalar context value was number of elements.
# Changed AUTOLOAD() to return only the first element in scalar context.
#
# 2001-10-02 jmb
# new() now also calls $self->load.
#
# 2001-10-02 jmb
# Added 'startdir' to _build subtype.
#
# 2001-10-09 jmb
# Added some missing subtypes.
# Fixed AUTOLOAD of DESTROY (added DESTROY sub).
# Got rid of warnings from AUTOLOAD (predefined $private).
# Moved Data::Dumper and FileHandle to main package (were only in _save_pm).
# Added 'hosts' to @types and started on get/set methods for it.
#
# 2001-10-12 jmb
# For now just put hosts in _ftp (as 'urilist').
# Added 'hosts' subtype to _source - location of 'MIRRORED.BY'.
# Had to add all the programs from Setup so that _set_ftp() would work!
#
# 2001-10-31 jmb
# Added dslip and sdslip to _source
#
# 2001-11-07 jmb
# Added ncftp and wget to _build
#

package CPANPLUS::Configure;

use strict;

use CPANPLUS::Config;
use CPANPLUS::Configure::Setup;
use CPANPLUS::Error;

use Data::Dumper;
use Exporter;
use FileHandle ();

use vars qw/$AUTOLOAD/;

my $conf = {};

## list of valid major types
my @types = qw(
    conf
    _build
    _ftp
    _source
);

## valid subtypes - must add anything new for Config.pm here
my %subtypes = (
    conf    => [ qw(cpantest debug flush force lib makeflags makemakerflags md5 prereqs shell storable verbose) ],
    _build  => [ qw(ftp gzip lynx make ncftp ncftpget pager shell tar unzip wget autdir base moddir startdir targetdir) ],
    _ftp    => [ qw(auth base dslip email mod passive proto source urilist) ],
    _source => [ qw(auth dslip hosts mod sauth sdslip smod update) ],
);


################################################################################
##
##  under construction :o)
##

## create a Configure object
## if passed a hash then we assume they are override options
##
## (takes optional hash argument, returns Configure object)
##
sub new {
    my $class = shift;
    my %args;

    %args = @_ unless scalar(@_) % 2;

    my $self = bless {}, $class;

    $self->load(options => { %args });
    #$self->{conf} = $conf;

    $self->{_error} ||= CPANPLUS::Error->new(
        message_level   => (
            defined $self->{options}{'debug'}
                ? $self->{options}{'debug'}
                : 1
        ),
        error_level     => 2,
        error_track     => 1,
    );

    return $self;

} #new


################################################################################
##
##  AUTOLOAD'ed get/set methods
##

#sub AUTOLOAD {
#    my ($self, $value) = @_;
#    my ($field) = $AUTOLOAD =~ /.*::(.*)$/;
#    return if $field eq 'DESTROY';
#    return @_==1 ? $self->{$field} : $self->{$field} = $value;
#}

## AUTOLOAD, what can I say?
##
## This expects to see a method call of get_ or set_ (with or without a
## preceding '_', depending on the type you are after) followed by an
## appropriate type.  Ie. '_get_build'.
##
## On a get_ call, with no args the entire type hash is returned, otherwise
## valid args result in only returning the subtype(s) asked for.
##
## A set_ call expects one or more valid subtypes and the values to set them to.
## The set_ is aborted if even one subtype is invalid, and NO values are
## changed.  (Returns 1 on success.)
##
## Both get_ and set_ return 0 on failure, as will any invalid calls.
##
## (takes scalar, array, or hash arguments, returns scalar or array)
##
sub AUTOLOAD {
    my $self = shift;

    #print "AUTOLOAD: $AUTOLOAD\n";

    ## fancy AUTOLOAD magic
    my $name = $AUTOLOAD;
    $name =~ s/.*://; # strip fully-qualified portion

    ## split out action (get/set) and field (in @types) we are after
    my ($private, $action, $field) = $name =~ m/^(_)?([gs]et)_([a-z]+)$/;

    ### we have to have my $type first to make sure the grep doesn't fail! -kane
    my $type = '';
    $type  = $private, if $private;
    $type .= $field,   if $field;
    #print "$type, $action\n";

    ## we don't work with invalid types
    return 0, unless grep {/^$type$/} @types;

    #return $self->hosts([@_]), if $type eq 'hosts';

    if ($action eq 'get') {
        #my $key = shift;
        my $keys = [@_];

        #if (defined $key) {
        if (defined $keys) {
            my @list;
            map { push @list, $conf->{$type}->{$_} } @{$keys};
            #return $conf->{$type}->{$key};
            #return @list;
            # in scalar context the above gives number of elements
            # not what I wanted -jmb
            return (wantarray) ? @list : $list[0];
        } else {
            return %{$conf->{$type}};
        } #if

    } elsif ($action eq 'set') {
        my $args  = {@_};
        my $types = join ':', @{$subtypes{$type}};

        ## if even one arg type is invalid, we abort
        map { return 0, unless $types =~ m/^$_:|:$_:|:$_$/ } keys %{$args};

        ## load up the passed settings
        map { $conf->{$type}->{$_} = $args->{$_} } keys %{$args};

        return 1; # if we got this far we succeeded

    } #if

    return 0; # must have failed - but I hate defaults

} #AUTOLOAD


## just here to keep AUTOLOAD from being called incorrectly
##
## (takes no arguments, returns no values)
##
sub DESTROY { 1; }


################################################################################
##
##  file methods - load and save config data
##

## load up Config.pm
## If passed valid args they will override Config.pm settings.
## Args are passed in a hash called 'options':
##     options => {
##                    conf => {
##                                debug   => 0,
##                                verbose => 1
##                            },
##                    _build => {
##                                  make => 'nmake'
##                              }
##                }
##
## Additionally, if _build => make is undefined or blank, the Setup routine
## will be invoked.
##
## (takes optional hash argument, returns no values)
##
sub load {
    my $self = shift;
    my %args = @_;

    ### initialize
    $conf = new CPANPLUS::Config;

    ### load user invocation options
    $self->_load_args($args{options}) if $args{options};

    CPANPLUS::Configure::Setup->init(conf => $self), unless $self->_get_build('make');

    #$self->get_user_config;

} #load


## load passed in args overtop of Config.pm defaults
## $options is a hashref of the values you want to replace
## (see comments for load)
##
## (takes hashref argument, returns no values)
##
sub _load_args {
    my $self    = shift;
    my $options = shift;

    for my $option (keys %{$options}) {
        (my $method = $option) =~ s/^(_)?/$1set_/; # translate to calling syntax
        $self->$method(%{$options->{$option}});
    }

} #_load_args


## ultimately this will allow multiple methods of saving,
## but for now it just calls _save_pm
##
## (takes no arguments, returns no values)
##
sub save {
    shift->_save_pm;
    #my $self   = shift;
    #my ($conf) = @_;

} #save


## generate a new Config.pm file and save it (after backing up the old)
##
## (takes no arguments, returns no values)
##
sub _save_pm {
    my $self = shift;
    my $err  = $self->{_error} ||= CPANPLUS::Error->new(
        error_level => 1,
    );

    ## ultimately $file should be passed in or divined from Config.pm
    my $file = $INC{'CPANPLUS/Config.pm'};
    chmod 0644, $file;

    my $mode;
    if (-f $file) {
        $mode = (stat _)[2]; ## do we really need all this?
        if ($mode && ! -w _) {
            $err->trap(error => "$file is not writable");
        } #if
    } #if

    my $time = gmtime;
    my $data = Data::Dumper->Dump([$conf], ['conf']);

    ## get rid of the bless'ing
    $data =~ s/=\s*bless\s*\(\s*\{/= {/;
    $data =~ s/\s*},\s*'[A-Za-z0-9:]+'\s*\);/\n    };/;

    my $msg = <<_END_OF_CONFIG_;
############################################
###         CPANPLUS::Config.pm          ###
###  Configuration structure for CPAN++  ###
############################################

#last changed: $time GMT

package CPANPLUS::Config;

use strict;

sub new {
    my \$class = shift;

    my $data
    bless(\$conf, \$class);
    return \$conf;

} #new


1;

__END__
_END_OF_CONFIG_

    rename $file, "$file~", if -f _;

    my $fh = FileHandle->new;
    $fh->open(">$file")
        or $err->trap(error => "Couldn't open >$file: $!");
    $fh->print($msg);
    $fh->close;

} #_save_pm


## get a dump of the $conf object, for debugging
##
## (takes no arguments, returns scalar)
##
sub _dump {
    #my $self = shift;
    return Data::Dumper->Dump([$conf], ['conf']);
    #return $data;
    #return Dumper(shift);

} #_dump;


## allow external programs read access to @types
## use this if you need to know what 'types' are valid
##
## (takes no arguments, returns array)
##
sub types {
    my $self = shift;
    return @types;
} #types


## allow external programs read access to @subtypes of given $type
## use this if you need to know what 'subtypes' are valid for 'type'
##
## (takes scalar argument, returns array)
##
sub subtypes {
    my $self = shift;
    my $type = shift;

    return @{ $subtypes{$type} } if grep { m/^$type$/ } @types;

} #types


1;
__END__

=pod

=head1 NAME

CPANPLUS::Configure - Configuration interface for CPAN++

=head1 SYNOPSIS

    use CPANPLUS::Configure;

    my $conf = new CPANPLUS::Configure;

    my @conf_options = $conf->subtypes('conf');

    $conf->load('options' => {'conf' => {'md5' => 1, 'flush' => 0}});

    my $_md5_setting = $conf->get_md5();
    $conf->set_debug(0); 

    print $conf->dump();

    $conf->save();

=head1 DESCRIPTION

CPANPLUS::Configure can be used to view and manipulate configuration
settings for CPANPLUS.

=head1 METHODS

=head2 new(conf => {CONFIGURATION});

The constructor will make a Config object.  It will attempt to use a
saved Config.pm if it exists.  Arguments for 'conf' can be specified
to replace those in the default Config for this object.  The possible
options are specified in set_conf().

If no Config.pm is found, or it is corrupt, you will be bumped to
CPANPLUS::Configure::Setup to create one.

=head2 load(options => {OPTIONS});

Load is almost like the constructor, except that it takes a hash
called 'options' which can contain keys such as 'conf'.  Valid
arguments which are passed will override Config settings. 

=head2 save();

The save() function saves the Configure object to Config.pm,
which is the default configuration for all CPANPLUS operations.

=head2 @subtypes = subtypes('conf');

This method will return a list of the subtypes of 'conf', which is
the only public type.  Every subtype in the array can be used as
an argument in get_conf() and set_conf().

=head2 get_conf(SUBTYPE);

This function can be used to see the configuration setting of 
the named subtype.  

Available subtypes are listed in set_conf().

=head2 set_conf(SUBTYPE => SETTING);

This method can be used to set any of the subtypes to new settings.

=over 4

=item * C<cpantest>

This is a boolean value; a true value enables prompting user to
send test report to cpan-testers after each 'make test'.

=item * C<debug>

This is a boolean value; a true value enables debugging mode and overrides
verbosity settings.

=item * C<flush>

This is a boolean value; a true value means that the cache will be 
automatically flushed.

=item * C<force>

This is a boolean value.  A true setting means that CPANPLUS will
attempt to install modules even if they fail 'make test.'  It will
also force re-fetching of modules which have already been downloaded.

=item * C<lib>

This is an array reference.  It is analogous to 'use lib' for the
paths specified.  In scalar context, get_conf('lib') will return
the first element in the array; in list context it will return the
entire array.

=item * C<makeflags>

This is a scalar value.  The flags named in the string are added to the
make command.

=item * C<prereqs>

This argument relates to the treatment of prerequisite modules and
has a value of 0, 1 or 2.  A 0 indicates that prerequisites are
disallowed, a 1 enables automatic prerequisite installation, and
a 2 prompts for each prerequisite.

=item * C<storable>

This is a boolean value.  A true setting allows the use of Storable.

=item * C<verbose>

This is a boolean value.  A true setting enables verbose mode.

=item * C<md5>

This is a boolean value.  A true setting enables md5 checks.

=item * C<makemakerflags>

This is a hash reference.  Keys are flags to be added to the
'perl Makefile.PL' command and values are the settings the
flags should be set to.

=item * C<shell>

This is a scalar.  It is the name of the default CPANPLUS shell.

=back

=head1 AUTHORS

This module by
Joshua Boschert E<lt>jambe@cpan.orgE<gt>.

This pod text by Ann Barcomb E<lt>kudra@cpan.orgE<gt>.

=head1 COPYRIGHT

The CPAN++ interface (of which this module is a part of) is
copyright (c) 2001-2002 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=head1 SEE ALSO

L<CPANPLUS::Configure::Setup>

=cut
