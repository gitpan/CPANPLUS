#!/usr/bin/perl
# $File: //depot/cpanplus/dist/t/0-signature.t $ $Author: autrijus $
# $Revision: #2 $ $Change: 1939 $ $DateTime: 2002/11/04 14:34:37 $

use strict;
use lib 't/lib';
use Test::More tests => 1;

SKIP: {
    if (!-e 'SIGNATURE') {
	skip("No signature file found", 1);
    }
    elsif (!eval { require Socket; Socket::inet_aton('pgp.mit.edu') }) {
	skip("Cannot connect to the keyserver", 1);
    }
    elsif (!eval { require Module::Signature; 1 }) {
	diag("Next time around, consider install Module::Signature,\n".
	     "so you can verify the integrity of this distribution.\n");
	skip("Module::Signature not installed", 1);
    }
    else {
	ok(Module::Signature::verify() == Module::Signature::SIGNATURE_OK()
	    => "Valid signature" );
    }
}

__END__
