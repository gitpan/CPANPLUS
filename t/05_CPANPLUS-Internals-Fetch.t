BEGIN { chdir 't' if -d 't' };

### this is to make devel::cover happy ###
BEGIN { 
    use File::Spec;
    require lib;
    for (qw[../lib inc]) { my $l = 'lib'; $l->import(File::Spec->rel2abs($_)) }
}

use strict;

use CPANPLUS::Backend;

use Test::More 'no_plan';
use Data::Dumper;

BEGIN { require 'conf.pl'; }
my $conf = gimme_conf();

### Redirect errors to file ###
local $CPANPLUS::Error::ERROR_FH = output_handle() unless @ARGV;
local $CPANPLUS::Error::MSG_FH   = output_handle() unless @ARGV;

my $cb = CPANPLUS::Backend->new( $conf );
isa_ok($cb, "CPANPLUS::Internals" );

my $mod = $cb->module_tree('Text::Bastardize');
isa_ok( $mod,  'CPANPLUS::Module' );

### fail host tests ###
{   my $host = {};
    my $rv   = $cb->_add_fail_host( host => $host );
    
    ok( $rv,                    "Failed host added " );
    ok(!$cb->_host_ok( host => $host),   
                                "   Host registered as failed" );
    ok( $cb->_host_ok( host => {} ),    
                                "   Fresh host unregistered" );
}

### refetch, even if it's there already ###
{   my $where = $cb->_fetch( module => $mod, force => 1 );

    ok( $where,                 "File downloaded to '$where'" );
    ok( -s $where,              "   File exists" );                          
    unlink $where;
    ok(!-e $where,              "   File removed" );
}

### try to fetch something that doesn't exist ###
{   ### set up a bogus host first ###
    my $hosts   = $conf->get_conf('hosts');
    my $fail    = { scheme  => 'file', 
                    path    => "$0/$0" };
    
    unshift @$hosts, $fail;
    $conf->set_conf( hosts => $hosts );
    
    ### the fallback host will get it ###
    my $where = $cb->_fetch( module => $mod, force => 1, verbose => 0 );
    ok($where,                  "File downloaded to '$where'" );
    ok( -s $where,              "   File exists" );                          
    
    ### but the error should be recorded ###
    like( CPANPLUS::Error->stack_as_string, qr/Fetching of .*? failed/s,
                                "   Error recorded appropriately" ); 

    ### host marked as bad? ###
    ok(!$cb->_host_ok( host => $fail ),   
                                "   Failed host logged properly" );    

    ### restore the hosts ###
    shift @$hosts; $conf->set_conf( hosts => $hosts );
}

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
