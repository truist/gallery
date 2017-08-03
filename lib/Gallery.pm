package Gallery;
use Mojo::Base 'Mojolicious';

use File::Basename;
use File::Path 'make_path';
use File::stat;
use File::Copy;
use IO::Handle;
use Image::Imlib2;
use Image::JpegTran::AutoRotate;
use List::Util qw{min shuffle first};
use Mojo::Util;

my $ORIGINAL = 'original';

use Exporter 'import';
our @EXPORT_OK = qw(cache_image_as_needed exifdate find_prev_and_next load_album url_escape $config);

our $config;

my $highlight_regex;

sub startup {
	my ($self) = @_;

	STDOUT->autoflush(1);
	STDERR->autoflush(1);

	$config = $self->app->plugin('Config' => { default => {
				site_base_url => 'https://gallery.example.com',
				site_title => 'YOUR SITE TITLE',

				albums_dir => '/path/to/your/original/images',
				highlight_filename => '#highlight',
				sort_images_by => 'name',

				cache_dir => '/path/to/a/cache/dir',

				scaled_width => 800,
				scaled_height => 600,

				thumb_width => 150,
				thumb_height => 150,
				thumb_square => 1,
			} });

	my $static = $self->app->static;
	push(@{$static->paths}, $config->{cache_dir});

	$self->app->types->type(json => 'application/json');

	my $router = $self->routes;
	$router->get('/')->to('controller#route', path => '');
	$router->get('/*path')->to('controller#route');

	$highlight_regex = qr{^\Q$config->{highlight_filename}\E$};
}

sub load_album {
	my ($target, $basepath) = @_;
	my %target = %$target;

	my (@subalbums, @images);
	my $album_dir = "$config->{albums_dir}/$target{album}";
	opendir(my $dh, $album_dir) or die "unable to list $album_dir: $!";
	while (my $entry = readdir $dh) {
		next if $entry =~ /^\./;
		next if $entry =~ /$highlight_regex/;
		if (-d "$album_dir/$entry") {
			if (my $highlight = pick_subalbum_highlight("$album_dir/$entry")) {
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
				date => exifdate("$album_dir/$entry"), # note that `exifdate` returns 'unused' unless date sort is enabled
			});
		}
	}
	closedir $dh;

	@subalbums = sort { $a->{name} cmp $b->{name} } @subalbums;
	@images = sort { $a->{$config->{sort_images_by}} cmp $b->{$config->{sort_images_by}} } @images;

	return (\@subalbums, \@images);
}

sub pick_subalbum_highlight {
	my ($subalbum) = @_;

	opendir(my $dh, $subalbum) or die "unable to list $subalbum: $!";
	my @entries = grep { !/^\./ } readdir $dh;
	closedir $dh;
	die "dir has no contents: $subalbum" unless @entries;

	my $highlight = first { /$highlight_regex/ } @entries;
	if ($highlight && -l "$subalbum/$highlight") {
		$highlight = readlink("$subalbum/$highlight");
		return $highlight if -f "$subalbum/$highlight";
		if (-d "$subalbum/$highlight") {
			my $deeper_highlight = pick_subalbum_highlight("$subalbum/$highlight");
			return "$highlight/$deeper_highlight" if $deeper_highlight;
		}
	}

	@entries = shuffle(@entries);

	foreach my $entry (@entries) {
		return $entry if -f "$subalbum/$entry";

		if (-d "$subalbum/$entry") {
			my $highlight = pick_subalbum_highlight("$subalbum/$entry");
			return "$entry/$highlight" if $highlight;
		}
	}

	return undef;
}

sub find_prev_and_next {
	my ($target, $basepath) = @_;
	my %target = %$target;

	my $album_dir = "$config->{albums_dir}/$target{album}";
	opendir(my $dh, $album_dir) or die "unable to list $album_dir: $!";
	my @files = grep { !/^\./ && !/$highlight_regex/ && -f "$album_dir/$_" } readdir $dh;
	closedir $dh;

	@files = map { {
		name => $_,
		date => exifdate("$album_dir/$_"), # note that `exifdate` returns 'unused' unless date sort is enabled
	} } @files;
	@files = sort { $a->{$config->{sort_images_by}} cmp $b->{$config->{sort_images_by}} } @files;

	my ($prev, $next, $found_it);
	foreach my $each (@files) {
		if ($found_it) {
			$next = $each->{name};
			last;
		} elsif ($each->{name} eq $target{image}) {
			$found_it = 1;
		} else {
			$prev = $each->{name};
		}
	}
	$prev = "$basepath$prev" if $prev;
	$next = "$basepath$next" if $next;

	return ($prev, $next);
}

sub cache_image_as_needed {
	my (%target) = @_;

	return unless $target{image};
	my $original_path = "$config->{albums_dir}/$target{album}/$target{image}";
	return unless -f $original_path;

	my $image_cache_dir = "$config->{cache_dir}/$target{album}/$target{image}";
	make_path($image_cache_dir);

	my $rotated_path = "$image_cache_dir/$ORIGINAL";
	rotate_and_cache_raw_image($original_path, $rotated_path);

	my $final_name;
	if ($target{raw}) {
		$final_name = $ORIGINAL;
	} elsif ($target{scaled}) {
		$final_name = resize_image(
			$image_cache_dir, $ORIGINAL,
			$config->{scaled_width}, $config->{scaled_height}, 0,
		);
	} elsif ($target{thumb}) {
		$final_name = resize_image(
			$image_cache_dir, $ORIGINAL,
			$config->{thumb_width}, $config->{thumb_height}, $config->{thumb_square},
		);
	} else {
		# not a direct image request
		return;
	}

	return "$target{album}/$target{image}/$final_name";
}

sub rotate_and_cache_raw_image {
	my ($cur_path, $new_path) = @_;

	if (enforce_cache_is_newer($cur_path, $new_path, 0)) {
		# auto_rotate() has tricky return codes;
		# 1 means success; -1 means doesn't need rotated; undef means error
		# since -1 evaluates to true, we can't just `if (auto_rotate())`
		my $result = auto_rotate($cur_path => $new_path);
		unless (defined $result && $result > 0) {
			copy($cur_path, $new_path);
		}
	}
}

sub resize_image {
	my ($working_dir, $source_name, $max_width, $max_height, $square) = @_;

	my $cur_path = "$working_dir/$source_name";

	my $new_name = "${max_width}x$max_height" . ($square ? '-square' : '');
	my $new_path = "$working_dir/$new_name";
	return $new_name unless enforce_cache_is_newer($cur_path, $new_path, 1);

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

	#$image->image_set_format("jpeg");
	if ($scale_factor < 1) {
		$image = $image->create_scaled_image($width * $scale_factor, $height * $scale_factor);

		save_image_while_working_around_imlib_bug($image, $new_path);
	} elsif ($square) {
		# we hit this case if the image is to be squared and just one dimension
		# was smaller than the square size, so we still need to crop the other
		# dimension (which was done above, but now we need to save it)
		save_image_while_working_around_imlib_bug($image, $new_path);
	} else {
		symlink($cur_path, $new_path);
	}

	return $new_name;
}

sub save_image_while_working_around_imlib_bug {
	my ($image, $new_path) = @_;

	my $make_imlib_happy = "$new_path.jpg";
	$image->save($make_imlib_happy);
	rename($make_imlib_happy, $new_path);
}

# This is a fix for https://github.com/truist/gallery/issues/2#issuecomment-316259361
# It also provides a feature: if an original is modified, the gallery will notice
sub enforce_cache_is_newer {
	my ($original, $cached, $same_ok) = @_;

	if (-e $cached) {
		if (original_is_newer($original, $cached, $same_ok)) {
			return unlink $cached;
		} else {
			return 0;
		}
	} else {
		return 1;
	}
}

sub original_is_newer {
	my ($original, $cached, $same_ok) = @_;

	# only 'stat' each file once
	my $original_stat = lstat($original);
	my $cached_stat = lstat($cached);

	# ctime tells us when the inode was last modified (which will be when it was created, at the earliest)
	# mtime tells us when the file was last modified
	# if either one (for the original) is greater than the cache's ctime, we say 'true'
	return greater($original_stat->ctime, $cached_stat->ctime, $same_ok)
		|| greater($original_stat->mtime, $cached_stat->ctime, $same_ok);
}

sub greater {
	my ($left, $right, $same_ok) = @_;

	if ($same_ok) {
		return $left > $right;
	} else {
		return $left >= $right;
	}
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

sub url_escape {
	return Mojo::Util::url_escape(@_, '^A-Za-z0-9\-._~\/\?\=');
}

1;
