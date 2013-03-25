package Gallery::Controller;
use Mojo::Base 'Mojolicious::Controller';

use Mojolicious::Static;
use Mojo::Util;

use Data::Dumper;
use List::Util 'shuffle';

use Gallery;

sub route {
	my ($self) = @_;

	my %target = $self->split_path();

	return $self->rendered() if $self->handle_direct_image_request(%target);

	my $basepath = ($target{album} ? "/$target{album}/" : "/"); # watch out for site root
	my @parent_links = $self->generate_parent_links('/', %target);
	if ($target{image}) {
		return $self->render_image_page(\%target, $basepath, \@parent_links);
	} else {
		return $self->render_album_page(\%target, $basepath, \@parent_links);
	}
}

sub split_path {
	my ($self) = @_;

	my $path = $self->stash('path');
	my @parts = split('/', $path);
	my $image;
	$image = pop(@parts) if @parts && $parts[-1] =~ /\./;

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

	if ($target{raw}) {
		Gallery::cache_raw_image(%target);
		return $self->app->static->serve_asset(
			$self,
			$self->app->static->file(".originals/$target{album}/$target{image}"),
		);
	} elsif ($target{scaled}) {
		my $new_name = Gallery::cache_scaled_image(%target);
		return $self->app->static->serve_asset(
			$self,
			$self->app->static->file("$target{album}/$new_name"),
		);
	} elsif ($target{thumb}) {
		my $new_name = Gallery::cache_thumb_image(%target);
		return $self->app->static->serve_asset(
			$self,
			$self->app->static->file("$target{album}/$new_name"),
		);
	}
	return undef;
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
	my %target = %$target;
	my @parent_links = @$parent_links;

	my $album_dir = "$Gallery::albums_dir/$target{album}";
	opendir(my $dh, $album_dir) or die "unable to list $album_dir: $!";
	my @files = sort(grep { !/^\./ && -f "$album_dir/$_" } readdir $dh);
	closedir $dh;

	my ($prev, $next, $found_it);
	foreach my $each (@files) {
		if ($found_it) {
			$next = $each;
			last;
		} elsif ($each eq $target{image}) {
			$found_it = 1;
		} else {
			$prev = $each;
		}
	}
	$prev = "$basepath$prev" if $prev;
	$next = "$basepath$next" if $next;

	return $self->render(
		template => 'pages/image',
		image => {
			scaled => url_escape("$basepath$target{image}?scaled=1"),
			link => url_escape("$basepath$target{image}?raw=1"),
			name => $target{image},
		},
		name => $target{image},
		title => "$Gallery::site_title | $target{album} | $target{image}",
		parent_links => \@parent_links,
		prev => ($prev ? url_escape($prev) : undef),
		next => ($next ? url_escape($next) : undef),
	);
}


sub render_album_page {
	my ($self, $target, $basepath, $parent_links) = @_;
	my %target = %$target;
	my @parent_links = @$parent_links;

	my (@subalbums, @images);
	my $album_dir = "$Gallery::albums_dir/$target{album}";
	opendir(my $dh, $album_dir) or die "unable to list $album_dir: $!";
	while (my $entry = readdir $dh) {
		next if $entry =~ /^\./;
		if (-d "$album_dir/$entry") {
			if (my $highlight = $self->pick_subalbum_highlight("$album_dir/$entry")) {
				push(@subalbums, {
					thumb => url_escape("$basepath$entry/$highlight?thumb=1"),
					link => url_escape("$basepath$entry/"),
					name => $entry,
				});
			}
		} else {
			push(@images, {
				thumb => url_escape("$basepath$entry?thumb=1"),
				link => url_escape("$basepath$entry"),
				name => $entry,
			});
		}
	}
	closedir $dh;

	@subalbums = sort { $a->{name} cmp $b->{name} } @subalbums;
	@images = sort { $a->{name} cmp $b->{name} } @images;
	pop(@parent_links) if @parent_links; # don't include the current album
	my @albums = split(/\//, $target{album});
	my $name = (@albums ? pop(@albums) : undef);

	return $self->render(
		template => 'pages/album',
		subalbums => \@subalbums,
		images => \@images,
		name => $name,
		title => "$Gallery::site_title | $target{album}",
		parent_links => \@parent_links,
	);
}


sub pick_subalbum_highlight {
	my ($self, $subalbum) = @_;

	opendir(my $dh, $subalbum) or die "unable to list $subalbum: $!";
	my @entries = shuffle(grep { !/^\./ } readdir $dh);
	closedir $dh;
	die "dir has no contents: $subalbum" unless @entries;

	foreach my $entry (@entries) {
		return $entry if -f "$subalbum/$entry";

		if (-d "$subalbum/$entry") {
			my $highlight = $self->pick_subalbum_highlight("$subalbum/$entry");
			return "$entry/$highlight" if $highlight;
		}
	}

	return undef;
}

sub url_escape {
	return Mojo::Util::url_escape(@_, '^A-Za-z0-9\-._~\/\?\=');
}

1;
