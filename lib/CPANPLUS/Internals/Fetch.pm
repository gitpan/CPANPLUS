# $File: //depot/cpanplus/dist/lib/CPANPLUS/Internals/Fetch.pm $
# $Revision: #11 $ $Change: 11204 $ $DateTime: 2004/09/20 20:15:05 $

#######################################################
###            CPANPLUS/Internals/Fetch.pm          ###
###      Subclass to fetch modules for cpanplus     ###
###         Written 23-02-2002 by Jos Boumans       ###
#######################################################

### Fetch.pm ###

package CPANPLUS::Internals::Fetch;

use strict;
use FileHandle;
use Data::Dumper;
use CPANPLUS::I18N;
use CPANPLUS::Tools::Check qw[check];

BEGIN {
    use vars        qw( $VERSION );
    $VERSION    =   $CPANPLUS::Internals::VERSION;
}

### method to download a file from CPAN
sub _fetch {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

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

    my $tmpl = {
        file        => { default => '' },
        dir         => { default => '' },
        fetchdir    => { default => '' },
        force       => { default => $conf->get_conf('force') },
        verbose     => { default => $conf->get_conf('verbose') },
        data        => { allow => sub { ref $_[1] &&
                                          $_[1]->isa('CPANPLUS::Internals::Module')
                                      } },
    };


    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose = $args->{verbose};
    my $force   = $args->{force};

    my $remote_path;
    ### get the file name and remote path
    if (my $modobj = $args->{data}) {
        ### they gave us a module 'object'
        $remote_path = File::Spec::Unix->catfile(
                          $conf->_get_ftp('base'),
                          $modobj->path,
                          $modobj->package,
                      );

    } else {
        ### no module, must 'build' our own
        $remote_path = File::Spec::Unix->catfile( $args->{dir}, $args->{file} );
    }

    ### with no remote path we can't really expect to fetch anything!
    unless ($remote_path) {
        $err->inform(
            msg   => loc("No remote file given to download!"),
            quiet => !$verbose
        );
        return 0;
    }

    ### get the local path+filename
    ### ($args{file} and $args{fetchdir} will always override)
    ### the default local path will now look like remote - we 'mirror' CPAN -jmb

    my $local_path = $args->{fetchdir}
                  || File::Spec->catdir(
                         $conf->_get_build('base'),
                         $conf->_get_ftp('base'),
                         $args->{data}->path,
                     );

    ### must insure that this directory exists or we will get errors later
    unless (-d $local_path) {
        unless( $self->_mkdir( dir => $local_path ) ) {
            $err->inform(
                msg   => loc("Could not create %1", $local_path) ,
                quiet => !$conf->get_conf('verbose'),
            );
            return 0;
        }
    }

    my $local_file = $args->{file} || $args->{data}->package;

    my $path = {
        local => File::Spec->catfile($local_path, $local_file)
    };

    ### no sense in dl'ing the file if we already have it - unless you force
    ### BUG HERE - tried to delete my root-dir (d:/cpandevel) when updating sources
    ### try to track down what's going on - Kane
    ### then you passed it the dir only, with no file
    ### ie, $args{file} was blank and there was no $args{data} -jmb
    ### perhaps we should return in this case?
    ### I had assumed you may have passed the file in $args{fetchdir} -jmb
    if (-e $path->{local}) {
        if ($force) {

            ### on at least two of the _*_get methods an existing file will
            ### cause failure, so we delete the file now to prevent that -jmb
            unlink $path->{local}
                or $err->inform(
                       msg   => loc("Could not delete %1, some methods may fail to force a download", $path->{local}),
                       quiet => !$verbose
                   );
        } else {

            ### the file exists and you didn't force - we return the old version
            $err->inform(
                msg   => loc("Already downloaded %1, won't download again without force", $path->{local}),
                quiet => !$verbose,
            );

            ### store this info in the object if we got an object ###
            if ($args->{data}) { $args->{data}->status->fetch( $path->{local} ) }

            return $path->{local};
        }
    }

    ### methods available to fetch the file depending on the scheme
    my $methods = {
        http => [ qw|lwp wget curl lynx| ],
        ftp  => [ qw|lwp netftp ncftpget wget curl lynx ftp ncftp| ],
        file => [ qw|lwp curl file| ],
        rsync => [ qw|filersyncp rsync| ],
    };

    ### potential bad hosts -- won't know for sure until there's one successful later
    my @bad_uris;

	my @uri_list = @{$self->configure_object->_get_ftp('urilist')};	
	unless( @uri_list ) {
		$err->trap(error => loc("You have no mirrors defined! Can not fetch anything."));
		return;
	}	


    HOST:
    for my $uri ( @uri_list ) {
        ### some URIs does not work
        next if exists $self->{_uris}{$uri} and !$self->{_uris}{$uri};

        ### full path to remote file
        $path->{remote} = File::Spec::Unix->catdir($uri->{path}, $remote_path);

        ### add these arguments for calls to the *get methods ###

        #print map { Data::Dumper->Dump([$args{$_}], [$_]) } keys %args;

        $err->inform(
                msg   => loc("Trying to get %1 from %2 via %3", $path->{'remote'},
                             ($uri->{host} || loc('local disk')), $uri->{scheme}),
                quiet => !$verbose,
        );

        my $meth_args = {
                path    => $path,
                uri     => $uri,
                verbose => $verbose,
        };

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

                if (my $file = $self->$method(%$meth_args)) {
                    ### this host is good, previous ones are not
                    $self->{_uris}{$uri} = 1;
                    $self->{_uris}{$_} = 0 foreach @bad_uris;

                    unless (-e $path->{local} && -s _) {

                        $self->{_methods}->{$method} = 0;
                        $err->inform(
                            msg   => loc("%1 said it fetched %2, but it was not created!",
                                         $method, $path->{local}),
                            quiet => !$verbose,
                        );

                    } else {
                        ### store this info in the object if we got an object ###
                        if ($args->{data} ) { $args->{data}->status->fetch( $file ) }

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
            if ($self->{_methods}->{$method}) {
                push @bad_uris, $uri;
                next HOST;
            }

        } #for (METHOD)

        $err->inform(
            msg     => loc("Fetch failed: no way to download source file!"),
            quiet   => !$verbose
        );
        return 0;

    } #for (HOST)

    ### we exhausted the entire host list - _fetch truly failed
    ### is this where we use ftp.funet.fi as a last resort? or ftp.cpan.org? - kane
    ### no, if we got this far we just give up - we COULD loop back in though
    ### what I *don't* want to do is always fall back to ftp.funet.fi
    ### it would be better to force them to set up correctly -jmb
    $err->inform(
        msg     => loc("Fetch failed: host list exhausted - are you connected today?"),
        quiet   => !$verbose
    );
    return 0;

} #_fetch


sub _lwp_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};

    ### hard coding is not very graceful
    ### i propose this as a more elegant solution:
    #my $method = '_lwp_get';
    my $method = $self->_whoami();
    $method =~ s/.*://; # strip fully-qualified portion;

    ### check prerequisites
    my $use_list = {
        LWP                 => '0.0',
        'LWP::UserAgent'    => '0.0',
        'HTTP::Request'     => '0.0',
        'HTTP::Status'      => '0.0',
        URI                 => '0.0',

    };

    if ($self->_can_use(modules => $use_list)) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        ### avoid two calls
        my $email = $conf->_get_ftp('email');

        ### create a URI
        ### it doesn't work to pass the scheme here for some reason
        my $uri = URI->new( $args->{path}->{remote} );

        ### set scheme and host
        $uri->scheme( $args->{uri}->{scheme} );
        $uri->host( $args->{uri}->{host} ) unless $uri->scheme eq 'file';

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
        my $res = $ua->mirror($uri, $args->{path}->{local});

        ### we need better handlers... especially for 304
        ### we already throw out 304's with the force check so remove this -jmb
        ### reactivated for 'x' (rebuild index) command in default shell -autrijus

        if ($res->code == 304) {
            $err->inform(
                msg     => loc("%1 is up to date", $args->{path}->{local}),
                quiet   => !$verbose
            );
            ### we shouldn't return the same thing in two different places -jmb
            ### solution? - Kane
            return $args->{path}->{local};
        }

        ### the only acceptable return from this is OK (200)
        if ($res->code == 200) {
            return $args->{path}->{local};
        } else {
            $err->trap(
                error => loc("Fetch failed! HTTP response code: %1 [%2]", $res->code,
                             HTTP::Status::status_message($res->code)),
            );
            return undef;
        }

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg => loc("Can't use LWP"),
            quiet => !$verbose
        );

        return undef;
    }

} #_lwp_get


sub _file_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $subname     = $self->_whoami();
    my ($method)    = $subname =~ m|.+::(.+?)|;

    my $use_list = {
        'File::Spec'  => '0.82',
        'File::Copy'  => '0.0',
    };

    if ($self->_can_use(modules => $use_list)) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        ### since we're now expecting local mirrors, we can't be sure
        ### that the dir delimers are the same.
        ### so, we split the entire damn thing out in seperate dirs,
        ### then re-make the path, making sure we got the delimiters properly
        ### this might not be necessary this way, so feel free to change/patch
        ### -kane

        my ($volume, $path, $file)  = File::Spec->splitpath( $args->{path}->{remote} );
        my @dirs                    = File::Spec->splitdir( $path );

        unshift @dirs, $args->{uri}->{host} if defined $args->{uri}->{host};

        my $remote = File::Spec->catfile( @dirs, $file );
        my $local = $args->{path}->{local};

        {
            ### file::copy is littered with DIE statements
            ### so must eval...
            #local $@; - can't use this, it's buggy -kane
            my $rv = eval( File::Copy::copy( $remote, $local ) );

            if ( !$rv or $@ ) {
                $err->trap( error => loc("Could not copy %1 to %2: %3 %4", $remote, $local, $!, $@ ) );
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
            msg => loc("Can't use File::* functions. They should be core modules!"),
            quiet => !$verbose
        );

        return 0;
    }
}

sub _ftp_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;


    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $subname     = $self->_whoami();
    my ($method)    = $subname =~ m|.+::(.+?)|;

    if (my $ftp = $conf->_get_build('ftp')) {
        my $fh = FileHandle->new;

        local $SIG{CHLD} = 'IGNORE';
        unless ($fh->open("|$ftp -n")) {
            $err->trap( error => loc("ftp creation failed: %1", $!) );
            return 0;
        }

        my $email = $conf->_get_ftp('email');
        my ($remote, $local) = ($args->{path}->{remote}, $args->{path}->{local});

        my @remote_path = split('/', $remote); $remote = pop @remote_path;
        my @local_path  = split('/', $local);  $local  = pop @local_path;

        my @dialog = (
            "lcd ".join('/', @local_path),
            "open $args->{uri}->{host}",
            "user anonymous $email",
            "cd /",
            (map { "cd $_" } grep { length } @remote_path),
            "binary",
            "get $remote $local",
            "quit",
        );

        foreach (@dialog) { $fh->print($_, "\n") }
        $fh->close;

        return -e $args->{path}->{local} ? $args->{path}->{local} : undef;
    }
}


sub _netftp_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $subname     = $self->_whoami();
    my ($method)    = $subname =~ m|.+::(.+?)|;

    ### check prerequisites
    my $use_list = { 'Net::FTP' => '0.0' };

    if ($self->_can_use(modules => $use_list)) {

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
        unless ($ftp = Net::FTP->new($args->{uri}->{host})) {
            $err->trap( error => loc("ftp creation failed: %1", $@) );
            return 0;
        };

        ### login
        unless ($ftp->login('anonymous', $conf->_get_ftp('email'))) {
            $err->trap( error => loc("could not log in to %1", $args->{uri}->{host}) );
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
        my ($remote, $local) = ($args->{path}->{remote}, $args->{path}->{local});

        ### get the damn thing
        my $target;
        unless ($target = $ftp->get($remote, $local)) {
            $err->trap(
                error => loc("could not fetch %1 from %2", $remote, $args->{uri}->{host})
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
            msg   => loc("Can't use Net::FTP"),
            quiet => !$verbose
        );
        return 0;
    }
} #_ftp_get


### lynx is stupid - it decompresses any .gz file it finds to be text
sub _lynx_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $subname     = $self->_whoami();
    my ($method)    = $subname =~ m|.+::(.+?)|;

    if (my $lynx = $conf->_get_build('lynx')) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        my $url = $args->{uri}->{scheme} . q[://]
                . $args->{uri}->{host}
                . $args->{path}->{remote};

        my $email = $conf->_get_ftp('email');
        my $captured;

        unless ( $self->_run(
            command => [
                $lynx,
                '-source',
                "-auth=anonymous:$email",
                $url
            ],
            buffer  => \$captured,
            verbose => 0,
        ) ) {
            $err->trap( error => loc("Could not run command: %1", $!) );
            return 0;
        }

        my $local = new FileHandle;
        unless ($local->open(">$args->{path}->{local}")) {
            $err->trap( error => loc("Could not open %1: %2", $args->{path}->{local}, $!) );
            return 0;
        }

        binmode $local;
        unless ($local->print($captured)) {
            $err->trap( error => loc("Could not write to %1: %2", $args->{path}->{local}, $!) );
            return 0;
        }

        unless ($local->close) {
            $err->inform(
                msg   => loc("Could not close %1: %2", $args->{path}->{local}, $!),
                quiet => !$verbose,
            );
        }

        return $args->{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => loc("%1 not available", "lynx"),
            quiet => !$verbose
        );

        return undef;
    }

}


sub _ncftpget_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $subname     = $self->_whoami();
    my ($method)    = $subname =~ m|.+::(.+?)|;
    my $use_list    = { 'File::Spec' => '0.82' };

    if (my $ncftpget = $conf->_get_build('ncftpget') and $self->_can_use(modules => $use_list) ) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        unless ($args->{uri}->{scheme} eq 'ftp') {
            $err->inform(
                msg   => loc("ncftpget only works with ftp capable hosts"),
                quiet => !$verbose
            );
            return 0;
        }

        my $email = $conf->_get_ftp('email');

        ### portably find the full local directory path
        my ($vol, $dir, $file) = File::Spec->splitpath($args->{path}->{local});
        my $local_dir          = File::Spec->catdir($vol, $dir);
        my $captured;

        unless ( $self->_run(
            command => [
                $ncftpget,             # program
                '-V',                  # not verbose
                '-p', $email,          # $email as pwd
                $args->{uri}->{host},    # ftp host
                $local_dir,            # local dir for file
                $args->{path}->{remote}, # remote path to file
            ],
            buffer  => \$captured,
            verbose => 0,
        ) ) {
            $captured =~ s/\n/ /g;
            $err->trap( error => loc("command failed: %1", $captured) );

            ### we don't want to try a new host, the command itself failed
            $self->{_methods}->{$method} = 0;
            return undef;
        }

        return $args->{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => loc("%1 not available", "ncftpget"),
            quiet => !$verbose
        );

        return undef;
    }

}


### bug in wget:
### creates an empty local file when the remote file does not exist
### and --quiet kills ALL output to stderr, but --non-verbose doesn't work
### buggy on redhat 7.1 in my experience - kane
sub _wget_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $subname     = $self->_whoami();
    my ($method)    = $subname =~ m|.+::(.+?)|;

    if (my $wget = $conf->_get_build('wget')) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        my $url = $args->{uri}->{scheme} . q[://]
                . $args->{uri}->{host}
                . $args->{path}->{remote};

        my $email = $conf->_get_ftp('email');
        my $captured;

        ### these long opts are self explanatory - I like that -jmb
        my $cmd = [
                    $wget,
                    '--quiet',
                    '--execute', "passwd=$email",
                    '--output-document', $args->{path}->{local},
                    $url,
            ];

        if($conf->_get_ftp('passive') or $ENV{FTP_PASSIVE} ) {
            splice @$cmd, 1, 0, '--passive-ftp';
        }

        unless ( $self->_run(
            command => $cmd,
            buffer  => \$captured,
            verbose => 0,
        ) ) {
            $captured =~ s/\n/ /g;
            $err->trap( error => loc("command failed: %1", $captured) );

            ### we don't want to try a new host, the command itself failed
            $self->{_methods}->{$method} = 0;
            return undef;
        }

        return $args->{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => loc("%1 not available", "wget"),
            quiet => !$verbose
        );

        return undef;
    }

}


### only works with older versions of ncftp
sub _ncftp_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $subname     = $self->_whoami();
    my ($method)    = $subname =~ m|.+::(.+?)|;

    if (my $ncftp = $conf->_get_build('ncftp')) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        unless ($args->{uri}->{scheme} eq 'ftp') {
            $err->inform(
                msg   => loc("ncftp only works with ftp capable hosts"),
                quiet => !$verbose
            );
            return 0;
        }

        my $url = $args->{uri}->{scheme} . q[://]
                . $args->{uri}->{host}
                . $args->{path}->{remote};

        my $captured;
        unless ( $self->_run(
            command => "$ncftp -a $url > $args->{path}{local}",
            buffer  => \$captured,
            verbose => 0,
        ) ) {
            $captured =~ s/\n.*//gs;
            $err->trap( error => loc("command failed: %1", $captured) );

            ### we don't want to try a new host, the command itself failed
            $self->{_methods}->{$method} = 0;
            return undef;
        }

        return $args->{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => loc("%1 not available", "ncftp"),
            quiet => !$verbose
        );

        return undef;
    }

}

sub _curl_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $subname     = $self->_whoami();
    my ($method)    = $subname =~ m|.::(.?)|;

    if (my $curl = $conf->_get_build('curl')) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        my $url = $args->{uri}->{scheme} . q[://]
                . ($args->{uri}->{host} || '')  # might be local host 
                . $args->{path}->{remote};

        my $email = $conf->_get_ftp('email');
        my $captured;

        ### these long opts are self explanatory - I like that -jmb
	    my $cmd = [ $curl ];

	    push(@$cmd, '--silent') unless $verbose;

    	if ($args->{uri}->{scheme} eq 'ftp') {
    		push(@$cmd, '-P', '-') unless $conf->_get_ftp('passive');
    		push(@$cmd, '--user', "anonymous:$email");
    	}

        unless ( $self->_run(
            command => [
                @$cmd,
		        #'--remote-time', # it's not supported by stock osx curl
		        '--fail', 
		        '--output', $args->{path}->{local},
		        $url,
            ],
            buffer  => \$captured,
            verbose => 0,
        ) ) {
            $captured =~ s/\n/ /g;
            $err->trap( error => loc("command failed: %1", $captured) );

            ### we don't want to try a new host, the command itself failed
            $self->{_methods}->{$method} = 0;
            return undef;
        }

        return $args->{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => loc("%1 not available", "curl"),
            quiet => !$verbose
        );

        return undef;
    }
}

sub _rsync_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $subname     = $self->_whoami();
    my ($method)    = $subname =~ m|.::(.?)|;

    if (my $rsync = $conf->_get_build('rsync')) {

        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        my $url = $args->{uri}->{scheme} . q[://]
                . $args->{uri}->{host}
                . $args->{path}->{remote};

        my $captured;

        my $cmd = [ $rsync ];
        push(@$cmd, '-v') if $verbose;

        unless ( $self->_run(
            command => [ @$cmd, '-L', $url, $args->{path}->{local} ],
            buffer  => \$captured,
            verbose => 0,
        ) ) {
            $captured =~ s/\n/ /g;
            $err->trap( error => loc("command failed: %1", $captured) );

            ### we don't want to try a new host, the command itself failed
            $self->{_methods}->{$method} = 0;
            return undef;
        }

        return $args->{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => loc("%1 not available", "rsync"),
            quiet => !$verbose
        );

        return undef;
    }
}

sub _filersyncp_get {
    my $self = shift;
    my %hash = @_;
    my $conf = $self->configure_object;
    my $err  = $self->error_object;

    my $tmpl = {
        path    => { required => 1, default => {}, strict_type => 1 },
        uri     => { required => 1, default => {}, strict_type => 1 },
        verbose => { default =>$conf->get_conf('verbose') },
    };

    my $args = check( $tmpl, \%hash ) or return undef;

    my $verbose     = $args->{verbose};
    my $subname     = $self->_whoami();
    my ($method)    = $subname =~ m|.::(.?)|;

    ### check prerequisites
    my $use_list = { 'File::RsyncP' => '0.0', 'File::Basename' => '0.0' };

    if ($self->_can_use(modules => $use_list)) {
        ### set _methods so we use this one
        $self->{_methods}->{$method} = 1;

        my ($user, $pass, $host, $port) = ($1, $2, $3, $4)
            if ($args->{uri}->{host} =~ /(?:([^:]+):([^@]+)@)?([^:]+)(?::(\d+))?/);

        my ($module, $remote) = ($1, $2)
            if $args->{path}->{remote} =~ m!^/?([^/]+)/?(.+)!;

        my ($local) = (File::Basename::fileparse($args->{path}->{local}))[1];

        my $rs = File::RsyncP->new({
            logLevel    => ($verbose ? 1 : 0),
            rsyncArgs  => [ ($verbose ? "-v" : ()), '-L' ]
        });
        my $captured = $rs->serverConnect($host, $port) or
                       $rs->serverService($module)      or
                       $rs->serverStart(1, $remote)     or
                       $rs->go($local);

        if ($captured) {
            $err->trap( error => loc("command failed: %1", $captured) );

            ### we don't want to try a new host, the command itself failed
            $self->{_methods}->{$method} = 0;
            return undef;
        }

        $rs->serverClose;
        return $args->{path}->{local};

    } else {
        ### set _methods so we don't try this again
        $self->{_methods}->{$method} = 0;

        $err->inform(
            msg   => loc("%1 not available", "rsync"),
            quiet => !$verbose
        );

        return undef;
    }
}

### give a list of still (possibly) working uris
sub _good_uris {
    my $self = shift;
    my $conf = $self->configure_object;

    my @good = grep {
                defined $self->{_uris}->{$_}
                    ? $self->{_uris}->{$_} == 0
                        ? 0                     # failed before this session
                        : 1                     # proven to work
                    : 1                         # we dont know yet
            } @{ $conf->_get_ftp('urilist') };

    return \@good;
}
1;

# Local variables:
# c-indentation-style: bsd
# c-basic-offset: 4
# indent-tabs-mode: nil
# End:
# vim: expandtab shiftwidth=4:
