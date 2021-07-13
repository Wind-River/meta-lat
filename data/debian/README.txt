In order to make LAT support external debian, we need to add tools
to customize 5 debian packages and create a debian package feed.

In these 5 debian packages, 2 of them based on existed debian sources,
and 3 of them come from this layer.

Packages from debian
- ostree, debian/2019.1-1
- watchdog, 5.16-1

Packages from this layer
- ostree-upgrade-mgr, 1.0,
- mttyexec, 0.1
- initramfs-ostree, 1.0

Start a debian 11 (bullseye) container to build packages:

Create customize debian package feed:

  $ docker run -it -w /workdir -v /path_to/this_layer:/mnt/lat debian:bullseye \
      /mnt/lat/data/debian/create_customize_debian_feed.sh -n <ostree_osname>

Setup a web server (such as httpd, apache2), and create a symlink
to outdir

  $ ln -snf path_to/wr-ostree/customize_debian/debian /var/www/html/debian

Then http://<web-server-url>/debian is accessible
