package Gallery::Controller;
use Mojo::Base 'Mojolicious::Controller';

use Mojolicious::Static;

use Gallery qw(cache_image_as_needed find_prev_and_next load_album url_escape $config);
use JSONFeed qw(json_feed);


sub route {
	my ($self) = @_;

	my %target = $self->split_path();

	my $basepath = ($target{album} ? "/$target{album}/" : "/"); # watch out for site root

	if ($self->handle_direct_image_request(%target) || $self->handle_feed_request(\%target, $basepath)) {
		return $self->rendered()
	}

	my @parent_links = $self->generate_parent_links('/', %target);
	if ($target{image}) {
		return $self->render_image_page(\%target, $basepath, \@parent_links);
	} else {
		return $self->render_album_page(\%target, $basepath, \@parent_links);
	}
}

sub split_path {
	my ($self) = @_;

	my $path = $self->stash('totally_not_path');
	my @parts = split('/', $path);
	my $image;
	$image = pop(@parts) if @parts && $parts[-1] =~ /\./ && $path !~ /\/$/;

	return (
		album => join('/', @parts),
		image => $image,
		raw => scalar $self->param('raw'),
		scaled => scalar $self->param('scaled'),
		thumb => scalar $self->param('thumb'),
	);
}

sub handle_direct_image_request {
	my ($self, %target) = @_;

	if (my $image = cache_image_as_needed(%target)) {
		return $self->serve_static($image);
	}
}

sub handle_feed_request {
	my ($self, $target, $basepath) = @_;

	if (my $feed = json_feed($target, $basepath)) {
		return $self->render(text => $feed, format => 'json');
	}
}

sub serve_static {
	my ($self, $path) = @_;

	return unless $path;

	my $static = $self->app->static;
	return $static->serve($self, $path);
}

sub generate_parent_links {
	my ($self, $basepath, %target) = @_;

	my @links;
	foreach my $ancestor (split(/\//, $target{album})) {
		push(@links, {
			name => $ancestor,
			link => url_escape("$basepath$ancestor/"),
		});
		$basepath = "$basepath$ancestor/";
	}
	return @links;
}

sub render_image_page {
	my ($self, $target, $basepath, $parent_links) = @_;

	my ($prev, $next) = find_prev_and_next($target, $basepath);

	return $self->render(
		template => 'pages/image',
		image => {
			scaled => url_escape("$basepath$target->{image}?scaled=1"),
			link => url_escape("$basepath$target->{image}?raw=1"),
		},
		name => '',
		title => "$config->{site_title} | $target->{album}",
		parent_links => $parent_links,
		prev => ($prev ? url_escape($prev) : undef),
		next => ($next ? url_escape($next) : undef),
		feed_url => '',
	);
}

sub render_album_page {
	my ($self, $target, $basepath, $parent_links) = @_;

	my ($subalbums, $images) = load_album($target, $basepath);

	pop(@$parent_links) if @$parent_links; # don't include the current album
	my @albums = split(/\//, $target->{album});
	my $name = (@albums ? pop(@albums) : undef);

	my $req_url = $self->req->url->to_abs;

	return $self->render(
		template => 'pages/album',
		subalbums => $subalbums,
		images => $images,
		name => $name,
		title => $config->{site_title} . ($target->{album} ? " | $target->{album}" : ""),
		parent_links => $parent_links,
		feed_url => $req_url->base . $req_url->path . 'feed.json',
	);
}

1;
