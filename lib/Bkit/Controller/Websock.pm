package Bkit::Controller::Websock;
use Mojo::Base 'Mojolicious::Controller';
use IO::Async::Loop::Mojo;
use IO::Async::Socket;
use Mojo::JSON qw|decode_json|;
use Mojo::Log;

my $loop = IO::Async::Loop::Mojo->new();
my $clients = {};  #connected clients

my $log = Mojo::Log->new( path => '/var/log/bkit/websock.log', level => 'debug' ); #temporary log. Only until first call to default.

my $socket = IO::Async::Socket->new(
  on_recv => sub {
    my ( $self, $dgram, $addr ) = @_;
    $log->debug("UDP:$dgram");
    foreach my $c (keys %$clients) {
      $clients->{$c}->send({
        json => {
          type => 'udp',
          msg => $dgram
        }
      })
    }
  },
  on_recv_error => sub {
    my ( $self, $errno ) = @_;
    $log->warn("Cannot recv - $errno");
  },
  on_closed => sub {
    $log->info("Socket Closed");
  }
);

$loop->add( $socket );
#line above always before line bellow. Don't work if changed
$socket->bind(
  host => '127.0.0.1',
  service  => 8765,
  socktype => 'dgram'
)->get;

$log->info('Start Websock controler');

sub default {
  my $self = shift;

  $log = $self->app->log;                            #redirect from websocket
  $self->inactivity_timeout(86400);
  my $tx = $self->tx;
  my $id = $tx->connection;
  my $client = $tx->remote_address . ':' . $tx->remote_port;
  $log->info("Client connected: $client");
  $log->debug("Connection: $id");

  $clients->{$id} = $self->tx;

  $self->on(finish => sub {
    $log->info("Client $client disconnected");
    delete $clients->{$id};
  });
  $self->on(message => sub {
    my ($c, $msg) = @_;
    my $r = decode_json $msg;
    open my $fh, "+>", $r->{id} or warn "Can't open $r->{id}";
    $log->debug("Forward $r->{answer} to $r->{id}");
    print $fh "$r->{answer}\n";
    close $fh;
  });
}

1;
