###########################################################
###             CPANPLUS/Backend/RV.pm                  ###
###  Module to provide a return value class for CPAN++  ###
###         Written 07-05-2001 by Jos Boumans           ###
###########################################################

package CPANPLUS::Backend::RV;

use strict;

### make it easier to check if($rv) { foo() }
### this allows people to not have to explicitly say
### if( $rv->ok ) { foo() }
use overload bool => \&ok, fallback => 1;

use CPANPLUS::I18N;
use Data::Dumper;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION $AUTOLOAD);
    @ISA        =   qw( Exporter );
    $VERSION    =   $CPANPLUS::Backend::VERSION;
}

### this class is written after a talk with acme and sky about return values:
### <acme> so you know which steps to check (and to ignore the magical prereq and dir)
### <kane> ah, like an array ref of steps we DID you mean?
### <kane> steps = [makefile make install] # to indicate we skipped test
###
### and the conclusion from my talk with sky:
### <kane>ok, so a class for the rv to be blessed in, with easy methods to tell
### you summaries about the command in BOOL form

my $Class = 'CPANPLUS::Backend';

sub new {
    my $class   = shift;
    my %hash    = @_;

    my $obj = $hash{object} or return 0;
    my $err = $obj->error_object;

    ### doesn't actually need to go in our new object ###
    delete $hash{object};

    my $_data = {
        args    => { required => 1, default => {} },
        rv      => { required => 1, default => {} },
        type    => { required => 1, default => '' },
        ok      => { required => 1, default => '' },
    };


    ### Input Check ###
    my $args = $obj->_is_ok( $_data, \%hash );

    unless( $args ) {
        $err->trap( error => loc("Error validating input to 'CPANPLUS::Backend::RV'") );
        return 0;
    }

    return bless { %$args, _id => $obj->{_id} }, $class;
}

sub ok      { return shift->{ok}    }
sub rv      { return shift->{rv}    }
sub args    { return shift->{args}  }
sub type    { return shift->{type}  }

### make a new backend object for us to use ###
sub _make_object {
    my $self = shift;

    my $obj = CPANPLUS::Internals->_retrieve_id( $self->{_id} );

    return bless $obj, $Class;
}

### experimental AUTOLOAD:
### should return a map of the requested key and their RV.
### example:
### below is a dumper of the following command:
### my $rv = $cb->install( modules => [qw[UNIVERSAL::exports]], target => 'dist', prereq_target => 'test', type => 'PPM' );
### print Dumper $rv->rv;
#$VAR1 = {
#          'Exporter::Lite' => {
#                                'install' => '1',
#                                'extract' => 'D:\\cpanplus\\5.6.0\\build\\Exporter-Lite-0.01',
#                                'md5' => 1,
#                                'fetch' => 'D:\\cpanplus\\authors\\id\\M\\MS\\MSCHWERN\\Exporter-Lite-0.01.tar.gz',
#                                'make' => {
#                                            'dir' => 'D:\\cpanplus\\5.6.0\\build\\Exporter-Lite-0.01',
#                                            'prereq' => {},
#                                            'makefile' => 1,
#                                            'overall' => 1,
#                                            'make' => 1,
#                                            'test' => 1
#                                          }
#                              },
#          'UNIVERSAL::exports' => {
#                                    'install' => '1',
#                                    'dist' => {
#                                                'object' => bless( {
#                                                                     'path' => 'M/MS/MSCHWERN',
#                                                                     'description' => '',
#                                                                     'dslip' => '    ',
#                                                                     'status' => {
#                                                                                   'install' => '1',
#                                                                                   'extract' => 'D:\\cpanplus\\5.6.0\\build\\UNIVERSAL-exports-0.03',
#                                                                                   'md5' => 1,
#                                                                                   'fetch' => 'D:\\cpanplus\\authors\\id\\M\\MS\\MSCHWERN\\UNIVERSAL-exports-0.03.tar.gz',
#                                                                                   'make' => {
#                                                                                               'dir' => 'D:\\cpanplus\\5.6.0\\build\\UNIVERSAL-exports-0.03',
#                                                                                               'prereq' => {
#                                                                                                             'Exporter::Lite' => '0.01'
#                                                                                                           },
#                                                                                               'makefile' => 1,
#                                                                                               'overall' => 1,
#                                                                                               'make' => 1,
#                                                                                               'test' => 1
#                                                                                             },
#                                                                                   'ppm' => {
#                                                                                              'zip' => 'D:\\cpanplus\\5.6.0\\PPM\\UNIVERSAL-exports-0.03\\UNIVERSAL-exports-0.03-MSWin32-x86-multi-thread.zip',
#                                                                                              'tgz' => 'D:\\cpanplus\\5.6.0\\PPM\\UNIVERSAL-exports-0.03\\UNIVERSAL-exports-0.03.tar.gz',
#                                                                                              'ppd' => 'D:\\cpanplus\\5.6.0\\PPM\\UNIVERSAL-exports-0.03\\UNIVERSAL-exports-0.03.ppd',
#                                                                                              'readme' => 'D:\\cpanplus\\5.6.0\\PPM\\UNIVERSAL-exports-0.03\\README.MSWin32-x86-multi-thread',
#                                                                                              'ppd_dir' => 'D:\\cpanplus\\5.6.0\\PPM\\UNIVERSAL-exports-0.03'
#                                                                                            }
#                                                                                 },
#                                                                     'prereqs' => {},
#                                                                     'module' => 'UNIVERSAL::exports',
#                                                                     'comment' => '',
#                                                                     'author' => 'MSCHWERN',
#                                                                     '_id' => 1,
#                                                                     'version' => '0.03',
#                                                                     'package' => 'UNIVERSAL-exports-0.03.tar.gz'
#                                                                   }, 'CPANPLUS::Dist::PPM' ),
#                                                'created' => {
#                                                               'zip' => 'D:\\cpanplus\\5.6.0\\PPM\\UNIVERSAL-exports-0.03\\UNIVERSAL-exports-0.03-MSWin32-x86-multi-thread.zip',
#                                                               'ppd' => 'D:\\cpanplus\\5.6.0\\PPM\\UNIVERSAL-exports-0.03\\UNIVERSAL-exports-0.03.ppd',
#                                                               'tgz' => 'D:\\cpanplus\\5.6.0\\PPM\\UNIVERSAL-exports-0.03\\UNIVERSAL-exports-0.03.tar.gz',
#                                                               'readme' => 'D:\\cpanplus\\5.6.0\\PPM\\UNIVERSAL-exports-0.03\\README.MSWin32-x86-multi-thread'
#                                                             }
#                                              },
#                                    'extract' => 'D:\\cpanplus\\5.6.0\\build\\UNIVERSAL-exports-0.03',
#                                    'md5' => 1,
#                                    'fetch' => 'D:\\cpanplus\\authors\\id\\M\\MS\\MSCHWERN\\UNIVERSAL-exports-0.03.tar.gz',
#                                    'make' => $VAR1->{'UNIVERSAL::exports'}{'dist'}{'object'}{'status'}{'make'}
#                                  }
#        };

### the below output can be generated by this AUTOLOAD method
### for example, you might give these commands:
### print Dumper $rv->install;
### print Dumper $rv->extract;
### print Dumper $rv->fetch;

### and you'd get this output:
#$VAR1 = {
#          'Exporter::Lite' => '1',
#          'UNIVERSAL::exports' => '1'
#        };
#$VAR1 = {
#          'Exporter::Lite' => 'D:\\cpanplus\\5.6.0\\build\\Exporter-Lite-0.01',
#          'UNIVERSAL::exports' => 'D:\\cpanplus\\5.6.0\\build\\UNIVERSAL-exports-0.03'
#        };
#$VAR1 = {
#          'Exporter::Lite' => 'D:\\cpanplus\\authors\\id\\M\\MS\\MSCHWERN\\Exporter-Lite-0.01.tar.gz',
#          'UNIVERSAL::exports' => 'D:\\cpanplus\\authors\\id\\M\\MS\\MSCHWERN\\UNIVERSAL-exports-0.03.tar.gz'
#        };


sub AUTOLOAD {
    my $self = shift;

    #print "AUTOLOAD: $AUTOLOAD\n";

    ## fancy AUTOLOAD magic
    my $name = $AUTOLOAD;
    $name =~ s/.*://; # strip fully-qualified portion

    my $return;

    my $rv = $self->rv;
    for my $key ( keys %{$rv} ) {
        $return->{$key} = $rv->{$key}->{$name};
    }

    unless( grep { defined } values %$return ) {
        my $obj = $self->_make_object();

        my $type = $self->type;

        $obj->error_object->trap(
                error => loc("'%1' is not an existing accessor for '%2'", $name, $type),
        );
        return 0;
    }

    return $return;
}

sub can {
    my $self    = shift;
    my $rv      = $self->rv;

    my @return;
    for my $module(keys %$rv) {
        for my $can ( keys %{$rv->{$module}} ) {
            push @return, $can unless grep /^$can$/, @return;
        }
    }

    return [ sort @return ];
}


sub DESTROY { 1 }

1;

__END__

=pod

=head1 NAME

CPANPLUS::Backend::RV - Return Value class for CPAN++

=head1 SYNOPSIS

    my $rv = $backend_obj->some_function();

    unless ($rv->ok()) {
        warn "There was an error with ".$rv->type().".  Examining it.\n";
        my $calling_args = $rv->args();
        my $full_return = $rv->rv();

        # See what extra method calls are valid for this object
        my $allowed = $rv->can();

        # Refer to the 'rv' method for documentation on key accessors
        my $fetch_results = $rv->fetch();
        my $make_results = $rv->make();
        ...
    }

=head1 DESCRIPTION

A return value class for CPANPLUS to facilitate error checking and
to handle the many possible values in an expandable manner.  The RV
object is provided as a return value for most CPANPLUS::Backend
functions.

=head1 METHODS

=head2 ok()

This is the most basic method of the RV class.  It returns a boolean
value indicating overall success or failure.

It is also possible to get the result of I<ok> simply by checking
the RV object in boolean context.  Thus these two statements are
equivalent:

    # $return is a RV object

    if ($return) ...
    if ($return->ok()) ...

=head2 can()

This method returns an array ref of all extra methods which are
valid for the object.

For example, the C<extract> method will be available only if an
action including extraction was attempted.

Refer to L<rv()> for more information about what sorts of methods
will be available.

=head2 rv()

This method returns a hash reference of the original return value.
The structure is a bit complex, so it is recommended that you delve
in to it only if you receive a failure value from I<ok>.

Methods also exist for all of the 'top level keys' (in reality
the keys one level below the module names).  Examine
this dumper of one of the more elaborate results of I<rv>:

    {
        'Exporter::Lite' => {
            'install' => '1',
            'extract' => 'D:\\cpanplus\\5.6.0\\build\\Exporter-Lite-0.01',
            'md5' => 1,
            'fetch' => 'D:\\cpanplus\\authors\\id\\M\\MS\\MSCHWERN\\Exporter-Lite-0.01.tar.gz',
            'make' => {
                'dir' => 'D:\\cpanplus\\5.6.0\\build\\Exporter-Lite-0.01',
                'prereq' => {},
                'makefile' => 1,
                'overall' => 1,
                'make' => 1,
                'test' => 1
            },
        },
        'UNIVERSAL::exports' => {
            'install' => '1',
            'extract' => 'D:\\cpanplus\\5.6.0\\build\\UNIVERSAL-exports-0.03',
            'md5' => 1,
            'fetch' => 'D:\\cpanplus\\authors\\id\\M\\MS\\MSCHWERN\\UNIVERSAL-exports-0.03.tar.gz',
            'make' => {
                'dir' => 'D:\\cpanplus\\5.6.0\\build\\UNIVERSAL-exports-0.03',
                'prereq' => {
                    'Exporter::Lite' => '0.01'
                },
                'makefile' => 1,
                'overall' => 1,
                'make' => 1,
                'test' => 1
            },
        }
    };

In this example, the 'top level keys' include I<install>, I<extract>,
I<md5>, I<fetch>, I<make> and I<ppm>.  A summary of all I<md5>s, for
example, could be fetched with the following code:

    my $md5s = $rv->md5();

This will return a hash reference where each key corresponds to the module
name and each value is the value for that module.  The example code
used on the dumper above would return:

    {
        'UNIVERSAL::exports' => 1,
        'Exporter::Lite' => 1
    }

A warning will be given if the key that is being accessed doesn't exist.

=head2 type()

This function will return the type of return value, usually the name
of the method that generated it.

=head2 args()

This will return a hash reference of the arguments that were
passed to the method.  Note that the arguments may have been
modified by the input checker.

For example, the following code:

    my $rv = $backend_obj->distributions(authors => ['KANE', 'KUDRA']);

generates this structure for I<args>:

    {
        'authors' => [
            'KANE',
            'KUDRA'
        ]
    }


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

L<CPANPLUS::Backend>

=cut


# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
