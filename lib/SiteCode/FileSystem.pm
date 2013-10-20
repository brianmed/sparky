package SiteCode::FileSystem::Directory;

use SiteCode::Modern;

use Moose;
use namespace::autoclean;

use SiteCode::DBX;

extends 'SiteCode::FileSystem';

sub entries
{
    my $self = shift;

    my $entries = $self->dbx()->array("SELECT * FROM filesystem WHERE root = ?", undef, $self->id);

    my @objs = ();
    foreach my $e (@{$entries}) {
        if ("directory" eq $$e{type}) {
            push(@objs, SiteCode::FileSystem::Directory->new(id => $$e{id}));
        }
        elsif ("file" eq $$e{type}) {
            push(@objs, SiteCode::FileSystem::File->new(id => $$e{id}));
        }
    }

    # $self->route->app->log->debug($self->route->dumper(\@objs));
    return(\@objs);
}

sub contains
{
    my $self = shift;
    my %ops = @_;

    if ($ops{physical}) {
        my $flag = $self->dbx->col("SELECT id FROM filesystem WHERE disk_path = ? and root = ?", undef, $ops{physical}, $self->id);
        return($flag);
    }
}

sub toggle
{
    my $self = shift;
    my %ops = @_;

    my $basename = (File::Basename::fileparse($ops{path}))[0];
    # $self->route->app->log->debug("basename: $basename");
    my $exists = $self->dbx->col("SELECT id FROM filesystem WHERE root = ? and name = ?", undef, $self->id, $basename);
    # $self->route->app->log->debug("exists: $exists");

    if ($exists) {
        $self->dbx->do("DELETE FROM filesystem WHERE id = ?", undef, $exists);
        return 1;
    }
    else {
        $self->dbx->do("INSERT INTO filesystem (root, name, type, disk_path) VALUES (?, ?, ?, ?)", undef, $self->id, $basename, "file", $ops{path});
        my $id = $self->dbx->col("SELECT id FROM filesystem WHERE root = ? and name = ?", undef, $self->id, $basename);
        return $id ? 1 : 0;
    }
}

sub size
{
    my $self = shift;

    return("0");
}

sub type
{
    my $self = shift;

    return("directory");
}

package SiteCode::FileSystem::File;

use SiteCode::Modern;

use Moose;
use namespace::autoclean;

use SiteCode::DBX;

extends 'SiteCode::FileSystem';

sub type
{
    my $self = shift;

    return("file");
}

1;

package SiteCode::FileSystem;

use SiteCode::Modern;

use Moose;
use namespace::autoclean;

use SiteCode::DBX;

has 'id' => ( isa => 'Int', is => 'rw' );
has 'dbx' => ( isa => 'SiteCode::DBX', is => 'ro', lazy => 1, default => sub { SiteCode::DBX->new() } );

has 'route' => ( isa => 'Mojolicious::Controller', is => 'ro' );

sub root
{
    my $self = shift;
    my $dbx = shift;

    my $row = SiteCode::DBX->new()->row("SELECT * FROM filesystem WHERE name = '/'");
    my $dir = SiteCode::FileSystem::Directory->new(id => $$row{id}, route => $self->route);

    return($dir);
}

sub name
{
    my $self = shift;

    my $name = $self->dbx()->col("SELECT name FROM filesystem WHERE id = ?", undef, $self->id);

    return($name);
}

sub disk_path
{
    my $self = shift;

    my $disk_path = $self->dbx()->col("SELECT disk_path FROM filesystem WHERE id = ?", undef, $self->id);

    return($disk_path);
}

sub size
{
    my $self = shift;

    my $disk_path = $self->dbx()->col("SELECT disk_path FROM filesystem WHERE id = ?", undef, $self->id);
    my @stat = stat($disk_path);

    return($stat[7]);
}

sub ctime
{
    my $self = shift;

    my $time = $self->dbx()->col("SELECT inserted FROM filesystem WHERE id = ?", undef, $self->id);

    return($time);
}

sub virtual
{
    my $self = shift;

    return 1;
}

1;

