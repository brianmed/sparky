package Sparky;

use Mojo::Base 'Mojolicious';

use SiteCode::Account;
use SiteCode::Site;
use Compress::Zlib;
use IO::Zlib qw(:gzip_external 0);
use Archive::Tar;
use File::Basename;
use Mojo::Util;
use Fcntl qw(:mode);
use Cwd;
use POSIX qw();

sub setup_valid {
    my $self  = shift;
    my $topics = shift;

    my $v = $self->validation;

    foreach my $topic (@{$topics}) {
        if ("login" eq $topic) {
            $v->required("login");
            $v->size(3, 16);
            $v->like(qr/^[[:alnum:]]+$/);
        }
        elsif ("password" eq $topic) {
            $v->required("password");
            $v->size(8, 16);
            $v->like(qr/^[0-9a-zA-Z]+$/),
        }
        elsif ("_password" eq $topic) {
            $v->required("_password");
            $v->equal_to("password");
        }
        elsif ("entry.name" eq $topic) {
            $v->required("entry.name");
            $v->like(qr/^[[:print:] ]+$/);
        }
    }

    return($v);
}

sub phys_dir_listing { my $self  = shift;
    my $dir_name = shift;

    my @entries = ();

    my ($dot, $dotdot);

    eval {
        my $opendir = $dir_name;

        opendir(my $dh, $opendir) or die("error: opendir: $opendir: $!");
        my @files = readdir($dh);
        foreach (sort @files) {
            my $file = $_;

            # next if "." eq $_;
            # next if ".." eq $_;

            my $abs_path = Cwd::abs_path("$opendir/$file");
            next if !$abs_path || $abs_path =~ m/^\s*$/;
            my $entry = $self->phys_file_entry($abs_path);
            
            if ("." eq $file) {
                my (undef, $dirname, undef) = File::Basename::fileparse($abs_path);
                $$entry{name} = ". [$abs_path]";
                $dot = $entry;
            }
            elsif (".." eq $file) {
                $$entry{name} = "..";
                $dotdot = $entry;
            }
            else {
                my ($filename, undef, undef) = File::Basename::fileparse($abs_path);
                $$entry{name} = $filename;

                push(@entries, $entry);
            }
        }
        closedir($dh);
    };
    if ($@) {
        my $err = $@;
        $self->app->log->debug($@);
        $self->flash("error" => $err);
    }

    unshift(@entries, $dotdot) if $dotdot;
    unshift(@entries, $dot) if $dot;

    return(\@entries);
}

sub phys_file_entry {
    my $self  = shift;
    my $full_path = shift;

    my @stat = stat($full_path);

    my $path = Mojo::Util::b64_encode($full_path, "");
    chomp($path);

    my $type = "";
    if (S_ISREG($stat[2])) {
        $type = "file";
    }
    elsif (S_ISDIR($stat[2])) {
        $type = "directory";
    }

    return({ name => $full_path, path => $path, type => $type, size => $stat[7], ctime => $stat[10] });
}

sub container_valid {
    my $self  = shift;
    my %ops = @_;

    my $path = $ops{path};
    my $container = $ops{container};

    if (-f $path && -f $container) {
        my $ipath = (stat($path))[1];
        my $icontainer = (stat($container))[1];

        if ($path eq $container) {
            return 1;
        }
        else {
            return 0;
        }
    }
    elsif (-d $path && -f $container) {
        return 0;
    }

    # Container is a directory; path can be either
    foreach (1 .. 15) {
        # $self->app->log->debug("path: $path");
        # $self->app->log->debug("container: $container");

        if ($path eq $container) {
            return 1;
        }
        my $dirname = File::Basename::dirname($path);
        last if $dirname eq $path;
        $path = $dirname;
    }

    return 0;
}

sub version {
    my $self = shift;
    
    # === START version
    return("2014-01-29.105");
    # === STOP version
}

sub uname {
    my $self = shift;
    
    my @u = POSIX::uname();

    return(wantarray ? @u : join("|", @u));
}

sub is_admin {
    my $self = shift;

    my $name = $self->session->{have_user} || '';
    if (!$name) {
        return(undef);
    }

    my $id = SiteCode::Account->exists(username => $name);
    if (!$id) {
        return(undef);
    }
    
    return(1 == $id);
}

sub forkcall {
    my $self = shift;

    state $fc = Mojo::IOLoop::ForkCall->new;
}
    

sub startup {
    my $self = shift;
    
    $self->log->level("debug");

    $self->helper(setup_valid => \&setup_valid);
    $self->helper(phys_dir_listing => \&phys_dir_listing);
    $self->helper(phys_file_entry => \&phys_file_entry);
    $self->helper(container_valid => \&container_valid);
    $self->helper(version => \&version);
    $self->helper(uname => \&uname);
    $self->helper(is_admin => \&is_admin);
    $self->helper(forkcall => \&forkcall);

    warn("Version: " . $self->version, "\n");
    warn("Uname: " . $self->uname, "\n");

    my $ffmpeg_bin;

    if ($PerlApp::VERSION) {
        my $datafile = "sparky.tgz";
        my $filename = PerlApp::extract_bound_file($datafile);
        die "$datafile not bound to application\n" unless defined $filename;

        my $tar = Archive::Tar->new;

        my $dirname = File::Basename::dirname($filename);

        if ("darwin" eq $^O) {
            $ffmpeg_bin = "$dirname/ffmpeg/ffmpeg-osx";
        }
        elsif ("MSWin32" eq $^O) {
            $ffmpeg_bin = "$dirname/ffmpeg/ffmpeg-win32.exe";
        }
        elsif ("linux" eq $^O) {
        }

        $tar->setcwd($dirname);
        $tar->read($filename);
        $tar->extract();

        push(@{$self->renderer->paths}, "$dirname/includes/templates");
        push(@{$self->static->paths}, "$dirname/includes/public");
    }
    else {
        push(@{$self->renderer->paths}, "includes/templates");
        push(@{$self->static->paths}, "includes/public");
    }

    $self->helper(ffmpeg_bin => sub { $ffmpeg_bin });

    my $site_config = SiteCode::Site->config();

    # Increase limit to 10MB
    $ENV{MOJO_MAX_MESSAGE_SIZE} = 10485760;

    $self->plugin(tt_renderer => {template_options => {CACHE_SIZE => 0, COMPILE_EXT => undef, COMPILE_DIR => undef}});
    if (-d "log") {
        $self->plugin(AccessLog => {log => "log/access.log", format => '%h %l %u %t "%r" %>s %b %D "%{Referer}i" "%{User-Agent}i"'});
    }
    $self->plugin('RenderFile'); 

    $self->renderer->default_handler('tt');

    $self->secret($$site_config{site_secret} || sprintf("%05d%05d%05d", int(rand(10000)), int(rand(10000)), int(rand(10000))));

    my $r = $self->routes;

    my $logged_in = $r->under (sub {
        my $self = shift;

        # Authenticated
        my $name = $self->session->{have_user} || '';
        return 1 if SiteCode::Account->exists(username => $name);

        # Not authenticated
        $self->redirect_to('/');
        return undef;
    });

    my $is_admin = $r->under (sub {
        my $self = shift;

        my $is = $self->is_admin;

        if (!defined $is) {
            # Not authenticated
            $self->redirect_to('/');
            return undef;
        }

        if (0 == $is) {
            $self->redirect_to('/');
            return undef;
        }

        return 1;
    });

    $r->get('/')->to(controller => 'Index', action => 'slash');
    $r->any('/init')->to(controller => 'Index', action => 'init');
    $r->any('/login')->to(controller => 'Index', action => 'login');
    $r->get('/logout')->to(controller => 'Index', action => 'logout');
    
    $r->get('/dashboard/shares')->to(controller => 'Public', action => 'shares');

    $r->get('/dashboard/shares/pls/:selection')->to(controller => 'Public', action => 'pls');
    $r->get('/dashboard/shares/audio/:selection')->to(controller => 'Public', action => 'audio');
    $r->get('/dashboard/shares/m3u/:selection')->to(controller => 'Public', action => 'm3u');
    $r->get('/dashboard/shares/pls/:whence/:selection')->to(controller => 'Public', action => 'pls');
    $r->get('/dashboard/shares/audio/:whence/:selection')->to(controller => 'Public', action => 'audio');
    $r->get('/dashboard/shares/m3u/:whence/:selection')->to(controller => 'Public', action => 'm3u');
    # $r->get('/dashboard/shares/ogv/:selection/:mode' => {mode => 'html'})->to(controller => 'Public', action => 'ogv');
    # $r->get('/dashboard/shares/ogv/:whence/:selection/:mode' => {mode => 'html'})->to(controller => 'Public', action => 'ogv');

    $r->get('/dashboard/shares/:browse')->to(controller => 'Public', action => 'browse');
    $r->get('/dashboard/shares/:whence/:browse')->to(controller => 'Public', action => 'browse');

    $is_admin->get('/dashboard/itunes')->to(controller => 'Dashboard', action => 'itunes');
    $is_admin->get('/dashboard/itunes/audio/:mode/:selection')->to(controller => 'Dashboard', action => 'audio');
    $is_admin->get('/dashboard/itunes/:type')->to(controller => 'Dashboard', action => 'itunes');

    $is_admin->get('/dashboard/browse')->to(controller => 'Dashboard', action => 'browse');
    $is_admin->get('/dashboard/browse/audio/:selection/:mode' => {mode => 'html'})->to(controller => 'Dashboard', action => 'audio');
    $is_admin->get('/dashboard/browse/video/:selection/:mode' => {mode => 'html'})->to(controller => 'Dashboard', action => 'video');
    # $is_admin->get('/dashboard/browse/ogv/:selection/:mode' => {mode => 'html'})->to(controller => 'Dashboard', action => 'ogv');
    $is_admin->get('/dashboard/browse/:findme')->to(controller => 'Dashboard', action => 'findme');

    $is_admin->get('/dashboard/show')->to(controller => 'Dashboard', action => 'show');
    $is_admin->post('/show/userdir')->to(controller => 'Dashboard', action => 'userdir');
    $is_admin->get('/add/share/#b64_path/:timed')->to(controller => 'Dashboard', action => 'add_share');
    $is_admin->get('/add/share/#b64_path')->to(controller => 'Dashboard', action => 'add_share');
    $is_admin->get('/del/share/#b64_path')->to(controller => 'Dashboard', action => 'del_share');
    $is_admin->get('/del/share/:whence/#b64_path')->to(controller => 'Dashboard', action => 'del_share');

    $is_admin->any('/add/user')->to(controller => 'Index', action => 'add_user');
}

1;
