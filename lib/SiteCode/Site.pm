package SiteCode::Site;

use Typed;
# use Moose;
# use namespace::autoclean;

use SiteCode::DBX;

sub config
{
    my $dbx = SiteCode::DBX->new();

    my @site = $dbx->array(qq(
        SELECT 
            site_key, site_value 
        FROM 
            site_key, site_value 
        WHERE site_key.id = site_value.site_key_id
    ));

    my %site;

    foreach my $item (@{ $site[0] }) {
        my $site_key = ${ $item }{site_key};
        my $site_value = ${ $item }{site_value};

        $site{$site_key} = $site_value;
    }

    return(\%site);
}

# __PACKAGE__->meta->make_immutable;

1;
