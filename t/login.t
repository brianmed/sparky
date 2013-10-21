use Test::More;
use Test::Mojo;

# Load application class
my $t = Test::Mojo->new('Sparky');
$t->ua->max_redirects(3);

$t->get_ok('/dashboard/show')->status_is(200);
$t->content_like(qr/Initialization/, 'Did not get view file page.');

$t->get_ok('/dashboard/browse')->status_is(200);
$t->content_like(qr/Initialization/, 'Did not get browse page.');

# warn $t->app->dumper($t->tx->res->content);
# exit;

$t->get_ok('/')
  ->status_is(200)
  ->element_exists('form input[name="login"]')
  ->element_exists('form input[name="password"]')
  ->element_exists('form input[type="submit"]');

$t->content_like(qr/Initialization/, 'On Initialization page');

my $path = $t->tx->req->url->path->{path};

$t->post_ok($path => form => {login => 'bpmedley', password => 'secr3tItIs', _password => 'secr3tItIs'})
  ->status_is(200);

# warn $t->app->dumper($t->tx->req->url->path->{path});

$path = $t->tx->req->url->path->{path};
$t->post_ok($path => form => {login => 'bpmedley', password => 'secr3tItIs'})
  ->status_is(200);

warn $t->app->dumper($t->tx->res->content);

# $t->get_ok('/protected')->status_is(200)->text_like('a' => qr/Logout/);
# 
# $t->get_ok('/logout')->status_is(200)
#   ->element_exists('form input[name="user"]')
#   ->element_exists('form input[name="pass"]')
#   ->element_exists('form input[type="submit"]');

done_testing();
