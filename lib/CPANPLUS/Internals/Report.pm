package CPANPLUS::Internals::Report;

use strict;
use CPANPLUS::inc;
use CPANPLUS::Error;
use CPANPLUS::Internals::Constants;
use CPANPLUS::Internals::Constants::Report;

use Data::Dumper;

use Params::Check               qw[check];
use Locale::Maketext::Simple    Class => 'CPANPLUS', Style => 'gettext';
use Module::Load::Conditional   qw[can_load];

$Params::Check::VERBOSE = 1;

### for the version ###
require CPANPLUS::Internals;


=head2 _query_report( module => $modobj, [all_versions => BOOL, verbose => BOOL] )

This function queries the CPAN testers database at
I<http://testers.cpan.org/> for test results of specified module objects,
module names or distributions.

The optional argument C<all_versions> controls whether all versions of
a given distribution should be grabbed.  It defaults to false
(fetching only reports for the current version).

Returns the a list with the following data structures (for CPANPLUS 
version 0.042) on success, or false on failure:

          {
            'grade' => 'PASS',
            'dist' => 'CPANPLUS-0.042',
            'platform' => 'i686-pld-linux-thread-multi'
          },
          {
            'grade' => 'PASS',
            'dist' => 'CPANPLUS-0.042',
            'platform' => 'i686-linux-thread-multi'
          },
          {
            'grade' => 'FAIL',
            'dist' => 'CPANPLUS-0.042',
            'platform' => 'cygwin-multi-64int',
            'details' => 'http://nntp.x.perl.org/group/perl.cpan.testers/99371'
          },
          {
            'grade' => 'FAIL',
            'dist' => 'CPANPLUS-0.042',
            'platform' => 'i586-linux',
            'details' => 'http://nntp.x.perl.org/group/perl.cpan.testers/99396'
          },

The status of the test can be one of the following:
UNKNOWN, PASS, FAIL or NA (not applicable).

=cut

sub _query_report {
    my $self = shift;
    my $conf = $self->configure_object;
    my %hash = @_;
    
    my($mod, $verbose, $all);
    my $tmpl = {
        module          => { required => 1, allow => IS_MODOBJ, 
                                store => \$mod },
        verbose         => { default => $conf->get_conf('verbose'), 
                                store => \$verbose },
        all_versions    => { default => 0, store => \$all },
    };
    
    check( $tmpl, \%hash ) or return;       
    
    my $use_list = {
        LWP              => '0.0',
        'LWP::UserAgent' => '0.0',
        'HTTP::Request'  => '0.0',
        URI              => '0.0',
        YAML             => '0.0',
    };

    return unless can_load( modules => $use_list, verbose => 1 );
    
    ### new user agent ###
    my $ua = LWP::UserAgent->new;
    $ua->agent( CPANPLUS_UA->() );
    
    ### set proxies if we have them ###
    $ua->env_proxy();
   
    my $url = TESTERS_URL->($mod->package_name);
    my $req = HTTP::Request->new( GET => $url);
    
    msg( loc("Fetching: '%1'", $url), $verbose );
    
    my $res = $ua->request( $req );
    
    unless( $res->is_success ) {
        error( loc( "Fetching report for '%1' failed: %2",
                    $url, $res->message ) );
        return;               
    }
    
    my $aref = YAML::Load( $res->content );

    my $dist = $mod->package_name .'-'. $mod->package_version;

    my @rv;    
    for my $href ( @$aref ) {
        next unless $all or $href->{'distversion'} eq $dist;
    
        push @rv, { platform    => $href->{'platform'},
                    grade       => $href->{'action'},
                    dist        => $href->{'distversion'},
                    ( $href->{'action'} eq 'FAIL' 
                        ? (details => TESTERS_DETAILS_URL->($mod->package_name))
                        : ()
                    ) }; 
    }                             
                    
    return @rv if @rv;
    return;                       
}

=pod

=head2 _send_report( module => $modobj, buffer => $make_output, failed => BOOL, [save => BOOL, address => $email_to, dontcc => BOOL, verbose => BOOL, force => BOOL]);

This function sends a testers report to C<cpan-testers@perl.org> for a
particular distribution. 
It returns true on success, and false on failure.

It takes the following options:

=over 4

=item module

The module object of this particular distribution

=item buffer

The output buffer from the 'make/make test' process

=item failed

Boolean indicating if the 'make/make test' went wrong

=item save

Boolean indicating if the report should be saved locally instead of 
mailed out. If provided, this function will return the location the
report was saved to, rather than a simple boolean 'TRUE'.

Defaults to false.

=item address

The email address to mail the report for. You should never need to
override this, but it might be useful for debugging purposes. 

Defaults to C<cpan-testers@perl.org>.

=item dontcc

Boolean indicating whether or not we should Cc: the author. If false,
previous error reports are inspected and checked if the author should
be mailed. If set to true, these tests are skipped and the author is
definitely not Cc:'d. 
You should probably not change this setting.

Defaults to false.

=item verbose

Boolean indicating on whether or not to be verbose. 

Defaults to your configuration settings

=item force

Boolean indicating whether to force the sending, even if the max
amount of reports for fails have already been reached, or if you
may already have sent it before.

Defaults to your configuration settings

=back

=cut


sub _send_report {
    my $self = shift;
    my $conf = $self->configure_object;
    my %hash = @_;

    ### do you even /have/ test::reporter? ###
    unless( can_load(modules => {'Test::Reporter' => 1.19}, verbose => 1) ) {
        error( loc( "You don't have '%1' installed, you can not report " .
                    "test results.", 'Test::Reporter' ) );
        return;              
    }

    ### check arguments ###
    my ($buffer, $failed, $mod, $verbose, $force, $address, $save, $dontcc);
    my $tmpl = {
            module  => { required => 1, store => \$mod, allow => IS_MODOBJ },
            buffer  => { required => 1, store => \$buffer },   
            failed  => { required => 1, store => \$failed },
            address => { default  => CPAN_TESTERS_EMAIL, store => \$address },   
            save    => { default  => 0, store => \$save },   
            dontcc  => { default  => 0, store => \$dontcc },
            verbose => { default  => $conf->get_conf('verbose'), 
                            store => \$verbose },
            force   => { default  => $conf->get_conf('force'),
                            store => \$force },
    };

    check( $tmpl, \%hash ) or return;

    ### get the data to fill the email with ###
    my $name    = $mod->module;  
    my $dist    = $mod->package_name . '-' . $mod->package_version;
    my $author  = $mod->author->author;
    my $email   = $mod->author->email || CPAN_MAIL_ACCOUNT->( $author );   
    my $cp_conf = $conf->get_conf('cpantest') || '';
    my $int_ver = $CPANPLUS::Internals::VERSION;

    
    ### determine the grade now ###
    
    my $grade;
    ### check if this is a platform specific module ###
    unless( RELEVANT_TEST_RESULT->( $mod) ) {
        msg(loc("'%1' is a platform specific module, and the test results on".
                " your platform are not relevant --sending N/A grade.", 
                $name), $verbose);
        
        $grade = GRADE_NA;
    
    ### see if the thing even had tests ###
    } elsif ( NO_TESTS_DEFINED->( $buffer ) ) {
        $grade = GRADE_UNKNOWN;
  
    ### see if it was a pass or fail ###
    } else {      
        $grade = $failed ? GRADE_FAIL : GRADE_PASS;                
    }

    ### so an error occurred, let's see what stage it went wrong in ###
    my $message;
    if( $grade eq GRADE_FAIL or $grade eq GRADE_UNKNOWN) {
    
        ### will be 'fetch', 'make', 'test', 'install', etc ###
        my $stage   = TEST_FAIL_STAGE->($buffer);

        ### return if we're only supposed to report make_test failures ###
        return 1 if $cp_conf =~  /\bmaketest_only\b/i 
                    and ($stage !~ /\btest\b/);

        ### the header
        $message =  REPORT_MESSAGE_HEADER->( $author );    

        ### the bit where we inform what went wrong
        $message .= REPORT_MESSAGE_FAIL_HEADER->(
                        $int_ver, $stage, $buffer );
        
        ### was it missing prereqs? ###
        if( my @missing = MISSING_PREREQS_LIST->($buffer) ) {
            $message .= REPORT_MISSING_PREREQS->(@missing);
        }        

        ### was it missing test files? ###
        if( NO_TESTS_DEFINED->($buffer) ) {
            $message .= REPORT_MISSING_TESTS->();
        }
    }
    
    ### if it failed, and that already got reported, we're not cc'ing the
    ### author. Also, 'dont_cc' might be in the config, so check this;
    my $dont_cc_author = $dontcc;
    
    unless( $dont_cc_author ) {
        if( $cp_conf =~ /\bdont_cc\b/i ) {
            $dont_cc_author++;
        
        } elsif ( $grade eq GRADE_PASS ) {
            $dont_cc_author++
        
        } elsif( $grade eq GRADE_FAIL ) {
            my @already_sent = 
                $self->_query_report( module => $mod, verbose => $verbose );
            
            ### if we can't fetch it, we'll just assume no one 
            ### mailed him yet
            my $count = 0;
            if( @already_sent ) {
                for my $href (@already_sent) {
                    $count++ if uc $href->{'grade'} eq uc GRADE_FAIL;        
                }
            }
    
            if( $count > MAX_REPORT_SEND and !$force) {
                msg(loc("'%1' already reported for '%2', ".
                        "not cc-ing the author",
                        GRADE_FAIL, $dist ), $verbose );
                $dont_cc_author++;
            }                   
        }    
    }

    ### reporter object ###
    my $reporter = Test::Reporter->new(
                        grade           => $grade,
                        distribution    => $dist,
                        via             => "CPANPLUS $int_ver",
                    ); 

    ### set the from address ###
    $reporter->from( $conf->get_conf('email') ) 
        if $conf->get_conf('email') !~ /\@example\.\w+$/i;
    
    ### add the body if we have any ###
    $reporter->comments( $message ) if defined $message && length $message;
    
    ### ask if you'd like to actually send the report, since it's a fail
    if ($grade eq GRADE_FAIL and not
        $self->_callbacks->send_test_report->($mod)
    ) {
        msg(loc("Ok, not sending test report"));
        return 1;
    }
    
    ### do a callback to ask if we should edit the report
    ### if the grade is a 'fail'
    if ($grade eq GRADE_FAIL and
        $self->_callbacks->edit_test_report->($mod) 
    ) {      
        ### test::reporter 1.20 and lower don't have a way to set
        ### the preferred editor with a method call, but it does
        ### respect your env variable, so let's set that.
        local $ENV{VISUAL} = $conf->get_program('editor')
                                if $conf->get_program('editor');
        
        $reporter->edit_comments;
    }                                

    ### people to mail ###
    my @inform;
    #push @inform, $email unless $dont_cc_author;  

    ### allow to be overridden, but default to the normal address ###
    $reporter->address( $address );
    
    ### should we save it locally? ###
    if( $save ) {
        if( my $file = $reporter->write() ) {
            msg(loc("Succesfully wrote report for '%1' to '%2'", 
                    $dist, $file), $verbose);
            return $file;
        
        } else {
            error(loc("Failed to write report for '%1'", $dist));
            return;
        }
        
    ### should we send it to a bunch of people? ###
    ### XXX should we do an 'already sent' check? ###
    } elsif( $reporter->send( @inform ) ) {
        msg(loc("Succesfully sent report for '%1'", $dist), $verbose);
        return 1;
    
    ### something broke :( ###
    } else {
        error(loc("Could not send report for '%1': %2", 
                $dist, $reporter->errstr));
        return;
    }
}

1;


# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
