BEGIN { chdir 't' if -d 't' };
use lib qw[../lib inc config];
use strict;
use CPANPLUS::Configure;
use FileHandle;
use File::Basename  qw[basename];

{   ### Force the ignoring of .po files for L::M::S
    $INC{'Locale::Maketext::Lexicon.pm'} = __FILE__;
    $Locale::Maketext::Lexicon::VERSION = 0;
}

my $conf = CPANPLUS::Configure->new( 
                conf => {   
                    hosts   => [ { 
                        path    => 'dummy-CPAN',
                        scheme  => 'file',
                    } ],      
                    base    => 'dummy-cpanplus',   
                } );

sub gimme_conf { return $conf };

my $fh;
my $file = ".".basename($0).".output";
sub output_handle {
    return $fh if $fh;
    
    $fh = FileHandle->new(">$file")
                or warn "Could not open output file '$file': $!";
   
    $fh->autoflush(1);
    return $fh;
}

sub output_file { return $file }

1;
