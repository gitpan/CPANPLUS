#!/usr/bin/perl -w
# $File: //depot/cpanplus/dist/t/3-backend.t $
# $Revision: #3 $ $Change: 1963 $ $DateTime: 2002/11/04 16:32:10 $

# This is going test all of CPANPLUS::Backend except the parts which
# actually download and install modules.

use strict;
use lib 't/lib';
use Test::More tests => 74;

BEGIN { use File::Path; mkpath 't/dummy-cpanplus' }
END   { rmtree 't/dummy-cpanplus' }

my $Class = 'CPANPLUS::Backend'; # I got tired of typing it out.

use_ok $Class;

can_ok($Class, qw(
    new error_object configure_object
    module_tree author_tree
    search details readme install fetch extract make uninstall
    files distributions modules reports
    uptodate validate installed
    flush reload_indices pathname
));

my $cp = $Class->new(
    _ftp => {
        urilist => [
            {
                path    => 't/dummy-CPAN/',
                scheme  => 'file',
            }
        ],
    },

    _build => { base => 't/dummy-cpanplus/'},
);

isa_ok( $cp, $Class, 'new' );

isa_ok( $cp->error_object, 'CPANPLUS::Error', 'error_object' );
isa_ok( $cp->configure_object, 'CPANPLUS::Configure', 'configure_object' );

is( $cp->{_modtree}, undef, 'lazy loading: _modtree' );
is( $cp->{_authtree}, undef, 'lazy loading: _authtree' );

my $mods = $cp->module_tree;
isa_ok( $mods, 'HASH', 'module_tree' );
isnt( keys %$mods, 0,  '    got some modules' );

my $auths = $cp->author_tree;
isa_ok( $auths, 'HASH', 'author_tree' );
isnt( keys %$auths, 0,  '    got some authors' );

my %TB;
my $author  = 'AYRNIEU';
my $authobj = $auths->{$author};

%TB = (
    email  => 'julian@imaji.net',
    name   => 'julian fondren',
    _id    => 1,
    cpanid => $author,
);

is_deeply([sort keys %$authobj], [sort keys %TB], 'author object keys');

foreach my $k (keys %TB) {
    my $v = $TB{$k};
    is_deeply( $authobj->{$k}, $v, "    $k (hash)" );
    is_deeply( eval "\$authobj->$k",   $v, "    $k (accesor)" );
}

my $modname  = 'Text::Bastardize';
my $modobj   = $mods->{$modname};
my $distname = 'Text-Bastardize-0.06.tar.gz';

%TB = (
    _id         => $modobj->{_id},
    version     => 0.06,
    path        => 'A/AY/AYRNIEU',
    comment     => '',
    author      => $author,
    package     => $distname,
    dslip       => 'cdpO',
    status      => {},
    prereqs     => {},
    module      => $modname,
    description => 'corrupts text in various ways'
);

is_deeply([sort keys %$modobj], [sort keys %TB], 'module object keys');

foreach my $k (keys %TB) {
    my $v = $TB{$k};
    is_deeply( $modobj->{$k}, $v, "    $k (hash)" );
    is_deeply( eval"\$modobj->$k",   $v, "    $k (accesor)" );
}

### okay, sanity check passed. now let us try backend methods.

my $rv;

$rv = $cp->search( type => 'module', list => ['^Text::Bastard'] );
is_deeply($rv, { $modname => $modobj }, 'search()');

$rv = $cp->details(modules => [ $modname ])->rv;
is_deeply($rv, { $modname => {
    'Version on CPAN'	=> '0.06',
    'Version Installed'	=> $rv->{$modname}{'Version Installed'},
    'Language Used'     => 'Perl-only, no compiler needed, should be platform independent',
    'Interface Style'   => 'Object oriented using blessed references and/or inheritance',
    'Support Level'     => 'Developer',
    'Development Stage' => 'under construction but pre-alpha (not yet released)',
    'Description'       => 'corrupts text in various ways',
    'Package'           => 'Text-Bastardize-0.06.tar.gz',
    'Author'            => 'julian fondren (julian@imaji.net)'
} }, 'details()');
is_deeply($modobj->details, $rv->{$modname}, '    module method');
is_deeply($cp->details(modules => [$modobj])->rv, $rv, '    modobj');

delete $rv->{$modname}{'Version Installed'};
delete $rv->{$modname}{'Version on CPAN'};
is_deeply(
    $cp->details(modules => [ $distname ])->rv->{$cp->pathname(to => $distname)},
    $rv->{$modname}, '    distname'
);

$rv = $cp->readme(modules => [ $modname ])->rv;
like($rv->{$modname}, '/^\s+'.$modname.'[\d\D]+make install/', 'readme()');
is_deeply($modobj->readme, $rv->{$modname}, '    module method');

SKIP: {
    skip "won't write to disk", 6;
    my $file = './'.$modobj->pathname;

    $rv = $cp->install(modules => [ $modname ]);
    is_deeply($rv, {$modname => 1}, 'install()');
    is_deeply($modobj->install, $rv->{$modname}, '    module method');

    $rv = $cp->fetch(modules => [ $modname ], fetchdir => '.');
    is_deeply($rv, {$modname => $file}, 'fetch()');
    is_deeply($modobj->fetch, $rv->{$modname}, '    module method');

    $rv = $cp->extract(files => [ $file ], extractdir => '.');
    is_deeply($rv, {$file => '.'}, 'extract()');

    $rv = $cp->make(dirs => [ $modobj->path ]);
    is_deeply($rv, {$modobj->path => 1}, 'make()');

    $rv = $cp->uninstall(modules => [ $modname ]);
    is_deeply($rv, {$modname => 1}, 'uninstall()');
    is_deeply($modobj->uninstall, $rv->{$modname}, '    module method');
}

SKIP: {
    skip "$modname is installed", 5 if eval "use $modname; 1";
    local $cp->error_object->{ELEVEL} = 0; # shut up

    $rv = $cp->files(modules => [ $modname ])->rv;
    is_deeply($rv, {$modname => 0}, 'files()');

    $rv = $cp->uptodate(modules => [ $modname ])->rv;
    is_deeply($rv, {$modname => {}}, 'uptodate()');
    is_deeply($modobj->uptodate, $rv->{$modname}, '    module method');

    $rv = $cp->validate(modules => [ $modname ])->rv;
    is_deeply($rv, {$modname => 0}, 'validate()');
}

$rv = $cp->distributions(authors => [ $modobj->author ])->rv;

my $modinfo = {
    shortname  => 'textb006.tgz',
    mtime      => '1999-05-13',
    'md5-ungz' => '8a148408fb4f7e434b7d3ea3671960cc',
    md5        => '0567a1beaa950b5881c706ebc3dde0d5',
    size       => '3467'
};

is_deeply($rv->{$author}{$distname}, $modinfo, 'distributions()');
is_deeply($authobj->distributions, $rv->{$author}, '    author method');
is_deeply($modobj->distributions, $rv->{$author}, '    module method');

$rv = $cp->modules(authors => [ $modobj->author ])->rv;
is_deeply($rv->{$author}{$modname}, $modobj, 'module()');
is_deeply($authobj->modules->{$modname}, $modobj, '    author method');
is_deeply($modobj->modules->{$modname}, $modobj, '    module method');

SKIP: {
    skip "requires LWP", 2
        unless eval { require LWP; 1 };
    skip "requires HTML::HeadParser", 2
        unless eval { require HTML::HeadParser; 1 };
    skip "requires internet connectivity", 2
        unless eval { require Socket; Socket::inet_aton('testers.cpan.org') };

    diag "Connecting to testers.cpan.org; this may take a while";
    $rv = $cp->reports(modules => [ $modname ], all_versions => 1)->rv;
    is_deeply(ref($rv->{$modname}), 'ARRAY', 'reports()');
    is_deeply($modobj->reports, $rv->{$modname}, '    module method');
}

is_deeply($cp->flush('all'), 1, 'flush()');
is_deeply($cp->reload_indices(update_source => 1), 1, 'reload_indices()');

my $pathname = '/A/AY/AYRNIEU/Text-Bastardize-0.06.tar.gz';
is_deeply($cp->pathname(to => $modname), $pathname, 'pathname()');
is_deeply($modobj->pathname, $pathname, '    module method');
is_deeply($cp->pathname(to => $modobj), $pathname, '    modobj');
is_deeply($cp->pathname(to => $distname), $pathname, '    distname');

exit;
__END__
