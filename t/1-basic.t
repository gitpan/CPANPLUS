#!/usr/bin/perl -w
# $File: //depot/cpanplus/dist/t/1-basic.t $
# $Revision: #3 $ $Change: 2926 $ $DateTime: 2002/12/25 15:39:55 $

use strict;
use lib 't/lib';
use Test::More tests => 2;

# use a BEGIN block so we print our plan before MyModule is loaded

# works around strange term::readkey bug
$ENV{COLUMNS} ||= 80;
$ENV{LINES}   ||= 25;

# Load CPANPLUS::Shell::Default -- this doesn't require setup.
use_ok('CPANPLUS::Shell::Default');

is(
    $CPANPLUS::Internals::Report::VERSION,
    $CPANPLUS::Internals::VERSION,
    "Internals.pm should initialize submodule's version properly"
);

exit;

() = ($CPANPLUS::Internals::Report::VERSION, $CPANPLUS::Internals::VERSION);
