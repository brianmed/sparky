package SiteCode::Modern;

use strict;
use warnings;
use utf8;
use feature qw(:5.10);

use parent qw(Exporter);

# enable methods on filehandles; unnecessary when 5.14 autoloads them
use IO::File qw();
use IO::Handle qw();

sub import {
    strict->import;
    warnings->import;
    utf8->import;
    feature->import(':5.10');
}

1;
