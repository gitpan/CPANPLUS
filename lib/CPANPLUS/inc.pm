package CPANPLUS::inc;

use strict;
use vars        qw[$DEBUG $VERSION $ENABLE_INC_HOOK];
use File::Spec  ();
use Config      ();

### 5.6.1. nags about require + bareword otherwise ###
use lib ();

$DEBUG              = 0;

=pod 

=head1 NAME

CPANPLUS::inc - runtime inclusion of privately bundled modules

=head1 SYNOPSIS

    ### set up CPANPLUS::inc to do it's thing ###
    BEGIN { use CPANPLUS::inc };
    
    ### enable debugging ###
    use CPANPLUS::inc qw[DEBUG];

=head1 DESCRIPTION

This module enables the use of the bundled modules in the 
C<CPANPLUS/inc> directory of this package. These modules are bundled
to make sure C<CPANPLUS> is able to bootstrap itself. It will do the
following things:

=over 4

=item Put a coderef at the beginning of C<@INC> 

This allows us to decide which module to load, and where to find it.
For details on what we do, see the C<INTERESTING MODULES> section below.
Also see the C<CAVEATS> section.

=item Add the full path to the C<CPANPLUS/inc> directory to C<$ENV{PERL5LIB>.

This allows us to find our bundled modules even if we spawn off a new 
process. Although it's not able to do the selective loading as the 
coderef in C<@INC> could, it's a good fallback.

=back

=head1 METHODS

=head2 CPANPLUS::inc->inc_path()

Returns the full path to the C<CPANPLUS/inc> directory.

=head2 CPANPLUS::inc->my_path()

Returns the full path to be added to C<@INC> to load 
C<CPANPLUS::inc> from.

=cut

{   my $ext     = '.pm';
    my $file    = (join '/', split '::', __PACKAGE__) . $ext;
    
    ### os specific file path, if you're not on unix 
    my $osfile  = File::Spec->catfile( split('::', __PACKAGE__) ) . $ext;
    
    ### this returns a unixy path, compensate if you're on non-unix
    my $path    = File::Spec->rel2abs(  
                        File::Spec->catfile( split '/', $INC{$file} )
                    );
    
    ### don't forget to quotemeta; win32 paths are special
    my $qm_osfile = quotemeta $osfile;
    my $path_to_me  = $path; $path_to_me    =~ s/$qm_osfile$//i;
    my $path_to_inc = $path; $path_to_inc   =~ s/$ext$//i;
    
    sub inc_path { return $path_to_inc  }
    sub my_path  { return $path_to_me   }
}

=head2 CPANPLUS::inc->original_perl5lib

Returns the value of $ENV{PERL5LIB} the way it was when C<CPANPLUS::inc>
got loaded.

=head2 CPANPLUS::inc->original_perl5opt

Returns the value of $ENV{PERL5OPT} the way it was when C<CPANPLUS::inc>
got loaded.

=head2 CPANPLUS::inc->original_inc

Returns the value of @INC the way it was when C<CPANPLUS::inc> got 
loaded.

=cut

{   my $org_opt = $ENV{PERL5OPT}; 
    my $org_lib = $ENV{PERL5LIB};
    my @org_inc = @INC;

    sub original_perl5opt   { $org_opt };
    sub original_perl5lib   { $org_lib };
    sub original_inc        { @org_inc };
}

=head2 CPANPLUS::inc->interesting_modules()

Returns a hashref with modules we're interested in, and the minimum
version we need to find.

It would looks something like this:

    {   File::Fetch             => 0.05,
        IPC::Cmd                => 0.22,
        ....
    }            

=cut

{
    my $map = {
        'File::Fetch'               => '0.05',
        #'File::Spec'                => '0.82', # can't, need it ourselves...
        'IPC::Run'                  => '0.77',
        'IPC::Cmd'                  => '0.23',
        'Locale::Maketext::Simple'	 => 0,
        'Log::Message'              => 0,
        'Module::Load'              => '0.10',
        'Module::Load::Conditional' => '0.05',
        'Module::Build'             => '0.2605',
        'Params::Check'             => '0.21',
        'Term::UI'                  => '0.03',
        'Archive::Extract'          => '0.03',
        'Archive::Tar'              => '1.21',
        'IO::Zlib'                  => '1.01',   
        'Object::Accessor'          => '0.02',
        'Module::CoreList'          => '1.97',
        #'Config::Auto'             => 0,   # not yet, not using it yet
    };    

    sub interesting_modules { return $map; }
}


=head1 INTERESTING MODULES    

C<CPANPLUS::inc> doesn't even bother to try find and find a module
it's not interested in. A list of I<interesting modules> can be 
obtained using the C<interesting_modules> method described above.

Note that all subclassed modules of an C<interesting module> will
also be attempted to be loaded, but a version will not be checked.

When it however does encounter a module it is interested in, it will
do the following things:

=over 4

=item Loop over your @INC

And for every directory it finds there (skipping all non directories
-- see the C<CAVEATS> section), see if the module requested can be 
found there. 

=item Check the version on every suitable module found in @INC

After a list of modules has been gathered, the version of each of them
is checked to find the one with the highest version, and return that as
the module to C<use>. 

This enables us to use a recent enough version from our own bundled 
modules, but also to use a I<newer> module found in your path instead, 
if it is present. Thus having access to bugfixed versions as they are 
released.

If for some reason no satisfactory version could be found, a warning
will be emitted. See the C<DEBUG> section for more details on how to
find out exactly what C<CPANPLUS::inc> is doing.

=back

=cut

my $loaded;
sub import {
    ### up the debug level if required ###
    $DEBUG++ if $_[1] && $_[1] eq 'DEBUG';

    ### only load once ###
    return 1 if $loaded++;

    ### first, add our own private dir to the end of @INC:
    {   
        push @INC, __PACKAGE__->my_path, __PACKAGE__->inc_path;
        
        ### add the path to this module to PERL5OPT in case 
        ### we spawn off some programs...
        ### then add this module to be loaded in PERL5OPT...
        {   local $^W;
            $ENV{'PERL5LIB'} .= $Config::Config{'path_sep'} 
                             . __PACKAGE__->my_path
                             . $Config::Config{'path_sep'} 
                             . __PACKAGE__->inc_path;
                             
            $ENV{'PERL5OPT'} = '-M'. __PACKAGE__ . ' ' 
                             . ($ENV{'PERL5OPT'} || '');
        }
    }      

    ### next, find the highest version of a module that
    ### we care about. very basic check, but will
    ### have to do for now.
    lib->import( sub { 
        my $path    = pop();                # path to the pm
        my $module  = $path;                # copy of the path, to munge
        my @parts   = split '/', $path;     # dirs + file name
        my $file    = pop @parts;           # just the file name
        my $map     = __PACKAGE__->interesting_modules;
        
        
        ### translate file name to module name ###
        $module =~ s|/|::|g; $module =~ s/\.pm//i;
   
        my $check_version; my $try;
        ### does it look like a module we care about?   
        ++$try if grep { $module =~ /^$_/ } keys %$map;    
          
        ### do we need to check the version too? 
        ++$check_version if exists $map->{$module};

        ### we don't care ###
        unless( $try ) {
            warn __PACKAGE__ .": Not interested in '$module'\n" if $DEBUG;
            return;
        }
        
        ### found filehandles + versions ###
        my @found;
        DIR: for my $dir (@INC) {
            next DIR unless -d $dir;
            
            ### get the full path to the module ###
            my $pm = File::Spec->catfile( $dir, @parts, $file );
            
            ### open the file if it exists ###
            if( -e $pm ) {
                my $fh;
                unless( open $fh, "$pm" ) {
                    warn __PACKAGE__ .": Could not open '$pm': $!\n" 
                        if $DEBUG;    
                    next DIR;
                }      

                my $found;
                ### XXX stolen from module::load::conditional ###            
                while (local $_ = <$fh> ) {

                    ### the following regexp comes from the ExtUtils::MakeMaker
                    ### documentation.
                    if ( /([\$*])(([\w\:\']*)\bVERSION)\b.*\=/ ) {

                        ### this will eval the version in to $VERSION if it
                        ### was declared as $VERSION in the module.
                        ### else the result will be in $res.
                        ### this is a fix on skud's Module::InstalledVersion
    
                        local $VERSION;
                        my $res = eval $_;
        
                        ### default to '0.0' if there REALLY is no version
                        ### all to satisfy warnings
                        $found = $VERSION || $res || '0.0';
                        
                        ### found what we came for                    
                        last if $found;
                    } 
                }

                ### no version defined at all? ###
                $found ||= '0.0';

                warn __PACKAGE__ .": Found match for '$module' in '$dir' "
                                 ."with version '$found'\n" if $DEBUG;

                ### reset the position of the filehandle ###
                seek $fh, 0, 0;
            
                ### store the found version + filehandle it came from ###
                push @found, [ $found, $fh, $dir, $pm ];             
            }   
        
        } # done looping over all the dirs
        
        ### nothing found? ###
        unless (@found) {
            warn __PACKAGE__ .": Unable to find any module named '$module'\n"
                    if $DEBUG;
            return;         
        }
        
        ### find highest version 
        ### or otherwise, newest file
        my @sorted = sort { ($b->[0] <=> $a->[0]) ||
                            (-M $a->[3] <=> -M $b->[3])
                      } @found;
        
        warn __PACKAGE__ .": Best match for '$module' is found in "
                         ."'$sorted[0][2]' with version '$sorted[0][0]'\n"
                if $DEBUG;                               
        
        if( $check_version and not ($sorted[0][0] >= $map->{$module}) ) {
            warn __PACKAGE__ .": Can not find high enough version for " 
                             ."'$module' -- need '$map->{$module}' but only "
                             ." found '$sorted[0][0]'. Returning highest found "
                             ." version but this may cause problems\n";                                  
        };
        
        ### best matching filehandle ###
        return $sorted[0][1];
    } );    
}

=pod

=head1 DEBUG

Since this module does C<Clever Things> to your search path, it might
be nice sometimes to figure out what it's doing, if things don't work 
as expected. You can enable a debug trace by calling the module like
this:

    use CPANPLUS::inc 'DEBUG';
    
This will show you what C<CPANPLUS::inc> is doing, which might look 
something like this:

    CPANPLUS::inc: Found match for 'Params::Check' in     
    '/opt/lib/perl5/site_perl/5.8.3' with version '0.07'
    CPANPLUS::inc: Found match for 'Params::Check' in 
    '/my/private/lib/CPANPLUS/inc' with version '0.21'
    CPANPLUS::inc: Best match for 'Params::Check' is found in 
    '/my/private/lib/CPANPLUS/inc' with version '0.21'

=head1 CAVEATS

This module has 2 major caveats, that could lead to unexpected 
behaviour. But currently I don't know how to fix them, Suggestions
are much welcomed.

=over 4

=item On multiple C<use lib> calls, our coderef may not be the first in @INC

If this happens, although unlikely in most situations and not happening
when calling the shell directly, this could mean that a lower (too low) 
versioned module is loaded, which might cause failures in the 
application.

=item Non-directories in @INC

Non-directories are right now skipped by CPANPLUS::inc. They could of 
course lead us to newer versions of a module, but it's too tricky to 
verify if they would. Therefor they are skipped. In the worst case 
scenario we'll find the sufficing version bundled with CPANPLUS.


=cut

1;    

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
    
