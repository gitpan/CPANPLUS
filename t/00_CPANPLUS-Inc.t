BEGIN { chdir 't' if -d 't' };
### this is to make devel::cover happy ###

BEGIN { 
    use File::Spec;
    require lib;
    for (qw[../lib inc config]) { my $l = 'lib'; $l->import(File::Spec->rel2abs($_)) }
}

use strict;
use Test::More 'no_plan';

my $Module = 'Params::Check';
my $File   = File::Spec->catfile(qw|Params Check.pm|);
my $Ufile  = 'Params/Check.pm';
my $Boring = 'IO::File';
my $Bfile  = 'IO/File.pm';

use_ok('CPANPLUS::inc');

### now, first element should be a coderef ###
my $code = $INC[0];
is( ref $code, 'CODE',          'Coderef loaded in @INC' );

### check interesting modules ###
{   my $mods = CPANPLUS::inc->interesting_modules();
    ok( $mods,                  "Retrieved interesting modules list" );
    is( ref $mods, 'HASH',      "   It's a hashref" );
    ok( scalar(keys %$mods),    "   With some keys in it" );
    ok( $mods->{$Module},       "   Found a module we care about" );
}

### checking include path ###
{   my $path = CPANPLUS::inc->inc_path();
    ok( $path,                  "Retrieved include path" );
    ok( -d $path,               "   Include path is an actual directory" );    
    ok( -s File::Spec->catfile( $path, $File ),
                                "   Found '$File' in include path" ); 

    my $out = join '', `$^X -V`; my $qm_path = quotemeta $path;
    like( $out, qr/$qm_path/s,  "   Path found in perl -V output" );
}

### back to the coderef ###                                
### try a boring module ###
{   local $CPANPLUS::inc::DEBUG = 1;
    my $warnings; local $SIG{__WARN__} = sub { $warnings .= "@_" };
    
    my $rv = $code->($code, $Bfile);                                
    ok( !$rv,                   "Ignoring boring module" );
    ok( !$INC{$Bfile},         "   Boring file not loaded" );
    like( $warnings, qr/CPANPLUS::inc: Not interested in '$Boring'/s,
                                "   Warned about boringness" );
}
 
### try an interesting module ### 
{   local $CPANPLUS::inc::DEBUG = 1;
    my $warnings; local $SIG{__WARN__} = sub { $warnings .= "@_" };
    
    my $rv = $code->($code, $Ufile);                                
    ok( $rv,                    "Found interesting module" );
    ok( !$INC{$Ufile},          "   Interesting file not loaded" );
    like( $warnings, qr/CPANPLUS::inc: Found match for '$Module'/,
                                "   Match noted in warnings" );
    like( $warnings, qr/CPANPLUS::inc: Best match for '$Module'/,
                                "   Best match noted in warnings" );

    my $contents = do { local $/; <$rv> };
    ok( $contents,              "   Read contents from filehandle" );
    like( $contents, qr/$Module/s,
                                "   Contents is from '$Module'" );
}    
    
### now do some real loading ###
{   use_ok($Module);
    ok( $INC{$Ufile},           "   Regular use of '$Module'" );
    
    use_ok($Boring);
    ok( $INC{$Bfile},           "   Regular use of '$Boring'" );
}    
 
### check we didn't load our coderef anymore than needed ### 
{   my $amount = 5;
    for( 0..$amount ) { CPANPLUS::inc->import; };
    
    my $flag; 
    map { $flag++ if ref $_ eq 'CODE' } @INC[0..$amount];
    
    my $ok = $amount + 1 == $flag ? 0 : 1;
    ok( $ok,                    "Only loaded coderef into \@INC $flag times" );       
}    
    
    
