BEGIN { chdir 't' if -d 't' };
### this is to make devel::cover happy ###

BEGIN { 
    use File::Spec;
    require lib;
    for (qw[../lib inc config]) { my $l = 'lib'; $l->import(File::Spec->rel2abs($_)) }
}

use Test::More 'no_plan';
use Data::Dumper;
use strict;
use CPANPLUS::Internals::Constants;
BEGIN { require 'conf.pl'; }

### purposely avert messages and errors to a file? ###
my $Trap_Output = @ARGV ? 0 : 1;
my $Config_pm   = 'CPANPLUS/Config.pm';


for my $mod (qw[CPANPLUS::Configure CPANPLUS::Config]) {
    use_ok($mod) or diag qq[Can't load $mod];
}    

my $c = CPANPLUS::Configure->new();
isa_ok($c, 'CPANPLUS::Configure');

my $r = $c->conf;
isa_ok( $r, 'CPANPLUS::Config' );


for my $cat ( keys %$r ) {

    ### what field can they take? ###
    my @options = $c->options( type => $cat );
    
    my $prepend = ($cat =~ s/^_//) ? '_' : '';
    
    my $getmeth = $prepend . 'get_'. $cat;
    my $setmeth = $prepend . 'set_'. $cat;
    my $addmeth = $prepend . 'add_'. $cat;
    
    ok( scalar(@options),               "Possible options obtained" );
    
    ### test adding keys too ###
    {   my $add_key = 'test_key';
        my $add_val = [1..3];
    
        my $found = grep { $add_key eq $_ } @options;
        ok( !$found,                    "Key '$add_key' not yet defined" );
        ok( $c->$addmeth( $add_key => $add_val ),
                                        "   Key '$add_key' added" ); 

        ### this one now also exists ###
        push @options, $add_key
    }

    ### poke in the object, get the actual hashref out ### 
    my $hash = $r->{ $prepend . $cat };
    
    while( my ($key,$val) = each %$hash ) {
        my $is = $c->$getmeth($key); 
        is_deeply( $val, $is,           "deep check for '$key'" );
        ok( $c->$setmeth($key => 1 ),   "   setting '$key' to 1" );
        is( $c->$getmeth($key), 1,      "   '$key' set correctly" );
        ok( $c->$setmeth($key => $val), "   restoring '$key'" );
    }

    ### now check if we found all the keys with options or not ###
    delete $hash->{$_} for @options;
    ok( !(scalar keys %$hash),          "All possible keys found" );
    
}    

### see if we can save the config ###
{   my $file = File::Spec->catfile('dummy-cpanplus','.config');
    ok( $c->can_save($file),    "Able to save config" );
    ok( $c->save($file),        "   File saved" );
    ok( -e $file,               "   File exists" );
    ok( -s $file,               "   File has size" );

    ### now see if we can load this config too ###
    {   my $env = ENV_CPANPLUS_CONFIG;
        local $ENV{$env}        = $file;
        local $INC{$Config_pm}  = 0;
        
        my $conf; 
        {   local $^W; # redefining 'sub new'
            $conf = CPANPLUS::Configure->new();
        }       
        ok( $conf,              "Config loaded from environment" );
        isa_ok( $conf,          "CPANPLUS::Configure" );
        is( $INC{$Config_pm}, $file,
                                "   Proper config file loaded" );
    }
}


{   local $CPANPLUS::Error::ERROR_FH  = output_handle() if $Trap_Output;
    
    CPANPLUS::Error->flush;
    
    {   ### try a bogus method call 
        my $x   = $c->flubber('foo');
        my $err = CPANPLUS::Error->stack_as_string;
        is  ($x, undef,         "Bogus method call returns undef");
        like($err, "/flubber/", "   Bogus method call recognized");
    }
    
    CPANPLUS::Error->flush;
    
    #################################################
    ### tests for config version too low for cpanplus
    #################################################
    
    {   ### try creating a new configure object with an out of date
        ### config. set version to 0, remove entry from %INC     
        local $CPANPLUS::Config::VERSION = 0;      
        local $INC{$Config_pm} = 0;
        
        my $rv  = CPANPLUS::Configure->new();
        my $err = CPANPLUS::Error->stack_as_string;
        ok( !$rv,       "Out of date config version detected" );
        like( $err, qr/You will need to reconfigure/,
                        "   Error stored as expected" );
    }

    CPANPLUS::Error->flush;
    
    {   ### ensure that we handle x.xx_aa < x.xx_bb properly
        local $CPANPLUS::Config::VERSION = "0.00_01";
        local $CPANPLUS::Configure::MIN_CONFIG_VERSION = "0.00_02";
        local $INC{$Config_pm} = 0;
        
        my $rv  = CPANPLUS::Configure->new();
        my $err = CPANPLUS::Error->stack_as_string;
        ok( !$rv,       "Out of date config version detected" );
        like( $err, qr/You will need to reconfigure/,
                        "   Error stored as expected" );
    }
    
    CPANPLUS::Error->flush;
    
    {   ### ensure that we handle x.xx_aa < y.yy_aa properly
        local $CPANPLUS::Config::VERSION = "0.00_00";
        local $CPANPLUS::Configure::MIN_CONFIG_VERSION = "0.01_00";
        local $INC{$Config_pm} = 0;
        
        my $rv  = CPANPLUS::Configure->new();
        my $err = CPANPLUS::Error->stack_as_string;
        ok( !$rv,       "Out of date config version detected" );
        like( $err, qr/You will need to reconfigure/,
                        "   Error stored as expected" );
    }
    
    CPANPLUS::Error->flush;
    
    {   ### load config when versions are equal
        local $CPANPLUS::Config::VERSION = "0.00_00";
        local $CPANPLUS::Configure::MIN_CONFIG_VERSION = "0.00_00";
        local $INC{$Config_pm} = 0;
        
        my $rv  = CPANPLUS::Configure->new();
        ok( $rv,        "Config loaded from environment" );
        isa_ok( $rv,    "CPANPLUS::Configure" );
    }

    CPANPLUS::Error->flush;

    
    #################################################
    ### tests for CPANPLUS version too low for config
    #################################################

    {   ### ensure that we handle x.xx_aa < y.yy_aa properly
        local $CPANPLUS::Configure::VERSION = "0.00_00";
        local $CPANPLUS::Config::MIN_CONFIG_VERSION = "0.01_00";
        local $INC{$Config_pm} = 0;
        
        my $rv  = CPANPLUS::Configure->new();
        my $err = CPANPLUS::Error->stack_as_string;
        ok( !$rv,       "Out of date cpanplus version detected" );
        like( $err, qr/You will need to reconfigure/,
                        "   Error stored as expected" );
    }

    CPANPLUS::Error->flush;

    {   ### ensure that we handle x.xx_aa < x.xx_bb properly
        local $CPANPLUS::Configure::VERSION = "0.00_01";
        local $CPANPLUS::Config::MIN_CONFIG_VERSION = "0.00_02";
        local $INC{$Config_pm} = 0;
        
        my $rv  = CPANPLUS::Configure->new();
        my $err = CPANPLUS::Error->stack_as_string;
        ok( !$rv,       "Out of date cpanplus version detected" );
        like( $err, qr/You will need to reconfigure/,
                        "   Error stored as expected" );
    }

    CPANPLUS::Error->flush;

    {   ### load config when versions are equal
        local $CPANPLUS::Config::MIN_CPANPLUS_VERSION = "0.00_00";
        local $CPANPLUS::Configure::VERSION = "0.00_00";
        local $INC{$Config_pm} = 0;
        
        my $rv  = CPANPLUS::Configure->new();
        ok( $rv,        "Config loaded from environment" );
        isa_ok( $rv,    "CPANPLUS::Configure" );
    }

    CPANPLUS::Error->flush;

};

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
