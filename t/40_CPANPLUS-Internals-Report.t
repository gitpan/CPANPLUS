BEGIN { chdir 't' if -d 't' };

### this is to make devel::cover happy ###
BEGIN { 
    use File::Spec;
    require lib;
    for (qw[../lib inc]) { my $l = 'lib'; $l->import(File::Spec->rel2abs($_)) }
}

use strict;

use CPANPLUS::inc;
use CPANPLUS::Backend;
use CPANPLUS::Internals::Constants::Report;

my $send_tests  = 26;
my $query_tests = 7;
my $total_tests = $send_tests + $query_tests;

use Test::More                  tests => 58;
use Module::Load::Conditional   qw[can_load];

use FileHandle;
use Data::Dumper;

use constant NOBODY => 'nobody@xs4all.nl';

BEGIN { require 'conf.pl'; }

my $conf    = gimme_conf();
my $cb      = CPANPLUS::Backend->new( $conf );
my $mod     = $cb->module_tree('Text::Bastardize');

### explicitly enable testing if possible ###
$cb->configure_object->set_conf(cpantest =>1) if $ARGV[0];

my $map = {
    all_ok  => {
        buffer  => '',
        failed  => 0,
        match   => [qw|/PASS/|],
        check   => 0,
    },         
    missing_prereq  => {    
        buffer  => missing_prereq_buffer(), 
        failed  => 1,
        match   => ['/The comments below are created mechanically/',
                    '/automatically by CPANPLUS/',
                    '/test suite seem to fail without these modules/',
                    '/floo/', 
                    '/FAIL/',
                    '/make test/',
                ],
        check   => 1,          
    },
    missing_tests   => {
        buffer  => missing_tests_buffer(),
        failed  => 1,
        match   => ['/The comments below are created mechanically/',
                    '/automatically by CPANPLUS/',
                    '/ask for a simple test script/',
                    '/UNKNOWN/',
                    '/make test/',
                ],
        check   => 0,             
    }
};

### test constants ###
{   {   my $to = CPAN_MAIL_ACCOUNT->('foo');
        is( $to, 'foo@cpan.org',        "Got proper mail account" );
    }
    
    {   ok(RELEVANT_TEST_RESULT->($mod),"Test is relevant" );
        
        ### test non-relevant tests ###
        my $cp = $mod->clone;
        $cp->module( $mod->module . '::' . ($^O eq 'beos' ? 'MSDOS' : 'Be') );    
        ok(!RELEVANT_TEST_RESULT->($cp),"Test is irrelevant");
    }
    
    {   my $tests = "test.pl";
        my $none  = "No tests defined for Foo extension.";
        ok(!NO_TESTS_DEFINED->($tests), "Tests defined");
        ok( NO_TESTS_DEFINED->($none),  "No tests defined");
    }
    
    {   my $fail = 'MAKE TEST'; my $unknown = 'foo';
        is( TEST_FAIL_STAGE->($fail), lc $fail,
                                        "Proper test fail stage found" );
        is( TEST_FAIL_STAGE->($unknown), 'fetch',
                                        "Proper test fail stage found" );                                                                             
    }          

    {   my @list = MISSING_PREREQS_LIST->(q[Can't locate Foo::Bar in @INC]);
        is( scalar(@list),  1,          "List of missing prereqs found" );
        is( $list[0], 'Foo::Bar',       "   Proper prereq found" );
    }

    {                                       # author
        my $header = REPORT_MESSAGE_HEADER->('foo');
        ok( $header,                    "Test header generated" );
        like( $header, qr/NOTE/,        "   Proper content found" );
        like( $header, qr/foo/,         "   Proper content found" );
        like( $header, qr/CPAN/,        "   Proper content found" );
        like( $header, qr/comments/,    "   Proper content found" );
    }     

    {                                       # cp version, stage, buffer
        my $header = REPORT_MESSAGE_FAIL_HEADER->('1','test','buffer');
        ok( $header,                    "Test header generated" );
        like( $header, qr/CPANPLUS/,    "   Proper content found" );
        like( $header, qr/stack/,       "   Proper content found" );
        like( $header, qr/buffer/,      "   Proper content found" );
    }        

    {   my $prereqs = REPORT_MISSING_PREREQS->('Foo::Bar');
        ok( $prereqs,                   "Test output generated" );
        like( $prereqs, qr/Foo::Bar/,     "   Proper content found" );
        like( $prereqs, qr/prerequisite/, "   Proper content found" );
        like( $prereqs, qr/PREREQ_PM/,    "   Proper content found" );
    }

    {   my $missing = REPORT_MISSING_TESTS->();
        ok( $missing,                   "Missing test string generated" );
        like( $missing, qr/tests/,      "   Proper content found" );
        like( $missing, qr/Test::More/, "   Proper content found" );
    }
}    
 
### test creating test reports ###
SKIP: {
    skip "You have chosen not to enable test reporting", $total_tests,
        unless $cb->configure_object->get_conf('cpantest');

    skip "No report send & query modules installed", $total_tests
        unless $cb->_have_query_report_modules(verbose => 0);
    
    
    {   my @list = $mod->fetch_report;
        my $href = $list[0];
        ok( scalar(@list),                  "Fetched test report" );
        is( ref $href, ref {},              "   Return value has hashrefs" );
    
        ok( $href->{grade},                 "   Has a grade" );
        like( $href->{grade}, qr/pass|fail|unknown|na/i,
                                            "   Grade as expected" );
    
        my $pkg_name = $mod->package_name;        
        ok( $href->{dist},                  "   Has a dist" );
        like( $href->{dist}, qr/$pkg_name/, "   Dist as expected" );
        
        ok( $href->{platform},              "   Has a platform" );
    }
    
    skip "No report sending modules installed", $send_tests
        unless $cb->_have_send_report_modules(verbose => 0);
    
    for my $type ( keys %$map ) {
        
        
        ### never enter the editor for test reports
        ### but check if the callback actually gets called;
        my $called_edit; my $called_send;
        $cb->_register_callback( 
            name => 'edit_test_report', 
            code => sub { $called_edit++; 0 } 
        );

        $cb->_register_callback( 
            name => 'send_test_report', 
            code => sub { $called_send++; 1 } 
        );


        my $file = $cb->_send_report(
                        module  => $mod,
                        buffer  => $map->{$type}->{'buffer'},
                        failed  => $map->{$type}->{'failed'},         
                        save    => 1,
                    );
        
        ok( $file,              "Type '$type' written to file" );
        ok( -e $file,           "   File exists" );
         
        my $fh = FileHandle->new($file);
        ok( $fh,                "   Opened file for reading" );
        
        my $in = do { local $/; <$fh> };
        ok( $in,                "   File has contents" );
        
        for my $regex ( @{$map->{$type}->{match}} ) {
            like( $in, $regex,  "   File contains expected contents" );   
        }
        
        ### check if our registered callback got called ###
        if( $map->{$type}->{check} ) {
            ok( $called_edit,   "   Callback to edit was called" );
            ok( $called_send,   "   Callback to send was called" );
        }
        
        unlink $file;
        
 
### T::R tests don't even try to mail, let's not try and be smarter
### ourselves
#        {   ### use a dummy 'editor' and see if the editor 
#            ### invocation doesn't break things
#            $conf->set_program( editor => "$^X -le1" );
#            $cb->_callbacks->edit_test_report( sub { 1 } );
#            
#            ### XXX whitebox test!!! Might change =/
#            ### this makes test::reporter not ask for what editor to use
#            ### XXX stupid lousy perl warnings;
#            local $Test::Reporter::MacApp = 1;
#            local $Test::Reporter::MacApp = 1;
#            
#            ### now try and mail the report to a /dev/null'd mailbox
#            my $ok = $cb->_send_report(
#                            module  => $mod,
#                            buffer  => $map->{$type}->{'buffer'},
#                            failed  => $map->{$type}->{'failed'},         
#                            address => NOBODY,
#                            dontcc  => 1,
#                        );
#            ok( $ok,                "   Mailed report to NOBODY" );
#       }
    }
}


sub missing_prereq_buffer {
    return q[
MAKE TEST:    
Can't locate floo.pm in @INC (@INC contains: /Users/kane/sources/p4/other/archive-extract/lib /Users/kane/sources/p4/other/file-fetch/lib /Users/kane/sources/p4/other/archive-tar-new/lib /Users/kane/sources/p4/other/carp-trace/lib /Users/kane/sources/p4/other/log-message/lib /Users/kane/sources/p4/other/module-load/lib /Users/kane/sources/p4/other/params-check/lib /Users/kane/sources/p4/other/qmail-checkpassword/lib /Users/kane/sources/p4/other/module-load-conditional/lib /Users/kane/sources/p4/other/term-ui/lib /Users/kane/sources/p4/other/ipc-cmd/lib /Users/kane/sources/p4/other/config-auto/lib /Users/kane/sources/NSA /Users/kane/sources/NSA/misc /Users/kane/sources/NSA/test /Users/kane/sources/beheer/perl /opt/lib/perl5/5.8.3/darwin-2level /opt/lib/perl5/5.8.3 /opt/lib/perl5/site_perl/5.8.3/darwin-2level /opt/lib/perl5/site_perl/5.8.3 /opt/lib/perl5/site_perl .).
BEGIN failed--compilation aborted.
    ];
}        

sub missing_tests_buffer {
    return q[
cp lib/Acme/POE/Knee.pm blib/lib/Acme/POE/Knee.pm
cp demo_race.pl blib/lib/Acme/POE/demo_race.pl
cp demo_simple.pl blib/lib/Acme/POE/demo_simple.pl
MAKE TEST:
No tests defined for Acme::POE::Knee extension.
    ];    
}

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
