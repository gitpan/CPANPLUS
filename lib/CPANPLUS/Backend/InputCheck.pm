# $File: //depot/cpanplus/dist/lib/CPANPLUS/Backend/InputCheck.pm $
# $Revision: #1 $ $Change: 1913 $ $DateTime: 2002/11/04 12:35:28 $

#######################################################
###           CPANPLUS/Backend/InputCheck.pm        ###
### Utility functions to validate inputs to Backend ###
###         Written 17-08-2001 by Jos Boumans       ###
#######################################################

package CPANPLUS::Backend::InputCheck;

use strict;

use Carp;
use CPANPLUS::I18N;
use CPANPLUS::Configure;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( CPANPLUS::Internals Exporter );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

### input checks ###
{
    ### scoped variables for the input check methods ###
    my ($data, $args);


    # Return 1 if the specified key is part of %_data; 0 otherwise
    sub _is_ok{
        my $self    = shift;
        $data       = shift;
        my $href    = shift;

        #print Dumper $data, $href;

        my $err = $self->{_error};
        my $verbose = $self->{_conf}->get_conf( 'verbose' );

        #%$args = map { my $k = lc $_; $k, $href->{$_} } keys %$href;
        # same thing, but no temp needed -jmb
        %$args = map { lc, $href->{$_} } keys %$href;

        ### check if the required keys have been entered ###
        my $flag;
        for my $key ( %$data ) {

            ### check if the key is required and whether or not it was supplied
            my $rv = $self->_hasreq( $key );

            unless ( $rv ) {
                $err->trap(
                    error => loc("Required option '%1' is not provided for %2", $key, (caller(1))[3]),
                );
                $flag = 1;
            }
        }

        ### if $flag is set, at least one required option wasn't passed, and we return 0
        return 0 if $flag;

        ### set defaults for all arguments ###
        my ($defs) = $self->_hashdefs();

        ### check if all keys are valid ###
        for my $key ( keys %$args ) {

            my $rv = $self->_iskey( $key );


            ### if the key exists, override the default with the provided value ###
            if ( $rv ) {

                ### this is NOT quite working... trying to check if both data types
                ### are of the same ref. but it's screwing up =/

                #print qq(ref $defs->{$key} eq ref $args->{$key});
                #if ( ref $defs->{$key} eq ref $args->{$key} ) {

                if(1){
                    $defs->{$key} = $args->{$key};
                } else {
                    $err->inform(
                        msg     => loc("'%1' is not of a valid type for %2, using default instead!", $key, (caller(1))[3]),
                        quiet   => !$verbose,
                    );
                }

            ### no $rv, means $key isn't a valid option. we just inform for this
            } else {
                $err->inform(
                    msg     => loc("'%1' is not a valid option for %2", $key, (caller(1))[3]),
                    quiet   => !$verbose,
                );
            }
        }

        ### return the 'updated' $args
        return $defs;
    }


    ### check if the key exists in $data ###
    sub _iskey {
        my ($self, $key) = @_;

        return 0 unless ($self->_okcaller());

        return 1 if $data->{$key};

        return 0;
    }


    ### check if the $key is required, and if so, whether it's in $args ###
    sub _hasreq {
        my ($self, $key) = @_;
        my $reqs = $self->_listreqs();
        my $err  = $self->{_error};


        return 0 unless ($self->_okcaller());

        if ( $reqs->{$key} ) {
            return exists $args->{$key} ? 1 : 0;
        } else {
            return 1;
        }
    }


    # Return a hash ref of $_data keys with required values
    sub _listreqs {
        my %hash = map { $_ => 1 } grep { $data->{$_}->{required} } keys %$data;
        return \%hash;
    }


    # Return a hash of $data keys with default values => defaults
    sub _hashdefs {
        my %hash = map {
            $_ => $data->{$_}->{default}
        } grep {
            $data->{$_}->{default}
        } keys %$data ;

        return \%hash;
    }


    sub _okcaller {
        my $self = shift;
        my $err  = $self->{_error};

        my $package = __PACKAGE__;
        my $caller = (caller(2))[3];

        # Couldn't get a caller
        unless ( $caller ) {
            $err->trap( error => loc("Unable to identify caller"));
            return 0;
        }

        # Caller is part of current package
        return 1 if ($caller =~ /^$package/);

        # Caller is not part of current package
        $err->trap( error => loc("Direct access to private method %1 is forbidden", (caller(1))[3]) );

        return 0;
    }
}


### input check, mainly used by 'search' ###
sub _check_input {
    my $self = shift;
    my %args = @_;

    ### check if we're searching for some valid key ###
    for( keys %{$self->module_tree->{ (each %{$self->module_tree})[0] }} ) {
        if ( $_ eq $args{'type'} ) { return 1 }
    }

    return 0;
}

1;
