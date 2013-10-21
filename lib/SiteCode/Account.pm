package SiteCode::Account;

use SiteCode::Modern;

use Typed;
# use Moose;
# use namespace::autoclean;

use Mojo::Util;

use SiteCode::DBX;
use SiteCode::Site;

has 'id' => ( isa => 'Int', is => 'rw' );
has 'dbx' => ( isa => 'SiteCode::DBX', is => 'ro', lazy => 1, default => sub { SiteCode::DBX->new() } );

has 'username' => ( isa => 'Str', is => 'ro', required => 1 );
has 'password' => ( isa => 'Str', is => 'rw' );
has 'route' => ( isa => 'Mojolicious::Controller', is => 'ro' );

sub _lookup_id_with_username {
    my $self = shift;

    return($self->dbx()->col("SELECT id FROM account WHERE username = ?", undef, $self->username()));
}

sub _lookup_password {
    my $self = shift;

    return($self->dbx()->col("SELECT password FROM account WHERE id = ?", undef, $self->id()));
}

sub _lookup_username {
    my $self = shift;

    return($self->dbx()->col("SELECT username FROM account WHERE id = ?", undef, $self->id()));
}

sub BUILD {
    my $self = shift;

    eval {
        $self->id($self->_lookup_id_with_username());
        if ($self->password()) {
            unless($self->chkPw($self->password())) {
                die("Credentials mis-match.\n");
            }
        }
        else {
            $self->password($self->_lookup_password());
        }
    };
    if ($@) {
        $self->route->app->log->debug("sparky::Account::new: $@") if $self->route;
        die("Account::new:: $@\n");
    }
}

sub insert
{
    my $class = shift;
    my %ops = @_;

    my $dbx = SiteCode::DBX->new();
    my $password_md5 = Mojo::Util::md5_sum($ops{password});

    if ($ops{id}) {
        $dbx->do("INSERT INTO account (id, username, password) VALUES (?, ?, ?)", undef, $ops{id}, $ops{username}, $password_md5);
    }
    else {
        $dbx->do("INSERT INTO account (username, password) VALUES (?, ?)", undef, $ops{username}, $password_md5);
    }

    my $id = $dbx->col("SELECT id FROM account WHERE username = ?", undef, $ops{username});

    return($id);
}

sub key
{
    my $self = shift;
    my $key = shift;

    my $dbx = $self->dbx;

    if (scalar(@_)) {
        if (defined $_[0]) {
            my $value = shift;
            my $defined = $self->key($key);

            if ($defined) {
                my $id = $dbx->col("SELECT id FROM account_key WHERE account_id = ? AND account_key = ?", undef, $self->id(), $key);
                $dbx->do("UPDATE account_value SET account_value = ? WHERE account_key_id = ?", undef, $value, $id);

                # $dbx->dbh->commit;
            }
            else {
                $dbx->do("INSERT INTO account_key (account_id, account_key) VALUES (?, ?)", undef, $self->id(), $key);
                my $id = $dbx->col("SELECT id FROM account_key WHERE account_id = ? AND account_key = ?", undef, $self->id(), $key);
                $dbx->do("INSERT INTO account_value (account_key_id, account_value) VALUES (?, ?)", undef, $id, $value);

                # $dbx->dbh->commit;
            }
        }
        else {
            my $defined = $self->key($key);

            if ($defined) {
                my $id = $dbx->col("SELECT id FROM account_key WHERE account_id = ? AND account_key = ?", undef, $self->id(), $key);
                $dbx->do("DELETE FROM account_value where account_key_id = ?", undef, $id);
                $dbx->do("DELETE FROM account_key where id = ?", undef, $id);

                # $dbx->dbh->commit;
            }
        }
    }

    my $row = $dbx->row(qq(
        SELECT 
            account_key, account_value 
        FROM 
            account_key, account_value 
        WHERE account_key = ?
            AND account_id = ?
            AND account_key.account_id = account_id
            AND account_key.id = account_value.account_key_id
    ), undef, $key, $self->id());

    my $ret = $row->{account_value};
    return($ret);
}

sub chkPw
{
    my $self = shift;
    my $pw = shift;

    my $password_md5 = Mojo::Util::md5_sum($pw);

    my $ret = $self->dbx()->col("SELECT password FROM account WHERE id = ?", undef, $self->id());

    return($password_md5 eq $ret);
}

sub exists {
    my $class = shift;

    my %opt = @_;

    if ($opt{username}) {
        return(SiteCode::DBX->new()->col("SELECT id FROM account WHERE username = ?", undef, lc $opt{username}));
    }

    return(0);
}

# __PACKAGE__->meta->make_immutable;

1;
