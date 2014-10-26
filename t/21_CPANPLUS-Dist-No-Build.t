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

BEGIN { require 'conf.pl'; }

use strict;
use Test::More 'no_plan';

use CPANPLUS::Dist;
use CPANPLUS::Backend;
use CPANPLUS::Module::Fake;
use CPANPLUS::Module::Author::Fake;
use CPANPLUS::Internals::Constants;

my $Conf    = gimme_conf();
my $CB      = CPANPLUS::Backend->new( $Conf );

### set the config so that we will ignore the build installer,
### but prefer it anyway
{   CPANPLUS::Dist->_ignore_dist_types( INSTALLER_BUILD );
    $Conf->set_conf( prefer_makefile => 0 );
}

### create a fake object, so we don't use the actual module tree
my $Mod = CPANPLUS::Module::Fake->new(
                module  => 'Foo::Bar',
                path    => File::Spec->catdir(qw[src Build noxs]),
                author  => CPANPLUS::Module::Author::Fake->new,
                package => 'Foo-Bar-0.01.tar.gz',
            );
ok( $Mod,                   "Module object created" );        
ok( not grep { $_ eq INSTALLER_BUILD } CPANPLUS::Dist->dist_types,
                            "   Build installer not returned" );
            
            
### set the fetch location -- it's local
{   my $where = File::Spec->rel2abs(
                        File::Spec->catdir( $Mod->path, $Mod->package )
                    );
                    
    $Mod->status->fetch( $where );

    ok( -e $where,          "   Tarball '$where' exists" );
}
    
### extract it, silence warnings/messages    
{   local $CPANPLUS::Error::MSG_FH   = output_handle();    
    local $CPANPLUS::Error::ERROR_FH = output_handle();

    my $where = $Mod->extract;
    ok( -e $where,          "   Tarball extracted to '$where'" );
}

### check the installer type 
{   is( $Mod->status->installer_type, INSTALLER_MM, 
                            "Proper installer type found" );

    my $err = CPANPLUS::Error->stack_as_string;
    like( $err, '/'.INSTALLER_MM.'/',
                            "   Error mentions " . INSTALLER_MM );
    like( $err, '/'.INSTALLER_BUILD.'/',
                            "   Error mentions " . INSTALLER_BUILD );
    like( $err, qr/but might not be able to install/,
                            "   Error mentions install warning" );
}

END { 1 while unlink output_file()  }
