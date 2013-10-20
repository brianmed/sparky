#!/usr/local/ActivePerl-5.16/bin/perl

# dlna
#
# upnp

# $self->res->headers->content_disposition('attachment; filename=bar.png;');
# $self->render_static('foo/bar.png');

use 5.012;

use lib qw(lib);

use File::Basename;

BEGIN {
    return if $^C;

    push(@ARGV, 'daemon', '-l', 'http://*:8080') unless @ARGV;

    if ($PerlApp::VERSION) {
        my $dirname = File::Basename::dirname(PerlApp::exe());
        chdir($dirname) or die("error: chdir: $!\n");
    }
};

use Mojolicious::Lite;

use SiteCode::Account;
use SiteCode::FileSystem;
use SiteCode::Site;
use Mojo::Util;
use Archive::Tar;
use Cwd;
use File::Temp;
use Fcntl qw(:mode);
use MP3::Info;
use MP4::Info;

post '/show/userdir' => sub {
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
};

