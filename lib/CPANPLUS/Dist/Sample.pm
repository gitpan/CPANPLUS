package CPANPLUS::Dist::Sample;

#######################################################################
###
### This is a sample module that you can use as a skeleton to create
### a custom distribution builder/installer.
###
### Every CPANPLUS::Dist::* module must provide a few required
### variables and functions, which are explained more in detail below.
### But as a short overview, you at least need the following variables:
###     @ISA                # inherit from CPANPLUS::Dist
###
### And you need these methods:
###     format_available    # a sanity check to see if we can use this
###                         # module
###     init                # init custom code, create accessors
###     create              # create a distribution
###     install             # install the created distribution
###
### To make this format active, you will need to add an entry to the
### CPANPLUS::Config. If you're creating this CPANPLUS::Dist::* module
### outside of CPANPLUS core (as a 3rd party), you will want to add a
### few lines like the following to your Makefile.pl:
###
###     my $cb = CPANPLUS::Backend->new;
###     $cb->configure_object->_add_dist('sample');
###     $cb->configure_object->_set_dist(
###             sample => 'CPANPLUS::Dist::Sample' );
###     $cb->configure_object->save;
###
### If you want to see more actual code for writing your own
### CPANPLUS::Dist::* module, take a look at the other modules in the
### same class. Especially CPANPLUS::Dist::Ports should be a good
### example.
###
######################################################################

use strict;
use vars    qw[@ISA];

### inherit from CPANPLUS::Dist ###
@ISA =      qw[CPANPLUS::Dist];

### to set up the include paths properly for bundled modules ###
use CPANPLUS::inc;

### for I18N ###
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';

### for error handling, which gets added to the error stack
### use as: error(loc("Something is wrong: %1", $error));
### or:     msg(loc("FYI: %1 and %2", $foo, $bar), $verbose);
use CPANPLUS::Error;

### common constants ###
use CPANPLUS::Internals::Constants;

### specific constants to this package
#use CPANPLUS::Internals::Constants::Sample;

### verbose errors on param checking ###
local $Params::Check::VERBOSE = 1;

### sub called to see if it is possible to create this type of dist
### on the environment we're running in. should warn about why this
### dist cannot be run on this environment. return true on possible,
### false otherwise.
sub format_available { 1; }

### sub called just after the CPANPLUS::Dist object is created, to
### initialize any custom code you might want to run at creation
### time. At this time you should at least create the required
### accessors you're going to use, like in the example below
sub init {
    my $dist    = shift;
    my $status  = $dist->status;

    ### minimally required accessors
    $status->mk_accessors(qw[created installed uninstalled]);

    ### more accessors as you may desire
    # ...

    ### other code here
    # ....

    return 'ALL OK' ? 1 : 0;
};


### actually create the dist target required.
### you will probably need to run 'perl Makefile.PL' or 'perl Build.PL'
### first to get a usable environment.
sub create {
    ### just in case you already did a create call for this module object
    ### just via a different dist object
    my $dist = shift;
    my $self = $dist->parent;
    $dist    = $self->status->dist   if      $self->status->dist;
    $self->status->dist( $dist )     unless  $self->status->dist;

    my $cb   = $self->parent;
    my $conf = $cb->configure_object;
    my %hash = @_;

    ### there's a good chance the module has only been extracted so far,
    ### so let's go and build it first
    {   my $builder = CPANPLUS::Dist->new(
                            module  => $self,
                            format  => $self->status->installer_type
                        );

        unless( $builder ) {
            error( loc( q[Could not create a dist for '%1' with ] .
                        q[installer type '%2'], $self->module,
                        $self->status->installer_type ) );
            $dist->status->created(0);
            return;
        }


        unless( $builder->create(%hash, prereq_format => 'SAMPLE' ) ) {
            $dist->status->created(0);
            return;
        }
    }

    ### other code here ###
    # ....

    return $dist->created( 'TRUE' ? 1 : 0 );

}


### takes care of the actual installation of the created dist
### you will need to require that 'create' has been run before
sub install {
    ### just in case you already did a create call for this module object
    ### just via a different dist object
    my $dist = shift;
    my $self = $dist->parent;
    $dist    = $self->status->dist   if      $self->status->dist;
    $self->status->dist( $dist )     unless  $self->status->dist;

    my $cb   = $self->parent;
    my $conf = $cb->configure_object;
    my %hash = @_;

    ### params::check template ###
    my $tmpl = {
        key => { default => '' },
    };

    check( $tmpl, \%hash ) or return;

    ### actual install code here....
    # ....

    return $dist->status->installed( 'TRUE' ? 1 : 0 );
}

1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:





