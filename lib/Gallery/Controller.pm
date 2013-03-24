package Gallery::Controller;
use Mojo::Base 'Mojolicious::Controller';

use Mojolicious::Static;

use Image::Magick;
use Data::Dumper;
use List::Util 'shuffle';

use Gallery;

sub route {
	my ($self) = @_;

	my %target = $self->split_path();

	if ($target{raw}) {
		Gallery::cache_raw_image(%target);
		return $self->rendered() if $self->app->static->serve_asset(
			$self,
			$self->app->static->file(".originals/$target{album}/$target{image}"),
		);
	} elsif ($target{scaled}) {
		my $new_name = Gallery::cache_scaled_image(%target);
		return $self->rendered() if $self->app->static->serve_asset(
			$self,
			$self->app->static->file("$target{album}/$new_name"),
		);
	} elsif ($target{thumb}) {
		my $new_name = Gallery::cache_thumb_image(%target);
		return $self->rendered() if $self->app->static->serve_asset(
			$self,
			$self->app->static->file("$target{album}/$new_name"),
		);
	}

	if ($target{image}) {
		return $self->render(
			template => 'pages/image',
			path => "/$target{album}/$target{image}?scaled=1",
			name => $target{image},
		);
	} else {
		my (@subalbums, @images);
		my $album_dir = "$Gallery::albums_dir/$target{album}";
		opendir(my $dh, $album_dir) or die "unable to list $album_dir: $!";
		while (my $entry = readdir $dh) {
			next if $entry =~ /^\./;
			if (-d "$album_dir/$entry") {
				if (my $highlight = $self->pick_subalbum_highlight("$album_dir/$entry")) {
					push(@subalbums, ["/$target{album}/$entry/$highlight?thumb=1" => "/$target{album}/$entry/"]);
				}
			} else {
				push(@images, ["/$target{album}/$entry?thumb=1" => "/$target{album}/$entry"]);
			}
		}
		closedir $dh;
		@subalbums = sort { $a->[0] cmp $b->[0] } @subalbums;
		@images = sort { $a->[0] cmp $b->[0] } @images;
		return $self->render(
			template => 'pages/album',
			subalbums => \@subalbums,
			images => \@images,
		);
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

1;
