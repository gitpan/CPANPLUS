package Object::Accessor;

use strict;
use Carp        qw[carp];
use vars        qw[$FATAL $DEBUG $AUTOLOAD $VERSION];

$VERSION    = '0.03';
$FATAL      = 0;
$DEBUG      = 0;

=head1 NAME

Object::Accessor

=head1 SYNOPSIS

    ### using the object
    $object = Object::Accessor->new;        # create object

    $bool   = $object->mk_accessors('foo'); # create accessors
    $clone  = $object->mk_clone;            # create a clone of the original
                                            # object without data
    $bool   = $object->mk_flush;            # clean out all data    
    
    @list   = $object->ls_accessors;        # retrieves a list of all 
                                            # accessors for this object
    
    $bar    = $object->foo('bar');          # set 'foo' to 'bar'
    $bar    = $object->foo();               # retrieve 'bar' again

    $sub    = $object->can('foo');          # retrieve coderef for
                                            # 'foo' accessor
    $bar    = $sub->('bar');                # set 'foo' via coderef
    $bar    = $sub->();                     # retrieve 'bar' by coderef

    ### using the object as base class
    package My::Class;
    use base 'Object::Accessor';
    
    $object     = My::Class->new;               # create base object
    $bool       = $object->mk_accessors('foo'); # create accessors, etc...

    ### make all attempted access to non-existant accessors fatal
    ### (defaults to false)
    $Object::Accessor::FATAL = 1;

    ### enable debugging
    $Object::Accessor::DEBUG = 1;

=head1 DESCRIPTION

C<Object::Accessor> provides an interface to create per object 
accessors (as opposed to per C<Class> accessors, as, for example,
C<Class::Accessor> provides).

You can choose to either subclass this module, and thus using its
accessors on your own module, or to store an C<Object::Accessor>
object inside your own object, and access the accessors from there.
See the C<SYNOPSIS> for examples.

=head1 METHODS

=head2 $object = Object::Accessor->new();

Creates a new (and empty) C<Object::Accessor> object. This method is
inheritable.

=cut 

sub new {
    return bless {}, $_[0];
}

=head2 $bool = $object->mk_accessors( @ACCESSORS );

Creates a list of accessors for this object (and C<NOT> for other ones
in the same class!). 
Will not clobber existing data, so if an accessor already exists, 
requesting to create again is effectively a C<no-op>.

Returns true on success, false on failure.

Accessors that are called on an object, that no do exist return 
C<undef> by default, but you can make this a fatal error by setting the
global variable C<$FATAL> to true. See the section on C<GLOBAL 
VARIABLES> for details.

Note that all accessors are read/write for everyone. See the C<TODO>
section for details.

=cut

sub mk_accessors {
    my $self = $_[0];
    
    for my $acc (@_[1..$#_]) {
    
        ### already created apparently
        if( exists $self->{$acc} ) {
            _debug( "Accessor '$acc' already exists");
            next;
        }            
    
        _debug( "Creating accessor '$acc'");
    
        ### explicitly vivify it, so that exists works in ls_accessors()
        $self->{$acc} = undef;
    }
    
    return 1;
}    

=head2 @list = $self->ls_accessors;

Returns a list of accessors that are supported by the current object.
The corresponding coderefs can be retrieved by passing this list one
by one to the C<can> method.

=cut

sub ls_accessors {
    return sort keys %{$_[0]};
}    

=head2 $clone = $self->mk_clone;

Makes a clone of the current object, which will have the exact same
accessors as the current object, but without the data stored in them.

=cut

sub mk_clone {
    my $self    = $_[0];
    my $class   = ref $self;
    
    my $clone   = $class->new;
    
    # copy the accessors from $self to $clone
    $clone->mk_accessors( $self->ls_accessors );
    
    return $clone;
}

=head2 $bool = $self->mk_flush;

Flushes all the data from the current object; all accessors will be
set back to their default state of C<undef>.

Returns true on success and false on failure.

=cut

sub mk_flush {
    my $self = $_[0];

    # set each accessor's data to undef
    $self->$_( undef ) for $self->ls_accessors;
    
    return 1;
}    

=head2 $bool = $self->can( METHOD_NAME )

This method overrides C<UNIVERAL::can> in order to provide coderefs to
accessors which are loaded on demand. It will behave just like 
C<UNIVERSAL::can> where it can -- returning a class method if it exists,
or a closure pointing to a valid accessor of this particular object.

You can use it as follows:

    $sub = $object->can('some_accessor');   # retrieve the coderef
    $sub->('foo');                          # 'some_accessor' now set
                                            # to 'foo' for $object
    $foo = $sub->();                        # retrieve the contents 
                                            # of 'foo'                                            

See the C<SYNOPSIS> for more examples.

=cut

### custom 'can' as UNIVERSAL::can ignores autoload
sub can {
    my($self, $method) = @_;
    
    ### it's one of our regular methods
    if( $self->UNIVERSAL::can($method) ) {
        _debug( "Can '$method' -- provided by package" );
        return $self->UNIVERSAL::can($method);
    }
    
    ### it's an accessor we provide;
    if( exists $self->{$method} ) {
        _debug( "Can '$method' -- provided by object" );
        return sub { $self->$method(@_); } 
    }        
    
    ### we don't support it
    _debug( "Cannot '$method'" );
    return;
}

### don't autoload this
sub DESTROY { 1 };

### use autoload so we can have per-object accessors, 
### not per class, as that is incorrect
sub AUTOLOAD {
    my $self    = $_[0];
    my($method) = ($AUTOLOAD =~ /([^:']+$)/);
    
    unless( exists $self->{$method} ) {
        _error("No such accessor '$method'");
        return;
    }        

    ### if there's more arguments than $self, then
    ### replace the method called by the accessor.
    ### XXX implement rw vs ro accessors!
    $self->{$method} = $_[1] if @_ > 1;
    
    return $self->{$method};
}

sub _debug { 
    return unless $DEBUG;

    local $Carp::CarpLevel += 1;
    carp(@_); 
}

sub _error { 
    local $Carp::CarpLevel += 1;
    $FATAL ? croak(@_) : carp(@_); 
}

=head1 GLOBAL VARIABLES 

=head2 $Object::Accessor::FATAL

Set this variable to true to make all attempted access to non-existant
accessors be fatal. 
This defaults to C<false>.

=head2 $Object::Accessor::DEBUG

Set this variable to enable debugging output.
This defaults to C<false>.

=head1 TODO

=head2 Create read-only accessors

Currently all accessors are read/write for everyone. Perhaps a future
release should make it possible to have read-only accessors as well.

=head1 AUTHOR

This module by
Jos Boumans E<lt>kane@cpan.orgE<gt>.

=head1 COPYRIGHT

This module is
copyright (c) 2004 Jos Boumans E<lt>kane@cpan.orgE<gt>.
All rights reserved.

This library is free software;
you may redistribute and/or modify it under the same
terms as Perl itself.

=cut

1;
