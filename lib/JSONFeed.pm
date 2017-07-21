package JSONFeed;

use JSON;

use Gallery qw(load_album $config);

use Exporter 'import';
our @EXPORT_OK = qw(cache_feed_as_needed);

my $FEED_FILE = 'feed.json';

sub cache_feed_as_needed {
	my ($target, $basepath) = @_;

	return if $target->{image};
	return unless $target->{feed} eq 'json';

	my $album_url = "$config->{site_base_url}/$target->{album}";
	my $feed = {
		version => 'https://jsonfeed.org/version/1',
		title => $config->{site_title},
		home_page_url => $album_url,
		feed_url => "$album_url?feed=json",
	};

	my ($subalbums, $images) = load_album($target, $basepath);
	my @items = (@$subalbums, @$images);
	@items = map {
		my $full_url = $config->{site_base_url} . $_->{link};
		my $thumb_url = $config->{site_base_url} . $_->{thumb};
		{
			id => $_->{link},
			url => $full_url,
			content_html => qq{<img src="$thumb_url" />},
			image => $thumb_url,
		};
	} @items;
	$feed->{items} = \@items;

	my $json_feed = encode_json($feed);

	my $work_dir = "$config->{cache_dir}/$target->{album}";
	my $feed_file = "$work_dir/$FEED_FILE";
	my $fh;
	open($fh, '>', $feed_file) or die "unable to open $feed_file: $!";
	print { $fh } $json_feed or die "unable to write to $feed_file: $!";
	close $fh or die "unable to close $feed_file: $!";

	return "$target->{album}/$FEED_FILE";
}

1;

