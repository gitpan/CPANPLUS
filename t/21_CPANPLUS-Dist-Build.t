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
use CPANPLUS::Dist::Build;

use Config;
use Test::More 'no_plan';
use Data::Dumper;
use File::Basename ();

BEGIN { require 'conf.pl'; }

my $conf    = gimme_conf();
my $cb      = CPANPLUS::Backend->new( $conf );
my $has_mb  = eval { require Module::Build; 1 };
my $noperms = ($< and not $conf->get_program('sudo')) &&
              ($conf->get_conf('makemakerflags') or 
                not -w $Config{installsitelib} );

### don't start sending test reports now... ###
$cb->_callbacks->send_test_report( sub { 0 } );
$conf->set_conf( cpantest => 0 );

### start with fresh sources ###
ok( $cb->reload_indices( update_source => 0 ),  
                                "Rebuilding trees" );

### set alternate install dir ###
### XXX this doesn't quite work yet =/ ###
### XXX this means that the uninstall test will fail too for now ###
if(0){   
    my $dir     = File::Spec->rel2abs(File::Basename::dirname($0));
    my $lib     = File::Spec->catdir( $dir, qw[dummy-perl lib] );
    my $man3    = File::Spec->catdir( $dir, qw[dummy-perl man man3] );
    my $man1    = File::Spec->catdir( $dir, qw[dummy-perl man man1] );
    
    my $rv = $cb->configure_object->set_conf( 
                    key => val,         
                );       

    die q[Could not set alternate install path -- aborting!] unless $rv;
}    

my $mod = $cb->module_tree('Devel::Caller::Perl');

ok( $mod->fetch,    "Fetching module" );
ok( $mod->extract,  "Extracting module" );

### config might determine to use Makefile.PL instead 
### but to test M::B we need build.pl ;)
ok( $mod->get_installer_type( prefer_makefile => 0 ),
                                "Getting build installer type" );
is( $mod->status->installer_type, ($has_mb ? 'build' : 'makemaker'),
                                "   Proper installer type found" );    
                                    
ok( $mod->test,                 "Testing module" );
ok( $mod->status->dist_cpan->status->test,  
                                "   Test success registered as status" );

ok( $mod->dist,                 "Building distribution" );
ok( $mod->status->dist_cpan,    "   Dist registered as status" );
isa_ok( $mod->status->dist_cpan,    "CPANPLUS::Dist::Build" );

### flush the lib cache
### otherwise, cpanplus thinks the module's already installed
### since the blib is already in @INC
$cb->_flush( list => [qw|lib|] );


diag("\nSorry, installing into your real perl dir, rather than our test area");
diag('since Module::Builds API does not accept arguments to change this.');
diag('mail bug-module-build@rt.cpan.org if this upsets you');

SKIP: {
    skip(q[Probably no permissions to install, skipping], 2)
        if $noperms;

    ### force the install, make sure the Dist::Build->install() sub gets called
    ok( $mod->install( force => 1, verbose => 1 ),"Installing module" ); # 
    ok( $mod->status->installed,    "   Module installed according to status" );
}

### XXX can be removed when we have install into dummy dir working ###
SKIP: {
    skip(q[Can't uninstall: Module::Build writes no .packlist], 1);
    
    skip( "Probably no permission to uninstall", 1 ) if $noperms;

    ### XXX M::B doesn't seem to write into the .packlist...
    ### can't figure out what to uninstall then... 
    ok( $mod->uninstall,  "Uninstalling module" );
}

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
