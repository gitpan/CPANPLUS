#!/usr/bin/perl
# $File: //depot/cpanplus/dist/t/0-signature.t $ $Author: autrijus $
# $Revision: #6 $ $Change: 7707 $ $DateTime: 2003/08/25 18:50:40 $

use strict;
use lib 't/lib';
use Test::More tests => 1;

SKIP: {
    if (!-s 'SIGNATURE') {
	skip("No signature file found", 1);
    }
    elsif (!eval { require Module::Signature; 1 }) {
	skip("Next time around, consider install Module::Signature, ".
	     "so you can verify the integrity of this distribution.", 1);
    }
    elsif (!eval { require Socket; Socket::inet_aton('pgp.mit.edu') }) {
	skip("Cannot connect to the keyserver", 1);
    }
    else {
	ok(Module::Signature::verify() == Module::Signature::SIGNATURE_OK()
	    => "Valid signature" );
    }
}

__END__
