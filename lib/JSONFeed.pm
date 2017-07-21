package JSONFeed;

use JSON;

use Gallery qw($config);

use Exporter 'import';
our @EXPORT_OK = qw(cache_feed_as_needed);

sub cache_feed_as_needed {
	my (%target) = @_;

	return unless $target{feed} eq 'json';

	my $feed = {
		version => 'https://jsonfeed.org/version/1',
		title => $config->{site_title},
	};

	my @items;

	print STDERR "JSON: " . encode_json($feed) . "\n";

	return undef;
}


1;

