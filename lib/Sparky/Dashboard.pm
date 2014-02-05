package Sparky::Dashboard;                                                                                                                                              
                                                                                                                                                                        
use Mojo::Base 'Mojolicious::Controller';                                                                                                                               

use SiteCode::Account;
use SiteCode::DBX;
use Mojo::Util;
use Cwd;
use File::HomeDir;
use Mac::iTunes::Library;
use Mac::iTunes::Library::Item;
use Mac::iTunes::Library::XML;
use MP3::Info;
use MP4::Info;
# use Mojo::IOLoop::ForkCall;
use File::Spec;

sub browse {
    my $self = shift;

    unless ($self->session->{have_user}) {
        $self->redirect_to("/");
        return;
    }

    my @paths = ();

    my $home = File::HomeDir->my_home;

    push(@paths, File::HomeDir->my_home) if File::HomeDir->my_home;
    push(@paths, File::HomeDir->my_desktop) if File::HomeDir->my_desktop && $home ne File::HomeDir->my_desktop;
    push(@paths, File::HomeDir->my_documents) if File::HomeDir->my_documents  && $home ne File::HomeDir->my_documents;
    push(@paths, File::HomeDir->my_music) if File::HomeDir->my_music && $home ne File::HomeDir->my_music;
    push(@paths, File::HomeDir->my_pictures) if File::HomeDir->my_pictures && $home ne File::HomeDir->my_pictures;
    push(@paths, File::HomeDir->my_videos) if File::HomeDir->my_videos && $home ne File::HomeDir->my_videos;
    push(@paths, File::HomeDir->my_data) if File::HomeDir->my_data && $home ne File::HomeDir->my_data;

    if ("darwin" eq $^O) {
        push(@paths, "/");
    }
    elsif ("MSWin32" eq $^O) {
        push(@paths, "C:\\");
    }
    elsif ("linux" eq $^O) {
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
        $self->app->types->type(mp4 => 'video/x-m4v');
        $self->app->types->type(mpg => 'video/mpg');
        $self->app->types->type(mpeg => 'video/mpeg');
        $self->app->types->type(mov => 'video/quicktime');

        # $self->render_file('filepath' => $path);
        # $self->render_static($path);

        $path =~ m#\.(\w+)#;
        my $format = $1 || "txt";

        $self->render_file(
            'filepath' => $path,
            'format' => $format,
            'content_disposition' => 'inline',   # will change Content-Disposition from "attachment" to "inline"
        );

        return;
    }

    $path =~ s#^/## if $^O eq "MSWin32";
    my $entries = $self->phys_dir_listing($path);

    foreach my $entry (@{$entries}) {
        $$entry{ctime} = $$entry{ctime} ? scalar(localtime($$entry{ctime})) : "";
    }

    my $user = SiteCode::Account->new(route => $self, username => $self->session->{have_user});
    $user->key("_t_entries", $self->dumper($entries));
    $self->flash("entry.name", "Browse");

    # $self->redirect_to($url);

    ## hack OMG
    # if ($self->flash("entry.name")) {
        $self->stash(error => $self->flash("error")) if $self->flash("error");
        # $self->stash(entry_name => $self->flash("entry.name"));
        $self->stash(entry_name => "Browse");
    
        $user = SiteCode::Account->new(route => $self, username => $self->session->{have_user});
        $entries = eval($user->key("_t_entries"));
        $self->stash(entries => $entries);
        $self->stash(have_files => scalar(@$entries));
        $user->key("_t_entries", undef);
        # }

    $self->stash(cur_title => "Sparky: " . ($path ? $path : "Dashboard"));

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
    ##

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

    $self->stash(cur_title => "Sparky: Dashboard");

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
    my $timed = $self->param("timed");
    my $path = Mojo::Util::b64_decode($b64_path);
    my $abs = Cwd::abs_path($path);

    my $ret = 0;
    my $whence = time();
    eval {
        my $dbx = SiteCode::DBX->new();

        my $id = $dbx->col("SELECT id FROM share WHERE abs_path = ?", undef, $abs);
        if ($id) {
            $ret = 1;

            my $t = $dbx->col("SELECT timelimit FROM share WHERE abs_path = ?", undef, $abs);
            if ($t) {
                $whence = $t;
            }
        }
        else {
            if ($timed) {
                $dbx->do("INSERT INTO share (abs_path, timelimit) VALUES (?, ?)", undef, $abs, $whence);
            }
            else {
                $dbx->do("INSERT INTO share (abs_path) VALUES (?)", undef, $abs);
            }
            $ret = 1;
        }
    };
    
    $self->render(json => { ret => $ret, whence => $whence });
};

sub del_share {
    my $self = shift;

    my $whence = $self->param("whence");
    my $b64_path = $self->param("b64_path");
    my $path = Mojo::Util::b64_decode($b64_path);
    my $abs = Cwd::abs_path($path);

    my $ret = 0;
    eval {
        my $dbx = SiteCode::DBX->new();

        if ($whence) {
            $dbx->do("DELETE FROM share WHERE abs_path = ? AND timelimit = ?", undef, $abs, $whence);
        }
        else {
            $dbx->do("DELETE FROM share WHERE abs_path = ?", undef, $abs);
        }
        $ret = 1;
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

sub itunes {
     my $self = shift;
 
     my $music_dir = File::HomeDir->my_music;

     $self->stash(cur_title => "Sparky");
     $self->stash(menu => 1);

     my $xml = "$music_dir/iTunes/iTunes Music Library.xml";
     if (-f $xml) {
         $self->stash(have_xml => 1);
     }
     else {
         $self->stash(no_xml => 1);
     }

     my $type = $self->param("type");
     if ($type) {
        if ("albums" eq $type) {
            my $albums = $self->_albums($xml);
            my @albums = ();

            foreach my $album (sort keys %$albums) {
                push(@albums, { path => Mojo::Util::b64_encode($album), name => $album });
            }
            $self->stash(albums => \@albums);
        }
        else {
            my $tracks = $self->_tracks($xml);

            $self->stash(tracks => $tracks);
        }

        $self->stash(menu => 0);
     }

     $self->render("dashboard/itunes");
}

sub _tracks {
    my $self = shift;
    my $file = shift;

    my $library = Mac::iTunes::Library->new();
    $library = Mac::iTunes::Library::XML->parse($file);

    my %items = $library->items();

    my %albums = ();

    while ((my ($artist, $artistSongs)) = each %items) {
        while ((my ($songName, $artistSongItems)) = each %$artistSongs) {
            foreach my $item (@$artistSongItems) {
                # Do something here to every item in the library
                my $album = $item->{Album};
                my $track = $item->{"Track Number"};

                if (!$album || !$track) {
                    next;
                }

                $albums{$album}{$track} = $item;
            }
        }
    }

    my %tracks = ();

    foreach my $album (sort keys %albums) {
        foreach my $track (sort( {$a <=> $b} keys %{$albums{$album}})) {
            my $item = $albums{$album}{$track};

            $$item{Location} =~ s#file://localhost##;
            push(@{$tracks{$album}}, { path => Mojo::Util::b64_encode($$item{Location}), name => $$item{Name} });
        }
    }

    return(\%tracks);
}

sub _albums {
    my $self = shift;
    my $file = shift;

    my $library = Mac::iTunes::Library->new();
    $library = Mac::iTunes::Library::XML->parse($file);

    my %items = $library->items();

    my %albums = ();

    while ((my ($artist, $artistSongs)) = each %items) {
        while ((my ($songName, $artistSongItems)) = each %$artistSongs) {
            foreach my $item (@$artistSongItems) {
                # Do something here to every item in the library
                my $album = $item->{Album};
                my $track = $item->{"Track Number"};

                if (!$album || !$track) {
                    next;
                }

                $albums{$album}{$track} = $item;
            }
        }
    }

    return(\%albums);
}

sub audio {
    my $self = shift;

    my $selection = $self->param("selection");
    return unless $selection;
    $selection = Mojo::Util::b64_decode($selection);
    # $selection = Cwd::abs_path($selection);
    
    my $mode = $self->param("mode");
    return unless $mode;

    my @albums = ();
    my @muzak = ();

    if ("album" eq $mode) {
        my $music_dir = File::HomeDir->my_music;
        my $xml_file = "$music_dir/iTunes/iTunes Music Library.xml";
        my $albums = $self->_albums($xml_file);

        foreach my $album (sort keys %$albums) {
            next unless $album eq $selection;
            foreach my $track (sort( {$a <=> $b} keys %{$$albums{$album}})) {
                my $l = $$albums{$album}{$track}{Location};
                $l =~ s#file://localhost##;
                $l =~ s#^/## if $^O eq "MSWin32";

                push(@muzak, $l);
            }
        }
    }
    else {
        # push(@muzak, $selection);
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
        my $src = $self->url_for("/dashboard/browse/$b64")->to_abs;

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

sub video {
    my $self = shift;

    my $mode = $self->param("mode");
    return unless $mode;

    my $selection = $self->param("selection");
    return unless $selection;
    my $decoded = Mojo::Util::b64_decode($selection);
    
    if (-f $decoded) {
        my $src = $self->url_for("/dashboard/browse/video/$selection/transcode")->to_abs;
        $self->stash(src => $src);
    }

    if ("html" eq $mode) {
        return $self->render("dashboard/video");
    }

    # transcode
    # ./ffmpeg/ffmpeg-osx -i movie.avi -acodec libmp3lame -vcodec libx264
    my $bin = $self->ffmpeg_bin;
    # my @cmd = ($bin, "-i", $decoded, "-acodec", "libmp3lame", "-vcodec", "libx264", "-f", "m4v", "-");

###     my $tmp = File::Spec->tmpdir();
###     mkdir("$tmp/sparky") unless -d "$tmp/sparky";
###     mkdir("$tmp/sparky/transcode") unless -d "$tmp/sparky/transcode";
###     my $dir = $self->stash->{_dir} = "$tmp/sparky/transcode";
### 
###     opendir(my $dh, $dir) or die("error: opendir: $dir: $!");
###     my @files = grep { /stream/ && -f "$dir/$_" } readdir($dh);
###     foreach my $file (@files) {
###         unlink("$dir/$file");
###     }
###     closedir($dh);
### 
###     $self->forkcall->run(
###         sub {   
###             my $dir = $self->stash->{_dir};
###             my @cmd = ($bin);
###             push(@cmd, "-i", $decoded, "-async", "1", "-ss", "00:00:05", "-strict", "-2", "-acodec", "aac");
###             push(@cmd, "-b:v", "3000k", "-ac", "2", "-vcodec", "libx264", "-preset", "superfast", "-tune", "zerolatency", "-threads", "2", "-s", "1280x720");
###             push(@cmd, "-flags", "-global_header", "-map", "0:0", "-map", "0:1", "-f", "segment", "-segment_time", "10", "-segment_list", "$dir/stream.m3u8");
###             push(@cmd, "-segment_format", "mpegts", "-segment_wrap", "10", "-segment_list_size", "6", "-segment_list_flags", "live", "$dir/stream%03d.ts");
### 
###             warn(join(" ", @cmd));
###             open(my $fh, "-|", @cmd) or die("error: open: ffmepg: $bin: $!");
###             while(<$fh>) {
###                 warn($_);
###             }
###             close($fh);
###             my @cmd = ($bin, "-i", $decoded, "-acodec", "libmp3lame", "-vcodec", "libx264", "-f", "m4v", "-");
###         },
###         sub { 
###             my ($fc, $err, $ret) = @_;
### 
###             $self->stash->{_dir} = undef;
###         },
###         
###     );
### 
###     foreach my $i (1 .. 10) {
###         my $dir = $self->stash->{_dir};
###         last if -f "$dir/stream.m3u8";
###         sleep 2;
###     }
### 
###     if (-f "$dir/stream.m3u8") {
###         $self->app->types->type(mpeg => 'video/MP2T');
###         $self->render_file('filepath' => "$dir/stream.m3u8");
###     }
###     else {
###         $self->render(text => "No stream created.\n");
###     }

    $self->res->headers->content_type('video/ogg');
    # my @cmd = ($bin, "-i", $decoded, "-acodec", "libmp3lame", "-vcodec", "libx264", "-f", "m4v", "-");
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

sub ogv {
    my $self = shift;

    my $mode = $self->param("mode");
    return unless $mode;

    my $selection = $self->param("selection");
    return unless $selection;
    my $decoded = Mojo::Util::b64_decode($selection);
    
    if (-f $decoded) {
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
