package Gallery;
use Mojo::Base 'Mojolicious';

use File::Basename;
use File::Path 'make_path';
use IO::Handle;
use List::Util 'min';

our $albums_dir = '/home/truist/sites/rainskit.com/gallery/content/albums';
my $cache_dir = '/home/truist/devel/gallery/cache';
my $scaled_width = 800;
my $scaled_height = 600;
my $thumb_width = 150;
my $thumb_height = 150;
my $thumb_square = 1;

sub startup {
	my ($self) = @_;

	STDOUT->autoflush(1);
	STDERR->autoflush(1);

	my $static = $self->app->static;
	push(@{$static->paths}, $cache_dir);

	my $router = $self->routes;
	$router->get('/')->to('controller#route', path => '');
	$router->get('/*path')->to('controller#route');
}

sub cache_raw_image {
	my (%target) = @_;

	my $cur_path = "$albums_dir/$target{album}/$target{image}";
	my $dest_dir = "$cache_dir/.originals/$target{album}";
	make_path($dest_dir);
	my $new_path = "$dest_dir/$target{image}";
	symlink($cur_path, $new_path) unless -e $new_path;
}

sub cache_scaled_image {
	my (%target) = @_;

	my ($name, $path, $extension) = fileparse($target{image}, qr/\.[^.]*/);
	return resize_image(
		"$albums_dir/$target{album}", $name, $extension,
		$scaled_width, $scaled_height, 0,
		"$cache_dir/$target{album}",
	);
}

sub cache_thumb_image {
	my (%target) = @_;

	my ($name, $path, $extension) = fileparse($target{image}, qr/\.[^.]*/);
	return resize_image(
		"$albums_dir/$target{album}", $name, $extension,
		$thumb_width, $thumb_height, $thumb_square,
		"$cache_dir/$target{album}",
	);
}

sub resize_image {
	my ($source_dir, $name, $extension, $max_width, $max_height, $square, $dest_dir) = @_;

	my $cur_path = "$source_dir/$name$extension";

	my $new_name = "$name--${max_width}x$max_height" . ($square ? '-square' : '') . "$extension";
	my $new_path = "$dest_dir/$new_name";
	return $new_name if -e $new_path;

	my $image = Image::Magick->new();
	my $error = $image->Read($cur_path);
	STDERR->print("error reading $cur_path: $error\n") if $error;
	return if $error;

	my ($width, $height) = $image->Get('width', 'height');
	if ($square) {
		my $size = min($width, $height);
STDOUT->print("ABOUT TO CROP $cur_path\n");
		$error = $image->Crop(
			x => ($width - $size) / 2,
			y => ($height - $size) / 2,
			width => $size,
			height => $size,
		);
		STDERR->print("error cropping image: $error") if $error;
		return if $error;
		$width = $height = $size;
	}

	my ($width_factor, $height_factor) = (1, 1);
	$width_factor = $max_width / $width if $width > $max_width;
	$height_factor = $max_height / $height if $height > $max_height;
	my $scale_factor = min($width_factor, $height_factor);

	if ($scale_factor < 1) {
STDOUT->print("ABOUT TO SCALE $cur_path\n");
		$error = $image->Scale(
			width => $width * $scale_factor,
			height => $height * $scale_factor,
		);
		STDERR->print("error resizing image: $error") if "$error";
		return if $error;

		make_path($dest_dir);
		$error = $image->Write($new_path);
		STDERR->print("error writing image: $error") if "$error";
		return if $error;
	} else {
		symlink($cur_path, $new_path);
	}

	return $new_name;
}


1;
