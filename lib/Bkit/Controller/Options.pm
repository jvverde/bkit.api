package Bkit::Controller::Options;
use Mojo::Base 'Mojolicious::Controller';

sub default {
  my $c = shift;
  my $origin = $c->req->headers->origin;

  $c->res->headers->header('Access-Control-Allow-Origin' => $origin);
  # $c->res->headers->header('Access-Control-Allow-Credentials' => 'true'); we don't user sessions
  $c->res->headers->header('Access-Control-Allow-Methods' => 'GET, OPTIONS, POST, DELETE, PUT');
  $c->res->headers->header('Access-Control-Allow-Headers' => 
    'Authorization', 'Content-Type', 'Origin', 'Accept', 'X-bKit-API'
  );
  $c->res->headers->header('Access-Control-Max-Age' => '1728000');                                                                                                                              

  $c->respond_to(any => { data => '', status => 200 });
}

1;
