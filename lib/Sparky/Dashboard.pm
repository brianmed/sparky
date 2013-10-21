package Sparky::Dashboard;                                                                                                                                              
                                                                                                                                                                        
use Mojo::Base 'Mojolicious::Controller';                                                                                                                               

use SiteCode::Account;
use SiteCode::DBX;
use Mojo::Util;
use Cwd;

sub browse {
    my $self = shift;

    unless ($self->session->{have_user}) {
        $self->redirect_to("/");
        return;
    }

    my @paths = ();
    if ("darwin" eq $^O) {
        push(@paths, $ENV{HOME});
        push(@paths, "$ENV{HOME}/Documents");
        push(@paths, "$ENV{HOME}/Downloads");
        push(@paths, "$ENV{HOME}/Desktop");
        push(@paths, "$ENV{HOME}/Music");
        push(@paths, "$ENV{HOME}/Pictures");
        push(@paths, "/Volumes");
        push(@paths, "/");
    }
    elsif ("MSWin32" eq $^O) {
        my $home = "$ENV{HOMEDRIVE}$ENV{HOMEPATH}";
        push(@paths, $home);
        push(@paths, "$home\\My Documents");
        push(@paths, "$home\\Downloads") if -f "$home\\Downloads";
        push(@paths, "$home\\Desktop");
        push(@paths, "$home\\My Documents\\My Music");
        push(@paths, "$home\\My Documents\\My Pictures");
        push(@paths, "C:\\");
    }
    elsif ("linux" eq $^O) {
        push(@paths, $ENV{HOME});
        push(@paths, "/mnt");
        push(@paths, "/");
    }

    my @entries = ();

    foreach my $path (@paths) {
        my $entry = $self->phys_file_entry($path);
        $$entry{name} = $path;
        push(@entries, $entry);
    }

    foreach my $entry (@entries) {
        $$entry{ctime} = $$entry{ctime} ? scalar(localtime($$entry{ctime})) : "";
    }

    my $user = SiteCode::Account->new(route => $self, username => $self->session->{have_user});
    $user->key("_t_entries", $self->dumper(\@entries));
    $self->flash("entry.name", "Browse");

    my $host = $self->req->url->to_abs->host;
    my $port = $self->req->url->to_abs->port;
    $self->redirect_to($self->url_for("//$host:$port/dashboard/show")->to_abs);

    return;
}

sub findme {
    my $self = shift;

    unless ($self->session->{have_user}) {
        $self->redirect_to("/");
        return;
    }

    my $host = $self->req->url->to_abs->host;
    my $port = $self->req->url->to_abs->port;
    my $url = $self->url_for("//$host:$port/dashboard/show")->to_abs;

    my $path = $self->param("findme");
    $path = Mojo::Util::b64_decode($path);

    if (-f $path) {
        $self->render_file('filepath' => $path);
        return;
    }

    my $entries = $self->phys_dir_listing($path);

    foreach my $entry (@{$entries}) {
        $$entry{ctime} = $$entry{ctime} ? scalar(localtime($$entry{ctime})) : "";
    }

    my $user = SiteCode::Account->new(route => $self, username => $self->session->{have_user});
    $user->key("_t_entries", $self->dumper($entries));
    $self->flash("entry.name", "Browse");

    $self->redirect_to($url);

    return;
};

sub show {
    my $self = shift;

    unless ($self->session->{have_user}) {
        $self->redirect_to("/");
        return;
    }

    # From /dashboard/add
    # $self->app->log->debug($self->flash("entry.name"));
    if ($self->flash("entry.name")) {
        $self->stash(error => $self->flash("error")) if $self->flash("error");
        $self->stash(entry_name => $self->flash("entry.name"));
    
        my $user = SiteCode::Account->new(route => $self, username => $self->session->{have_user});
        my $entries = eval($user->key("_t_entries"));
        $self->stash(entries => $entries);
        $self->stash(have_files => scalar(@$entries));
        $user->key("_t_entries", undef);
    }

    $self->stash(cur_title => "Sparky");

    my $home;
    if ("darwin" eq $^O) {
        $home = $ENV{HOME};
    }
    elsif ("MSWin32" eq $^O) {
        $home = "$ENV{HOMEDRIVE}$ENV{HOMEPATH}";
    }
    elsif ("linux" eq $^O) {
        $home = $ENV{HOME};
    }
    
    $self->stash(placeholder => $home);
    $self->stash(version => $self->version);

    $self->render("dashboard/show");
};

sub add_share {
    my $self = shift;

    my $b64_path = $self->param("b64_path");
    my $path = Mojo::Util::b64_decode($b64_path);
    my $abs = Cwd::abs_path($path);

    my $ret = 0;
    eval {
        my $dbx = SiteCode::DBX->new();
        my $id = $dbx->col("SELECT id FROM share WHERE abs_path = ?", undef, $abs);
        if ($id) {
            $ret = 1;
        }
        else {
            $dbx->do("INSERT INTO share (abs_path) VALUES (?)", undef, $abs);
            $ret = 1;
        }
    };
    
    $self->render(json => { ret => $ret });
};

sub del_share {
    my $self = shift;

    my $b64_path = $self->param("b64_path");
    my $path = Mojo::Util::b64_decode($b64_path);
    my $abs = Cwd::abs_path($path);

    my $ret = 0;
    eval {
        my $dbx = SiteCode::DBX->new();
        $self->app->log->debug("Hi");
        $dbx->do("DELETE FROM share WHERE abs_path = ?", undef, $abs);
        $ret = 1;
        $self->app->log->debug("There");
    };
    if ($@) {
        $self->stash(error => $@);
        $self->app->log->debug($@);
    }
    
    $self->render(json => { ret => $ret });
};

sub userdir {
     my $self = shift;
 
     my $v = $self->setup_valid([qw(entry.name)]);
     return $self->render unless $v->has_data;
 
     my @names = $v->param;
     my %params;
     foreach my $name (@names) {
         $params{$name} = $v->param($name);
         $self->stash($name, $v->param($name));
     }
 
     if ($self->validation->has_error) {
         $self->flash(error => "Invalid input");
         $self->redirect_to("/dashboard/show");
         return;
     }
 
     if (-e $params{"entry.name"}) {
         my $path = Mojo::Util::b64_encode($params{"entry.name"}, "");
         chomp($path);
         $self->redirect_to("/dashboard/browse/$path");
         return;
     }
     else {
         $self->flash(error => "Doesn't seem to exist");
         $self->redirect_to("/dashboard/show");
         return;
     }
 
     $self->redirect_to("/dashboard/show");
}

1;
