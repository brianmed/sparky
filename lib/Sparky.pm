package Sparky;

use Mojo::Base 'Mojolicious';

use SiteCode::Site;
use Archive::Tar;
use File::Basename;
use Mojo::Util;
use Fcntl qw(:mode);
use Cwd;

sub setup_valid {
    my $self  = shift;
    my $topics = shift;

    my $v = $self->validation;

    foreach my $topic (@{$topics}) {
        if ("login" eq $topic) {
            $v->required("login");
            $v->size(5, 10);
            $v->like(qr/^admin$/);
        }
        elsif ("password" eq $topic) {
            $v->required("password");
            $v->size(8, 16);
            $v->like(qr/[[:word:]]/);
            $v->like(qr/[[:digit:]]/);
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

sub phys_dir_listing {
    my $self  = shift;
    my $dir_name = shift;

    my @entries = ();

    eval {
        my $opendir = $dir_name;

        opendir(my $dh, $opendir) or die("error: opendir: $opendir: $!\n");
        while(readdir($dh)) {
            my $file = $_;

            # next if "." eq $_;
            # next if ".." eq $_;

            my $abs_path = Cwd::abs_path("$opendir/$file");
            next if !$abs_path || $abs_path =~ m/^\s*$/;
            my $entry = $self->phys_file_entry($abs_path);
            
            if ("." eq $file) {
                my (undef, $dirname, undef) = File::Basename::fileparse($abs_path);
                $$entry{name} = ". [$abs_path]";
            }
            elsif (".." eq $file) {
                $$entry{name} = "..";
            }
            else {
                my ($filename, undef, undef) = File::Basename::fileparse($abs_path);
                $$entry{name} = $filename;
            }

            push(@entries, $entry);
        }
        closedir($dh);
    };
    if ($@) {
        my $err = $@;
        $self->app->log->debug($@);
        $self->flash("error" => $err);
    }

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

    # my ($filename, undef, undef) = File::Basename::fileparse($full_path);

    return({ name => $full_path, path => $path, type => $type, size => $stat[7], ctime => $stat[10] });
}

sub dir_contains_path {
    my $self  = shift;
    my %ops = @_;


    my $path = $ops{path};
    my $container = $ops{container};

    my @path_stat = ();
    if (-d $path) {
        @path_stat = stat($path);
    }
    else {
        my (undef, $dirname, undef) = File::Basename::fileparse($path);
        @path_stat = stat($dirname);
    }

    # $self->app->log->debug("container: $container");
    # $self->app->log->debug("path: $path");

    foreach (1 .. 15) {
        my @container_stat = stat($container);

        return 1 if $path_stat[1] == $container_stat[1];

        my (undef, $dirname, undef) = File::Basename::fileparse($container);
        last if $dirname eq $container;
        $container = $dirname;
    }

    return 0;
}

sub startup {
    my $self = shift;
    
    $self->log->level("debug");

    $self->helper(setup_valid => \&setup_valid);
    $self->helper(phys_dir_listing => \&phys_dir_listing);
    $self->helper(phys_file_entry => \&phys_file_entry);
    $self->helper(dir_contains_path => \&dir_contains_path);

    if ($PerlApp::VERSION) {
        my $datafile = "sparky.tgz";
        my $filename = PerlApp::extract_bound_file($datafile);
        die "$datafile not bound to application\n" unless defined $filename;

        use Archive::Tar;
        my $tar = Archive::Tar->new;

        my $dirname = File::Basename::dirname($filename);

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
        return 1 if $name eq 'admin';

        # Not authenticated
        $self->redirect_to('/');
        return undef;
    });

    $r->get('/')->to(controller => 'Index', action => 'slash');
    $r->get('/init')->to(controller => 'Index', action => 'init');
    $r->any('/login')->to(controller => 'Index', action => 'login');
    $r->get('/logout')->to(controller => 'Index', action => 'logout');

    $r->any('/add/user')->to(controller => 'Index', action => 'add_user');
    
    $r->get('/dashboard/shares')->to(controller => 'Public', action => 'shares');
    $r->get('/dashboard/shares/pls/:selection')->to(controller => 'Public', action => 'pls');
    $r->get('/dashboard/shares/audio/:selection/:mode' => {mode => 'html'})->to(controller => 'Public', action => 'audio');
    $r->get('/dashboard/shares/m3u/:selection')->to(controller => 'Public', action => 'm3u');
    $r->get('/dashboard/shares/:browse')->to(controller => 'Public', action => 'browse');

    $logged_in->get('/dashboard/browse')->to(controller => 'Dashboard', action => 'browse');
    $logged_in->get('/dashboard/browse/:findme')->to(controller => 'Dashboard', action => 'findme');
    $logged_in->get('/dashboard/show')->to(controller => 'Dashboard', action => 'show');
    $logged_in->post('/show/userdir')->to(controller => 'Dashboard', action => 'userdir');
    $logged_in->get('/add/share/#b64_path')->to(controller => 'Dashboard', action => 'add_share');
    $logged_in->get('/del/share/#b64_path')->to(controller => 'Dashboard', action => 'del_share');
}

1;
