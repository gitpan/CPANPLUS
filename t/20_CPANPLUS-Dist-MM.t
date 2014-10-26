#!/usr/bin/perl -w

BEGIN { chdir 't' if -d 't' };

### this is to make devel::cover happy ###
BEGIN { 
    use File::Spec;
    require lib;
    for (qw[../lib inc]) { my $l = 'lib'; $l->import(File::Spec->rel2abs($_)) }
}
use strict;

use CPANPLUS::inc;
use CPANPLUS::Configure;
use CPANPLUS::Backend;
use CPANPLUS::Dist;
use CPANPLUS::Dist::MM;
use CPANPLUS::Internals::Constants;

use Test::More 'no_plan';
use Cwd;
use Config;
use Data::Dumper;
use File::Basename ();
use File::Spec ();

BEGIN { require 'conf.pl'; }

my $conf    = gimme_conf();
my $cb      = CPANPLUS::Backend->new( $conf );
my $noperms = ($< and not $conf->get_program('sudo')) &&
              ($conf->get_conf('makemakerflags') or 
                not -w $Config{installsitelib} );

### don't start sending test reports now... ###
$cb->_callbacks->send_test_report( sub { 0 } );
$conf->set_conf( cpantest => 0 );

### Redirect errors to file ###
local $CPANPLUS::Error::ERROR_FH = output_handle() unless @ARGV;
local $CPANPLUS::Error::MSG_FH   = output_handle() unless @ARGV;
*STDOUT                          = output_handle() unless @ARGV;
*STDERR                          = output_handle() unless @ARGV;

### start with fresh sources ###
ok( $cb->reload_indices( update_source => 0 ),  
                                "Rebuilding trees" );

### set alternate install dir ###
### XXX rather pointless, since we can't uninstall them, due to a bug
### in EU::Installed (6871). And therefor we can't test uninstall() or any of
### the EU::Installed functions. So, let's just install into sitelib... =/
#my $prefix  = File::Spec->rel2abs( File::Spec->catdir(cwd(),'dummy-perl') );
#my $rv = $cb->configure_object->set_conf( makemakerflags => "PREFIX=$prefix" );       
#ok( $rv,                        "Alternate install path set" );

### enable signature checks ###
ok( $conf->set_conf( signature => 1 ),
                                "Enabling signature checks" );

my $mod = $cb->module_tree('Text::Bastardize');

### format_available tests ###
{   ok( CPANPLUS::Dist::MM->format_available,
                                "Format is available" );
    
    ### whitebox test!
    {   local $^W;
        local *CPANPLUS::Dist::MM::can_load = sub { 0 };
        ok(!CPANPLUS::Dist::MM->format_available,
                                "   Making format unavailable" );
    }
    
    ### test if the error got logged ok ###
    like( CPANPLUS::Error->stack_as_string,
          qr/You do not have .+?'CPANPLUS::Dist::MM' not available/s,
                                "   Format failure logged" );

    ### flush the stack ###
    CPANPLUS::Error->flush;       
}

ok( $mod->fetch,                "Fetching module" );
ok( $mod->extract,              "Extracting module" );

ok( $mod->test,                 "Testing module" );
ok( $mod->status->dist_cpan->status->test,  
                                "   Test success registered as status" );

ok( $mod->dist,                 "Building distribution" );
ok( $mod->status->dist_cpan,    "   Dist registered as status" );
isa_ok( $mod->status->dist_cpan,    "CPANPLUS::Dist::MM" );

### flush the lib cache 
### otherwise, cpanplus thinks the module's already installed
### since the blib is already in @INC
$cb->_flush( list => [qw|lib|] );

diag("\nSorry, installing into your real perl dir, rather than our test area");
diag('since ExtUtils::Installed does not probe for .packlists in other dirs');
diag('than those in %Config. See bug #6871 on rt.cpan.org for details');

SKIP: {

    skip(q[Probably no permissions to install, skipping], 10)
        if $noperms;
    
    ok( $mod->install( force =>1 ),
                                "Installing module" );
    ok( $mod->status->installed,"   Module installed according to status" );


    SKIP: {   ### EU::Installed tests ###
        skip("makemakerflags set -- probably EU::Installed tests will fail", 8)
            if $conf->get_conf('makemakerflags');

        skip("Old perl on cygwin detected -- tests will fail due to know bugs", 8) 
            if ON_OLD_CYGWIN;
    
        {   ### validate
            my @missing = $mod->validate;

            is_deeply( \@missing, [],
                                    "No missing files" );
        }
        
        {   ### files
            my @files = $mod->files;
            
            ### number of files may vary from OS to OS
            ok( scalar(@files),     "All files accounted for" );
            ok( grep( /Bastardize\.pm/, @files),
                                    "   Found the module" );
            
            ### XXX does this work on all OSs?
            #ok( grep( /man/, @files ),
            #                        "   Found the manpage" );                                        
        }       
         
        {   ### packlist 
            my ($obj) = $mod->packlist;
            isa_ok( $obj,           "ExtUtils::Packlist" );
        }
        
        {   ### directory_tree
            my @dirs = $mod->directory_tree;
            ok( scalar(@dirs),      "Directory tree obtained" );
            
            my $found;
            for my $dir (@dirs) {
                ok( -d $dir,        "   Directory exists" );
                
                my $file = File::Spec->catfile( $dir, "Bastardize.pm" );  
                $found = $file if -e $file;
            }
            
            ok( -e $found,          "   Module found" );
        }                                
    
        SKIP: {
            skip("Probably no permissions to uninstall", 1)
                if $noperms;
        
            ok( $mod->uninstall,    "Uninstalling module" );
        }
    }
}

### test exceptions in Dist::MM->create ###
{   ok( $mod->status->mk_flush, "Old status info flushed" );
    my $dist = CPANPLUS::Dist->new( module => $mod,
                                    format => 'makemaker' );
                                    
    ok( $dist,                  "New dist object made" );
    ok(!$dist->create,          "   Dist->create failed" );
    like( CPANPLUS::Error->stack_as_string, qr/No dir found to operate on/s,
                                "   Failure logged" );

    ### manually set the extract dir ###
    $mod->status->extract($0);
    
    ok(!$dist->create,          "   Dist->create failed" );                                 
    like( CPANPLUS::Error->stack_as_string, qr/Could not chdir/s,
                                "   Failure logged" );
}



### writemakefile.pl tests ###
{   ### remove old status info
    ok( $mod->status->mk_flush, "Old status info flushed" );
    ok( $mod->fetch,            "Module fetched again" );
    ok( $mod->extract,          "Module extracted again" );
    
    ### cheat and add fake prereqs ###
    $mod->status->prereqs( { strict => '0.001', Carp => '0.002' } );

    my $makefile_pl = MAKEFILE_PL->( $mod->status->extract );
    my $dist        = $mod->dist;
    ok( $dist,                  "Dist object built" );

    ### check for a makefile.pl and 'write' one
    ok( -s $makefile_pl,        "   Makefile.PL present" );
    ok( $dist->write_makefile_pl( force => 0 ),
                                "   Makefile.PL written" );
    like( CPANPLUS::Error->stack_as_string, qr/Already created/,
                                "   Prior existance noted" );

    ### ok, unlink the makefile.pl, now really write one 
    ok( unlink($makefile_pl),   "Deleting Makefile.PL");
    ok( !-s $makefile_pl,       "   Makefile.PL deleted" );
    ok($dist->write_makefile_pl,"   Makefile.PL written" );
    
    ### see if we wrote anything sensible 
    my $fh = OPEN_FILE->( $makefile_pl );
    ok( $fh,                    "Makefile.PL open for read" );

    my $str = do { local $/; <$fh> };
    like( $str, qr/### Auto-generated .+ by CPANPLUS ###/,
                                "   Autogeneration noted" );
    like( $str, '/'. $mod->module .'/',
                                "   Contains module name" );
    like( $str, '/'. quotemeta($mod->version) . '/',       
                                "   Contains version" );
    like( $str, '/'. $mod->author->author .'/',
                                "   Contains author" );
    like( $str, '/PREREQ_PM/',  "   Contains prereqs" );
    like( $str, qr/Carp.+0.002/,"   Contains prereqs" );
    like( $str, qr/strict.+001/,"   Contains prereqs" );
    
    close $fh;

    ### seems ok, now delete it again and go via install()
    ### to see if it picks up on the missing makefile.pl and 
    ### does the right thing 
    ok( unlink($makefile_pl),   "Deleting Makefile.PL");
    ok( !-s $makefile_pl,       "   Makefile.PL deleted" );
    ok( $dist->status->mk_flush,"Dist status flushed" );
    ok( $dist->create,          "   Dist->create run again" );
    ok( -s $makefile_pl,        "   Makefile.PL present" );
    like( CPANPLUS::Error->stack_as_string,
          qr/attempting to generate one/,
                                "   Makefile.PL generation attempt logged" );

    ### now let's throw away the makefile.pl, flush the status and not
    ### write a makefile.pl
    {   local $^W;
        local *CPANPLUS::Dist::MM::write_makefile_pl = sub { 1 };
    
        unlink $makefile_pl;
        ok(!-s $makefile_pl,        "Makefile.PL deleted" );
        ok( $dist->status->mk_flush,"Dist status flushed" );
        ok(!$dist->create,          "   Dist->create failed" );
        like( CPANPLUS::Error->stack_as_string, 
              qr/Could not find 'Makefile.PL'/i,
                                    "   Missing Makefile.PL noted" );
        is( $dist->status->makefile, 0,
                                    "   Did not manage to create Makefile" );
    }

    ### now let's write a makefile.pl that just does 'die'
    {   local $^W;
        local *CPANPLUS::Dist::MM::write_makefile_pl = sub {  
                my $dist = shift; my $self = $dist->parent;
                my $fh = OPEN_FILE->( 
                            MAKEFILE_PL->($self->status->extract), '>' );
                print $fh "die '$0'";
                close $fh;
            };
    
        ### there's no makefile.pl now, since the previous test failed
        ### to create one
        #ok( -e $makefile_pl,        "Makefile.PL exists" );
        #ok( unlink($makefile_pl),   "   Deleting Makefile.PL");
        ok(!-s $makefile_pl,        "Makefile.PL deleted" );
        ok( $dist->status->mk_flush,"Dist status flushed" );
        ok(!$dist->create,          "   Dist->create failed" );    
        like( CPANPLUS::Error->stack_as_string, qr/Could not run/s,
                                    "   Logged failed 'perl Makefile.PL'" );
        is( $dist->status->makefile, 0,
                                    "   Did not manage to create Makefile" );    
    }
    
    ### clean up afterwards ###
    ok( unlink($makefile_pl),   "Deleting Makefile.PL");
    $dist->status->mk_flush;

}


# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:


