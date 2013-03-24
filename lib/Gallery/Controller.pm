package Gallery::Controller;
use Mojo::Base 'Mojolicious::Controller';

use Mojolicious::Static;

use Image::Magick;
use Data::Dumper;

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
	}

	if ($target{image}) {
		return $self->render(
			template => 'pages/image',
			path => "/$target{album}/$target{image}?scaled=1",
			name => $target{image},
		);
	} else {
		my @subalbums, @images;
		my $album_dir = "$Gallery::albums_dir/$target{album}";
		opendir(my $dh, $album_dir) or die "unable to list $album_dir: $!";
		while (my $entry = readdir $dh) {
			next if $entry =~ /^\./;
			if (-d "$album_dir/$entry") {
				if (my $thumb = $self->pick_subalbum_thumb($album_dir, $entry)) {
					push(@subalbums, {$thumb => "/$target{album}/$entry/"});
				}
			} else {
				push(@images, {"/$target{album}/$entry?thumb=1" => "/$target{album}/$entry"});
			}
		}
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
	);
}

1;
