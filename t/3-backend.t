#!/usr/bin/perl -w
# $File: //member/autrijus/cpanplus/dist/t/3-backend.t $
# $Revision: #3 $ $Change: 3540 $ $DateTime: 2002/03/26 04:28:49 $

# This is going test all of CPANPLUS::Backend except the parts which
# actually download and install modules.  Those will be in another part.

use lib 't/lib';
use Test::More tests => 30;

BEGIN { use File::Path; mkpath 't/dummy-cpanplus' }
END   { rmtree 't/dummy-cpanplus' }

my $Class = 'CPANPLUS::Backend'; # I got tired of typing it out.

use_ok $Class;

foreach my $meth (qw(new  error_object 
                     module_tree  author_tree
                     search  details  get_conf  set_conf
                     install  flush  fetch  extract  make
                    )) {
    can_ok($Class, $meth);
}


my $cp = $Class->new( _ftp => {
                               urilist => [
                                           {
                                            path    => 't/dummy-CPAN/',
                                            scheme  => 'file',
                                           }
                                          ]
                              },

			_build => { base => 't/dummy-cpanplus/'},
                    );

isa_ok( $cp, $Class, 'new' );

my $mods = $cp->module_tree;
isa_ok( $mods, 'HASH', 'module_tree' );
isnt( keys %$mods, 0,  '    got some modules' );

my $name = 'Text::Bastardize';
my $info = $mods->{$name};

{
    #local $TODO = 'description undocumented';
    is_deeply([sort keys %$info], [sort qw(_id module prereqs status version path comment
                                           author package dslip description)]);
}

my %TB = (
          _id       => $info->{_id},
          module    => $name,
          version   => 0.06,
          path      => 'A/AY/AYRNIEU',
          comment   => '',
          author    => 'AYRNIEU',
          package   => 'Text-Bastardize-0.06.tar.gz',
          dslip     => 'cdpO',
          status    => '',
          prereqs   => {},
          module    => 'Text::Bastardize',
          description   => 'corrupts text in various ways'
         );

is_deeply([sort keys %$info], [sort keys %TB]);

while( my($k,$v) = each %TB ) {
    #local $TODO = "path doesn't jive with the docs" if $k eq 'path';
    is_deeply( $info->{$k},  $v, "    $k" );
}
