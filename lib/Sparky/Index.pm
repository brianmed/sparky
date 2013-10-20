package Sparky::Index;                                                                                                                                              
                                                                                                                                                                        
use Mojo::Base 'Mojolicious::Controller';                                                                                                                               

use SiteCode::Account;
use SiteCode::DBX;

sub slash {
    my $self = shift;

    if ($self->session->{have_user}) {
        $self->redirect_to("/dashboard/browse");
    }
    elsif (!SiteCode::DBX->new()->col("SELECT id FROM account WHERE username = 'admin'")) {
        $self->redirect_to("/init");
    }
    else {
        $self->redirect_to("/login");
    }
}

sub init {
    my $self = shift;

    if ("127.0.0.1" ne $self->tx->remote_address) {
        my $host = $self->req->url->to_abs->host;
        my $port = $self->req->url->to_abs->port;
        my $url = $self->url_for("//127.0.0.1:$port/")->to_abs;

        $self->stash(error => "Please initialize from <a href='$url'>localhost</a>.");
        return($self->render("index/localhost"));                                                                                                                                        
    }

    if ("GET" eq $self->req->method) {                                                                                                                                  
        $self->stash("info", "Creating admin user");
        return($self->render("index/init"));                                                                                                                                        
    }                                                                                                                                                                   
}

sub login {
    my $self = shift;

    if ("GET" eq $self->req->method) {                                                                                                                                  
        return($self->render("index/login"));                                                                                                                                        
    }                                                                                                                                                                   

    my $v = $self->setup_valid([qw(login password)]);
    return $self->render unless $v->has_data;

    my @names = $v->param;
    my %params;
    foreach my $name (@names) {
        $params{$name} = $v->param($name);
        $self->stash($name, $v->param($name));
    }

    if ($self->validation->has_error) {
        $self->stash("error", "Incorrect credentials");
        $self->render("index/login");
        return;
    }

    unless (SiteCode::Account->exists(username => $params{login})) {
        $self->flash(login => $params{login});
        $self->flash(password => $params{password});
        $self->redirect_to("/add/user");
        return;
    }
    
    eval {
        my $user = SiteCode::Account->new(route => $self, username => $params{login}, password => $params{password});
    };
    if ($@) {
        my $err = $@;

        if ($err =~ m/\n\z/) {
            chomp($err);
            $self->stash("error", $err);
            $self->render("index/login");
            return;
        }
    }

    $self->session->{have_user} = $params{login};

    $self->redirect_to("/dashboard/browse");
}

sub logout {
    my $self = shift;

    $self->session(expires => 1);
    $self->redirect_to("/");

    return;
}

sub add_user {
    my $self = shift;

    if ("GET" eq $self->req->method) {                                                                                                                                  
        my $login = $self->flash("login");
        my $password = $self->flash("password");

        $self->stash(info => "Adding: $login") if $login;
        $self->stash(login => $login);
        $self->stash(password => $password);

        $self->render("add/user");
        
        return;
    }

    if ("127.0.0.1" ne $self->tx->remote_address) {
        $self->stash(error => "Please add users from localhost.");
        $self->render("add/user");
        return;
    }

    my $v = $self->setup_valid([qw(login password _password)]);
    return $self->render unless $v->has_data;

    my @names = $v->param;
    my %params;
    foreach my $name (@names) {
        $params{$name} = $v->param($name);
        $self->stash($name, $v->param($name));
    }

    if ($self->validation->has_error) {
        $self->render("add/user");
        return;
    }

    if (SiteCode::Account->insert(
            username => $params{login}, 
            password => $params{password},
            route => $self,
    )) {
        $self->flash(info => "Added: $params{login}");
        $self->flash(login => $params{login});

        $self->redirect_to("/login");
        return;
    }

    $self->render("add/user");
}

1;
