package PDLNA::Config;

#
# pDLNA - a perl DLNA media server
# Copyright (C) 2010-2013 Stefan Heumader <stefan@heumader.at>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use warnings;

use base 'Exporter';

our @ISA = qw(Exporter);
our @EXPORT = qw(%CONFIG);

# use Config::ApacheFormat;
use DBD::SQLite;
use DBI;
use Digest::MD5;
use Digest::SHA;
use File::Basename;
use File::MimeInfo;
use Net::IP;
use Net::Netmask;
use Sys::Hostname qw(hostname);
use File::HomeDir qw();

use PDLNA::Media;

our %CONFIG = (
	# values which can be modified by configuration file
	'FRIENDLY_NAME' => 'pDLNA $VERSION on $HOSTNAME',
	'LOCAL_IPADDR' => "127.0.0.1",
	'LISTEN_INTERFACE' => undef,
	'HTTP_PORT' => 8080,
	'CACHE_CONTROL' => 1800,
	'PIDFILE' => ($ENV{TEMP} || $ENV{TMP} || $ENV{TMPDIR}) . "/pdlna.pid",
	'ALLOWED_CLIENTS' => [],
	'DB_TYPE' => 'SQLITE3',
	'DB_NAME' => 'pdlna.db',
	'DB_USER' => 'pdlna',
	'DB_PASS' => '',
	'LOG_FILE_MAX_SIZE' => 10485760, # 10 MB
	'LOG_FILE' => 'STDERR',
	'LOG_CATEGORY' => [],
	'DATE_FORMAT' => '%Y-%m-%d %H:%M:%S',
	'BUFFER_SIZE' => 32768, # 32 kB
	'DEBUG' => 2,
	'SPECIFIC_VIEWS' => 0,
	'CHECK_UPDATES' => 0,
	'CHECK_UPDATES_NOTIFICATION' => 0,
	'ENABLE_GENERAL_STATISTICS' => 0,
	'RESCAN_MEDIA' => 86400,
	'UUID' => 'Version4',
	'TMP_DIR' => $ENV{TEMP} || $ENV{TMP} || $ENV{TMPDIR},
	'IMAGE_THUMBNAILS' => 0,
	'VIDEO_THUMBNAILS' => 0,
	'LOW_RESOURCE_MODE' => 0,
	'FFMPEG_BIN' => '/usr/bin/ffmpeg',
	'DIRECTORIES' => [],
	'EXTERNALS' => [],
	'TRANSCODING_PROFILES' => [],
	# values which can be modified manually :P
	'PROGRAM_NAME' => 'pDLNA',
	'PROGRAM_VERSION' => '0.64.3',
	'PROGRAM_DATE' => '2013-12-29',
	'PROGRAM_BETA' => 0,
	'PROGRAM_DBVERSION' => '1.6',
	'PROGRAM_WEBSITE' => 'http://www.pdlna.org',
	'PROGRAM_AUTHOR' => 'Stefan Heumader',
	'PROGRAM_DESC' => 'Perl DLNA MediaServer',
	'AUTHOR_WEBSITE' => 'http://www.urandom.at',
	'PROGRAM_SERIAL' => 1337,
	# arrays holding supported codec
	'AUDIO_CODECS_ENCODE' => [],
	'AUDIO_CODECS_DECODE' => [],
	'VIDEO_CODECS_ENCODE' => [],
	'VIDEO_CODECS_DECODE' => [],
	'FORMATS_ENCODE' => [],
	'FORMATS_DECODE' => [],
	'OS' => $^O,
	'OS_VERSION' => $^O,
	'HOSTNAME' => hostname(),
);

sub print_version
{
	my $string = $CONFIG{'PROGRAM_VERSION'};
	$string .= 'b' if $CONFIG{'PROGRAM_BETA'};
	return $string;
}

sub eval_binary_value
{
	my $value = lc(shift);

	if ($value eq 'on' || $value eq 'true' || $value eq 'yes' || $value eq 'enable' || $value eq 'enabled' || $value eq '1')
	{
		return 1;
	}
	return 0;
}

sub parse_config
{
    my $version_string = print_version();
    $CONFIG{'FRIENDLY_NAME'} =~ s/\$VERSION/v$version_string/;
    $CONFIG{'FRIENDLY_NAME'} =~ s/\$HOSTNAME/$CONFIG{'HOSTNAME'}/;
    $CONFIG{'FRIENDLY_NAME'} =~ s/\$OS/$CONFIG{'OS'}/;

    my $home = File::HomeDir->my_home;

    PDLNA::Config::add_directory(File::HomeDir->my_music, "all") if File::HomeDir->my_music && $home ne File::HomeDir->my_music;
    PDLNA::Config::add_directory(File::HomeDir->my_videos, "all") if File::HomeDir->my_videos && $home ne File::HomeDir->my_videos;
	
	if ("MSWin32" eq $^O) {
		my @lines = `ipconfig`;
		foreach (@lines) {
			if (/IP Address.*:\s+(\d+.\d+.\d+.\d+)/) {
                my $ip = $1;
                next if $ip =~ m/^127/;
				$CONFIG{'LOCAL_IPADDR'} = $ip;
				last;
			}
		}
	} elsif ("darwin" eq $^O) {
		my @lines = `ifconfig`;
		foreach (@lines) {
			if (/inet\s+(\d+.\d+.\d+.\d+)\s+netmask/) {
                my $ip = $1;
                next if $ip =~ m/^127/;
				$CONFIG{'LOCAL_IPADDR'} = $ip;
				last;
			}
		}
	} else {
	}

	return 1;

	#
	# UUID
	#
	# some of the marked code lines are taken from UUID::Tiny perl module,
	# which is not working
	# IMPORTANT NOTE: NOT compliant to RFC 4122
	my $mac = undef;
	if ($CONFIG{'UUID'} eq 'Version3')
	{
		my $md5 = Digest::MD5->new;
		$md5->add($CONFIG{'HOSTNAME'});
		$CONFIG{'UUID'} = substr($md5->digest(), 0, 16);
		$CONFIG{'UUID'} = join '-', map { unpack 'H*', $_ } map { substr $CONFIG{'UUID'}, 0, $_, '' } ( 4, 2, 2, 2, 6 ); # taken from UUID::Tiny perl module
	}
	elsif ($CONFIG{'UUID'} eq 'Version4' || $CONFIG{'UUID'} eq 'Version4MAC')
	{
		if ($CONFIG{'UUID'} eq 'Version4MAC') # determine the MAC address of our listening interfae
		{
			die; ### figure out way to get mac address
			# $mac; ### = lc($interface->hwaddr());
		}

		my @chars = qw(a b c d e f 0 1 2 3 4 5 6 7 8 9);
		$CONFIG{'UUID'} = '';
		while (length($CONFIG{'UUID'}) < 36)
		{
			$CONFIG{'UUID'} .= $chars[int(rand(@chars))];
			$CONFIG{'UUID'} .= '-' if length($CONFIG{'UUID'}) =~ /^(8|13|18|23)$/;
		}

		if (defined($mac))
		{
			$mac =~ s/://g;
			$CONFIG{'UUID'} = substr($CONFIG{'UUID'}, 0, 24).$mac;
		}
	}
	elsif ($CONFIG{'UUID'} eq 'Version5')
	{
		my $sha = Digest::SHA->new();
		$sha->add($CONFIG{'HOSTNAME'});
		$CONFIG{'UUID'} = substr($sha->digest(), 0, 16);
		$CONFIG{'UUID'} = join '-', map { unpack 'H*', $_ } map { substr $CONFIG{'UUID'}, 0, $_, '' } ( 4, 2, 2, 2, 6 ); # taken from UUID::Tiny perl module
	}
	elsif ($CONFIG{'UUID'} =~ /^[0-9a-f]{8}\-[0-9a-f]{4}\-[0-9a-f]{4}\-[0-9a-f]{4}\-[0-9a-f]{12}$/i)
	{
	}
	$CONFIG{'UUID'} = 'uuid:'.$CONFIG{'UUID'};

	#
	# MEDIA DIRECTORY PARSING
	#
### 	foreach my $directory_block ($cfg->get('Directory'))
### 	{
### 		my $block = $cfg->block(Directory => $directory_block->[1]);
		my $block;
		my $directory_block;

		my $recursion = 'yes';
		if (defined($block->get('Recursion')))
		{
			$recursion = $block->get('Recursion');
		}

		my @exclude_dirs = ();
		if (defined($block->get('ExcludeDirs')))
		{
			@exclude_dirs = split(',', $block->get('ExcludeDirs'));
		}
		my @exclude_items = ();
		if (defined($block->get('ExcludeItems')))
		{
			@exclude_items = split(',', $block->get('ExcludeItems'));
		}

		my $allow_playlists = eval_binary_value($block->get('AllowPlaylists')) if defined($block->get('AllowPlaylists'));

		push(@{$CONFIG{'DIRECTORIES'}}, {
				'path' => $directory_block->[1],
				'type' => $block->get('MediaType'),
				'recursion' => $recursion,
				'exclude_dirs' => \@exclude_dirs,
				'exclude_items' => \@exclude_items,
				'allow_playlists' => $allow_playlists,
			}
		);
### 	}

	return 1;
}

sub add_directory {
    my $path = shift;
    my $type = shift;

    push(@{$CONFIG{'DIRECTORIES'}}, {
            'path' => $path,
            'type' => $type,
            'recursion' => 1,
            'exclude_dirs' => [],
            'exclude_items' => [],
            'allow_playlists' => 1,
        }
    );
}

1;
