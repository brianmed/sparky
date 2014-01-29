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

    my $paths = $dbx->array("SELECT abs_path FROM share WHERE timelimit is NULL ORDER BY 1") || [];
    foreach my $row (@$paths) {
        my $path = $$row{abs_path};
        my $entry = $self->phys_file_entry($path);
        push(@entries, $entry);
    }

    if ($self->is_admin) {
        my @old = ();
        my $now = time;

        $paths = $dbx->array("SELECT id, abs_path, timelimit FROM share WHERE timelimit is NOT NULL ORDER BY 1") || [];
        foreach my $row (@$paths) {
            if ($now >= ($$row{timelimit} + 3600)) {
                push(@old, $$row{id});
            }
            else {
                my $path = $$row{abs_path};
                my $entry = $self->phys_file_entry($path);
                $entry->{timestring} = scalar(localtime($$row{timelimit}));
                $entry->{timelimit} = $$row{timelimit};
                push(@entries, $entry);
            }
        }

        foreach my $id (@old) {
            $dbx->do("DELETE FROM share WHERE id = ?", undef, $id);
        }
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
        if ($self->container_valid(path => $selection, container => $path)) {
            if (-f $selection) {
                push(@muzak, $selection);
            }
            else {
                opendir(my $dh, $selection) or die("error: opendir: $selection: $!");
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
    
    my @muzak = ();
    my $dbx = SiteCode::DBX->new();
    my $paths = $dbx->array("SELECT abs_path FROM share ORDER BY 1") || [];
    foreach my $row (@$paths) {
        my $path = $$row{abs_path};
        if ($self->container_valid(path => $selection, container => $path)) {
            if (-f $selection) {
                push(@muzak, $selection);
            }
            else {
                opendir(my $dh, $selection) or die("error: opendir: $selection: $!");
                while(readdir($dh)) {
                    next unless $_ =~ m/\.(mp3|m4a)$/i;
                    push(@muzak, "$selection/$_");
                }
                closedir($dh);
                @muzak = sort({ $a cmp $b } @muzak);
            }
        }
    }

    my @playlist = ();
    foreach my $file (@muzak) {
        $file = Mojo::Util::url_unescape($file);
        my $muzak;
        my $ext = "";
        if ($file =~ m/\.mp3/i) {
            $muzak = MP3::Info->new($file);
            $ext = "mp3";
        }
        else {
            $muzak = MP4::Info->new($file);
            $ext = "mp4";
        }
        my $b64 = Mojo::Util::b64_encode($file, "");
        my $src = $self->url_for("/dashboard/shares/$b64")->to_abs;

        my $title = $muzak ? $muzak->title : $file;
        unless ($muzak) {
            $title =~ s#.*/##;
            $title =~ s#.mp(3|4)##i;
        }
        $title =~ s#"#\\"#g;
        push(@playlist, { title => $title, src => $src, ext => $ext });
    }
    $self->stash(playlist => \@playlist);

    return $self->render("dashboard/audio");
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
        if ($self->container_valid(path => $selection, container => $path)) {
            if (-f $selection) {
                push(@muzak, $selection);
            }
            else {
                opendir(my $dh, $selection) or die("error: opendir: $selection: $!");
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

    my $whence = $self->param("whence");

    my $browse = $self->param("browse");
    $browse = Mojo::Util::b64_decode($browse);
    $browse = Cwd::abs_path($browse);

    my $dbx = SiteCode::DBX->new();
    my $paths;
    if ($whence) {
        $paths = $dbx->array("SELECT abs_path FROM share WHERE timelimit = ? ORDER BY 1", undef, $whence) || [];
    }
    else {
        if ($browse) {
            $paths = $dbx->array("SELECT abs_path FROM share ORDER BY 1") || [];
        }
        else {
            $paths = $dbx->array("SELECT abs_path FROM share WHERE timelimit is NULL ORDER BY 1") || [];
        }
    }

    foreach my $row (@$paths) {
        my $path = $$row{abs_path};
        if ($self->container_valid(path => $browse, container => $path)) {
            if (-f $browse) {
                $browse =~ m#\.(\w+)#;
                my $format = $1;

                $self->app->types->type(mp4 => 'video/x-m4v');
                $self->app->types->type(mpg => 'video/mpg');
                $self->app->types->type(mpeg => 'video/mpeg');
                $self->app->types->type(mov => 'video/quicktime');

                $self->render_file(
                    'filepath' => $browse,
                    'format' => $format,
                    'content_disposition' => 'inline',   # will change Content-Disposition from "attachment" to "inline"
                );
                # $self->render_file('filepath' => $browse);
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

sub ogv {
    my $self = shift;

    my $mode = $self->param("mode");
    return unless $mode;

    my $selection = $self->param("selection");
    return unless $selection;
    my $decoded = Mojo::Util::b64_decode($selection);
    
    if (-f $decoded) {
        my $src = $self->url_for("/dashboard/shares/ogv/$selection/transcode")->to_abs;
        $self->stash(src => $src);

        $self->res->headers->content_type('video/ogg');

        $self->render_later;

        my $bin = $self->ffmpeg_bin;
        my @cmd = ($bin, "-i", $decoded, "-strict", "-2", "-acodec", "libvorbis", "-vcodec", "libtheora", "-f", "ogg", "-");

        open(my $ffmpeg_fh, "-|", @cmd) or die("error: ffmpeg: $bin: $!");
        binmode($ffmpeg_fh);
        my $buf;
        while (0 != read($ffmpeg_fh,$buf,2048)) {
            $self->write_chunk($buf);
        }
        close($ffmpeg_fh);
        $self->finish;
    }
}

1;
