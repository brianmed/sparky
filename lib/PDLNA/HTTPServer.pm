package PDLNA::HTTPServer;
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

use Fcntl;
use Data::Dumper;
use Date::Format;
use GD;
use IO::Select;
use Net::Netmask;
use Socket;
use XML::Simple;
use File::Basename qw();
use Mojo::Util qw(b64_encode b64_decode);
require bytes;
no bytes;

use PDLNA::Config;
use PDLNA::ContentLibrary;
use PDLNA::Database;
use PDLNA::Devices;
use PDLNA::FFmpeg;
use PDLNA::HTTPXML;
use PDLNA::Log;
use PDLNA::SpecificViews;
### use PDLNA::WebUI;

sub start_webserver
{
	my $app = shift;
	my $get = shift;
	my $any = shift;
	my $post = shift;

	PDLNA::Log::log('Starting HTTP Server listening on '.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'.', 0, 'default');

	$get->('/ServerDesc.xml' => sub {
		my $self = shift;

		my $xml = PDLNA::HTTPXML::get_serverdescription($self->req->headers->user_agent);
		$self->render(text => $xml, format => 'xml');
	});

	$get->('/icons/:size/icon.:type' => sub {
		my $self = shift;

		my $size = $self->param("size");
		my $type = $self->param("type");
		PDLNA::Log::log('Delivering Logo in format '.$type.' and with '.$size.'x'.$size.' pixels.', 2, 'httpgeneric');

		GD::Image->trueColor(1);
		my $png = PerlApp::extract_bound_file("pDLNA.png");
		my $image = GD::Image->new($png);
		my $preview = GD::Image->new($size, $size);

		# all black areas of the image should be transparent
		my $black = $preview->colorAllocate(0,0,0);
		$preview->transparent($black);

		$preview->copyResampled($image, 0, 0, 0, 0, $size, $size, $image->width, $image->height);

		$self->render(data => $preview->$type(), format => $type);
	});

	$get->('/ContentDirectory1.xml' => sub {
		my $self = shift;

		my $xml = PDLNA::HTTPXML::get_contentdirectory();
		$self->render(text => $xml, format => 'xml');
	});

	$get->('/ConnectionManager1.xml' => sub {
		my $self = shift;

		my $xml = PDLNA::HTTPXML::get_connectionmanager();
		$self->render(text => $xml, format => 'xml');
	});

	my $event = sub {
		my $self = shift;

		my $response_content = '';
		if ("UNSUBSCRIBE" eq $self->req->method) {
			$response_content = '<html><body><h1>200 OK</h1></body></html>';
		}

		$self->res->headers->add(SID => $CONFIG{UUID});
		$self->res->headers->add(Timeout => "Second-$CONFIG{CACHE_CONTROL}");

		$self->render(text => $response_content);
	};

	$any->('/upnp/event/ContentDirectory1' => $event);
	$any->('/upnp/event/ConnectionManager1' => $event);

	$post->('/upnp/control/ContentDirectory1' => sub {
		my $self = shift;

		my $agent = $self->req->headers->user_agent;
		my $peer_ip_addr = $self->tx->remote_address;

		my $data = $self->req->body;

		my $post_xml;
		my $xmlsimple = XML::Simple->new();
		eval { $post_xml = $xmlsimple->XMLin($data) };
		if ($@)
		{
			PDLNA::Log::log('ERROR: Unable to convert POSTDATA with XML::Simple for '.$peer_ip_addr.': '.$@, 0, 'httpdir');
		}
		else
		{
			PDLNA::Log::log('Finished converting POSTDATA with XML::Simple for '.$peer_ip_addr.'.', 3, 'httpdir');
		}

		my $action = $self->req->headers->header('SOAPAction');
		my $response = ctrl_content_directory_1($post_xml, $action, $peer_ip_addr, $agent);

		$self->render(text => $response, format => "xml");
	});

	$get->('/media/:file' => sub {
		my $self = shift;

		my $file = $self->param("file");

		if ($file =~ m/(\d+)/) {
			my $id = $1;
			my @item = ();
			my $dbh = PDLNA::Database::connect();
			PDLNA::Database::select_db(
				$dbh,
				{
					'query' => 'SELECT NAME,FULLNAME,PATH,FILE_EXTENSION,SIZE,MIME_TYPE,TYPE,EXTERNAL FROM FILES WHERE ID = ?',
					'parameters' => [ $id, ],
				},
				\@item,
			);

			my @iteminfo = ();
			PDLNA::Database::select_db(
				$dbh,
				{
					'query' => 'SELECT CONTAINER, AUDIO_CODEC, VIDEO_CODEC FROM FILEINFO WHERE FILEID_REF = ?;',
					'parameters' => [ $id, ],
				},
				\@iteminfo,
			);

			$self->app->types->type($item[0]{FILE_EXTENSION} => $item[0]{MIME_TYPE});
			$self->render_file(
				'filepath' => $item[0]{FULLNAME},
				'format' => $item[0]{FILE_EXTENSION},
				'content_disposition' => 'inline',   # will change Content-Disposition from "attachment" to "inline"
			);
			PDLNA::Database::disconnect($dbh);

			return;
		}
	});
}

sub handle_connection
{
	my $FH = shift;
	my $peer_ip_addr = shift;
	my $peer_src_port = shift;

	PDLNA::Log::log("RECV HTTP: $FH: $peer_ip_addr: $peer_src_port: " . __LINE__, 3, 'httpgeneric');
	my $response = undef;

	PDLNA::Log::log("RECV HTTP: $FH: $peer_ip_addr: $peer_src_port: " . __LINE__, 3, 'httpgeneric');
	PDLNA::Log::log('Incoming HTTP connection from '.$peer_ip_addr.':'.$peer_src_port.'.', 3, 'httpgeneric');

	PDLNA::Log::log("RECV HTTP: $FH: $peer_ip_addr: $peer_src_port: " . __LINE__, 3, 'httpgeneric');
	# Check if the peer is one of our allowed clients
	my $client_allowed = 0;
	foreach my $block (@{$CONFIG{'ALLOWED_CLIENTS'}})
	{
		$client_allowed++ if $block->match($peer_ip_addr);
	}

	unless ($client_allowed)
	{
		PDLNA::Log::log('Received HTTP request from NOT allowed client IP '.$peer_ip_addr.'.', 2, 'httpgeneric');
		$response = http_header({
			'statuscode' => 403,
			'content_type' => 'text/plain',
		});

		print $FH $response;
		close($FH);
		return 0;
	}
	PDLNA::Log::log("RECV HTTP: $FH: $peer_ip_addr: $peer_src_port: " . __LINE__);

	#
	# PARSING HTTP REQUEST
	#
	binmode($FH);

	my %CGI = ();
	my %ENV = ();

	my $post_xml = undef;
	my $request_line = <$FH>;
	my $first_line = '';
	while (defined($request_line) && $request_line ne "\r\n")
	{
		next unless $request_line;
		$request_line =~ s/\r\n//g;
		chomp($request_line);

		if (!$first_line)
		{
			$first_line = $request_line;

			my @parts = split(' ', $first_line);
			close $FH if @parts != 3;

			$ENV{'METHOD'} = $parts[0];
			$ENV{'OBJECT'} = $parts[1];
			$ENV{'HTTP_VERSION'} = $parts[2];
		}
		else
		{
			my ($name, $value) = split(':', $request_line, 2);
			$name = uc($name);
			$value =~ s/^\s//g;
			$CGI{$name} = $value;
		}
		$request_line = <$FH>;
	}

	if (!defined($ENV{'METHOD'}) || !defined($ENV{'OBJECT'}))
	{
		PDLNA::Log::log('ERROR: Unable to parse HTTP request from '.$peer_ip_addr.':'.$peer_src_port.'.', 0, 'httpstream');
		$response = http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});

		print $FH $response;
		close($FH);
		return 0;
	}

	my $debug_string = '';
	foreach my $key (keys %CGI)
	{
		$debug_string .= "\n\t".$key.' -> '.$CGI{$key};
	}
	PDLNA::Log::log($ENV{'METHOD'}.' '.$ENV{'OBJECT'}.' from '.$peer_ip_addr.':'.$peer_src_port.':'.$debug_string, 3, 'httpgeneric');

	#
	# Reading POSTDATA, PARSING XML
	#
	if ($ENV{'METHOD'} eq "POST")
	{
		if (defined($CGI{'CONTENT-LENGTH'}) && length($CGI{'CONTENT-LENGTH'}) > 0)
		{
			PDLNA::Log::log('Reading '.$CGI{'CONTENT-LENGTH'}.' bytes from request for POSTDATA.', 2, 'httpgeneric');
			read($FH, $CGI{'POSTDATA'}, $CGI{'CONTENT-LENGTH'});
		}
		else
		{
			PDLNA::Log::log('Looking for \r\n in request for POSTDATA.', 2, 'httpgeneric');
			$CGI{'POSTDATA'} = <$FH>;
		}
		PDLNA::Log::log('POSTDATA: '.$CGI{'POSTDATA'}, 3, 'httpgeneric');

		my $xmlsimple = XML::Simple->new();
		eval { $post_xml = $xmlsimple->XMLin($CGI{'POSTDATA'}) };
		if ($@)
		{
			PDLNA::Log::log('ERROR: Unable to convert POSTDATA with XML::Simple for '.$peer_ip_addr.':'.$peer_src_port.': '.$@, 0, 'httpdir');
		}
		else
		{
			PDLNA::Log::log('Finished converting POSTDATA with XML::Simple for '.$peer_ip_addr.':'.$peer_src_port.'.', 3, 'httpdir');
		}
	}

	# adding device and/or request to Devices tables
	my $dbh = PDLNA::Database::connect();
	PDLNA::Devices::add_device(
		$dbh,
		{
			'ip' => $peer_ip_addr,
			'http_useragent' => $CGI{'USER-AGENT'},
		},
	);
	my $model_name = PDLNA::Devices::get_modelname_by_devicetype($dbh, $peer_ip_addr, 'urn:schemas-upnp-org:device:MediaRenderer:1');
	PDLNA::Log::log('ModelName for '.$peer_ip_addr.' is '.$model_name.'.', 2, 'httpgeneric');
	PDLNA::Database::disconnect($dbh);

	#
	# HANDLING DIFFERENT KIND OF REQUESTS
	#
	if ($ENV{'OBJECT'} eq '/ServerDesc.xml') # delivering ServerDescription XML
	{
		my $xml = PDLNA::HTTPXML::get_serverdescription($CGI{'USER-AGENT'});
		my @additional_header = (
			'Content-Type: text/xml; charset=utf8',
			'Content-Length: '.length($xml),
		);
		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
		});
		$response .= $xml;
	}
	elsif ($ENV{'OBJECT'} eq '/ContentDirectory1.xml') # delivering ContentDirectory XML
	{
		my $xml = PDLNA::HTTPXML::get_contentdirectory();
		my @additional_header = (
			'Content-Type: text/xml; charset=utf8',
			'Content-Length: '.length($xml),
		);
		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
		});
		$response .= $xml;
	}
	elsif ($ENV{'OBJECT'} eq '/ConnectionManager1.xml') # delivering ConnectionManager XML
	{
		my $xml = PDLNA::HTTPXML::get_connectionmanager();
		my @additional_header = (
			'Content-Type: text/xml; charset=utf8',
			'Content-Length: '.length($xml),
		);
		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
		});
		$response .= $xml;
	}
	elsif ($ENV{'OBJECT'} eq '/upnp/event/ContentDirectory1' || $ENV{'OBJECT'} eq '/upnp/event/ConnectionManager1')
	{
		my $response_content = '';
		$response_content = '<html><body><h1>200 OK</h1></body></html>' if $ENV{'METHOD'} eq 'UNSUBSCRIBE';

		my @additional_header = (
			'Content-Length: '.length($response_content),
			'SID: '.$CONFIG{'UUID'},
			'Timeout: Second-'.$CONFIG{'CACHE_CONTROL'},
		);
		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
		});
		$response .= $response_content;
	}
	elsif ($ENV{'OBJECT'} eq '/upnp/control/ContentDirectory1') # handling Directory Listings
	{
		$response = ctrl_content_directory_1($post_xml, $CGI{'SOAPACTION'}, $peer_ip_addr, $CGI{'USER-AGENT'});
	}
#	elsif ($ENV{'OBJECT'} eq '/upnp/control/ConnectionManager1')
#	{
#	}
	elsif ($ENV{'OBJECT'} =~ /^\/media\/(.*)$/) # handling media streaming
	{
		stream_media($1, $ENV{'METHOD'}, \%CGI, $FH, $model_name, $peer_ip_addr, $CGI{'USER-AGENT'});
	}
	elsif ($ENV{'OBJECT'} =~ /^\/subtitle\/(.*)$/) # handling delivering of subtitles
	{
		deliver_subtitle($1, $ENV{'METHOD'}, \%CGI, $FH, $model_name);
	}
	elsif ($ENV{'OBJECT'} =~ /^\/preview\/(.*)$/) # handling media thumbnails
	{
		$response = preview_media($1);
	}
	elsif ($ENV{'OBJECT'} =~ /^\/icons\/(.*)$/) # handling pDLNA logo
	{
		$response = logo($1);
	}
	elsif ($ENV{'OBJECT'} =~ /^\/webui\/js.js$/) # deliver javascript code
	{
		$response = PDLNA::WebUI::javascript();
	}
	elsif ($ENV{'OBJECT'} =~ /^\/webui\/css.css$/) # deliver stylesheet
	{
		$response = PDLNA::WebUI::css();
	}
	elsif ($ENV{'OBJECT'} =~ /^\/webui\/graphs\/(.+)\.png$/) # handling delivering graphs
	{
		print $FH PDLNA::WebUI::graph($1);
		close($FH);
	}
	elsif ($ENV{'OBJECT'} =~ /^\/webui\/(.*)$/) # handling WebUI
	{
		print $FH PDLNA::WebUI::show($1);
		close($FH);
	}
	else # NOT supported request
	{
		PDLNA::Log::log('Request '.$ENV{'METHOD'}.' '.$ENV{'OBJECT'}.' from '.$peer_ip_addr.' NOT supported yet.', 2, 'httpgeneric');
		$response = http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});
	}

	if (defined($response))
	{
		print $FH $response;
		close($FH);
	}
	return 1;
}

sub http_header
{
	my $params = shift;

	my %HTTP_CODES = (
		200 => 'OK',
		206 => 'Partial Content',
		400 => 'Bad request',
		403 => 'Forbidden',
		404 => 'Not found',
		406 => 'Not acceptable',
		501 => 'Not implemented',
	);

	my @response = ();
	push(@response, "HTTP/1.1 ".$$params{'statuscode'}." ".$HTTP_CODES{$$params{'statuscode'}}); # TODO (maybe) differ between http protocol versions
	push(@response, "Server: ".$CONFIG{'OS'}."/".$CONFIG{'OS_VERSION'}.", UPnP/1.0, ".$CONFIG{'PROGRAM_NAME'}."/".PDLNA::Config::print_version());
	push(@response, "Content-Type: ".$params->{'content_type'}) if $params->{'content_type'};
	push(@response, "Content-Length: ".$params->{'content_length'}) if $params->{'content_length'};
	push(@response, "Date: ".PDLNA::Utils::http_date());
#	push(@response, "Last-Modified: ".PDLNA::Utils::http_date());
	if (defined($$params{'additional_header'}))
	{
		foreach my $header (@{$$params{'additional_header'}})
		{
			push(@response, $header);
		}
	}
	push(@response, 'Cache-Control: no-cache');
	push(@response, 'Connection: close');

 	PDLNA::Log::log("HTTP Response Header:\n\t".join("\n\t",@response), 3, $$params{'log'}) if defined($$params{'log'});
	return join("\r\n", @response)."\r\n\r\n";
}

sub ctrl_content_directory_1
{
	my $xml = shift;
	my $action = shift;
	my $peer_ip_addr = shift;
	my $user_agent = shift;

	my $dbh = PDLNA::Database::connect();
	my $response_xml = undef;

	PDLNA::Log::log("Function PDLNA::HTTPServer::ctrl_content_directory_1 called", 3, 'httpdir');

	if ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#Browse"')
	{
		my ($object_id, $starting_index, $requested_count, $filter, $browse_flag) = 0;
		# determine which 'Browse' element was used
		if (defined($xml->{'s:Body'}->{'ns0:Browse'}->{'ObjectID'})) # coherence seems to use this one
		{
			$object_id = $xml->{'s:Body'}->{'ns0:Browse'}->{'ObjectID'};
			$starting_index = $xml->{'s:Body'}->{'ns0:Browse'}->{'StartingIndex'};
			$requested_count = $xml->{'s:Body'}->{'ns0:Browse'}->{'RequestedCount'};
			$browse_flag = $xml->{'s:Body'}->{'ns0:Browse'}->{'BrowseFlag'};
			$filter = $xml->{'s:Body'}->{'ns0:Browse'}->{'Filter'};
		}
		elsif (defined($xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}))
		{
			$object_id = $xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'};
			$starting_index = $xml->{'s:Body'}->{'u:Browse'}->{'StartingIndex'};
			$requested_count = $xml->{'s:Body'}->{'u:Browse'}->{'RequestedCount'};
			$browse_flag = $xml->{'s:Body'}->{'u:Browse'}->{'BrowseFlag'};
			$filter = $xml->{'s:Body'}->{'u:Browse'}->{'Filter'};
		}
		elsif (defined($xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'ObjectID'}->{'content'})) # and windows media player this one
		{
			$object_id = $xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'ObjectID'}->{'content'};
			$starting_index = $xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'StartingIndex'}->{'content'};
			$requested_count = $xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'RequestedCount'}->{'content'};
			$browse_flag = $xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'BrowseFlag'}->{'content'};
			$filter = $xml->{'SOAP-ENV:Body'}->{'m:Browse'}->{'Filter'}->{'content'};
		}
		else
		{
			PDLNA::Log::log('ERROR: Unable to find (a known) ObjectID in XML (POSTDATA).', 0, 'httpdir');
			return http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
			});
		}

		#
		# validate BrowseFlag
		#
		my @browsefilters = split(',', $filter) if length($filter) > 0;
		if ($browse_flag eq 'BrowseMetadata')
		{
			if (grep(/^\@parentID$/, @browsefilters))
			{
				@browsefilters = ('@id', '@parentID', '@childCount', '@restricted', 'dc:title', 'upnp:class');

				# set object_id to parentid
				my @directory_parent = ();
				PDLNA::Database::select_db(
					$dbh,
					{
						'query' => 'SELECT ID FROM DIRECTORIES WHERE PATH IN ( SELECT DIRNAME FROM DIRECTORIES WHERE ID = ? );',
						'parameters' => [ $object_id, ],
					},
					\@directory_parent,
				);
				$directory_parent[0]->{ID} = 0 if !defined($directory_parent[0]->{ID});
				$object_id = $directory_parent[0]->{ID};
			}
		}
		elsif ($browse_flag eq 'BrowseDirectChildren')
		{
			if ($filter eq '*')
			{
				@browsefilters = ();
			}

			# these filter seem to be mandatory, so we need to put them always into the HTTP response
			foreach my $filter ('@id', '@parentID', '@childCount', '@restricted', 'dc:title', 'upnp:class')
			{
				push(@browsefilters, $filter) unless grep(/^$filter$/, @browsefilters);
			}

			if ($filter eq '*')
			{
				push(@browsefilters, 'res@bitrate');
				push(@browsefilters, 'res@duration');
			}
		}
		else
		{
			PDLNA::Log::log('BrowseFlag: '.$browse_flag.' is NOT supported yet.', 2, 'httpdir');
			return http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
			});
		}

		PDLNA::Log::log('Starting to handle Directory Listing request for: '.$object_id.'.', 3, 'httpdir');
		PDLNA::Log::log('StartingIndex: '.$starting_index.'.', 3, 'httpdir');
		PDLNA::Log::log('RequestedCount: '.$requested_count.'.', 3, 'httpdir');
		PDLNA::Log::log('BrowseFlag: '.$browse_flag.'.', 3, 'httpdir');
		PDLNA::Log::log('Filter: '.join(', ', @browsefilters).'.', 3, 'httpdir');

		$requested_count = 10 if $requested_count == 0; # if client asks for 0 items, we should return the 'default' amount (in our case 10)

		if ($object_id =~ /^\d+$/)
		{
			PDLNA::Log::log('Received numeric Directory Listing request for: '.$object_id.'.', 2, 'httpdir');

### 			#
### 			# get the subdirectories for the object_id requested
### 			#
### 			my @dire_elements = ();
### 			PDLNA::ContentLibrary::get_subdirectories_by_id($dbh, $object_id, $starting_index, $requested_count, \@dire_elements);
### 
### 			#
### 			# get the full amount of subdirectories for the object_id requested
### 			#
### 			my $amount_directories = PDLNA::ContentLibrary::get_amount_subdirectories_by_id($dbh, $object_id);
### 
### 			$requested_count = $requested_count - scalar(@dire_elements); # amount of @dire_elements is already in answer
### 			if ($starting_index >= $amount_directories)
### 			{
### 				$starting_index = $starting_index - $amount_directories;
### 			}
### 
### 			#
### 			# get the files for the directory requested
### 			#
### 			my @file_elements = ();
### 			PDLNA::ContentLibrary::get_subfiles_by_id($dbh, $object_id, $starting_index, $requested_count, \@file_elements);
### 
### 			#
### 			# get the full amount of files in the directory requested
### 			#
### 			my $amount_files = PDLNA::ContentLibrary::get_amount_subfiles_by_id($dbh, $object_id);

 			my @dire_elements = ();
 			my @file_elements = ();
            my $amount_directories = 0;
            my $amount_files = 0;
            foreach my $directory (@{$CONFIG{'DIRECTORIES'}}) {
                ++$amount_directories;
                push(@dire_elements, { NAME => File::Basename::basename($$directory{path}), ID => b64_encode($$directory{path}) });
            }

			#
			# build the http response
			#
			$response_xml .= PDLNA::HTTPXML::get_browseresponse_header();

			foreach my $directory (@dire_elements)
			{
				$response_xml .= PDLNA::HTTPXML::get_browseresponse_directory(
					$directory->{ID},
					$directory->{NAME},
					\@browsefilters,
					$dbh,
				);
			}

			foreach my $file (@file_elements)
			{
				$response_xml .= PDLNA::HTTPXML::get_browseresponse_item($file->{ID}, \@browsefilters, $dbh, $peer_ip_addr, $user_agent);
			}

			my $elements_in_listing = scalar(@dire_elements) + scalar(@file_elements);
			my $elements_in_directory = $amount_directories + $amount_files;

			$response_xml .= PDLNA::HTTPXML::get_browseresponse_footer($elements_in_listing, $elements_in_directory);
 			PDLNA::Log::log('Done preparing answer for numeric Directory Listing request for: '.$object_id.'.', 3, 'httpdir');
		}
		elsif ($object_id =~ /^(\w)\_(\w)\_{0,1}(\d*)\_{0,1}(\d*)/)
		{
			PDLNA::Log::log('Received SpecificView Directory Listing request for: '.$object_id.'.', 2, 'httpdir');

			my $media_type = $1;
			my $group_type = $2;
			my $group_id = $3;
			my $item_id = $4;

			unless (PDLNA::SpecificViews::supported_request($media_type, $group_type))
			{
				PDLNA::Log::log('SpecificView: '.$media_type.'_'.$group_type.' is NOT supported yet.', 2, 'httpdir');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}

			if (length($group_id) == 0)
			{
				my @group_elements = ();
				PDLNA::SpecificViews::get_groups($dbh, $media_type, $group_type, $starting_index, $requested_count, \@group_elements);
				my $amount_groups = PDLNA::SpecificViews::get_amount_of_groups($dbh, $media_type, $group_type);

				$response_xml .= PDLNA::HTTPXML::get_browseresponse_header();
				foreach my $group (@group_elements)
				{
					$response_xml .= PDLNA::HTTPXML::get_browseresponse_group_specific(
						$group->{ID},
						$media_type,
						$group_type,
						$group->{NAME},
						\@browsefilters,
						$dbh,
					);
				}
				$response_xml .= PDLNA::HTTPXML::get_browseresponse_footer(scalar(@group_elements), $amount_groups);
			}
			elsif (length($group_id) > 0 && length($item_id) == 0)
			{
				$group_id = PDLNA::Utils::remove_leading_char($group_id, '0');

				my @item_elements = ();
				PDLNA::SpecificViews::get_items($dbh, $media_type, $group_type, $group_id, $starting_index, $requested_count, \@item_elements);
				my $amount_items = PDLNA::SpecificViews::get_amount_of_items($dbh, $media_type, $group_type, $group_id);

				$response_xml .= PDLNA::HTTPXML::get_browseresponse_header();
				foreach my $item (@item_elements)
				{
					$response_xml .= PDLNA::HTTPXML::get_browseresponse_item_specific(
						$item->{ID},
						$media_type,
						$group_type,
						$group_id,
						\@browsefilters,
						$dbh,
						$peer_ip_addr,
						$user_agent,
					);
				}
				$response_xml .= PDLNA::HTTPXML::get_browseresponse_footer(scalar(@item_elements), $amount_items);
			}
			else
			{
				PDLNA::Log::log('ERROR: SpecificView: Unable to understand request for ObjectID '.$object_id.'.', 0, 'httpdir');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}
		}
        else
        {
            my $directory = b64_decode($object_id);
            my @dire_elements = ();
            my @file_elements = ();

            opendir(my $dh, $directory);
            my @entries = sort readdir($dh);

            my $amount_directories = 0;
            my $amount_files = 0;

            foreach my $ent (@entries) {
                next if "." eq $ent;
                next if ".." eq $ent;

                if (-d "$directory/$ent") {
                    ++$amount_directories;
                    push(@dire_elements, { NAME => $ent, ID => b64_encode("$directory/$ent") }); #ID NAME SIZE DATA
                }
                elsif (-f "$directory/$ent") {
                    my @stat = stat("$directory/$ent");
                    my $time = scalar(localtime($stat[9]));

                    ++$amount_files;
                    push(@file_elements, { NAME => $ent, PARENT_ID => b64_encode($directory), ID => b64_encode("$directory/$ent"), SIZE => $stat[7], DATE => $time}); #ID NAME SIZE DATA
                }
            }
            
            closedir($dh);

			#
			# build the http response
			#
			$response_xml .= PDLNA::HTTPXML::get_browseresponse_header();

			foreach my $directory (@dire_elements)
			{
				$response_xml .= PDLNA::HTTPXML::get_browseresponse_directory(
					$directory->{ID},
					$directory->{NAME},
					\@browsefilters,
					$dbh,
				);
			}

			foreach my $file (@file_elements)
			{
				my $file_xml .= PDLNA::HTTPXML::get_browseresponse_item($file->{ID}, \@browsefilters, $dbh, $peer_ip_addr, $user_agent, $file->{PARENT_ID});
                $response_xml .= $file_xml;
			}

			my $elements_in_listing = scalar(@dire_elements) + scalar(@file_elements);
			my $elements_in_directory = $amount_directories + $amount_files;

			$response_xml .= PDLNA::HTTPXML::get_browseresponse_footer($elements_in_listing, $elements_in_directory);
        }
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSearchCapabilities"')
	{
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:GetSearchCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<SearchCaps></SearchCaps>';
		$response_xml .= '</u:GetSearchCapabilitiesResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSortCapabilities"')
	{
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:GetSortCapabilitiesResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<SortCaps></SortCaps>';
		$response_xml .= '</u:GetSortCapabilitiesResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#GetSystemUpdateID"')
	{
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:GetSystemUpdateIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<Id>0</Id>';
		$response_xml .= '</u:GetSystemUpdateIDResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
	# OLD CODE
#	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_GetObjectIDfromIndex"')
#	{
#		my $media_type = '';
#		my $sort_type = '';
#		if ($xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 14)
#		{
#			$media_type = 'I';
#			$sort_type = 'F';
#		}
#		elsif ($xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 22)
#		{
#			$media_type = 'A';
#			$sort_type = 'F';
#		}
#		elsif ($xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'CategoryType'} == 32)
#		{
#			$media_type = 'V';
#			$sort_type = 'F';
#		}
#		PDLNA::Log::log('Getting object for '.$media_type.'_'.$sort_type.'.', 2, 'httpdir');
#
#		my $index = $xml->{'s:Body'}->{'u:X_GetObjectIDfromIndex'}->{'Index'};
#
#		my $content_type_obj = $content->get_content_type($media_type, $sort_type);
#		my $i = 0;
#		my @groups = @{$content_type_obj->content_groups()};
#		while ($index >= $groups[$i]->content_items_amount())
#		{
#			$index -= $groups[$i]->content_items_amount();
#			$i++;
#		}
#		my $content_item_obj = $groups[$i]->content_items()->[$index];
#
#		$response = http_header({
#			'statuscode' => 200,
#		});
#
#		$response .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
#		$response .= '<s:Body>';
#		$response .= '<u:X_GetObjectIDfromIndexResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
#		$response .= '<ObjectID>'.$media_type.'_'.$sort_type.'_'.$groups[$i]->beautiful_id().'_'.$content_item_obj->beautiful_id().'</ObjectID>';
#		$response .= '</u:X_GetObjectIDfromIndexResponse>';
#		$response .= '</s:Body>';
#		$response .= '</s:Envelope>';
#	}
	# TODO X_GetIndexfromRID (i think it might be the question, to which item the tv should jump ... but currently i don't understand the question (<RID></RID>)
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_GetIndexfromRID"')
	{
		$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
		$response_xml .= '<s:Body>';
		$response_xml .= '<u:X_GetIndexfromRIDResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
		$response_xml .= '<Index>0</Index>'; # we are setting it to 0 - so take the first item in the list to be active
		$response_xml .= '</u:X_GetIndexfromRIDResponse>';
		$response_xml .= '</s:Body>';
		$response_xml .= '</s:Envelope>';
	}
	elsif ($action eq '"urn:schemas-upnp-org:service:ContentDirectory:1#X_SetBookmark"')
	{
		PDLNA::Log::log('Handling X_SetBookmark request.', 2, 'httpdir');
		if (defined($xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}) && defined($xml->{'s:Body'}->{'u:Browse'}->{'PosSecond'}))
		{
			my @device_ip = ();
			PDLNA::Database::select_db(
				$dbh,
				{
					'query' => 'SELECT ID FROM DEVICE_IP WHERE IP = ?',
					'parameters' => [ $peer_ip_addr, ],
				},
				\@device_ip,
			);

			if (defined($device_ip[0]->{ID}))
			{
				my @device_bm = ();
				PDLNA::Database::select_db(
					$dbh,
					{
						'query' => 'SELECT POS_SECONDS FROM DEVICE_BM WHERE FILE_ID_REF = ? AND DEVICE_IP_REF = ?',
						'parameters' => [ $xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}, $device_ip[0]->{ID}, ],
					},
					\@device_bm,
				);

				if (defined($device_bm[0]->{POS_SECONDS}))
				{
					PDLNA::Database::update_db(
						$dbh,
						{
							'query' => 'UPDATE DEVICE_BM SET POS_SECONDS = ? WHERE FILE_ID_REF = ? AND DEVICE_IP_REF = ?',
							'parameters' => [ $xml->{'s:Body'}->{'u:Browse'}->{'PosSecond'}, $xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}, $device_ip[0]->{ID}, ],
						}
					);
				}
				else
				{
					PDLNA::Database::insert_db(
						$dbh,
						{
							'query' => 'INSERT INTO DEVICE_BM (FILE_ID_REF, DEVICE_IP_REF, POS_SECONDS) VALUES (?,?,?)',
							'parameters' => [ $xml->{'s:Body'}->{'u:Browse'}->{'ObjectID'}, $device_ip[0]->{ID}, $xml->{'s:Body'}->{'u:Browse'}->{'PosSecond'}, ],
						}
					);
				}

				$response_xml .= '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">';
				$response_xml .= '<s:Body>';
				$response_xml .= '<u:X_SetBookmarkResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1">';
				$response_xml .= '</u:X_SetBookmarkResponse>';
				$response_xml .= '</s:Body>';
				$response_xml .= '</s:Envelope>';
			}
			else
			{
				PDLNA::Log::log('Unable to find matching DEVICE_IP database entry.', 2, 'httpdir');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}
		}
		else
		{
			PDLNA::Log::log('Missing ObjectID or PosSecond parameter.', 2, 'httpdir');
			return http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
			});
		}
	}
	else
	{
		PDLNA::Log::log('Action: '.$action.' is NOT supported yet.', 2, 'httpdir');
		return http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});
	}

	#
	# RETURN THE ANSWER
	#
	my $response = undef;
	if (defined($response_xml))
	{
		$response = http_header({
			'statuscode' => 200,
			'log' => 'httpdir',
			'content_length' => length($response_xml),
			'content_type' => 'text/xml; charset=utf8',
		});
		$response .= $response_xml;
 		PDLNA::Log::log('Response: '.$response, 3, 'httpdir');
	}
	else
	{
		PDLNA::Log::log('ERROR: No Response.', 0, 'httpdir');
		$response = http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});
	}
	return $response_xml;
}

#
# this functions handels delivering the subtitle files
#
sub deliver_subtitle
{
	my $content_id = shift;
	my $method = shift;
	my $CGI = shift;
	my $FH = shift;
	my $model_name = shift;

	if ($content_id =~ /^(\d+)\.(\w+)$/)
	{
		my $id = $1;
		my $type = $2;

		PDLNA::Log::log('Delivering subtitle: '.$id.'.'.$type.'.', 3, 'httpstream');

		my $dbh = PDLNA::Database::connect();
		my @subtitles = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT FULLNAME, SIZE FROM SUBTITLES WHERE ID = ? AND TYPE = ?',
				'parameters' => [ $id, $type, ],
			},
			\@subtitles,
		);
		PDLNA::Database::disconnect($dbh);

		if (defined($subtitles[0]->{FULLNAME}) && -f $subtitles[0]->{FULLNAME})
		{
			my @additional_header = ();
			if (defined($$CGI{'GETCONTENTFEATURES.DLNA.ORG'}) && $$CGI{'GETCONTENTFEATURES.DLNA.ORG'} == 1)
			{
				push(@additional_header, 'contentFeatures.dlna.org: DLNA.ORG_OP=00;DLNA.ORG_CI=0;');
			}
			if (defined($$CGI{'TRANSFERMODE.DLNA.ORG'}) && $$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Background')
			{
				push(@additional_header, 'transferMode.dlna.org: Background');
			}

			print $FH http_header({
				'content_length' => $subtitles[0]->{SIZE},
				'content_type' => 'smi/caption',
				'statuscode' => 200,
				'additional_header' => \@additional_header,
				'log' => 'httpstream',
			});

			sysopen(FILE, $subtitles[0]->{FULLNAME}, O_RDONLY);
			print $FH <FILE>;
			close(FILE);
		}
		else
		{
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
			});
		}
	}
	else
	{
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
		});
	}
}

sub stream_media_beta
{
	my $content_id = shift;
	my $method = shift;
	my $CGI = shift;
	my $FH = shift;
	my $model_name = shift;
	my $client_ip = shift;
	my $user_agent = shift;

	#
	# ContentID verification
	#
	my $id = 0;
	if ($content_id =~ /^(\d+)\.(\w+)$/)
	{
		$id = $1;
	}
	else
	{
		PDLNA::Log::log('ERROR: ContentID '.$content_id.' for Streaming Items is NOT supported yet.', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
		close(FILE);
		return;
	}
	PDLNA::Log::log('Found ContentID in streaming request: '.$id, 3, 'httpstream');

	#
	# getting information from database
	#
	my $dbh = PDLNA::Database::connect();

	my @item = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT NAME,FULLNAME,PATH,FILE_EXTENSION,SIZE,MIME_TYPE,TYPE,EXTERNAL FROM FILES WHERE ID = ?',
			'parameters' => [ $id, ],
		},
		\@item,
	);

	my @iteminfo = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT CONTAINER, AUDIO_CODEC, VIDEO_CODEC, DURATION FROM FILEINFO WHERE FILEID_REF = ?;',
			'parameters' => [ $id, ],
		},
		\@iteminfo,
	);

	my @subtitles = ();
	PDLNA::Database::select_db(
		$dbh,
		{
			'query' => 'SELECT ID, TYPE, FULLNAME FROM SUBTITLES WHERE FILEID_REF = ?',
			'parameters' => [ $id, ],
		},
		\@subtitles,
	);

	PDLNA::Database::disconnect($dbh);

	#
	# TODO sanity checks for file
	#

	my $transcode = 0;


	#
	# TODO HTTP response header
	#

	my @additional_header = ();
	push(@additional_header, 'Content-Type: '.PDLNA::Media::get_mimetype_by_modelname($item[0]->{MIME_TYPE}, $model_name));
	push(@additional_header, 'Content-Length: '.$item[0]->{SIZE}) if !$item[0]->{EXTERNAL}; # TODO
	push(@additional_header, 'Content-Disposition: attachment; filename="'.$item[0]->{NAME}.'"') if !$item[0]->{EXTERNAL};
	push(@additional_header, 'Accept-Ranges: bytes'); # TODO

	#
	# contentFeatures.dlna.org
	# Streaming of content is NOT working with SAMSUNG without this response header
	#
	if (defined($$CGI{'GETCONTENTFEATURES.DLNA.ORG'}))
	{
		if ($$CGI{'GETCONTENTFEATURES.DLNA.ORG'} == 1)
		{
			push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
		}
		else
		{
			PDLNA::Log::log('Invalid contentFeatures.dlna.org:'.$$CGI{'GETCONTENTFEATURES.DLNA.ORG'}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 400,
				'content_type' => 'text/plain',
			});
			close(FILE);
			return;
		}
	}

	#
	# SUBTITLES
	#
	if (defined($$CGI{'GETCAPTIONINFO.SEC'}))
	{
		if ($$CGI{'GETCAPTIONINFO.SEC'} == 1)
		{
			if ($item[0]->{TYPE} eq 'video')
			{
				foreach my $subtitle (@subtitles)
				{
					if ($subtitle->{TYPE} eq 'srt' && -f $subtitle->{FULLNAME})
					{
						push(@additional_header, 'CaptionInfo.sec: http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'/subtitle/'.$subtitle->{ID}.'.srt');
					}
				}
			}

			unless (grep(/^contentFeatures.dlna.org:/, @additional_header))
			{
				push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
			}
		}
		else
		{
			PDLNA::Log::log('Invalid getCaptionInfo.sec:'.$$CGI{'GETCAPTIONINFO.SEC'}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 400,
				'content_type' => 'text/plain',
			});
			close(FILE);
			return;
		}
	}

	#
	# DURATION
	#
	if (defined($$CGI{'GETMEDIAINFO.SEC'}))
	{
		if ($$CGI{'GETMEDIAINFO.SEC'} == 1)
		{
			if ($item[0]->{TYPE} eq 'video' || $item[0]->{TYPE} eq 'audio')
			{
				push(@additional_header, 'MediaInfo.sec: SEC_Duration='.$iteminfo[0]->{DURATION}.'000;'); # in milliseconds

				unless (grep(/^contentFeatures.dlna.org:/, @additional_header))
				{
					push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
				}
			}
		}
		else
		{
			PDLNA::Log::log('Invalid getMediaInfo.sec:'.$$CGI{'GETMEDIAINFO.SEC'}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 400,
				'content_type' => 'text/plain',
			});
			close(FILE);
			return;
		}
	}

	#
	# HANDLING THE THE REQUESTS
	#

	if ($method eq 'HEAD') # handling HEAD requests
	{
		PDLNA::Log::log('Delivering content information (HEAD Request) for: '.$item[0]->{NAME}.'.', 1, 'httpstream');

		print $FH http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
			'log' => 'httpstream',
		});
		close(FILE);
		return;
	}
	elsif ($method eq 'GET') # handling GET requests
	{
		# for clients, which are not sending the Streaming value for the transferMode.dlna.org parameter
		# we set it, because they seem to ignore it
		my @useragents = (
			'foobar2000', # since foobar2000 is NOT sending any TRANSFERMODE.DLNA.ORG param
			'vlc*', # since vlc is NOT sending any TRANSFERMODE.DLNA.ORG param
			'stagefright', # since UPnPlay is NOT sending any TRANSFERMODE.DLNA.ORG param
			'gvfs', # since Totem Movie Player is NOT sending any TRANSFERMODE.DLNA.ORG param
			'(null)',
		);
		if (defined($$CGI{'USER-AGENT'}))
		{
			foreach my $ua (@useragents)
			{
				$$CGI{'TRANSFERMODE.DLNA.ORG'} = 'Streaming' if $$CGI{'USER-AGENT'} =~ /^$ua/i;
			}
		}

		#
		# transferMode handling
		#
		if (defined($$CGI{'TRANSFERMODE.DLNA.ORG'}))
		{
			if ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Streaming') # for immediate rendering of audio or video content
			{
				push(@additional_header, 'transferMode.dlna.org: Streaming');

				if (defined($$CGI{'TIMESEEKRANGE.DLNA.ORG'}) && $$CGI{'TIMESEEKRANGE.DLNA.ORG'} =~ /^npt=(\d+)-(\d*)/)
				{
					PDLNA::Log::log('Delivering content for: '.$item[0]->{FULLNAME}.' with TIMESEEKRANGE request.', 1, 'httpstream');

					my $startseek = $1 ? $1 : 0;
					my $endseek = $2 ? $2 : $iteminfo[0]->{DURATION};





					push(@additional_header, 'TimeSeekRange.dlna.org: npt='.PDLNA::Utils::convert_seek_duration($startseek).'-'.PDLNA::Utils::convert_seek_duration($endseek).'/'.PDLNA::Utils::convert_seek_duration($iteminfo[0]->{DURATION}));
					push(@additional_header, 'X-Seek-Range: npt='.PDLNA::Utils::convert_seek_duration($startseek).'-'.PDLNA::Utils::convert_seek_duration($endseek).'/'.PDLNA::Utils::convert_seek_duration($iteminfo[0]->{DURATION}));





					my $command = $CONFIG{'FFMPEG_BIN'}.' -y -ss '.$1.' -i "'.$item[0]->{FULLNAME}.'" -vcodec copy -acodec copy -f avi pipe:';

					my $statuscode = 200;
					#@additional_header = map { /^(Content-Length|Accept-Ranges):/i ? () : $_ } @additional_header; # delete some header
					@additional_header = map { /^(Accept-Ranges):/i ? () : $_ } @additional_header; # delete some header

					open(ITEM, '-|', $command);
					binmode(ITEM);

					print $FH http_header({
						'statuscode' => $statuscode,
						'additional_header' => \@additional_header,
						'log' => 'httpstream',
					});
					my $buf = undef;
					while (sysread(ITEM, $buf, $CONFIG{'BUFFER_SIZE'}))
					{
						PDLNA::Log::log('Adding '.bytes::length($buf).' bytes to Streaming connection.', 3, 'httpstream');
						print $FH $buf or return 1;
					}
					close(ITEM);





				}
				else
				{

















#				if ($CONFIG{'LOW_RESOURCE_MODE'})
#				{
					my $statuscode = 200;
					my ($lowrange, $highrange) = 0;
					if (defined($$CGI{'RANGE'}) && $$CGI{'RANGE'} =~ /^bytes=(\d+)-(\d*)$/)
					{
						PDLNA::Log::log('Delivering content for: '.$item[0]->{FULLNAME}.' with RANGE request.', 1, 'httpstream');
						my $statuscode = 206;

						$lowrange = int($1);
						$highrange = $2 ? int($2) : 0;
						$highrange = $item[0]->{SIZE}-1 if $highrange == 0;
						$highrange = $item[0]->{SIZE}-1 if ($highrange >= $item[0]->{SIZE});

						my $bytes_to_ship = $highrange - $lowrange + 1;

						$additional_header[1] = 'Content-Length: '.$bytes_to_ship; # we need to change the Content-Length
						push(@additional_header, 'Content-Range: bytes '.$lowrange.'-'.$highrange.'/'.$item[0]->{SIZE});
					}

					sysopen(ITEM, $item[0]->{FULLNAME}, O_RDONLY);
					sysseek(ITEM, $lowrange, 0) if $lowrange;

					print $FH http_header({
						'statuscode' => $statuscode,
						'additional_header' => \@additional_header,
						'log' => 'httpstream',
					});
					my $buf = undef;
					while (sysread(ITEM, $buf, $CONFIG{'BUFFER_SIZE'}))
					{
						PDLNA::Log::log('Adding '.bytes::length($buf).' bytes to Streaming connection.', 3, 'httpstream');
						print $FH $buf or return 1;
					}
					close(ITEM);
				}
#				else
#				{
#					my $statuscode = 200;
#					my $command = $CONFIG{'FFMPEG_BIN'}.' -i '.$item[0]->{FULLNAME}.' -acodec copy -f mp3 pipe:';
#					#@additional_header = map { /^(Content-Length|Accept-Ranges):/i ? () : $_ } @additional_header; # delete some header
#					@additional_header = map { /^(Accept-Ranges):/i ? () : $_ } @additional_header; # delete some header
#
#					open(ITEM, '-|', $command);
#					binmode(ITEM);
#
#					print $FH http_header({
#						'statuscode' => $statuscode,
#						'additional_header' => \@additional_header,
#						'log' => 'httpstream',
#					});
#					my $buf = undef;
#					while (sysread(ITEM, $buf, $CONFIG{'BUFFER_SIZE'}))
#					{
#						PDLNA::Log::log('Adding '.bytes::length($buf).' bytes to Streaming connection.', 3, 'httpstream');
#						print $FH $buf or return 1;
#					}
#					close(ITEM);
#				}
#


















				close($FH);
				return;
			}
			elsif ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Interactive') # for immediate rendering of images or playlist files
			{
				PDLNA::Log::log('Delivering (Interactive) content for: '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
				push(@additional_header, 'transferMode.dlna.org: Interactive');

				# Delivering interactive content as a whole
				print $FH http_header({
					'statuscode' => 200,
					'additional_header' => \@additional_header,
				});
				sysopen(FILE, $item[0]->{FULLNAME}, O_RDONLY);
				print $FH <FILE>;
				close(FILE);
				return;
			}
			else # unknown TRANSFERMODE.DLNA.ORG is set
			{
				PDLNA::Log::log('ERROR: Transfermode '.$$CGI{'TRANSFERMODE.DLNA.ORG'}.' for Streaming Items is NOT supported yet.', 0, 'httpstream');
				print $FH http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
				close(FILE);
				return;
			}
		}
		else # no TRANSFERMODE.DLNA.ORG is set
		{
			PDLNA::Log::log('Delivering content information (no Transfermode) for: '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
				'log' => 'httpstream',
			});
			close(FILE);
			return;
		}
	}
	else # unknown HTTP METHOD is set
	{
		PDLNA::Log::log('ERROR: HTTP Method '.$method.' for Streaming Items is NOT supported yet.', 0, 'httpstream');
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
		close(FILE);
		return;
	}
}

sub stream_media
{
	my $content_id = shift;
	my $method = shift;
	my $CGI = shift;
	my $FH = shift;
	my $model_name = shift;
	my $client_ip = shift;
	my $user_agent = shift;

	my $dbh = PDLNA::Database::connect();

	PDLNA::Log::log('ContentID: '.$content_id, 3, 'httpstream');
	if ($content_id =~ /^(\d+)\.(\w+)$/)
	{
		my $id = $1;
		PDLNA::Log::log('ID: '.$id, 3, 'httpstream');

		#
		# getting information from database
		#
		my @item = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT NAME,FULLNAME,PATH,FILE_EXTENSION,SIZE,MIME_TYPE,TYPE,EXTERNAL FROM FILES WHERE ID = ?',
				'parameters' => [ $id, ],
			},
			\@item,
		);

		my @iteminfo = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT CONTAINER, AUDIO_CODEC, VIDEO_CODEC FROM FILEINFO WHERE FILEID_REF = ?;',
				'parameters' => [ $id, ],
			},
			\@iteminfo,
		);

		#
		# check if we need to transcode
		#
		my %media_data = (
			'fullname' => $item[0]->{FULLNAME},
			'external' => $item[0]->{EXTERNAL},
			'media_type' => $item[0]->{TYPE},
			'container' => $iteminfo[0]->{CONTAINER},
			'audio_codec' => $iteminfo[0]->{AUDIO_CODEC},
			'video_codec' => $iteminfo[0]->{VIDEO_CODEC},
		);
		my $transcode = 0;
		if ($transcode = PDLNA::FFmpeg::shall_we_transcode(
				\%media_data,
				{
					'ip' => $client_ip,
					'user_agent' => $user_agent,
				},
			))
		{
			$item[0]->{MIME_TYPE} = $media_data{'mime_type'};
		}

		#
		# sanity checks
		#
		unless (defined($item[0]->{FULLNAME}))
		{
			PDLNA::Log::log('Content with ID '.$id.' NOT found (in media library).', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
			return;
		}

		if (!$item[0]->{EXTERNAL} && !-f $item[0]->{FULLNAME})
		{
			PDLNA::Log::log('Content with ID '.$id.' NOT found (on filesystem): '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
			return;
		}

		if ($item[0]->{EXTERNAL} && !PDLNA::Media::is_supported_stream($item[0]->{FULLNAME}) && !-x $item[0]->{FULLNAME})
		{
			PDLNA::Log::log('Content with ID '.$id.' is a SCRIPT but NOT executable: '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
			print $FH http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
			return;
		}

		#
		# for streaming relevant code starts here
		#

		my @additional_header = ();
		push(@additional_header, 'Content-Type: '.PDLNA::Media::get_mimetype_by_modelname($item[0]->{MIME_TYPE}, $model_name));
		push(@additional_header, 'Content-Length: '.$item[0]->{SIZE}) if !$item[0]->{EXTERNAL};
		push(@additional_header, 'Content-Disposition: attachment; filename="'.$item[0]->{NAME}.'"') if !$item[0]->{EXTERNAL};
		push(@additional_header, 'Accept-Ranges: bytes'); # TODO

		# Streaming of content is NOT working with SAMSUNG without this response header
		if (defined($$CGI{'GETCONTENTFEATURES.DLNA.ORG'}))
		{
			if ($$CGI{'GETCONTENTFEATURES.DLNA.ORG'} == 1)
		{
				push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
			}
			else
			{
				PDLNA::Log::log('Invalid contentFeatures.dlna.org:'.$$CGI{'GETCONTENTFEATURES.DLNA.ORG'}.'.', 1, 'httpstream');
				print $FH http_header({
					'statuscode' => 400,
					'content_type' => 'text/plain',
				});
			}
		}

		# subtitles
		if (defined($$CGI{'GETCAPTIONINFO.SEC'}))
		{
			if ($$CGI{'GETCAPTIONINFO.SEC'} == 1)
			{
				if ($item[0]->{TYPE} eq 'video')
				{
					my @subtitles = ();
					PDLNA::Database::select_db(
						$dbh,
						{
							'query' => 'SELECT ID, TYPE, FULLNAME FROM SUBTITLES WHERE FILEID_REF = ?',
							'parameters' => [ $id, ],
						},
						\@subtitles,
					);
					foreach my $subtitle (@subtitles)
					{
						if ($subtitle->{TYPE} eq 'srt' && -f $subtitle->{FULLNAME})
						{
							push(@additional_header, 'CaptionInfo.sec: http://'.$CONFIG{'LOCAL_IPADDR'}.':'.$CONFIG{'HTTP_PORT'}.'/subtitle/'.$subtitle->{ID}.'.srt');
						}
					}
				}

				unless (grep(/^contentFeatures.dlna.org:/, @additional_header))
				{
					push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
				}
			}
			else
			{
				PDLNA::Log::log('Invalid getCaptionInfo.sec:'.$$CGI{'GETCAPTIONINFO.SEC'}.'.', 1, 'httpstream');
				print $FH http_header({
					'statuscode' => 400,
					'content_type' => 'text/plain',
				});
			}
		}

		# duration
		if (defined($$CGI{'GETMEDIAINFO.SEC'}))
		{
			if ($$CGI{'GETMEDIAINFO.SEC'} == 1)
			{
				if ($item[0]->{TYPE} eq 'video' || $item[0]->{TYPE} eq 'audio')
				{
					my @item_metainfo = ();
					PDLNA::Database::select_db(
						$dbh,
						{
							'query' => 'SELECT DURATION FROM FILEINFO WHERE FILEID_REF = ?',
							'parameters' => [ $id, ],
						},
						\@item_metainfo,
					);
					push(@additional_header, 'MediaInfo.sec: SEC_Duration='.$item_metainfo[0]->{DURATION}.'000;'); # in milliseconds

					unless (grep(/^contentFeatures.dlna.org:/, @additional_header))
					{
						push(@additional_header, 'contentFeatures.dlna.org: '.PDLNA::Media::get_dlnacontentfeatures($item[0], $transcode));
					}
				}
			}
			else
			{
				PDLNA::Log::log('Invalid getMediaInfo.sec:'.$$CGI{'GETMEDIAINFO.SEC'}.'.', 1, 'httpstream');
				print $FH http_header({
					'statuscode' => 400,
					'content_type' => 'text/plain',
				});
			}
		}

		if ($method eq 'HEAD') # handling HEAD requests
		{
			PDLNA::Log::log('Delivering content information (HEAD Request) for: '.$item[0]->{NAME}.'.', 1, 'httpstream');

			print $FH http_header({
				'statuscode' => 200,
				'additional_header' => \@additional_header,
				'log' => 'httpstream',
			});
		}
		elsif ($method eq 'GET') # handling GET requests
		{
			# for clients, which are not sending the Streaming value for the transferMode.dlna.org parameter
			# we set it, because they seem to ignore it
			if (defined($$CGI{'USER-AGENT'}))
			{
				if (
					$$CGI{'USER-AGENT'} =~ /^foobar2000/ || # since foobar2000 is NOT sending any TRANSFERMODE.DLNA.ORG param
					$$CGI{'USER-AGENT'} =~ /^vlc/i || # since vlc is NOT sending any TRANSFERMODE.DLNA.ORG param
					$$CGI{'USER-AGENT'} =~ /^stagefright/ || # since UPnPlay is NOT sending any TRANSFERMODE.DLNA.ORG param
					$$CGI{'USER-AGENT'} =~ /^gvfs/ || # since Totem Movie Player is NOT sending any TRANSFERMODE.DLNA.ORG param
					$$CGI{'USER-AGENT'} =~ /^\(null\)/
					)
				{
					$$CGI{'TRANSFERMODE.DLNA.ORG'} = 'Streaming';
				}
			}

			# transferMode handling
			if (defined($$CGI{'TRANSFERMODE.DLNA.ORG'}))
			{
				if ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Streaming') # for immediate rendering of audio or video content
				{
					push(@additional_header, 'transferMode.dlna.org: Streaming');

					my $statuscode = 200;
					my ($lowrange, $highrange) = 0;
					if (
							defined($$CGI{'RANGE'}) &&						# if RANGE is defined as HTTP header
							$$CGI{'RANGE'} =~ /^bytes=(\d+)-(\d*)$/ &&		# if RANGE looks like
							!$item[0]->{EXTERNAL} &&						# if FILE is not external
							!$transcode										# if TRANSCODING is not required
						)
					{
						PDLNA::Log::log('Delivering content for: '.$item[0]->{FULLNAME}.' with RANGE Request.', 1, 'httpstream');
						my $statuscode = 206;

						$lowrange = int($1);
						$highrange = $2 ? int($2) : 0;
						$highrange = $item[0]->{SIZE}-1 if $highrange == 0;
						$highrange = $item[0]->{SIZE}-1 if ($highrange >= $item[0]->{SIZE});

						my $bytes_to_ship = $highrange - $lowrange + 1;

						$additional_header[1] = 'Content-Length: '.$bytes_to_ship; # we need to change the Content-Length
						push(@additional_header, 'Content-Range: bytes '.$lowrange.'-'.$highrange.'/'.$item[0]->{SIZE});
					}

					#
					# sending the response
					#
					if (!$item[0]->{EXTERNAL} && !$transcode) # file on disk or TRANSFERMODE is NOT required
					{
						sysopen(ITEM, $item[0]->{FULLNAME}, O_RDONLY);
						sysseek(ITEM, $lowrange, 0) if $lowrange;
					}
					else # streams, scripts, or transcoding
					{
						my $command = '';
						if (PDLNA::Media::is_supported_stream($item[0]->{FULLNAME})) # if it is a supported stream
						{
							$command = PDLNA::FFmpeg::get_ffmpeg_stream_command(\%media_data);
						}
						elsif ($transcode) # if TRANSCODING is required
						{
							$command = $media_data{'command'};
						}
						else # if it is a script
						{
							$command = $item[0]->{FULLNAME};
						}

						open(ITEM, '-|', $command);
						binmode(ITEM);
						@additional_header = map { /^(Content-Length|Accept-Ranges):/i ? () : $_ } @additional_header; # delete some header
					}
					print $FH http_header({
						'statuscode' => $statuscode,
						'additional_header' => \@additional_header,
						'log' => 'httpstream',
					});
					my $buf = undef;
					while (sysread(ITEM, $buf, $CONFIG{'BUFFER_SIZE'}))
					{
						PDLNA::Log::log('Adding '.bytes::length($buf).' bytes to Streaming connection.', 3, 'httpstream');
						print $FH $buf or return 1;
					}
					close(ITEM);
					return 1;
				}
				elsif ($$CGI{'TRANSFERMODE.DLNA.ORG'} eq 'Interactive') # for immediate rendering of images or playlist files
				{
					PDLNA::Log::log('Delivering (Interactive) content for: '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
					push(@additional_header, 'transferMode.dlna.org: Interactive');

					# Delivering interactive content as a whole
					print $FH http_header({
						'statuscode' => 200,
						'additional_header' => \@additional_header,
					});
					sysopen(FILE, $item[0]->{FULLNAME}, O_RDONLY);
					print $FH <FILE>;
					close(FILE);
				}
				else # unknown TRANSFERMODE.DLNA.ORG is set
				{
					PDLNA::Log::log('Transfermode '.$$CGI{'TRANSFERMODE.DLNA.ORG'}.' for Streaming Items is NOT supported yet.', 2, 'httpstream');
					print $FH http_header({
						'statuscode' => 501,
						'content_type' => 'text/plain',
					});
				}
			}
			else # no TRANSFERMODE.DLNA.ORG is set
			{
				PDLNA::Log::log('Delivering content information (no Transfermode) for: '.$item[0]->{FULLNAME}.'.', 1, 'httpstream');
				print $FH http_header({
					'statuscode' => 200,
					'additional_header' => \@additional_header,
					'log' => 'httpstream',
				});
			}
		}
		else # not implemented HTTP method
		{
			PDLNA::Log::log('HTTP Method '.$method.' for Streaming Items is NOT supported yet.', 2, 'httpstream');
			print $FH http_header({
				'statuscode' => 501,
				'content_type' => 'text/plain',
				'log' => 'httpstream',
			});
		}
	}
	else
	{
		PDLNA::Log::log('ContentID '.$content_id.' for Streaming Items is NOT supported yet.', 2, 'httpstream');
		print $FH http_header({
			'statuscode' => 501,
			'content_type' => 'text/plain',
			'log' => 'httpstream',
		});
	}
}

sub preview_media
{
	my $content_id = shift;

	if ($content_id =~ /^(\d+)\./)
	{
		my $id = $1;

		my $dbh = PDLNA::Database::connect();
		my @item_info = ();
		PDLNA::Database::select_db(
			$dbh,
			{
				'query' => 'SELECT NAME,FULLNAME,PATH,FILE_EXTENSION,SIZE,MIME_TYPE,TYPE,EXTERNAL FROM FILES WHERE ID = ?',
				'parameters' => [ $id, ],
			},
			\@item_info,
		);
		PDLNA::Database::disconnect($dbh);

		if (defined($item_info[0]->{FULLNAME}))
		{
			unless (-f $item_info[0]->{FULLNAME})
			{
				PDLNA::Log::log('Delivering preview for NON EXISTING Item is NOT supported.', 2, 'httpstream');
				return http_header({
					'statuscode' => 404,
					'content_type' => 'text/plain',
				});
			}

			if ($item_info[0]->{EXTERNAL})
			{
				PDLNA::Log::log('Delivering preview for EXTERNAL Item is NOT supported yet.', 2, 'httpstream');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}

			if ($item_info[0]->{TYPE} eq 'audio')
			{
				PDLNA::Log::log('Delivering preview for Audio Item is NOT supported yet.', 2, 'httpstream');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}

			PDLNA::Log::log('Delivering preview for: '.$item_info[0]->{FULLNAME}.'.', 2, 'httpstream');

			my $randid = '';
			my $path = $item_info[0]->{FULLNAME};
			if ($item_info[0]->{TYPE} eq 'video') # we need to create the thumbnail
			{
				$randid = PDLNA::Utils::get_randid();
				mkdir($CONFIG{'TMP_DIR'}.'/'.$randid);
				my $thumbnail_path = $CONFIG{'TMP_DIR'}.'/'.$randid.'/thumbnail.jpg';
				system($CONFIG{'FFMPEG_BIN'}.' -y -ss 20 -i "'.$path.'" -vcodec mjpeg -vframes 1 -an -f rawvideo "'.$thumbnail_path.'" > /dev/null 2>&1');

				$path = $thumbnail_path;
				unless (-f $path)
				{
					PDLNA::Log::log('ERROR: Unable to create image for Item Preview.', 0, 'httpstream');
					return http_header({
						'statuscode' => 404,
						'content_type' => 'text/plain',
					});
				}
			}

			# image scaling stuff
			GD::Image->trueColor(1);
			my $image = GD::Image->new($path);
			unless ($image)
			{
				PDLNA::Log::log('ERROR: Unable to create GD::Image object for Item Preview.', 0, 'httpstream');
				return http_header({
					'statuscode' => 501,
					'content_type' => 'text/plain',
				});
			}
			my $height = $image->height / ($image->width/160);
			my $preview = GD::Image->new(160, $height);
			$preview->copyResampled($image, 0, 0, 0, 0, 160, $height, $image->width, $image->height);

			# remove tmp files from thumbnail generation
			if ($item_info[0]->{TYPE} eq 'video')
			{
				unlink($path);
				rmdir("$CONFIG{'TMP_DIR'}/$randid");
			}

			# the response itself
			my $response = http_header({
				'statuscode' => 200,
				'content_type' => 'image/jpeg',
			});
			$response .= $preview->jpeg();
			$response .= "\r\n";

			return $response;
		}
		else
		{
			PDLNA::Log::log('ContentID '.$id.' NOT found.', 2, 'httpstream');
			return http_header({
				'statuscode' => 404,
				'content_type' => 'text/plain',
			});
		}
	}
	else
	{
		PDLNA::Log::log('ContentID '.$content_id.' for Item Preview is NOT supported yet.', 2, 'httpstream');
		return http_header({
			'statuscode' => 404,
			'content_type' => 'text/plain',
		});
	}
}

sub logo
{
	my ($size, $type) = split('/', shift);
	$type = lc($1) if ($type =~ /\.(\w{3,4})$/);

	my $response = '';
	if ($type =~ /^(jpeg|png)$/)
	{
		PDLNA::Log::log('Delivering Logo in format '.$type.' and with '.$size.'x'.$size.' pixels.', 2, 'httpgeneric');

		GD::Image->trueColor(1);
		my $image = GD::Image->new('PDLNA/pDLNA.png');
		my $preview = GD::Image->new($size, $size);

		# all black areas of the image should be transparent
		my $black = $preview->colorAllocate(0,0,0);
		$preview->transparent($black);

		$preview->copyResampled($image, 0, 0, 0, 0, $size, $size, $image->width, $image->height);

		my @additional_header = ();
		$additional_header[0] = 'Content-Type: image/jpeg' if ($type eq 'jpeg');
		$additional_header[0] = 'Content-Type: image/png' if ($type eq 'png');

		$response = http_header({
			'statuscode' => 200,
			'additional_header' => \@additional_header,
		});
		$response .= $preview->jpeg() if ($type eq 'jpeg');
		$response .= $preview->png() if ($type eq 'png');
		$response .= "\r\n";
	}
	else
	{
		PDLNA::Log::log('Unknown Logo format '.$type.'.', 2, 'httpgeneric');
		$response = http_header({
			'statuscode' => 404,
			'content_type' => 'text/plain',
		});
	}

	return $response;
}

1;
