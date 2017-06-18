Gallery
=======

This is a simple (Perl-based) image gallery for static images. Once
set up, it is extremely simple to use - just drop a bunch of images
into a directory and they will be served up with a reasonable layout
(including mobile support), reasonable thumbnails, and reasonable
navigation. The original images will never be modified in any way.

It uses caches that are generated on-the-fly to improve performance,
but even un-cached loads are reasonably fast. The entire cache can
be wiped at any time and it will just regenerate as needed. The
cached images are auto-rotated per the orientation EXIF settings,
so you don't have to worry about pre-rotating them.

You can tweak a few aspects of the gallery via variables in the
source, or custom CSS, if you like.

The one (optional!) feature that requires some additional effort
is that you can define a "highlight" image (or sub-album) for each
album, and that will be used for the thumbnail for that album. To
do so, create a symlink to the image (or sub-album) you want
highlighted, and name the symlink `#highlight`. If you don't define
a highlight, the thumbnail image will be selected randomly each
time the page is loaded.

You can see a working example at <https://gallery.rainskit.com/>.

## Installation

0. Ensure you have the following things on your filesystem:

    0. Perl

    0. A clone of this repo

    0. A directory where your original images will go
        0. Outside the clone
        0. Readable by your production web server user

    0. A directory for the cache
        0. Outside the clone
        0. Readable and writable by your production web server user

    0. A place for log messages to go
        0. Outside the clone
        0. Writable by your web server

    0. The various perl modules this project depends on (see below)
        0. Findable by your web server user

0. Configure the variables at the top of `lib/Gallery.pm` to
   match the filesystem choices made in the prior step.

0. Run the built-in web server, `script/gallery`:

    0. If you run it with no arguments, it will show you usage.

    0. To get started testing the site, try:

        `script/gallery daemon -l http://*:8080`

    0. As you test you might see errors about missing perl modules;
       you'll need to install them in a location your web server
       can find them.

    0. For production usage, I suggest running it like so:

        `su -m $WEBUSER:$WEBGROUP -c "$GALLERY_DIR/script/gallery prefork -m production -l "http://127.0.0.1:$PORT" > $GALLERY_DIR/../logs/app.log 2>&1 &"`

    0. ...and then use your "real" web server to reverse-proxy that
       internal port to the internet, however you like.

0. Customize the site to your preferences:

    0. Configure the rest of the variables in `lib/Gallery.pm` to
       your liking. (You'll need to restart the site, if you do.)

    0. Add any site-specific static content (like `favicon.ico`)
       to `public/`.

    0. If you want to get fancy, customize `public/css.css`
       and/or the files in `templates/` to your liking.

