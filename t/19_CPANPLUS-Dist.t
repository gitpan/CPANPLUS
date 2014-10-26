#!/usr/bin/perl -w

BEGIN { chdir 't' if -d 't' };

### this is to make devel::cover happy ###
BEGIN {
    use File::Spec;
    require lib;
    for (qw[../lib inc]) { my $l = 'lib'; $l->import(File::Spec->rel2abs($_)) }
}

### dummy class for testing dist api ###
BEGIN {

    package CPANPLUS::Dist::_Test;
    use strict;
    use vars qw[$Available $Create $Install $Init $Prepare @ISA];

    @ISA        = qw[CPANPLUS::Dist];
    $Available  = 1;
    $Create     = 1;
    $Install    = 1;
    $Init       = 1;
    $Prepare    = 1;

    require CPANPLUS::Dist;
    CPANPLUS::Dist->_add_dist_types( __PACKAGE__ );

    sub init                { $_[0]->status->mk_accessors( qw[prepared created installed
                                     _prepare_args _install_args _create_args]);
                              return $Init };
    sub format_available    { return $Available }
    sub prepare             { return shift->status->prepared($Prepare) }
    sub create              { return shift->status->created($Create) }
    sub install             { return shift->status->installed($Install) }
}

use strict;

use CPANPLUS::Configure;
use CPANPLUS::Backend;
use CPANPLUS::Internals::Constants;

use Test::More 'no_plan';
use Cwd;
use Data::Dumper;
use File::Basename ();
use File::Spec ();
use Module::Load::Conditional qw[check_install];

BEGIN { require 'conf.pl'; }

my $conf = gimme_conf();
my $cb   = CPANPLUS::Backend->new( $conf );

### Redirect errors to file ###
local $CPANPLUS::Error::ERROR_FH = output_handle() unless @ARGV;
local $CPANPLUS::Error::MSG_FH   = output_handle() unless @ARGV;

### obsolete
#my $Format = '_test';
my $Module = 'CPANPLUS::Dist::_Test';

### XXX this version doesn't exist, but we don't check for it either ###
my $Prereq = { 'Devel::Caller::Perl' => '1000' };

### since it's in this file, not in it's own module file,
### make M::L::C think it already was loaded
$Module::Load::Conditional::CACHE->{$Module}->{usable} = 1;


use_ok('CPANPLUS::Dist');

### start with fresh sources ###
ok( $cb->reload_indices( update_source => 0 ),
                                "Rebuilding trees" );

my $Mod  = $cb->module_tree('Text::Bastardize');
ok( $Mod,                       "Got module object" );



### register new format ###
{   my $ok = $conf->_add_dist( $Module => 1 );
    ok( $ok,                    "New dist format registered" );

    my $class = $conf->_get_dist($Module);
    ok( $class,                 "   Proper format found" );
}

### straight forward dist build - prepare, create, install
{   my $dist = CPANPLUS::Dist->new(
                            format  => $Module,
                            module  => $Mod
                        );

    ok( $dist,                  "New dist object created" );
    isa_ok( $dist,              'CPANPLUS::Dist' );
    isa_ok( $dist,              $Module );

    my $status = $dist->status;
    ok( $status,                "Status object found" );
    isa_ok( $status,            "Object::Accessor" );

    ok( $dist->prepare,         "Prepare call" );
    ok( $dist->status->prepared,"   Status registered OK" );

    ok( $dist->create,          "Create call" );
    ok( $dist->status->created, "   Status registered OK" );

    ok( $dist->install,         "Install call" );
    ok( $dist->status->installed,
                                "   Status registered OK" );
}

### check 'sanity check' option ###
{   local $CPANPLUS::Dist::_Test::Available = 0;

    ok( !$Module->format_available,
                                "Format availabillity turned off" );

    {   $conf->_set_build('sanity_check' => 0);

        my $dist = CPANPLUS::Dist->new(
                                format => $Module,
                                module => $Mod
                            );

        ok( $dist,              "Dist created with sanity check off" );
        isa_ok( $dist,          $Module );

    }

    {   $conf->_set_build('sanity_check' => 1);
        my $dist = CPANPLUS::Dist->new(
                                format => $Module,
                                module => $Mod
                            );

        ok( !$dist,             "Dist not created with sanity check on" );
        like( CPANPLUS::Error->stack_as_string,
                qr/Format '$Module' is not available/,
                                "   Error recorded as expected" );
    }
}

### undef the status hash, make sure it complains ###
{   local $CPANPLUS::Dist::_Test::Init = 0;

    my $dist = CPANPLUS::Dist->new(
                        format => $Module,
                        module => $Mod
                    );

    ok( !$dist,                 "No dist created by failed init" );
    like( CPANPLUS::Error->stack_as_string,
            qr/Dist initialization of '$Module' failed for/s,
                                "   Error recorded as expected" );
}

### test _resolve prereqs, in a somewhat simulated set of circumstances
{   my $old_prereq = $conf->get_conf('prereqs');
    my $Mod_prereq = 'Devel::Caller::Perl';

    my $map = {
        0 => {
            'Previous install failed' => [
                sub { $cb->module_tree($Mod_prereq)->status->installed(0);
                                                                'install' },
                sub { like( CPANPLUS::Error->stack_as_string,
                      qr/failed to install before in this session/s,
                            "   Previous install failed recorded ok" ) },
            ],

            "Set $Module->prepare to false" => [
                sub { $CPANPLUS::Dist::_Test::Prepare = 0;       'install' },
                sub { like( CPANPLUS::Error->stack_as_string,
                      qr/Unable to create a new distribution object/s,
                            "   Dist creation failed recorded ok" ) },
                sub { like( CPANPLUS::Error->stack_as_string,
                      qr/Failed to install '$Mod_prereq' as prerequisite/s,
                            "   Dist creation failed recorded ok" ) },
            ],

            "Set $Module->create to false" => [
                sub { $CPANPLUS::Dist::_Test::Create = 0;       'install' },
                sub { like( CPANPLUS::Error->stack_as_string,
                      qr/Unable to create a new distribution object/s,
                            "   Dist creation failed recorded ok" ) },
                sub { like( CPANPLUS::Error->stack_as_string,
                      qr/Failed to install '$Mod_prereq' as prerequisite/s,
                            "   Dist creation failed recorded ok" ) },
            ],

            "Set $Module->install to false" => [
                sub { $CPANPLUS::Dist::_Test::Install = 0;      'install' },
                sub { like( CPANPLUS::Error->stack_as_string,
                      qr/Failed to install '$Mod_prereq' as/s,
                            "   Dist installation failed recorded ok" ) },
            ],

            "Set dependency to be perl-core" => [
                sub { $cb->module_tree( $Mod_prereq )->package(
                                        'perl-5.8.1.tar.gz' );  'install' },
                sub { like( CPANPLUS::Error->stack_as_string,
                      qr/Prerequisite '$Mod_prereq' is perl-core/s,
                            "   Dist installation failed recorded ok" ) },
            ],
            'Simple ignore'     => [
                sub { 'ignore' },
                sub { ok( !$_[0]->status->prepared,
                            "   Module status says not prepared" ) },
                sub { ok( !$_[0]->status->created,
                            "   Module status says not created" ) },
                sub { ok( !$_[0]->status->installed,
                            "   Module status says not installed" ) },
            ],
            'Ignore from conf'  => [
                sub { $conf->set_conf(prereqs => PREREQ_IGNORE);    '' },
                sub { ok( !$_[0]->status->prepared,
                            "   Module status says not prepared" ) },
                sub { ok( !$_[0]->status->created,
                            "   Module status says not created" ) },
                sub { ok( !$_[0]->status->installed,
                            "   Module status says not installed" ) },
                ### set the conf back ###
                sub { $conf->set_conf(prereqs => PREREQ_INSTALL); },
            ],
        },
        1 => {
            'Simple create'     => [
                sub { 'create' },
                sub { ok( $_[0]->status->prepared,
                            "   Module status says prepared" ) },
                sub { ok( $_[0]->status->created,
                            "   Module status says created" ) },
                sub { ok( !$_[0]->status->installed,
                            "   Module status says not installed" ) },
            ],
            'Simple install'    => [
                sub { 'install' },
                sub { ok( $_[0]->status->prepared,
                            "   Module status says prepared" ) },
                sub { ok( $_[0]->status->created,
                            "   Module status says created" ) },
                sub { ok( $_[0]->status->installed,
                            "   Module status says installed" ) },
            ],

            'Install from conf' => [
                sub { $conf->set_conf(prereqs => PREREQ_INSTALL);   '' },
                sub { ok( $_[0]->status->prepared,
                            "   Module status says prepared" ) },
                sub { ok( $_[0]->status->created,
                            "   Module status says created" ) },
                sub { ok( $_[0]->status->installed,
                            "   Module status says installed" ) },
            ],
            'Create from conf'  => [
                sub { $conf->set_conf(prereqs => PREREQ_BUILD);     '' },
                sub { ok( $_[0]->status->prepared,
                            "   Module status says prepared" ) },
                sub { ok( $_[0]->status->created,
                            "   Module status says created" ) },
                sub { ok( !$_[0]->status->installed,
                            "   Module status says not installed" ) },
                ### set the conf back ###
                sub { $conf->set_conf(prereqs => PREREQ_INSTALL); },
            ],

            'Ask from conf'     => [
                sub { $cb->_register_callback(
                            name => 'install_prerequisite',
                            code => sub {1} );
                      $conf->set_conf(prereqs => PREREQ_ASK);       '' },
                sub { ok( $_[0]->status->prepared,
                            "   Module status says prepared" ) },
                sub { ok( $_[0]->status->created,
                            "   Module status says created" ) },
                sub { ok( $_[0]->status->installed,
                            "   Module status says installed" ) },
                ### set the conf back ###
                sub { $conf->set_conf(prereqs => PREREQ_INSTALL); },

            ],

            'Ask from conf, but decline' => [
                sub { $cb->_register_callback(
                            name => 'install_prerequisite',
                            code => sub {0} );
                      $conf->set_conf( prereqs => PREREQ_ASK);      '' },
                sub { ok( !$_[0]->status->installed,
                            "   Module status says not installed" ) },
                sub { like( CPANPLUS::Error->stack_as_string,
                      qr/Will not install prerequisite '$Mod_prereq' -- Note/,
                            "   Install skipped, recorded ok" ) },
                ### set the conf back ###
                sub { $conf->set_conf(prereqs => PREREQ_INSTALL); },
            ],

            "Set recursive dependency" => [
                sub { $cb->_status->pending_prereqs({ $Mod_prereq => 1 });
                                                                'install' },
                sub { like( CPANPLUS::Error->stack_as_string,
                      qr/Recursive dependency detected/,
                            "   Recursive dependency recorded ok" ) },
            ],

          },
    };

    for my $bool ( sort keys %$map ) {

        diag("Running ". ($bool?'success':'fail') . " tests") if @ARGV;

        my $href = $map->{$bool};
        while ( my($txt,$aref) = each %$href ) {

            ### reset everything ###
            ok( $cb->reload_indices( update_source => 0 ),
                                "Rebuilding trees" );

            $CPANPLUS::Dist::_Test::Available   = 1;
            $CPANPLUS::Dist::_Test::Prepare     = 1;
            $CPANPLUS::Dist::_Test::Create      = 1;
            $CPANPLUS::Dist::_Test::Install     = 1;

            CPANPLUS::Error->flush;
            $cb->_status->mk_flush;

            ### get a new dist from Text::Bastardize ###
            my $dist = CPANPLUS::Dist->new(
                        format => $Module,
                        module => $cb->module_tree('Text::Bastardize'),
                    );

            ### first sub returns target ###
            my $sub    = shift @$aref;
            my $target = $sub->();

            my $flag = $dist->_resolve_prereqs(
                            format  => $Module,
                            force   => 1,
                            target  => $target,
                            prereqs => $Prereq );

            is( !!$flag, !!$bool,   $txt );

            ### any extra tests ###
            $_->($cb->module_tree($Mod_prereq)) for @$aref;

        }
    }
}

### dist_types tests
{   can_ok( 'CPANPLUS::Dist',       'dist_types' );

    SKIP: {
        skip "You do not have Module::Pluggable installed", 2
            unless check_install( module => 'Module::Pluggable' );

        my @types = CPANPLUS::Dist->dist_types;
        ok( scalar(@types),         "   Dist types found" );
        ok( grep( /_Test/, @types), "   Found our _Test dist type" );
    }
}
1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
