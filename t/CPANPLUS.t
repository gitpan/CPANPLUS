#!/usr/bin/perl -w
# $File: //depot/cpanplus/dist/t/CPANPLUS.t $
# $Revision: #3 $ $Change: 3187 $ $DateTime: 2003/01/04 20:45:36 $

BEGIN { chdir 't' if -d 't' };

use strict;
use lib '../lib', 'lib';
use Test::More tests => 35;
use Test::MockObject;

# Setting up the testing environment {{{

my ($mock, $result, $method, $args);
Test::MockObject->new->fake_module( 'CPANPLUS::Backend' );
use_ok( 'CPANPLUS' ) or diag "CPANPLUS.pm not found.  Dying", die;

# we are not testing l10n, so turn it off and use raw messages
undef $CPANPLUS::I18N::LangHandle if $CPANPLUS::I18N::LangHandle;

# }}}
# Testing CPANPLUS::install() {{{

$mock = Test::MockObject->new();
$mock->fake_module( 'CPANPLUS::Backend', new => sub { $mock } );
$mock->{_error} = $mock;
$mock->set_true( 'trap' )
     ->mock( '_can_use', sub { eval "use $_" for keys %{ { @_[ 1..$#_ ] }->{ modules } }; 1 })
     ->set_always( 'error_object', $mock );

$result = CPANPLUS::install();

($method, $args) = $mock->next_call(2);
is( $method, 'trap', 'install() should trap error without a module' );
is( join('-', ($args && @$args)), "$mock-error-No module specified!",
	'... with the appropriate error message' );
ok( !$result, '... returning false' );

$result = CPANPLUS::install( $mock );
($method, $args) = $mock->next_call(2);
is( $method, 'trap', 'install() should trap error given a reference argument' );
like( join('-', ($args && @$args)), qr/-error-You passed an object/,
	'... with the appropriate error message' );
ok( !$result, '... returning false' );

$mock->set_always( 'module_tree', { foo => 1 } )
     ->set_always( 'install', $mock )
     ->set_series( 'ok', 0, 'return value', 1 )
     ->set_true( 'inform' );

$result = CPANPLUS::install( 'foo' );
($method, $args) = $mock->next_call( 2 );
is( $method, 'install',
	'install() should call the backend install() if module is found' );
is( "$args->[1]-@{$args->[2]}", 'modules-foo', '... passing the module name' );
is( $mock->next_call(),  'ok', '... checking the return value status' );
($method, $args) = $mock->next_call();
is( $method, 'inform', '... registering a status message' );
like( join('-', ($args && @$args)), qr/msg-Installing of foo failed-quiet-0/,
	'... with the appropriate status message' );

CPANPLUS::install( 'foo' );
($method, $args) = $mock->next_call( -1 );
like( join('-', ($args && @$args)), qr/msg-Installing of foo successful-quiet-0/,
	'... for success or failure' );

is( $result, 'return value', '... returning the status' );

# }}}
# Testing CPANPLUS::fetch() {{{

$mock = Test::MockObject->new();
$mock->fake_module( 'CPANPLUS::Backend', new => sub { $mock } );

$mock->{_error} = $mock;
$mock->set_true( 'trap' );
$result = CPANPLUS::fetch();

($method, $args) = $mock->next_call();
is( $method, 'trap', 'fetch() should trap error without a module' );
is( join('-', ($args && @$args)), "$mock-error-No module specified!",
	'... with the appropriate error message' );
ok( !$result, '... returning false' );

$result = CPANPLUS::fetch($mock);
($method, $args) = $mock->next_call();
is( $method, 'trap', 'fetch() should trap error given a reference argument' );
like( join('-', ($args && @$args)), qr/-error-You passed an object/,
	'... with the appropriate error message' );
ok( !$result, '... returning false' );

$mock->set_always( 'module_tree', { foo => 1 } );
$result = CPANPLUS::fetch( 'bar' );
is( $mock->next_call(), 'module_tree',
	'fetch() should call module_tree() on backend given module name' );
($method, $args) = $mock->next_call();
is( $method, 'trap', '... trapping an error if module is unknown' );
like( join('-', ($args && @$args)), qr/error-Unknown module 'bar'/,
	'... with the appropriate error message' );
ok( !$result, '... returning false' );

$mock->set_always( 'fetch', $mock )
	 ->set_series( 'ok', 0, 'return value', 1, 'return value' )
	 ->set_true( 'inform' )
	 ->set_true( '_get_build');

$mock->{_conf} = $mock;

$result = CPANPLUS::fetch( 'foo' );
($method, $args) = $mock->next_call( 2 );
is( "$method-$args->[1]", '_get_build-startdir',
	'fetch() should call the backend _get_build("startdir") first' );
($method, $args) = $mock->next_call;
is( $method, 'fetch',
	'... call the backend fetch() if module is found' );
is( ($args && $args->[2] && "$args->[1]-@{$args->[2]}"), 'modules-foo', '... passing the module name' );
is( $mock->next_call(),  'ok', '... checking the return value status' );
($method, $args) = $mock->next_call();
is( $method, 'inform', '... registering a status message' );
like( join('-', ($args && @$args)), qr/msg-Fetching of foo failed-quiet-0/,
	'... with the appropriate status message' );

$result = CPANPLUS::fetch( 'foo' );
($method, $args) = $mock->next_call(-1);
like( join('-', ($args && @$args)), qr/msg-Fetching of foo successful-quiet-0/,
	'... for success or failure' );

is( $result, 'return value', '... returning the status' );

# }}}
# Testing CPANPLUS::get() {{{

{
    no strict 'refs';
    local $^W;
    local *{CPANPLUS::fetch} = sub { "fetch-@_" };
    $result = CPANPLUS::get( 'foo' );
    is ($result, 'fetch-foo', 'get() should be an alias to fetch()');

}

# }}}
# Testing CPANPLUS::shell() {{{

my $import;
$mock = Test::MockObject->new();
$mock->fake_module( 'CPANPLUS::Shell', new => sub { $mock }, import => sub { $import = [@_] } );
$mock->set_true( 'shell' );

CPANPLUS::shell('Classic');
is( "$import->[0]-$import->[1]", 'CPANPLUS::Shell-Classic',
	'shell() should import CPANPLUS::Shell with its option' );
is( $mock->next_call, 'shell',
	'... and delegate the shell() call to the new Shell object' );

# }}}

__END__
