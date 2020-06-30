package Bkit::Controller::Clients;
use Mojo::Base 'Mojolicious::Controller';
use List::MoreUtils qw|uniq|;
use Data::Dumper;
use File::Find::Rule;

sub _listclients {
  return [File::Find::Rule->mindepth(3)->maxdepth(3)->directory->in( shift )];
}
sub default {
  my $c = shift;

  $c->app->log->debug("Get Computers");
  my $config = $c->config;
  my $computers = eval {
    _listclients $config->{clients};
  } or warn "$@";

  my $r = [map {
    my ($domain, $name, $uuid) = $_ =~ m#.*/([^/]+)/([^/]+)/([^/]+)$#;
    {
      domain => $domain,
      name => $name,
      uuid => $uuid
    }
  } @$computers];

  $c->answer($r);
}

1;
