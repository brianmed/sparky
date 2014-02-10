package SiteCode::DBX;

use SiteCode::Modern;

use Typed;
# use Moose;
# use namespace::autoclean;

use DBI;
use Carp;
use DBIx::Connector

has 'dbdsn' => ( isa => 'Str', is => 'ro', default => sub { "dbi:SQLite:dbname=./sparky.db" } );
has 'dbh' => ( isa => 'DBI::db', is => 'ro', lazy => 1, builder => '_build_dbh' );
has 'route' => ( isa => 'Mojolicious::Controller', is => 'ro' );
has 'dbix' => ( isa => 'DBIx::Connector', is => 'ro', lazy => 1, builder => '_build_dbix' );

sub _build_dbh {
    my $self = shift;

    my $dbix = $self->dbix();

    return($dbix->dbh());
}

sub _build_dbix {
    my $self = shift;

    my $conn = DBIx::Connector->new($self->dbdsn, "", "", {
        RaiseError => 1,
        PrintError => 0,
        # AutoCommit => 1,
    });

    $conn->dbh->sqlite_busy_timeout(60_000);

    my $sth = $conn->dbh->table_info('', 'main', 'account', 'TABLE');
    my $row = $sth->fetchrow_hashref;

    unless ($row) {
        my $sql = "";
        while (<DATA>) {
            $sql .= $_;
            if (m/^\s*$/) {
                # warn($sql);
                $conn->dbh->do($sql);
                # $conn->dbh->commit;
                $sql = "";
            }
        }

        my $secret = sprintf("%05d%05d%05d", int(rand(10000)), int(rand(10000)), int(rand(10000)));
        $conn->dbh->do("INSERT INTO site_key (id, site_key) VALUES (1, 'site_secret')");
        $conn->dbh->do("INSERT INTO site_value (id, site_key_id, site_value) VALUES (1, 1, '$secret')");
    }

    return($conn);
}

sub do {
    my $self = shift;
    my $sql = shift;
    my $attrs = shift;
    my @vars = @_;

    if (ref($self)) {
        eval {
            return($self->dbh()->do($sql, $attrs, @vars));
        };
        if ($@) {
            croak("$@");
        }
    }
    else {
        my $dbh = $self->_build_dbh();
        return($dbh->do($sql, $attrs, @vars));
    }
}

sub success {
    my $self = shift;
    my $sql = shift;
    my $attrs = shift;
    my @vars = @_;

    my $ret = $self->dbh()->do($sql, $attrs, @vars);
    if ($ret && 0 != $ret) {  # 0E0
        return(1);
    }

    return(0);
}

sub last_insert_id
{
    my $self = shift;

    my $catalog = shift;
    my $schema = shift;
    my $table = shift;
    my $field = shift;
    my $attrs = shift;

    if ($attrs) {
        return($self->dbh()->last_insert_id(undef,undef,undef,undef,$attrs));
    }
    else {
        return($self->dbh()->last_insert_id($catalog, $schema, $table, $field, undef));
    }
}

sub col {
    my $self = shift;
    my $sql = shift;
    my $attrs = shift;
    my @vars = @_;

    my $ret = $self->dbh()->selectcol_arrayref($sql, $attrs, @vars);
    if ($ret && $$ret[0]) {
        return($$ret[0]);
    }

    return(undef);
}

sub row {
    my $self = shift;
    my $sql = shift;
    my $attrs = shift;
    my @vars = @_;

    my $ret = $self->dbh()->selectall_arrayref($sql, { Slice => {} }, @vars);
    if ($ret && $$ret[0]) {
        return($$ret[0]);
    }

    return(undef);
}

sub question
{
    my $self = shift;
    my $nbr = shift;

    return(join(", ", map({"?"} (1 .. $nbr))));
}

sub array {
    my $self = shift;
    my $sql = shift;
    my $attrs = shift;
    my @vars = @_;

    my $ret = $self->dbh()->selectall_arrayref($sql, { Slice => {} }, @vars);
    if ($ret) {
        return($ret);
    }

    return(undef);
}

# __PACKAGE__->meta->make_immutable;

1;

__DATA__
CREATE TABLE site_key(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  site_key VARCHAR(512) not null,
  updated timestamp not null default CURRENT_TIMESTAMP,
  inserted timestamp not null default CURRENT_TIMESTAMP
);

CREATE TABLE site_value(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  site_key_id integer not null unique,
  site_value VARCHAR(4096) not null,
  updated timestamp not null default CURRENT_TIMESTAMP,
  inserted timestamp not null default CURRENT_TIMESTAMP,
  foreign key (site_key_id) references site_key (id)
);

CREATE TABLE account(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  username VARCHAR(30) NOT NULL UNIQUE,
  password VARCHAR(128) NOT NULL,
  updated timestamp default CURRENT_TIMESTAMP,
  inserted timestamp default CURRENT_TIMESTAMP
);

CREATE TABLE account_key(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id integer not null,
  account_key VARCHAR(512) not null,
  updated timestamp not null default CURRENT_TIMESTAMP,
  inserted timestamp not null default CURRENT_TIMESTAMP,
  foreign key (account_id) references account (id) on delete cascade,
  unique (account_id, account_key)
);

CREATE TABLE account_value(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  account_key_id integer not null unique,
  account_value VARCHAR(4096) not null,
  updated timestamp not null default CURRENT_TIMESTAMP,
  inserted timestamp not null default CURRENT_TIMESTAMP,
  foreign key (account_key_id) references account_key (id) on delete cascade
);

CREATE TABLE share(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  abs_path VARCHAR(1024) not null unique,
  timelimit integer,
  updated timestamp not null default CURRENT_TIMESTAMP,
  inserted timestamp not null default CURRENT_TIMESTAMP
);

CREATE TABLE filesystem(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  root INTEGER,
  name VARCHAR(1024) not null,
  type VARCHAR(32) NOT NULL,
  disk_path VARCHAR(1024),
  updated timestamp not null default CURRENT_TIMESTAMP,
  inserted timestamp not null default CURRENT_TIMESTAMP,
  foreign key (root) references filesystem (id)
);

INSERT INTO filesystem (root, name, type) VALUES (NULL, '/', 'directory');

