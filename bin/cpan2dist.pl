#!/usr/bin/perl -w
use strict;
use CPANPLUS::Backend;
use Getopt::Std;

my $opts    = {};
my $cb      = CPANPLUS::Backend->new;
my %formats = map { $_ => 1 } 
                $cb->configure_object->options( type => '_dist' );


getopts('f:hv', $opts) or die usage();

die usage() unless @ARGV;
die usage() if $opts->{'h'};

my $format  = $opts->{'f'};
my $verbose = $opts->{'v'} ? 1 : 0;

die "Invalid format: $format\n".usage() unless $formats{$format};

$cb->configure_object->set_conf( verbose => $verbose );

my %done;
for my $name (@ARGV) {

    ### find the corresponding module object ###
    my $obj = $cb->parse_module( module => $name ) or (
            warn "Can not make a module object out of '$name' -- skipping\n",
            next );

    prepare( $obj );
}

sub prepare {
    my $obj = shift;

    print "Preparing ", $obj->module, "\n";

    ### first just unpack, etc ### 
    $obj->install(  target          => 'create', 
                    prereq_target   => 'ignore', 
                    skiptest        => 1 ) 
            or ( warn "Could not prepare '".$obj->module."'\n", return );

    ### now get the prereqs ###
    my $prereqs = $obj->status->prereqs;

    ### prepare each of the prereqs ###
    for my $p (keys %$prereqs) {
        my $mod = $cb->parse_module( module => $p ) or next;
        next if $mod->package_is_perl_core; # ignore perl core modules
        
        ### now prepare itif we haven't done so already 
        ### (this stops circular dependencies)
        prepare( $mod ) unless $done{$obj->module}++;
    }

    ### then make a dist it ### 
    distify( $obj ); 
}

sub distify {
    my $obj = shift;

    ### run create again, but with a different format ###
    my $rv = $obj->install( target          => 'create', 
                            prereq_target   => 'create',
                            format          => $format,
                        );

    unless( $rv ) {
        warn "Failed to create '$format' distribution from ", 
                $obj->module, "\n";
    } else {
        print "Created '$format' distribution for ", $obj->module, 
                " to:\n\t", $obj->status->dist->status->distdir, "\n";
    }
}

sub usage {
    my $formats = join "\n", map { "\t\t$_" } sort keys %formats;

    qq[
Usage:  $0 -f FORMAT Module::Name [Module::Name, ...]

    Will create a distribution of type FORMAT of the modules 
    specified on the command line, and all their prerequisites.

    Possible formats are:
$formats

    \n]
}
