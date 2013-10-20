package Sparky::Public;                                                                                                                                              
                                                                                                                                                                        
use Mojo::Base 'Mojolicious::Controller';                                                                                                                               

use Mojo::Util;
use SiteCode::DBX;
use MP3::Info;
use MP4::Info;
use Cwd;
use File::Temp;

sub shares {
    my $self = shift;

    my @entries = ();

    my $dbx = SiteCode::DBX->new();
    my $paths = $dbx->array("SELECT abs_path FROM share ORDER BY 1") || [];

    foreach my $row (@$paths) {
        my $path = $$row{abs_path};
        my $entry = $self->phys_file_entry($path);
        push(@entries, $entry);
    }

    foreach my $entry (@entries) {
        $$entry{ctime} = $$entry{ctime} ? scalar(localtime($$entry{ctime})) : "";
    }

    $self->stash(entries => \@entries);
    $self->stash(have_files => scalar(@entries));

    return $self->render("dashboard/shares");
}

sub pls {
    my $self = shift;

    my $entries = [];

    my $dbx = SiteCode::DBX->new();
    my $paths = $dbx->array("SELECT abs_path FROM share ORDER BY 1") || [];
    # $self->app->log->debug($self->dumper($paths));

    my $selection = $self->param("selection");
    $selection = Mojo::Util::b64_decode($selection);
    $selection = Cwd::abs_path($selection);

    my ($fh, $filename) = File::Temp::tempfile("playlistXXXXX", UNLINK => 0, SUFFIX => '.pls', TMPDIR => 1);
    print($fh "[playlist]\r\n");

    my @muzak = ();
    foreach my $row (@$paths) {
        my $path = $$row{abs_path};
        if ($self->dir_contains_path(path => $selection, container => $path)) {
            if (-f $selection) {
                push(@muzak, $selection);
            }
            else {
                opendir(my $dh, $selection) or die("error: opendir: $selection: $!\n");
                while(readdir($dh)) {
                    next unless $_ =~ m/\.(mp3|m4a)$/i;
                    push(@muzak, "$selection/$_");
                }
                closedir($dh);
                @muzak = sort({ $a cmp $b } @muzak);
            }
        }
    }

    printf($fh "NumberOfEntries=%d\r\n\r\n", scalar(@muzak));

    foreach my $idx (0 .. $#muzak) {
        my $j = $idx + 1;

        my $b64 = Mojo::Util::b64_encode($muzak[$idx], "");
        printf($fh "File%d=%s\r\n", $j, $self->url_for("/dashboard/shares/$b64")->to_abs);
        
    }

    close($fh);

    return $self->render_file('filepath' => $filename);
}

sub audio {
    my $self = shift;

    my $selection = $self->param("selection");
    return unless $selection;
    $selection = Mojo::Util::b64_decode($selection);
    $selection = Cwd::abs_path($selection);
    
    my $mode = $self->param("mode");
    return unless $mode;

    $self->stash(playlist_url => $self->url_for({mode => 'playlist'})->to_abs);
    return $self->render("dashboard/audio") unless "playlist" eq $mode;

    my @muzak = ();
    my $dbx = SiteCode::DBX->new();
    my $paths = $dbx->array("SELECT abs_path FROM share ORDER BY 1") || [];
    foreach my $row (@$paths) {
        my $path = $$row{abs_path};
        if ($self->dir_contains_path(path => $selection, container => $path)) {
            if (-f $selection) {
                push(@muzak, $selection);
            }
            else {
                opendir(my $dh, $selection) or die("error: opendir: $selection: $!\n");
                while(readdir($dh)) {
                    next unless $_ =~ m/\.(mp3|m4a)$/i;
                    push(@muzak, "$selection/$_");
                }
                closedir($dh);
                @muzak = sort({ $a cmp $b } @muzak);
            }
        }
    }

    my $xml = "<playlist>\n";
    foreach my $file (@muzak) {
        my $muzak;
        if ($file =~ m/\.mp3/i) {
            $muzak = MP3::Info->new($file);
        }
        else {
            $muzak = MP4::Info->new($file);
        }
        my $b64 = Mojo::Util::b64_encode($file, "");
        my $src = $self->url_for("/dashboard/shares/$b64")->to_abs;

        $xml .= sprintf(qq(
            <track>
                <title>%s</title>
                <artist>%s</artist>
                <mp3>%s</mp3>
                <free>false</free>
                <duration>%s</duration>
            </track>
        ), Mojo::Util::xml_escape($muzak->title), Mojo::Util::xml_escape($muzak->artist), Mojo::Util::xml_escape($src), Mojo::Util::xml_escape($muzak->time));
    }
    $xml .= "</playlist>\n";

    return $self->render(format => 'xml', text => $xml);
}

sub m3u {
    my $self = shift;

    my $entries = [];

    my $dbx = SiteCode::DBX->new();
    my $paths = $dbx->array("SELECT abs_path FROM share ORDER BY 1") || [];
    # $self->app->log->debug($self->dumper($paths));

    my $selection = $self->param("selection");
    return unless $selection;
    $selection = Mojo::Util::b64_decode($selection);
    $selection = Cwd::abs_path($selection);

    my ($fh, $filename) = File::Temp::tempfile("playlistXXXXX", UNLINK => 0, SUFFIX => '.m3u8', TMPDIR => 1);
    my $eol = "\n";

    my @muzak = ();
    foreach my $row (@$paths) {
        my $path = $$row{abs_path};
        if ($self->dir_contains_path(path => $selection, container => $path)) {
            if (-f $selection) {
                push(@muzak, $selection);
            }
            else {
                opendir(my $dh, $selection) or die("error: opendir: $selection: $!\n");
                while(readdir($dh)) {
                    next unless $_ =~ m/\.(mp3|m4a)$/i;
                    push(@muzak, "$selection/$_");
                }
                closedir($dh);
                @muzak = sort({ $a cmp $b } @muzak);
            }
        }
    }

    foreach my $idx (0 .. $#muzak) {
        my $j = $idx + 1;

        my $b64 = Mojo::Util::b64_encode($muzak[$idx], "");
        printf($fh "%s$eol", $self->url_for("/dashboard/shares/$b64")->to_abs);
    }

    close($fh);

    return $self->render_file('filepath' => $filename);
}

sub browse {
    my $self = shift;

    my $entries = [];

    my $dbx = SiteCode::DBX->new();
    my $paths = $dbx->array("SELECT abs_path FROM share ORDER BY 1") || [];

    my $browse = $self->param("browse");
    $browse = Mojo::Util::b64_decode($browse);
    $browse = Cwd::abs_path($browse);

    foreach my $row (@$paths) {
        my $path = $$row{abs_path};
        if ($self->dir_contains_path(path => $browse, container => $path)) {
            if (-f $browse) {
                $self->render_file('filepath' => $browse);
                return;
            }
            else {
                $entries = $self->phys_dir_listing($browse);
                foreach my $entry (@$entries) {
                    $$entry{ctime} = $$entry{ctime} ? scalar(localtime($$entry{ctime})) : "";
                }
            }
        }
    }

    if (0 == scalar(@$entries)) {
        return $self->redirect_to("dashboard/shares");
    }

    $self->stash(entries => $entries);
    $self->stash(have_files => scalar(@$entries));

    return $self->render("dashboard/shares");
}

1;
