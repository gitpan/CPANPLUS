#!/usr/bin/perl -w
# $File: //depot/cpanplus/dist/t/CPANPLUS-Backend.t $
# $Revision: #6 $ $Change: 7684 $ $DateTime: 2003/08/23 18:23:18 $

BEGIN { chdir 't' if -d 't' };

use strict;
use lib '../lib', 'lib';
use Test::More tests => 10;
use Test::MockObject;

# Setting up the testing environment {{{

my ($mock, $result, $method, $args);
Test::MockObject->new->fake_module( $_ ) for qw(
    CPANPLUS::Configure
    CPANPLUS::Internals
    CPANPLUS::Internals::Module
    CPANPLUS::Backend::RV
);

use_ok( 'CPANPLUS::Backend' ) or diag "CPANPLUS/Backend.pm not found.  Dying", die;
# we are not testing l10n, so turn it off and use raw messages
undef $CPANPLUS::I18N::LangHandle if $CPANPLUS::I18N::LangHandle;

# }}}
# Testing CPANPLUS::Backend::new() {{{

$mock = Test::MockObject->new();
$mock->fake_module( 'CPANPLUS::Configure', new => sub { join('-', @_) } );
$mock->fake_module( 'CPANPLUS::Internals', _init => sub { join('-', @_) } );

$result = CPANPLUS::Backend->new($mock);
is( $result, "CPANPLUS::Backend-conf-$mock", 'new($ref) should initialize with $ref' );

$result = CPANPLUS::Backend->new('arg1', 'arg2');
is( $result, "CPANPLUS::Backend-conf-CPANPLUS::Configure-arg1-arg2", 'new(@args) should initialize with CPANPLUS::Configure->new(@args)' );

# }}}
# Testing CPANPLUS::Backend::error_object() {{{

$mock = Test::MockObject->new();
$mock->{_error} = $mock;
$result = CPANPLUS::Backend::error_object($mock);
is( $result, $mock, 'error_object() should return $self->{_error}' );

# }}}
# Testing CPANPLUS::Backend::configure_object() {{{

$mock = Test::MockObject->new();
$mock->{_conf} = $mock;
$result = CPANPLUS::Backend::configure_object($mock);
is( $result, $mock, 'configure_object() should return $self->{_conf}' );

# }}}
# Testing CPANPLUS::Backend::module_tree() {{{

$mock = Test::MockObject->new();
$mock->set_always( _module_tree => 'return value' );
$result = CPANPLUS::Backend::module_tree($mock);
is( $result, 'return value', 'module_tree() should return $self->_module_tree' );

# }}}
# Testing CPANPLUS::Backend::author_tree() {{{

$mock = Test::MockObject->new();
$mock->set_always( _author_tree => 'return value' );
$result = CPANPLUS::Backend::author_tree($mock);
is( $result, 'return value', 'author_tree() should return $self->_author_tree' );

# }}}
# Testing CPANPLUS::Backend::search() {{{

$mock = Test::MockObject->new();
$mock->fake_module( 'CPANPLUS::Backend::RV', new => sub { 'return value' } );
$mock->set_always( 'error_object', $mock )
     ->set_always( 'configure_object', $mock )
     ->set_true( 'get_conf' )
     ->set_false( '_check_input' );

$result = CPANPLUS::Backend::search( $mock, type => 'foo', list => 'bar' );
($method, $args) = $mock->next_call(5);
is( $method, '_check_input', 'search() should verify input' );
like( join('-', @$args), qr/(?=.*type-foo)(?=.*list-bar)/, '... passing user data' );

ok( ! $result, '... return false given bad input' );

__END__

$mock->mock( '_is_ok', sub { $_[2] } );

$result = CPANPLUS::Backend::search( $mock, foo => 'bar' );
($method, $args) = $mock->next_call(1);
is( $method, 'error_object', 'search() should raise error on bad data' );

$mock->mock( '_query_author_tree', sub { join('-', @_) } )
     ->set_true( '_check_input' );
$result = CPANPLUS::Backend::search( $mock, type => 'author' );
($method, $args) = $mock->next_call(6);
is( join('-', $method, @$args), "_query_author_tree-$mock-type-author", 'search( type => "author" ) should call $self->_query_author_tree' );
is( $result, "$mock-type-author", '... and pass back its return value' );

$mock->mock( '_query_mod_tree', sub { join('-', @_) } );
$result = CPANPLUS::Backend::search( $mock, type => 'module' );
($method, $args) = $mock->next_call(3);
is( join('-', $method, @$args), "_query_mod_tree-$mock-type-module", 'search( type => "module" ) should call $self->_query_module_tree' );
is( $result, "$mock-type-module", '... and pass back its return value' );

# }}}
# Testing CPANPLUS::Backend::details() {{{
# }}}
# Testing CPANPLUS::Backend::readme() {{{
# }}}
# Testing CPANPLUS::Backend::install() {{{

$mock = Test::MockObject->new();
$mock->fake_module( 'CPANPLUS::Backend::RV', new => sub { 'return value' } );
$mock->set_always( 'error_object', $mock )
     ->set_always( 'configure_object', $mock )
     ->set_false( '_is_ok' );

$result = CPANPLUS::Backend::install( $mock, foo => 'bar' );
($method, $args) = $mock->next_call(3);
is( $method, '_is_ok', 'install() should verify input' );
# can check $_data here
is( join('-', %{ $args->[2] }), 'foo-bar', '... passing user data' );

ok( ! $result, 'install() should return false given bad input' );

$mock->mock( '_is_ok', sub { $_[2] } )
	 ->set_true( 'get_conf' )
	 ->set_true( '_get_build' )
	 ->set_true( 'flush' )
	 ->set_true( '_whoami' );

$mock->{_conf} = $mock;

$result = CPANPLUS::Backend::install( $mock, target => 'install' );
($method, $args) = $mock->next_call( 4 );
is( $method, 'get_conf', 'install() should check configuration if not forced' );
is( $args->[1], 'force', '... checking for force flag' );

($method, $args) = $mock->next_call( 3 );
is( $method, 'get_conf', 'install() should check to flush modules' );
is( $args->[1], 'flush', '... checking for the flush flag' );
($method, $args) = $mock->next_call();
is( $method, 'flush', '... doing so as necessary' );
is( $args->[1], 'modules', '... passing the modules argument' );

is( $result, 'return value', '... and should return a new RV' );
is( $mock->next_call(), '_whoami', '... checking the backend type' );

# }}}
# Testing CPANPLUS::Backend::fetch() {{{
# }}}
# Testing CPANPLUS::Backend::extract() {{{
# }}}
# Testing CPANPLUS::Backend::make() {{{
# }}}
# Testing CPANPLUS::Backend::uninstall() {{{
# }}}
# Testing CPANPLUS::Backend::files() {{{
# }}}
# Testing CPANPLUS::Backend::distributions() {{{
# }}}
# Testing CPANPLUS::Backend::modules() {{{
# }}}
# Testing CPANPLUS::Backend::reports() {{{
# }}}
# Testing CPANPLUS::Backend::uptodate() {{{
# }}}
# Testing CPANPLUS::Backend::validate() {{{
# }}}
# Testing CPANPLUS::Backend::installed() {{{
# }}}
# Testing CPANPLUS::Backend::flush() {{{
# }}}
# Testing CPANPLUS::Backend::reload_indices() {{{
# }}}
# Testing CPANPLUS::Backend::pathname() {{{

$mock = Test::MockObject->new();
$mock->fake_module( 'CPANPLUS::Backend::RV', new => sub { 'return value' } );
$mock->set_false( '_is_ok' );

$result = CPANPLUS::Backend::pathname( $mock, foo => 'bar' );
($method, $args) = $mock->next_call();
is( $method, '_is_ok', 'pathname() should verify input' );
is( join('-', %{ $args->[2] }), 'foo-bar', '... passing user data' );

ok( ! $result, '... return false given bad input' );

$mock->{_error} = $mock;
$mock->mock( '_is_ok', sub { $_[2] } )
     ->set_true( 'trap' )
     ->mock( '_can_use', sub { eval "use $_" for keys %{ { @_[ 1..$#_ ] }->{ modules } }; 1 });

$result = CPANPLUS::Backend::pathname( $mock, to => [ 'bar' ] );
($method, $args) = $mock->next_call(2);
like( "$method-$args->[1]-$args->[2]", qr/^trap-error-Array reference passed/, 'pathname() should reject (to => $arrayref)' );

$mock->set_always( 'parse_module', $mock )
     ->set_false( 'ok' );
$result = CPANPLUS::Backend::pathname( $mock, to => 'bar' );
($method, $args) = $mock->next_call(2);
is( "$method-$args->[1]-@{$args->[2]||[]}", 'parse_module-modules-bar', 'pathname() should call $self->parse_module' );
($method, $args) = $mock->next_call;
is( $method, 'ok', '... check for validity from parse_module()' );
ok( ! $result, '... return false given bad input' );

$mock->set_true( 'ok' )
     ->set_always( rv => { 'name', { path => 'foo', package => 'bar' } } );

$result = CPANPLUS::Backend::pathname( $mock, to => 'bar' );
($method, $args) = $mock->next_call(4);
is( $method, 'rv', 'pathname() should check get module from $self->parse_module()->rv' );
is( $result, '/foo/bar', '... and return the pathname from File::Spec::Unix->catdir' );

# }}}
# Testing CPANPLUS::Backend::parse_module() {{{
# }}}
# Testing CPANPLUS::Backend::dist() {{{
# }}}
# Testing CPANPLUS::Backend::autobundle() {{{
# }}}

__END__
