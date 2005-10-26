package CPANPLUS::Internals::Constants;

use strict;
use CPANPLUS::inc;
use CPANPLUS::Error;

use File::Spec;
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';

### for the version number ###
require CPANPLUS::Internals;


BEGIN {

    require Exporter;
    use vars    qw[$VERSION @ISA @EXPORT];
  
    $VERSION    = 0.01;
    @ISA        = qw[Exporter];
    @EXPORT     = qw[   
                    FILE_EXISTS FILE_READABLE DIR_EXISTS IS_MODOBJ IS_AUTHOBJ 
                    MAKEFILE MAKEFILE_PL BUILD_PL PREREQ_BUILD    
                    IS_FAKE_MODOBJ IS_FAKE_AUTHOBJ README CHECKSUMS OPEN_FILE
                    PGP_HEADER ENV_CPANPLUS_CONFIG DEFAULT_EMAIL DOT_CPANPLUS
                    CPANPLUS_UA TESTERS_URL TESTERS_DETAILS_URL BLIB ARCH LIB
                    DOT_SHELL_DEFAULT_RC PREREQ_INSTALL PREREQ_ASK IS_CONFOBJ 
                    PREREQ_IGNORE BOOLEANS CALLING_FUNCTION IS_RVOBJ LIB_DIR
                    ARCH_DIR DOT_EXISTS AUTO LIB_AUTO_DIR ARCH_AUTO_DIR    
                    PERL_CORE IS_INTERNALS_OBJ IS_CODEREF CREATE_FILE_URI   
                    STRIP_GZ_SUFFIX BLIB_LIBDIR GET_XS_FILES INSTALLER_BUILD
                    INSTALLER_MM ON_OLD_CYGWIN IS_FILE IS_DIR INSTALLER_SAMPLE
                    INSTALL_VIA_PACKAGE_MANAGER TARGET_CREATE TARGET_PREPARE
                    TARGET_INSTALL TARGET_IGNORE OPT_AUTOFLUSH 
                    UNKNOWN_DL_LOCATION
                ];
}

use constant INSTALLER_BUILD
                            => 'CPANPLUS::Dist::Build';
use constant INSTALLER_MM   => 'CPANPLUS::Dist::MM';    
use constant INSTALLER_SAMPLE   
                            => 'CPANPLUS::Dist::Sample';

use constant TARGET_CREATE  => 'create';
use constant TARGET_PREPARE => 'prepare';
use constant TARGET_INSTALL => 'install';
use constant TARGET_IGNORE  => 'ignore';

use constant OPT_AUTOFLUSH  => '-MCPANPLUS::Internals::Utils::Autoflush';

use constant UNKNOWN_DL_LOCATION
                            => 'UNKNOWN-ORIGIN';   

use constant INSTALL_VIA_PACKAGE_MANAGER 
                            => sub { my $fmt = $_[0] or return;
                                     return 1 if $fmt ne INSTALLER_BUILD and
                                                 $fmt ne INSTALLER_MM;
                            };                                                 

use constant IS_CODEREF     => sub { ref $_[-1] eq 'CODE' };
use constant IS_MODOBJ      => sub { UNIVERSAL::isa($_[-1], 
                                            'CPANPLUS::Module') }; 
use constant IS_FAKE_MODOBJ => sub { UNIVERSAL::isa($_[-1],
                                            'CPANPLUS::Module::Fake') };
use constant IS_AUTHOBJ     => sub { UNIVERSAL::isa($_[-1],
                                            'CPANPLUS::Module::Author') };
use constant IS_FAKE_AUTHOBJ
                            => sub { UNIVERSAL::isa($_[-1],
                                            'CPANPLUS::Module::Author::Fake') };

use constant IS_CONFOBJ     => sub { UNIVERSAL::isa($_[-1],
                                            'CPANPLUS::Configure') };

use constant IS_RVOBJ       => sub { UNIVERSAL::isa($_[-1],
                                            'CPANPLUS::Backend::RV') };
                                            
use constant IS_INTERNALS_OBJ
                            => sub { UNIVERSAL::isa($_[-1],
                                            'CPANPLUS::Internals') };                                            
                                            
use constant IS_FILE        => sub { return 1 if -e $_[-1] };                                            

use constant FILE_EXISTS    => sub {  
                                    my $file = $_[-1];
                                    return 1 if IS_FILE->($file);
                                    local $Carp::CarpLevel = 
                                            $Carp::CarpLevel+2;
                                    error(loc(  q[File '%1' does not exist],
                                                $file));
                                    return;
                            };    

use constant FILE_READABLE  => sub {  
                                    my $file = $_[-1];
                                    return 1 if -e $file && -r _;
                                    local $Carp::CarpLevel = 
                                            $Carp::CarpLevel+2;
                                    error( loc( q[File '%1' is not readable ].
                                                q[or does not exist], $file));
                                    return;
                            };    
use constant IS_DIR         => sub { return 1 if -d $_[-1] };

use constant DIR_EXISTS     => sub { 
                                    my $dir = $_[-1];
                                    return 1 if IS_DIR->($dir);
                                    local $Carp::CarpLevel = 
                                            $Carp::CarpLevel+2;                                    
                                    error(loc(q[Dir '%1' does not exist],
                                            $dir));
                                    return;
                            };   

use constant MAKEFILE_PL    => sub { return @_
                                        ? File::Spec->catfile( $_[0],
                                                            'Makefile.PL' )
                                        : 'Makefile.PL';
                            };                   
use constant MAKEFILE       => sub { return @_
                                        ? File::Spec->catfile( $_[0],
                                                            'Makefile' )
                                        : 'Makefile';
                            }; 
use constant BUILD_PL       => sub { return @_
                                        ? File::Spec->catfile( $_[0],
                                                            'Build.PL' )
                                        : 'Build.PL';
                            };
                            
use constant BLIB           => sub { return @_
                                        ? File::Spec->catfile($_[0], 'blib')
                                        : 'blib';
                            };                  

use constant LIB            => 'lib';
use constant LIB_DIR        => sub { return @_
                                        ? File::Spec->catdir($_[0], LIB)
                                        : LIB;
                            }; 
use constant AUTO           => 'auto';                            
use constant LIB_AUTO_DIR   => sub { return @_
                                        ? File::Spec->catdir($_[0], LIB, AUTO)
                                        : File::Spec->catdir(LIB, AUTO)
                            }; 
use constant ARCH           => 'arch';
use constant ARCH_DIR       => sub { return @_
                                        ? File::Spec->catdir($_[0], ARCH)
                                        : ARCH;
                            }; 
use constant ARCH_AUTO_DIR  => sub { return @_
                                        ? File::Spec->catdir($_[0],ARCH,AUTO)
                                        : File::Spec->catdir(ARCH,AUTO)
                            };                            

use constant BLIB_LIBDIR    => sub { return @_
                                        ? File::Spec->catdir(
                                                $_[0], BLIB->(), LIB )
                                        : File::Spec->catdir( BLIB->(), LIB );
                            };  
use constant README         => sub { my $obj = $_[0];
                                     my $pkg = $obj->package_name;
                                     $pkg .= '-' . $obj->package_version .
                                             '.readme';
                                     return $pkg;
                            };
use constant OPEN_FILE      => sub {
                                    my($file, $mode) = (@_, '');
                                    my $fh;
                                    open $fh, "$mode" . $file
                                        or error(loc(
                                            "Could not open file '%1': %2",
                                             $file, $!));
                                    return $fh if $fh;
                                    return;
                            };      
                            
use constant STRIP_GZ_SUFFIX 
                            => sub {
                                    my $file = $_[0] or return;
                                    $file =~ s/.gz$//i;
                                    return $file;
                            };            
                                        
use constant CHECKSUMS      => 'CHECKSUMS';
use constant PGP_HEADER     => '-----BEGIN PGP SIGNED MESSAGE-----';
use constant ENV_CPANPLUS_CONFIG
                            => 'PERL5_CPANPLUS_CONFIG';
use constant DEFAULT_EMAIL  => 'cpanplus@example.com';   
use constant DOT_CPANPLUS   => $^O eq 'VMS' ? '_cpanplus' : '.cpanplus';         
use constant CPANPLUS_UA    => sub { "CPANPLUS/$CPANPLUS::Internals::VERSION" };
use constant TESTERS_URL    => sub {
                                    "http://testers.cpan.org/show/" .
                                    $_[0] .".yaml" 
                                };
use constant TESTERS_DETAILS_URL
                            => sub {
                                    'http://testers.cpan.org/show/' .
                                    $_[0] . '.html';
                                };         

use constant CREATE_FILE_URI    
                            => sub { 
                                    my $dir = $_[0] or return;
                                    return $dir =~ m|^/| 
                                        ? 'file:/'  . $dir
                                        : 'file://' . $dir;   
                            };        

use constant DOT_SHELL_DEFAULT_RC
                            => '.shell-default.rc';

use constant PREREQ_IGNORE  => 0;                
use constant PREREQ_INSTALL => 1;
use constant PREREQ_ASK     => 2;
use constant PREREQ_BUILD   => 3;
use constant BOOLEANS       => [0,1];
use constant CALLING_FUNCTION   
                            => sub { my $lvl = $_[0] || 0;
                                     return join '::', (caller(2+$lvl))[3] 
                                };
use constant DOT_EXISTS     => '.exists';     
use constant PERL_CORE      => 'perl';

use constant GET_XS_FILES   => sub { my $dir = $_[0] or return;
                                     require File::Find;
                                     my @files;
                                     File::Find::find( 
                                        sub { push @files, $File::Find::name
                                                if $File::Find::name =~ /\.xs$/i
                                        }, $dir );
                                           
                                     return @files;
                                };  

use constant ON_OLD_CYGWIN  => do { $^O eq 'cygwin' and $] < 5.008 
                                    ? loc("Your perl version for %1 is too low; ".
                                            "Require %2 or higher for this function",
                                            $^O, '5.8.0' )
                                    : '';                                                                           
                                };
1;              

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
