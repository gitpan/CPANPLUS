package CPANPLUS::Internals::Constants::Deb;

use strict;
use CPANPLUS::Error;
use CPANPLUS::Internals::Constants;

use IPC::Cmd                    qw[can_run];
use File::Spec;
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';

BEGIN {

    require Exporter;
    use vars    qw[$VERSION @ISA @EXPORT];
  
    $VERSION    = 0.01;
    @ISA        = qw[Exporter];
    @EXPORT     = qw[   DEB_URGENCY DEB_CHANGELOG DEB_COMPAT DEB_RULES 
                        DEB_CONTROL DEB_PACKAGE_NAME DEB_LICENSE_GPL
                        DEB_LICENSE_ARTISTIC DEB_STANDARD_COPYRIGHT_PERL
                        DEB_VERSION DEB_STANDARDS_VERSION DEB_DEBHELPER
                        DEB_DEBIAN_DIR DEB_COPYRIGHT DEB_PERL_DEPENDS
                        DEB_RULES_ARCH DEB_DEB_FILE_NAME DEB_ARCHITECTURE
                        DEB_RULES_MM_NOXS_CONTENT DEB_BIN_BUILDPACKAGE
                        DEB_RULES_MM_XS_CONTENT DEB_RULES_BUILD_XS_CONTENT
                        DEB_RULES_BUILD_NOXS_CONTENT DEB_GET_RULES_CONTENT
                ];
}

use constant DEB_DEBIAN_DIR     => sub { File::Spec->catfile( @_,
                                            'debian' )
                                };
use constant DEB_CHANGELOG      => sub { File::Spec->catfile( @_,
                                            DEB_DEBIAN_DIR->(), 'changelog' )
                                };                   
use constant DEB_COMPAT         => sub { File::Spec->catfile( @_,
                                            DEB_DEBIAN_DIR->(), 'compat' )
                                };
use constant DEB_CONTROL        => sub { File::Spec->catfile( @_,
                                            DEB_DEBIAN_DIR->(), 'control' )
                                };
use constant DEB_RULES          => sub { File::Spec->catfile( @_,
                                            DEB_DEBIAN_DIR->(), 'rules' )
                                };
use constant DEB_COPYRIGHT      => sub { File::Spec->catfile( @_,
                                            DEB_DEBIAN_DIR->(), 'copyright' )
                                };
use constant DEB_ARCHITECTURE   => sub { my $arch = 
                                         `dpkg-architecture -qDEB_BUILD_ARCH`;
                                         chomp $arch; return $arch;
                                };

use constant DEB_BIN_BUILDPACKAGE
                                => sub {my $p = can_run('dpkg-buildpackage');
                                        unless( $p ) {
                                            error(loc(
                                                "Could not find '%1' in your ".
                                                "path --unable to genearte ".
                                                "debian archives",
                                                'dpkg-buildpackage' ));
                                            return;
                                        }
                                        return $p;
                                };                       
                                                
                                
use constant DEB_PACKAGE_NAME   => sub {my $mod = shift or return; 
                                        my $pkg = lc $mod->package_name;
                                        return 'lib' . $pkg . '-perl';
                                };          
use constant DEB_VERSION        => sub {my $mod = shift or return;
                                        return $mod->version . '-1';
                                };    
use constant DEB_RULES_ARCH     => sub { return shift() ? 'any' : 'all'; };
use constant DEB_DEB_FILE_NAME  => sub {my $mod = shift() or return;
                                        my $dir = shift() or return;
                                        my $xs  = shift() ? 1 : 0;
                                        my $arch = $xs
                                            ? DEB_ARCHITECTURE->()
                                            : DEB_RULES_ARCH->();
                                            
                                        my $name = join '_',
                                            DEB_PACKAGE_NAME->($mod),
                                            DEB_VERSION->($mod), 
                                            $arch .'.deb';
                                        return File::Spec->catfile(
                                                $dir, $name 
                                            );      
                                };
use constant DEB_LICENSE_GPL    => '/usr/share/common-licenses/GPL';
use constant DEB_LICENSE_ARTISTIC
                                => '/usr/share/common-licenses/Artistic';
                                
use constant DEB_URGENCY        => 'urgency=low';
use constant DEB_DEBHELPER      => 'debhelper (>= 4.0.2)';
use constant DEB_PERL_DEPENDS   => '${perl:Depends}, ${misc:Depends}';
use constant DEB_STANDARDS_VERSION
                                => '3.6.1';
                                
use constant DEB_STANDARD_COPYRIGHT_PERL =>
    "This library is free software; you can redistribute it and/or modify\n" .
    "it under the same terms as Perl itself (GPL or Artistic license).\n\n" .
    "On Debian systems the complete text of the GPL and Artistic\n" .
    "licenses can be found at:\n\t" . 
    DEB_LICENSE_GPL . "\n\t" . DEB_LICENSE_ARTISTIC;

use constant DEB_GET_RULES_CONTENT  => 
                                    sub {my $self    = shift;
                                         my $has_xs  = shift;
                                         my $verbose = shift || 0;
                                         my $inst    = 
                                                $self->status->inxtaller_type;
                                           
                                         my $sub = $inst eq INSTALLER_BUILD       
                                            ? $has_xs
                                                ? 'DEB_RULES_BUILD_XS_CONTENT'
                                                : 'DEB_RULES_BUILD_NOXS_CONTENT'
                                            : $has_xs
                                                ? 'DEB_RULES_MM_XS_CONTENT'
                                                : 'DEB_RULES_MM_NOXS_CONTENT';
                                         
                                         msg(loc("Using rule set '%1'", $sub),
                                                $verbose);
                                                
                                         ### returns a coderef to a coderef
                                         my $code = __PACKAGE__->can($sub);
                                         return $code->()->();
                                    };         


use constant DEB_RULES_MM_NOXS_CONTENT  => 
                                    sub {
                                        return q[#!/usr/bin/make -f
# This debian/rules file is provided as a template for normal perl
# packages. It was created by Marc Brockschmidt <marc@dch-faq.de> for
# the Debian Perl Group (http://pkg-perl.alioth.debian.org/) but may
# be used freely wherever it is useful.

# Uncomment this to turn on verbose mode.
#export DH_VERBOSE=1

# If set to a true value then MakeMaker's prompt function will
# always return the default without waiting for user input.
export PERL_MM_USE_DEFAULT=1

PACKAGE=$(shell dh_listpackages)

ifndef PERL
PERL = /usr/bin/perl
endif

TMP	=$(CURDIR)/debian/$(PACKAGE)

# Allow disabling build optimation by setting noopt in
# $DEB_BUILD_OPTIONS
CFLAGS = -Wall -g
ifneq (,$(findstring noopt,$(DEB_BUILD_OPTIONS)))
	CFLAGS += -O0
else
	CFLAGS += -O2
endif

build: build-stamp
build-stamp:
	dh_testdir

	# Add commands to compile the package here
	$(PERL) Makefile.PL INSTALLDIRS=vendor
	$(MAKE) OPTIMIZE="$(CFLAGS)"

	touch build-stamp

clean:
	dh_testdir
	dh_testroot

	# Add commands to clean up after the build process here
	-$(MAKE) distclean

	dh_clean build-stamp install-stamp

install: install-stamp
install-stamp: build-stamp
	dh_testdir
	dh_testroot
	dh_clean -k

	#$(MAKE) test
	$(MAKE) install DESTDIR=$(TMP) PREFIX=/usr

	# As this is a architecture independent package, we are not supposed to install
	# stuff to /usr/lib. MakeMaker creates the dirs, we delete them from the deb:
	rmdir --ignore-fail-on-non-empty --parents $(TMP)/usr/lib/perl5

	touch install-stamp

binary-arch:
# We have nothing to do by default.

binary-indep: build install
	dh_testdir
	dh_testroot
#	dh_installcron
#	dh_installmenu
#	dh_installexamples
### XXX PROBE
#	dh_installdocs #DOCS#
#	dh_installchangelogs #CHANGES#
	dh_perl
	dh_link
	dh_strip
	dh_compress
	dh_fixperms
	dh_installdeb
	dh_gencontrol
	dh_md5sums
	dh_builddeb

source diff:								      
	@echo >&2 'source and diff are obsolete - use dpkg-source -b'; false

binary: binary-indep binary-arch
.PHONY: build clean binary-indep binary-arch binary

];
                            };                                    
                                    
use constant DEB_RULES_MM_XS_CONTENT   
                                => sub {
                                    return q[#!/usr/bin/make -f
# This debian/rules file is provided as a template for normal perl
# packages. It was created by Marc Brockschmidt <marc@dch-faq.de> for
# the Debian Perl Group (http://pkg-perl.alioth.debian.org/) but may
# be used freely wherever it is useful.

# Uncomment this to turn on verbose mode.
#export DH_VERBOSE=1

# If set to a true value then MakeMaker's prompt function will
# always return the default without waiting for user input.
export PERL_MM_USE_DEFAULT=1

PACKAGE=$(shell dh_listpackages)

ifndef PERL
PERL = /usr/bin/perl
endif

TMP	=$(CURDIR)/debian/$(PACKAGE)

# Allow disabling build optimation by setting noopt in
# $DEB_BUILD_OPTIONS
CFLAGS = -Wall -g
ifneq (,$(findstring noopt,$(DEB_BUILD_OPTIONS)))
	CFLAGS += -O0
else
	CFLAGS += -O2
endif

build: build-stamp
build-stamp:
	dh_testdir

	# Add commands to compile the package here
	$(PERL) Makefile.PL INSTALLDIRS=vendor
	$(MAKE) OPTIMIZE="$(CFLAGS)" LD_RUN_PATH=""

	touch build-stamp

clean:
	dh_testdir
	dh_testroot

	# Add commands to clean up after the build process here
	-$(MAKE) realclean

	dh_clean build-stamp install-stamp

install: install-stamp
install-stamp:
	dh_testdir
	dh_testroot
	dh_clean -k

	# Add here commands to install the package into debian/tmp.
	#$(MAKE) test
	$(MAKE) install DESTDIR=$(TMP) PREFIX=/usr

	# As this is a architecture dependent package, we are not supposed to install
	# stuff to /usr/share/perl5. MakeMaker creates the dirs, we delete them from 
	# the deb:
	rmdir --ignore-fail-on-non-empty --parents $(TMP)/usr/share/perl5

	touch install-stamp

# Build architecture-independent files here.
binary-indep: build install
# We have nothing to do by default.

# Build architecture-dependent files here.
binary-arch: build install
	dh_testdir
	dh_testroot
### XXX PROBE	     
#	dh_installdocs #DOCS#
	dh_installexamples 
#	dh_installmenu
#	dh_installcron
#	dh_installman

### XXX PROBE
#	dh_installchangelogs #CHANGES#
	dh_link
ifeq (,$(findstring nostrip,$(DEB_BUILD_OPTIONS)))
	dh_strip
endif
	dh_compress
	dh_fixperms
	dh_makeshlibs
	dh_installdeb
	dh_perl 
	dh_shlibdeps
	dh_gencontrol
	dh_md5sums
	dh_builddeb

source diff:								      
	@echo >&2 'source and diff are obsolete - use dpkg-source -b'; false

binary: binary-indep binary-arch
.PHONY: build clean binary-indep binary-arch binary

];  
                                };

use constant DEB_RULES_BUILD_NOXS_CONTENT   => sub {
                                    return q[#!/usr/bin/make -f
# This debian/rules file is provided as a template for normal perl
# packages. It was created by Marc Brockschmidt <marc@dch-faq.de> for
# the Debian Perl Group (http://pkg-perl.alioth.debian.org/) but may
# be used freely wherever it is useful.

# Uncomment this to turn on verbose mode.
#export DH_VERBOSE=1

# If set to a true value then MakeMaker's prompt function will
# always return the default without waiting for user input.
export PERL_MM_USE_DEFAULT=1

PACKAGE=$(shell dh_listpackages)

ifndef PERL
PERL = /usr/bin/perl
endif

BUILD = ./Build

TMP	= $(CURDIR)/debian/$(PACKAGE)

# Allow disabling build optimation by setting noopt in
# $DEB_BUILD_OPTIONS
CFLAGS = -Wall -g
ifneq (,$(findstring noopt,$(DEB_BUILD_OPTIONS)))
	CFLAGS += -O0
else
	CFLAGS += -O2
endif

build: build-stamp
build-stamp:
	dh_testdir

	# Add commands to compile the package here
	$(PERL) -MCPANPLUS::inc Build.PL install installdirs=vendor
	
	### no optimize flags here?
	#$(MAKE) OPTIMIZE="$(CFLAGS)"
	$(BUILD) 

	touch build-stamp

clean:
	dh_testdir
	dh_testroot

	# Add commands to clean up after the build process here
	-$(Build) distclean

	dh_clean build-stamp install-stamp

install: install-stamp
install-stamp: build-stamp
	dh_testdir
	dh_testroot
	dh_clean -k

	#$(PERL) Build test
	-$(BUILD) distclean
	$(BUILD) install destdir=$(TMP)

	# As this is a architecture independent package, we are not supposed to install
	# stuff to /usr/lib. MakeMaker creates the dirs, we delete them from the deb:
	rmdir --ignore-fail-on-non-empty --parents $(TMP)/usr/lib/perl5

	touch install-stamp

binary-arch:
# We have nothing to do by default.

binary-indep: build install
	dh_testdir
	dh_testroot
#	dh_installcron
#	dh_installmenu
#	dh_installexamples
### XXX PROBE
#	dh_installdocs #DOCS#
#	dh_installchangelogs #CHANGES#
	dh_perl
	dh_link
	dh_strip
	dh_compress
	dh_fixperms
	dh_installdeb
	dh_gencontrol
	dh_md5sums
	dh_builddeb

source diff:								      
	@echo >&2 'source and diff are obsolete - use dpkg-source -b'; false

binary: binary-indep binary-arch
.PHONY: build clean binary-indep binary-arch binary

];
                            };     

use constant DEB_RULES_BUILD_XS_CONTENT   => sub { 
                                    return q[#!/usr/bin/make -f
# This debian/rules file is provided as a template for normal perl
# packages. It was created by Marc Brockschmidt <marc@dch-faq.de> for
# the Debian Perl Group (http://pkg-perl.alioth.debian.org/) but may
# be used freely wherever it is useful.

# Uncomment this to turn on verbose mode.
#export DH_VERBOSE=1

# If set to a true value then MakeMaker's prompt function will
# always return the default without waiting for user input.
export PERL_MM_USE_DEFAULT=1

PACKAGE=$(shell dh_listpackages)

ifndef PERL
PERL = /usr/bin/perl
endif

TMP	= $(CURDIR)/debian/$(PACKAGE)

BUILD = ./Build

# Allow disabling build optimation by setting noopt in
# $DEB_BUILD_OPTIONS
CFLAGS = -Wall -g
ifneq (,$(findstring noopt,$(DEB_BUILD_OPTIONS)))
	CFLAGS += -O0
else
	CFLAGS += -O2
endif

build: build-stamp
build-stamp:
	dh_testdir

	# Add commands to compile the package here
	$(PERL) -MCPANPLUS::inc Build.PL installdirs=vendor extra_compiler_flags="$(CFLAGS)"
	$(BUILD)

	touch build-stamp

clean:
	dh_testdir
	dh_testroot

	# Add commands to clean up after the build process here
	-$(BUILD) realclean

	dh_clean build-stamp install-stamp

install: install-stamp
install-stamp:
	dh_testdir
	dh_testroot
	dh_clean -k

	# Add here commands to install the package into debian/tmp.
	#$(MAKE) test
	$(BUILD) install destdir=$(TMP)

	# As this is a architecture dependent package, we are not supposed to install
	# stuff to /usr/share/perl5. MakeMaker creates the dirs, we delete them from 
	# the deb:
	rmdir --ignore-fail-on-non-empty --parents $(TMP)/usr/share/perl5

	touch install-stamp

# Build architecture-independent files here.
binary-indep: build install
# We have nothing to do by default.

# Build architecture-dependent files here.
binary-arch: build install
	dh_testdir
	dh_testroot
### XXX PROBE	     
#	dh_installdocs #DOCS#
	dh_installexamples 
#	dh_installmenu
#	dh_installcron
#	dh_installman

### XXX PROBE
#	dh_installchangelogs #CHANGES#
	dh_link
ifeq (,$(findstring nostrip,$(DEB_BUILD_OPTIONS)))
	dh_strip
endif
	dh_compress
	dh_fixperms
	dh_makeshlibs
	dh_installdeb
	dh_perl 
	dh_shlibdeps
	dh_gencontrol
	dh_md5sums
	dh_builddeb

source diff:								      
	@echo >&2 'source and diff are obsolete - use dpkg-source -b'; false

binary: binary-indep binary-arch
.PHONY: build clean binary-indep binary-arch binary

];  
                                };

1;
