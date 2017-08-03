package JSONFeed;

use JSON;
use POSIX 'strftime';
use File::stat;

use Gallery qw(load_album $config);

#my $JSON_FEED_FILE = 'feed.json';

use Exporter 'import';
our @EXPORT_OK = qw(cache_feed_as_needed);

sub cache_feed_as_needed {
	my ($target, $basepath) = @_;

	return if $target->{image};

	return update_json_feed($target, $basepath) if $target->{feed} eq 'json';

	return;
}

sub update_json_feed {
	my ($target, $basepath) = @_;

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
		my $item_file = "$config->{albums_dir}/$target->{album}/$_->{name}";

		{
			id => $_->{link},
			url => $full_url,
			content_html => qq{<img src="$thumb_url" />},
			image => $thumb_url,
			date_modified => rfc3339_date(stat($item_file)->mtime),
		};
	} @items;
	$feed->{items} = \@items;

	my $json_feed = encode_json($feed);

	return $json_feed;

	# my $work_dir = "$config->{cache_dir}/$target->{album}";
	# my $feed_file = "$work_dir/$JSON_FEED_FILE";
	# my $fh;
	# open($fh, '>', $feed_file) or die "unable to open $feed_file: $!";
	# print { $fh } $json_feed or die "unable to write to $feed_file: $!";
	# close $fh or die "unable to close $feed_file: $!";

	# return "$target->{album}/$JSON_FEED_FILE";
}

# based on https://unix.stackexchange.com/a/120490/223285
sub rfc3339_date {
	my ($timestamp) = @_;

	my $date_string = strftime("%Y-%m-%dT%T%z", localtime($timestamp));
	$date_string =~ s/(..)$/:\1/;
	return $date_string;
}

1;

