package Gallery;
use Mojo::Base 'Mojolicious';

use File::Basename;
use File::Path 'make_path';
use IO::Handle;
use List::Util 'min';
use Image::Imlib2;
use Image::JpegTran::AutoRotate;

use Exporter 'import';
our @EXPORT_OK = qw(cache_image_as_needed exifdate $config);

our $config;

sub startup {
	my ($self) = @_;

	STDOUT->autoflush(1);
	STDERR->autoflush(1);

	$config = $self->app->plugin('Config' => { default => {
				site_title => 'YOUR SITE TITLE',

				albums_dir => '/path/to/your/original/images',
				highlight_filename => '#highlight',
				sort_images_by => 'name',

				cache_dir => '/path/to/a/cache/dir',
				rotated_dir => '.rotated',

				scaled_width => 800,
				scaled_height => 600,

				thumb_width => 150,
				thumb_height => 150,
				thumb_square => 1,
			} });

	my $static = $self->app->static;
	push(@{$static->paths}, $config->{cache_dir});

	my $router = $self->routes;
	$router->get('/')->to('controller#route', path => '');
	$router->get('/*path')->to('controller#route');
}

sub cache_image_as_needed {
	my (%target) = @_;

	my $cur_path = "$config->{albums_dir}/$target{album}/$target{image}";
	return undef unless -f $cur_path;

	rotate_and_cache_raw_image(%target);

	my $new_name;
	my $path_prefix = '';
	if ($target{raw}) {
		$new_name = $target{image};
		$path_prefix = "$config->{rotated_dir}/";
	} elsif ($target{scaled}) {
		$new_name = cache_scaled_image(%target);
	} elsif ($target{thumb}) {
		$new_name = cache_thumb_image(%target);
	} else {
		# not a direct image request
		return undef;
	}

	return "$path_prefix$target{album}/$new_name";
}

sub rotate_and_cache_raw_image {
	my (%target) = @_;

	my $cur_path = "$config->{albums_dir}/$target{album}/$target{image}";
	my $dest_dir = "$config->{cache_dir}/$config->{rotated_dir}/$target{album}";
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
}

sub cache_scaled_image {
	my (%target) = @_;

	my ($name, $path, $extension) = fileparse($target{image}, qr/\.[^.]*/);
	return resize_image(
		"$config->{cache_dir}/$config->{rotated_dir}/$target{album}", $name, $extension,
		$config->{scaled_width}, $config->{scaled_height}, 0,
		"$config->{cache_dir}/$target{album}",
	);
}

sub cache_thumb_image {
	my (%target) = @_;

	my ($name, $path, $extension) = fileparse($target{image}, qr/\.[^.]*/);
	return resize_image(
		"$config->{cache_dir}/$config->{rotated_dir}/$target{album}", $name, $extension,
		$config->{thumb_width}, $config->{thumb_height}, $config->{thumb_square},
		"$config->{cache_dir}/$target{album}",
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

sub exifdate {
	my ($image_path) = @_;

	return 'unused' unless 'date' eq $config->{sort_images_by};

	eval q{use Image::ExifTool}; die "$@" if $@;
	eval q{use Date::Parse}; die "$@" if $@;

	my $exiftool = Image::ExifTool->new();
	$exiftool->ExtractInfo($image_path, {})
		or die "couldn't extract info for $image_path: $!";
	my $date = $exiftool->GetValue('DateTimeOriginal', 'ValueConv');
	$date = $exiftool->GetValue('FileModifyDate', 'ValueConv')
		unless defined $date;
	$date = (stat $image_path)[9]
		unless defined $date;

	return str2time($date);
}

1;
