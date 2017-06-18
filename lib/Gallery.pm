package Gallery;
use Mojo::Base 'Mojolicious';

use File::Basename;
use File::Path 'make_path';
use IO::Handle;
use List::Util 'min';
use Image::Imlib2;
use Image::JpegTran::AutoRotate;


our $site_title = 'Old rainskit.com gallery';
our $albums_dir = '/srv/http/rainskit.com/gallery/albums';
our $highlight_filename =  '#highlight';
my $cache_dir = '/srv/http/rainskit.com/gallery/cache';
our $rotated_dir = '.rotated';
# These are "landscape" not because we assume all pictures are landscape,
# but because we assume most monitors are landscape. That's probably not
# accurate in today's mobile world, though.
my $scaled_width = 800;
my $scaled_height = 600;
our $thumb_width = 150;
our $thumb_height = 150;
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

sub rotate_and_cache_raw_image {
	my (%target) = @_;

	my $cur_path = "$albums_dir/$target{album}/$target{image}";
	my $dest_dir = "$cache_dir/$rotated_dir/$target{album}";
	make_path($dest_dir);
	my $new_path = "$dest_dir/$target{image}";

	if (! -e $new_path) {
		# auto_rotate() has tricky return codes;
		# 1 means success; -1 means doesn't need rotated; undef means error
		# since -1 evaluates to true, we can't just `if (auto_rotate())`
		my $result = auto_rotate($cur_path => $new_path);
		unless (defined $result && $result > 0) {
			symlink($cur_path, $new_path);
		}
	}

	return $target{image};
}

sub cache_scaled_image {
	my (%target) = @_;

	$target{image} = rotate_and_cache_raw_image(%target);

	my ($name, $path, $extension) = fileparse($target{image}, qr/\.[^.]*/);
	return resize_image(
		"$cache_dir/$rotated_dir/$target{album}", $name, $extension,
		$scaled_width, $scaled_height, 0,
		"$cache_dir/$target{album}",
	);
}

sub cache_thumb_image {
	my (%target) = @_;

	$target{image} = rotate_and_cache_raw_image(%target);

	my ($name, $path, $extension) = fileparse($target{image}, qr/\.[^.]*/);
	return resize_image(
		"$cache_dir/$rotated_dir/$target{album}", $name, $extension,
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

	my $image = Image::Imlib2->load($cur_path);
	my $width  = $image->width();
	my $height = $image->height();

	if ($square) {
		my $size = min($width, $height);
		if ($size > $max_width && $size > $max_height) {
			$image = $image->crop(($width - $size) / 2, ($height - $size) / 2, $size, $size);
		} else {
			my $cropped_width = min($width, $max_width);
			my $cropped_height = min($height, $max_height);
			$image = $image->crop(($width - $cropped_width) / 2, ($height - $cropped_height) / 2, $cropped_width, $cropped_height);
		}
		$width = $height = $size;
	}

	my ($width_factor, $height_factor) = (1, 1);
	$width_factor = $max_width / $width if $width > $max_width;
	$height_factor = $max_height / $height if $height > $max_height;
	my $scale_factor = min($width_factor, $height_factor);

	if ($scale_factor < 1) {
		$image = $image->create_scaled_image($width * $scale_factor, $height * $scale_factor);

		make_path($dest_dir);
		$image->save($new_path);
	} elsif ($square) {
		# we hit this case if the image is to be squared and just one dimension
		# was smaller than the square size, so we still need to crop the other
		# dimension (which was done above, but now we need to save it)
		make_path($dest_dir);
		$image->save($new_path);
	} else {
		symlink($cur_path, $new_path);
	}

	return $new_name;
}


1;
