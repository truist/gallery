package JSONFeed;

use JSON;
use POSIX 'strftime';
use File::stat;

use Gallery qw(load_album $config);

use Exporter 'import';
our @EXPORT_OK = qw(json_feed);

sub json_feed {
	my ($target, $basepath) = @_;

	return unless $target->{image} eq 'feed.json';

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

	return encode_json($feed);
}

# based on https://unix.stackexchange.com/a/120490/223285
sub rfc3339_date {
	my ($timestamp) = @_;

	my $date_string = strftime("%Y-%m-%dT%T%z", localtime($timestamp));
	$date_string =~ s/(..)$/:\1/;
	return $date_string;
}

1;

