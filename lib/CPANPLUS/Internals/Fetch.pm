# $File: //member/autrijus/cpanplus/dist/lib/CPANPLUS/Internals/Fetch.pm $
# $Revision: #3 $ $Change: 3544 $ $DateTime: 2002/03/26 07:48:03 $

#######################################################
###            CPANPLUS/Internals/Fetch.pm          ###
###      Subclass to fetch modules for cpanplus     ###
###         Written 23-02-2002 by Jos Boumans       ###
#######################################################

### Fetch.pm ###

package CPANPLUS::Internals::Fetch;

use strict;
use CPANPLUS::Configure;
use CPANPLUS::Error;
use FileHandle;
use Data::Dumper;

BEGIN {
    use Exporter    ();
    use vars        qw( @ISA $VERSION );
    @ISA        =   qw( Exporter );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

### method to download a file from CPAN
sub _fetch {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    ### test for Backend->flush
    ###print "this is methods: ", Dumper $self->{_methods};

    ### OK, I am altering the behavior a bit here
    ###
    ### If you pass a $args{data} module 'object', the file name and remote path
    ### will be obtained from it.  This is as before.
    ###
    ### Also, you will still be able to alter the local file name and path
    ### with $args{file} and $args{fetchdir}.
    ###
    ### What it *does* change though, is the old way of a supplied $args{file}
    ### overriding the remote file name.  That no longer occurs for the remote
    ### file name.
    ###
    ### -jmb

    my ($path, $remote_path);

    ### get the file name and remote path

    if ($args{data}) {
        ### they gave us a module 'object'
        $remote_path = File::Spec::Unix->catfile(
                          $conf->_get_ftp('base'),
                          $args{data}->{path},
                          $args{data}->{package},
                      );

    } else {
        ### no module, must 'build' our own
        $remote_path = File::Spec::Unix->catfile($args{dir}, $args{file});
    }

    ### with no remote path we can't really expect to fetch anything!
    unless ($remote_path) {
        $err->inform(
            msg   => "No remote file given to download!",
            quiet => !$conf->get_conf('verbose')
        );
        return 0;
    }

    ### get the local path+filename
    ### ($args{file} and $args{fetchdir} will always override)
    ### the default local path will now look like remote - we 'mirror' CPAN -jmb

    my $local_path = $args{fetchdir}
                  || File::Spec->catdir(
                         $conf->_get_build('base'),
                         $conf->_get_ftp('base'),
                         $args{data}->{path},
                     );

    ### must insure that this directory exists or we will get errors later
    unless (-d $local_path) {
        ### we *must* eval here because mkpath dies on errors -jmb
        #local $@; - can't use this, it's buggy -kane
        eval { File::Path::mkpath($local_path) };

        if ($@) {
            chomp($@);
            $err->inform(
                msg   => "could not create $local_path: $@",
                quiet => !$conf->get_conf('verbose'),
            );
            return 0;
        }
    }

    my $local_file = $args{file} || $args{data}->{package};
    #my $local_file = $args{file} || $args{data}->{path};

    $path->{local} = File::Spec->catfile($local_path, $local_file);

    ### no sense in dl'ing the file if we already have it - unless you force
    ### BUG HERE - tried to delete my root-dir (d:/cpandevel) when updating sources
    ### try to track down what's going on - Kane
    ### then you passed it the dir only, with no file
    ### ie, $args{file} was blank and there was no $args{data} -jmb
    ### perhaps we should return in this case?
    ### I had assumed you may have passed the file in $args{fetchdir} -jmb
    if (-e $path->{local}) {

        if ($args{force} || $conf->get_conf('force')) {

            ### on at least two of the _*_get methods an existing file will
            ### cause failure, so we delete the file now to prevent that -jmb
            unlink $path->{local}
                or $err->inform(
                       msg   => "couldn't delete $path->{local}"
                              . ", some methods may fail to force a download",
                       quiet => !$conf->get_conf('verbose'),
                   );
        } else {

            ### the file exists and you didn't force - we return the old version
            $err->inform(
                msg   => "already downloaded $path->{local}"
                       . ", won't download again without force",
                quiet => !$conf->get_conf('verbose'),
            );

            return $path->{local};
        }
    }

    ### methods available to fetch the file depending on the scheme
    my $methods = {
        http => [ qw|lwp wget lynx| ],
        ftp  => [ qw|lwp ftp ncftpget wget lynx ncftp| ],
        file => [ qw|lwp file| ],
    };

    HOST:
    for my $uri (@{$self->{_conf}->_get_ftp('urilist')}) {

        ### full path to remote file
        $path->{remote} = File::Spec::Unix->catdir($uri->{path}, $remote_path);

        $args{path} = $path;
        $args{uri}  = $uri;

        #print map { Data::Dumper->Dump([$args{$_}], [$_]) } keys %args;

        $err->inform(
                msg   => "Trying to get $args{'path'}->{'remote'} from ".
                         ($uri->{host} || 'local disk'),
                quiet => !$conf->get_conf('verbose'),
        );

        METHOD:
        ### tests by kane: ncftpget seems to work great
        ### wget has issues, connecting but not mirroring
        ### lynx 'cant access startfile' and errors out
        ### ncftp's newer versions don't like the -a option
        ### so it errors out on my machine. Tests on:
        ### Linux sammy 2.4.7-10 #1 i686 unknown

        for my $m ( @{ $methods->{$uri->{scheme}} } ) {
            my $method = "_${m}_get"; #_lwp_get, etc

            ### either this method is available, or we haven't tried it yet
            if ($self->{_methods}->{$method}
             || ! exists $self->{_methods}->{$method}) {

                if (my $file = $self->$method(%args)) {

                    unless (-e $path->{local} && -s _) {

                        $self->{_methods}->{$method} = 0;
                        $err->inform(
                            msg   => "$method said it fetched $path->{local}"
                                   . ", but it was not created!",
                            quiet => !$conf->get_conf('verbose'),
                        );

                    } else {
                        return $file;
                    }
                }
            }

            ### this comment gleaned from CPAN.pm -jmb
            # Alan Burlison informed me that in firewall environments
            # Net::FTP can still succeed where LWP fails. So we do not
            # skip Net::FTP anymore when LWP is available.
            ### I have not implemented such an idea yet -jmb

            ### $method *works* but this host is bad - try the next one
            next HOST, if $self->{_methods}->{$method};

        } #for (METHOD)

        $err->inform(
            msg     => "Fetch failed: no way to download source file!",
            quiet   => !$conf->get_conf('verbose')
        );
        return 0;

    } #for (HOST)

    ### we exhausted the entire host list - _fetch truly failed
    ### is this where we use ftp.funet.fi as a last resort? or ftp.cpan.org? - kane
    ### no, if we got this far we just give up - we COULD loop back in though
    ### what I *don't* want to do is always fall back to ftp.funet.fi
    ### it would be better to force them to set up correctly -jmb
    $err->inform(
        msg     => "Fetch failed: host list exhausted - are you connected today?",
        quiet   => !$conf->get_conf('verbose')
    );
    return 0;

} #_fetch


sub _lwp_get {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    ### hard coding is not very graceful
    ### i propose this as a more elegant solution:
    #my $method = '_lwp_get';
    my $method = $self->_whoami();
    $method =~ s/.*://; # strip fully-qualified portion;

    ### check prerequisites
    my $use_list = {
        LWP             => '0.0',
        'LWP::UserAgent'  => '0.0',
        'HTTP::Request'   => '0.0',
        URI             => '0.0',
    };

    if ($self->_can_use($use_list)) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        ### avoid two calls
        my $email = $conf->_get_ftp('email');

        ### create a URI
        ### it doesn't work to pass the scheme here for some reason
        my $uri = URI->new($args{path}->{remote});

        ### set scheme and host
        $uri->scheme($args{uri}->{scheme});
        $uri->host($args{uri}->{host}) unless $uri->scheme eq 'file';

        ### set user/password
        ### it doesn't like the u/p set when it's a 'file://' scheme....
        ### i found it returns from the sub without error/warnign, whatever
        ### kinda scary.. -kane
        ### why scary? does the fetch below not fail? -jmb
        $uri->userinfo("anonymous:$email") unless $uri->scheme eq 'file';

        ### create our UA
        my $ua = LWP::UserAgent->new();

        ### set everything
        ### these must be done *after* we create the UA object
        $ua->agent("CPANPLUS/$CPANPLUS::Internals::VERSION");
        $ua->env_proxy();
        $ua->from($email);

        ### get the file!
        my $res = $ua->mirror($uri, $args{path}->{local});

        ### we need better handlers... especially for 304
        ### we already throw out 304's with the force check so remove this -jmb
        #if ($res->code == 304) {
        #    $err->inform(
        #        msg     => "already downloaded $args{path}->{local}, " .
        #                    "won't download again without force",
        #        quiet   => !$conf->get_conf('verbose')
        #    );
        #    ### we shouldn't return the same thing in two different places -jmb
        #    ### solution? - Kane
        #    return $args{path}->{local};
        #}

        ### the only acceptable return from this is OK (200)
        if ($res->code == 200) {
            return $args{path}->{local};
        } else {
            $err->trap( error => "fetch failed! " . $res->code );
            return 0;
        }

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg => "Can't use LWP",
            quiet => !$conf->get_conf('verbose')
        );

        return 0;
    }

} #_lwp_get


sub _file_get {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $subname = $self->_whoami();
    my ($method) = $subname =~ m|.+::(.+?)|;

    my $use_list = {
        'File::Spec'  => '0.82',
        'File::Copy'  => '0.0',
    };

    if ($self->_can_use($use_list)) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        ### since we're now expecting local mirrors, we can't be sure
        ### that the dir delimers are the same.
        ### so, we split the entire damn thing out in seperate dirs,
        ### then re-make the path, making sure we got the delimiters properly
        ### this might not be necessary this way, so feel free to change/patch
        ### -kane

        my ($volume, $path, $file)  = File::Spec->splitpath( $args{path}->{remote} );
        my @dirs                    = File::Spec->splitdir( $path );

        unshift @dirs, $args{uri}->{host} if defined $args{uri}->{host};

        my $remote = File::Spec->catfile( @dirs, $file );
        my $local = $args{path}->{local};

        {
            ### file::copy is littered with DIE statements
            ### so must eval...
            #local $@; - can't use this, it's buggy -kane
            my $rv = eval( File::Copy::copy( $remote, $local ) );

            if ( !$rv or $@ ) {
                $err->trap( error => qq[Could not copy $remote to $local: $! $@] );
                return 0;
            }
        }

        ### actually, since we just want to copy over a file location
        ### there's no real name for File::Copy and it's weird behaviour.
        ### so we'll just do it ourselves: -kane

        ### we can use this as soon as we can do a check if the path exists
        ### and make it if it doesn't. -kane

#        my ($infile, $outfile);
#        unless ( open $infile, $remote ) {
#            $err->trap( error => qq[Could not open $remote for reading: $!] );
#            return 0;
#        }
#
#        unless ( open $outfile, $local ) {
#            $err->trap( error => qq[Could not open $local for writing: $!] );
#            return 0;
#        }
#
#        binmode $infile;
#        binmode $outfile;
#
#        while(<$infile>) { print $outfile $_; }

        return $local;

    } else {

        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg => "Can't use File::* functions. They should be core modules!",
            quiet => !$conf->get_conf('verbose')
        );

        return 0;
    }
}


sub _ftp_get {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $subname = $self->_whoami();
    my ($method) = $subname =~ m|.+::(.+?)|;

    ### check prerequisites
    my $use_list = { 'Net::FTP' => '0.0' };

    if ($self->_can_use($use_list)) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        ### is this true? -jmb
        #unless ($args{uri}->{scheme} eq 'ftp') {
        #    $err->inform(
        #        msg   => "Net::FTP only works with ftp capable hosts",
        #        quiet => !$conf->get_conf('verbose')
        #    );
        #    return 0;
        #}

        ### connect
        my $ftp;
        unless ($ftp = Net::FTP->new($args{uri}->{host})) {
            $err->trap( error => "ftp creation failed: $@" );
            return 0;
        };

        ### login
        unless ($ftp->login('anonymous', $conf->_get_ftp('email'))) {
            $err->trap( error => "could not log in to $args{uri}->{host}" );
            return 0;
        };

        ### do we really need to do this?
        ### so far my testing says no... -jmb
        ### i want to trap errors is stuff goes wrong tho - Kane
        ### So then lets see what errors Net::FTP will cough up -jmb
        ### chdir
        #unless ($ftp->cwd($path)) {
        ##unless ($ftp->cwd($dir)) {
        #    $err->trap( error => "could not cd into $path" );
        #    #$err->trap( error => "could not cd into $dir" );
        #    return 0;
        #};

        ### binmode
        $ftp->binary;

        ### temps to keep the line lengths in order :o)
        my ($remote, $local) = ($args{path}->{remote}, $args{path}->{local});

        ### get the damn thing
        my $target;
        unless ($target = $ftp->get($remote, $local)) {
            $err->trap(
                error => "could not fetch $remote from $args{uri}->{host}"
            );
            return 0;
        };

        ### logoff
        $ftp->quit; # it's ok if this fails

        return $target;

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => "Can't use Net::FTP",
            quiet => !$conf->get_conf('verbose')
        );
        return 0;
    }
} #_ftp_get


### lynx is stupid - it decompresses any .gz file it finds to be text
sub _lynx_get {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $subname = $self->_whoami();
    my ($method) = $subname =~ m|.+::(.+?)|;

    if (my $lynx = $conf->_get_build('lynx')) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        my $url = "$args{uri}->{scheme}://"
                . $args{uri}->{host}
                . $args{path}->{remote};

        my $email = $conf->_get_ftp('email');

        #$url =~ s/pub/ub/;

        my $command = qq[$lynx -source -auth=anonymous:$email $url |];

        my $remote = new FileHandle;
        unless ($remote->open($command)) {
            $err->trap( error => "Could not fork opening $command: $!" );
            return 0;
        }

        #$remote->autoflush;
        binmode $remote;

        my $data;
        {
            local $/ = undef;
            $data = <$remote>;
        }

        unless ($remote->close) {
            $err->trap( error => "Could not 'close' $command: $!");
            return 0;
        }

        my $local = new FileHandle;
        unless ($local->open(">$args{path}->{local}")) {
            $err->trap( error => "Could not open $args{path}->{local}: $!" );
            return 0;
        }

        #$local->autoflush;
        binmode $local;

        unless ($local->print($data)) {
            $err->trap( error => "Could not write to $args{path}->{local}: $!" );
            return 0;
        }

        unless ($local->close) {
            $err->inform(
                msg   => "Could not close $args{path}->{local}: $!",
                quiet => !$conf->get_conf('verbose'),
            );
        }

        return $args{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => "lynx not available",
            quiet => !$conf->get_conf('verbose')
        );

        return 0;
    }

}


sub _ncftpget_get {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $subname = $self->_whoami();
    my ($method) = $subname =~ m|.+::(.+?)|;

    my $use_list = { 'File::Spec' => '0.82' };

    if (my $ncftpget = $conf->_get_build('ncftpget') and $self->_can_use($use_list) ) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        unless ($args{uri}->{scheme} eq 'ftp') {
            $err->inform(
                msg   => "ncftpget only works with ftp capable hosts",
                quiet => !$conf->get_conf('verbose')
            );
            return 0;
        }

        my $email = $conf->_get_ftp('email');

        ### portably find the full local directory path
        my ($vol, $dir, $file) = File::Spec->splitpath($args{path}->{local});
        my $local_dir          = File::Spec->catdir($vol, $dir);

        my $command = join(
                          ' ',
                           $ncftpget,             # program
                           #qq["$ncftpget"],       # program
                           #"-d stderr,            # debug to stdout
                           '-V',                  # not verbose
                           "-p $email",           # $email as pwd
                           $args{uri}->{host},    # ftp host
                           qq["$local_dir"],      # local dir for file
                           $args{path}->{remote}, # remote path to file
                           '2>&1',                # stderr => stdout
                       );

        my $rc = qx[$command];

        if ($rc || ! defined $rc) {
            $rc ||= '';

            $rc =~ s/\n/ /g;
            $err->trap( error => "command $command failed: $rc" );
            #$err->inform( msg => "command $command failed: $rc" );
            ### we don't want to try a new host, the command itself failed
            $self->{_methods}->{$method} = 0;
            return 0;
        }

        return $args{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => "ncftpget not available",
            quiet => !$conf->get_conf('verbose')
        );

        return 0;
    }

}


### bug in wget:
### creates an empty local file when the remote file does not exist
### and --quiet kills ALL output to stderr, but --non-verbose doesn't work
### buggy on redhat 7.1 in my experience - kane
sub _wget_get {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $subname = $self->_whoami();
    my ($method) = $subname =~ m|.+::(.+?)|;

    if (my $wget = $conf->_get_build('wget')) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        my $url = "$args{uri}->{scheme}://"
                . $args{uri}->{host}
                . $args{path}->{remote};

        my $email = $conf->_get_ftp('email');

        ### FSCK!!!
        ### to get it working on both NT4 and *nix had to leave $wget unquoted
        ### which means on win you must give a space free path to this pgm -jmb
        ###
        ### not to mention only qx[] would work on both reliably...

        ### these long opts are self explanatory - I like that -jmb
        my $command = join(
                          ' ',
                          #'get',
                          $wget,
                          '--quiet',
                          #'--non-verbose', # quiet is *too* quiet -jmb
                          #'--verbose',
                          "--execute passwd=$email",
                          #'--output-document=-',
                          qq[--output-document "$args{path}->{local}"],
                          $url,
                      );

        ### redirect stderr to stdout - with --quiet this should only produce
        ### output if the program wasn't found, I hope -jmb
        my $rc = qx[$command 2>&1];
        #my $rc = qx[$command];

#    qx/STRING/
#    `STRING`
#
#        A string which is (possibly) interpolated and then executed as a system
#        command with /bin/sh or its equivalent.  Shell wildcards, pipes, and
#        redirections will be honored.  The collected standard output of the
#        command is returned; standard error is unaffected.  In scalar context,
#        it comes back as a single (potentially multi-line) string, or undef if
#        the command failed.

        if ($rc || ! defined $rc) {
            $rc ||= '';
            $rc =~ s/\n/ /g;
            $err->trap( error => "command $command failed: $rc" );
            #$err->inform( msg => "command $command failed: $rc" );
            ### we don't want to try a new host, the command itself failed
            $self->{_methods}->{$method} = 0;
            return 0;
        }

        return $args{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => "wget not available",
            quiet => !$conf->get_conf('verbose')
        );

        return 0;
    }

}


### only works with older versions of ncftp
sub _ncftp_get {
    my $self = shift;
    my %args = @_;

    my $conf = $self->{_conf};
    my $err  = $self->{_error};

    my $subname = $self->_whoami();
    my ($method) = $subname =~ m|.+::(.+?)|;

    if (my $ncftp = $conf->_get_build('ncftp')) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        unless ($args{uri}->{scheme} eq 'ftp') {
            $err->inform(
                msg   => "ncftp only works with ftp capable hosts",
                quiet => !$conf->get_conf('verbose')
            );
            return 0;
        }

        my $url = "$args{uri}->{scheme}://"
                . $args{uri}->{host}
                . $args{path}->{remote};

        my $command = qq[$ncftp -a $url 2>&1 1>"$args{path}->{local}"];

        my $rc = qx[$command];
        if ($rc || ! defined $rc) {
            $rc ||= '';
            $rc =~ s/\n.*//gs;
            $err->trap( error => "command $command failed: $rc" );
            #$err->inform(
            #    msg   => "command $command failed: $rc",
            #    quiet => ! $conf->get_conf('verbose'),
            #);
            ### we don't want to try a new host, the command itself failed
            $self->{_methods}->{$method} = 0;
            return 0;
        }

        return $args{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => "ncftpget not available",
            quiet => !$conf->get_conf('verbose')
        );

        return 0;
    }

}

1;
