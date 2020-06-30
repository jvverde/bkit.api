package Bkit::Controller::Client;
use Mojo::Base 'Mojolicious::Controller';
use List::MoreUtils qw|uniq|;
use Data::Dumper;
use File::Find::Rule;
use File::Basename;
use utf8;
use JSON;

sub _2utf8 { #convert filenames to utf8
  my $list = shift;
  utf8::decode($_) foreach (@$list);
  return $list;
}

sub _listdisks {
  return _2utf8 [File::Find::Rule->mindepth(1)->maxdepth(1)->directory->relative->in( shift )];
}

sub _listsnaps {
  return _2utf8 [File::Find::Rule->mindepth(1)->maxdepth(1)->directory->ino(256)->relative->in( shift )];
}

sub _listdirs {
  return _2utf8 [File::Find::Rule->mindepth(1)->maxdepth(1)->directory->relative->in( shift )];
}
sub _listfiles {
  return _2utf8 [File::Find::Rule->mindepth(1)->maxdepth(1)->file->relative->in( shift )];
}

sub disks {
  my $c = shift;

  my $client = $c->stash('client');

  $c->app->log->debug("Get Disks for $client");
  my $config = $c->config;

  my $disks = eval {
    _listdisks( join '/', $config->{clients}, $client, 'data' );
  } or warn "$@";

  $c->answer($disks // []);
}

sub snaps {
  my $c = shift;

  my $client = $c->stash('client');
  my $disk = $c->stash('disk');

  $c->app->log->debug("Get Disk $client/data/$disk");
  my $config = $c->config;

  my $snaps = eval {
    _listsnaps( join '/', $config->{clients}, $client, 'data', $disk, '.snapshots' );
  } or warn "$@";

  $c->answer($snaps // []);
}

sub dirs {
  my $c = shift;

  my $client = $c->stash('client');
  my $disk = $c->stash('disk');
  my $snap = $c->stash('snap');
  my $path = $c->stash('path');

  $c->app->log->debug("Snap: $snap");
  $c->app->log->debug("Get Dirs $client/data/$disk/.snapshots/$snap/data/$path");
  my $config = $c->config;

  my $dirs = eval {
    _listdirs( join '/', $config->{clients}, $client, 'data', $disk, '.snapshots', $snap, 'data', $path );
  } or warn "$@";

  $c->answer($dirs // []);
}

sub files {
  my $c = shift;

  my $client = $c->stash('client');
  my $disk = $c->stash('disk');
  my $snap = $c->stash('snap');
  my $path = $c->stash('path');

  my $config = $c->config;

  my $dir = join '/', $config->{clients}, $client, 'data', $disk, '.snapshots', $snap, 'data', $path;
  $c->app->log->debug("Get Files $dir");

  my $entries = eval {
    _listfiles( $dir );
  } or warn "$@";

  my $files = [map {
    my @stats = stat "$dir/$_";
    {
      name => $_,
      size => $stats[7],
      datetime => $stats[9]
    }
  } @{$entries || []}];

  $c->answer($files);
}

sub view {
  my $c = shift;

  my $client = $c->stash('client');
  my $disk = $c->stash('disk');
  my $snap = $c->stash('snap');
  my $path = $c->stash('path');

  my $config = $c->config;

  my $fullpath = join '/', $config->{clients}, $client, 'data', $disk, '.snapshots', $snap, 'data', $path;
  $c->app->log->debug("View $fullpath");

  my ($fmt) = $fullpath =~ m/\.([^.]+)$/;
  $c->render_file(
    filepath => $fullpath,
    content_disposition => 'inline',
    format => $fmt
  );
}

sub download {
  my $c = shift;

  my $client = $c->stash('client');
  my $disk = $c->stash('disk');
  my $snap = $c->stash('snap');
  my $path = $c->stash('path');

  my $config = $c->config;

  my $fullpath = join '/', $config->{clients}, $client, 'data', $disk, '.snapshots', $snap, 'data', $path;
  $c->app->log->debug("Download $fullpath");

  my ($fmt) = $fullpath =~ m/\.([^.]+)$/;
  $c->render_file(
    filepath => $fullpath,
    content_disposition => 'attachment',
    format => $fmt
  );
}

sub bkit {
  my $c = shift;

  my $client = $c->stash('client');
  my $disk = $c->stash('disk');
  my $snap = $c->stash('snap');
  my $path = $c->stash('path');
  my $server = $c->req->url->to_abs->host;

  my $config = $c->config;

  my $basepath = join '/', $config->{clients}, $client, 'data', $disk, '.snapshots', $snap, 'data';
  my $fullpath = join '/', $basepath, $path;
  $c->app->log->debug("Restore $fullpath");

  my ($filename, $dirs, $suffix) = fileparse("$fullpath");
  my $result = {
    computer => $client,
    backup => $snap,
    drive => $disk,
    path => File::Spec->abs2rel($dirs,$basepath),
    entry => $filename.$suffix,
    server => $server
  };

  $c->render_file(
    data => encode_json $result,
    filename => "$filename.bkit",
    content_disposition => 'inline',
    format => 'bkit'
  );
}

1;
