BEGIN { chdir 't' if -d 't' };

### this is to make devel::cover happy ###
BEGIN { 
    use File::Spec;
    require lib;
    for (qw[../lib inc]) { my $l = 'lib'; $l->import(File::Spec->rel2abs($_)) }
}

use strict;
use Test::More 'no_plan';

use CPANPLUS::Configure;
use CPANPLUS::Backend;
use CPANPLUS::Internals::Constants;
use Data::Dumper;

BEGIN { require 'conf.pl'; }

my $cb = CPANPLUS::Backend->new( CPANPLUS::Configure->new() );

isa_ok($cb,                 'CPANPLUS::Internals');
is($cb->_id, $cb->_last_id, "Comparing ID's");

### delete/store/retrieve id tests ###
{   my $del = $cb->_remove_id( $cb->_id );
    ok( $del,                   "ID deleted" );
    isa_ok( $del,               "CPANPLUS::Internals" );
    is( $del, $cb,              "   Deleted ID matches last object" );
    
    my $id = $cb->_store_id( $del );
    ok( $id,                    "ID stored" );
    is( $id, $cb->_id,          "   Stored proper ID" );
    
    my $obj = $cb->_retrieve_id( $id );
    ok( $obj,                   "Object retrieved from ID" );
    isa_ok( $obj,               'CPANPLUS::Internals' );
    is( $obj->_id, $id,         "   Retrieved ID properly" );
    
    my @obs = $cb->_return_all_objects();
    ok( scalar(@obs),           "Returned objects" );
    is( scalar(@obs), 1,        "   Proper amount of objects found" );
    is( $obs[0]->_id, $id,      "   Proper ID found on object" );
    
    my $lid = $cb->_last_id;
    ok( $lid,                   "Found last registered ID" );
    is( $lid, $id,              "   ID matches last object" );

    my $iid = $cb->_inc_id;
    ok( $iid,                   "Incremented ID" );
    is( $iid, $id+1,            "   ID matched last ID + 1" );
}    

### host ok test ###
{
    my $host = $cb->configure_object->get_conf('hosts')->[0];
    
    is( $cb->_host_ok( host => $host ),     1,  "Host ok" );
    is( $cb->_add_fail_host(host => $host), 1,  "   Host now marked as bad" );
    is( $cb->_host_ok( host => $host ),     0,  "   Host still bad" );
    ok( $cb->_flush( list => ['hosts'] ),       "   Hosts flushed" );
    is( $cb->_host_ok( host => $host ),     1,  "   Host now ok again" );
}    

### callback registering tests ###
{   for my $callback (qw[install_prerequisite edit_test_report 
                        send_test_report]
    ) {
        
        {   local $CPANPLUS::Error::ERROR_FH = output_handle() unless @ARGV;

            ok( $cb->_callbacks->$callback->(),
                                "Default callback '$callback' called" );
            like( CPANPLUS::Error->stack_as_string, qr/DEFAULT HANDLER/s,  
                                "   Default handler warning recorded" );       
            CPANPLUS::Error->flush;
        }
        
        ### try to register the callback
        my $ok = $cb->_register_callback(
                        name    => $callback,
                        code    => sub { return $callback }
                    );
                    
        ok( $ok,                "Registered callback '$callback' ok" );
        
        my $sub = $cb->_callbacks->$callback;
        ok( $sub,               "   Retrieved callback" );
        ok( IS_CODEREF->($sub), "   Callback is a sub" );
        
        my $rv = $sub->();
        ok( $rv,                "   Callback called ok" );
        is( $rv, $callback,     "   Got expected return value" );
    }   
}


# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
