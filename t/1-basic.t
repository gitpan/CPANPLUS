#!/usr/bin/perl -w
# $File: //member/autrijus/cpanplus/dist/t/1-basic.t $
# $Revision: #2 $ $Change: 3540 $ $DateTime: 2002/03/26 04:28:49 $

use strict;
use lib 't/lib';
use Test::More tests => 1;

# use a BEGIN block so we print our plan before MyModule is loaded

# works around strange term::readkey bug
$ENV{COLUMNS} ||= 80;
$ENV{LINES}   ||= 25;

# Load CPANPLUS::Shell::Default -- this doesn't require setup.
use_ok('CPANPLUS::Shell::Default');

exit;
