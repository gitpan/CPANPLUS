### running under perl core?
BEGIN { 
    if( $ENV{PERL_CORE} ) {
        chdir '../lib/CPANPLUS' if -d '../lib/CPANPLUS';
        unshift @INC, '../../../lib';
    
        ### fix perl location too
        $^X = '../../../t/' . $^X;
    }
} 

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
$conf->set_conf( verbose => 0 );

my $Class       = 'CPANPLUS::Selfupdate';
my $ModClass    = "CPANPLUS::Selfupdate::Module";
my $CB          = CPANPLUS::Backend->new( $conf );
my $Acc         = 'selfupdate_object';
my $Conf        = $Class->_get_config;
my $Dep         = 'B::Deparse';   # has to be in our package file && core!
my $Feat        = 'some_feature';
my $Prereq      = { $Dep => 0 };

### test the object
{   ok( $CB,                    "New backend object created" );
    can_ok( $CB,                $Acc );

    ok( $Conf,                  "Got configuration hash" );

    my $su = $CB->$Acc;
    ok( $su,                    "Selfupdate object retrieved" );
    isa_ok( $su,                "CPANPLUS::Selfupdate" );
}

### test the feature list
{   ### start with defining our OWN type of config, as not all mentioned
    ### modules will be present in our bundled package files.
    ### XXX WHITEBOX TEST!!!!
    {   delete $Conf->{$_} for keys %$Conf;
        $Conf->{'dependencies'}         = $Prereq;
        $Conf->{'core'}                 = $Prereq;
        $Conf->{'features'}->{$Feat}    = [ $Prereq, sub { 1 } ];
    }

    is_deeply( $Conf, $Class->_get_config,
                                "Config updated succesfully" );

    my @feat = $CB->$Acc->list_features;
    ok( scalar(@feat),          "Features list returned" );

    ### test if we get modules for each feature
    for my $feat (@feat) {
        my $meth = 'modules_for_feature';
        my @mods = $CB->$Acc->$meth( $feat );
        
        ok( $feat,              "Testing feature '$feat'" );
        ok( scalar( @mods ),    "   Module list returned" );
    
        my $acc = 'is_installed_version_sufficient';
        for my $mod (@mods) {
            isa_ok( $mod,       "CPANPLUS::Module" );
            isa_ok( $mod,       $ModClass );
            can_ok( $mod,       $acc );
            ok( $mod->$acc,    "   Module uptodate" );
        }                                    
        
        ### check if we can get a hashref
        {   my $href = $CB->$Acc->$meth( $feat, 1 );
            ok( $href,          "Got result as hash" );
            isa_ok( $href,      'HASH' );
            is_deeply( $href, $Prereq,
                                "   With the proper entries" );

        }
        
    }

    ### find enabled features
    {   my $meth = 'list_enabled_features';
        can_ok( $Class,         $meth );        
        
        my @list = $CB->$Acc->$meth;
        ok( scalar(@list),      "Retrieved enabled features" );
        is_deeply( [$Feat], \@list,
                                "   Proper features found" );
    }
    
    ### find dependencies/core modules
    for my $meth ( qw[list_core_dependencies list_core_modules] ) {
        can_ok( $Class,         $meth );        
        
        my @list = $CB->$Acc->$meth;
        ok( scalar(@list),      "Retrieved modules" );
        is( scalar(@list), 1,   "   1 Found" );
        isa_ok( $list[0],       $ModClass ); 
        is( $list[0]->name, $Dep,
                                "   Correct module found" );

        ### check if we can get a hashref
        {   my $href = $CB->$Acc->$meth( 1 );
            ok( $href,          "Got result as hash" );
            isa_ok( $href,      'HASH' );
            is_deeply( $href, $Prereq,
                                "   With the proper entries" );
        }
    }

    ### now selfupdate ourselves
    {   ### XXX just test the mechanics, make sure install returns true
        ### declare twice because warnings are hateful
        ### declare in a block to quelch 'sub redefined' warnings.
        { local *CPANPLUS::Selfupdate::Module::install = sub { 1 }; }
        local *CPANPLUS::Selfupdate::Module::install = sub { 1 };
        
        my $meth = 'selfupdate';
        can_ok( $Class,         $meth );
        ok( $CB->$Acc->$meth( update => 'all'),   
                                "   Selfupdate successful" );
    }
}    

