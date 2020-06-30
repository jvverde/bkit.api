package Bkit;
use Mojo::Base 'Mojolicious';
use Minion;
use DBM::Deep;
use Mojolicious::Plugin::Bcrypt;
use Mojolicious::Sessions;
use Mojo::JSON qw/decode_json/;
use Data::Dumper;


# This method will run once at server start

sub read_json{
  local $/;
  
  open(my $fh, '<',$_[0]) or (warn "Cannot open file $_[0]:$!" and return undef);
  my $json_text = <$fh>;
  close $fh;
  return decode_json( $json_text );
}

sub startup {
  my $self = shift;

  $self->sessions->cookie_name('Bkit');
  $self->sessions->default_expiration(300);

  $self->plugin('RenderFile');                                                                                                                                                                                                                                                                                                                                                
  # Load configuration from hash returned by "bkit.conf"
  my $config = $self->plugin('Config', file => '/etc/bkit/api/bkit.conf');
  $self->helper(config => sub {$config});

  {
    my $logdir = $config->{log} || 'log';
    mkdir $logdir unless -d $logdir;
    my $log = Mojo::Log->new( path => "$logdir/$self->{mode}.log");
    $self->app->log($log);
  }

  {
    my $types = $self->types;
    $types->type(bkit => 'application/bkit');
    $types->type(log => 'text/plain');
    $types->type(LOG => 'text/plain');
    $types->type(ini => 'text/plain');

    if (my $file = $config->{mimetypes}){
      my $mimetypes = read_json("$file") // [];
      foreach my $entry (@$mimetypes){ #define missing mimetypes
        my ($t,$v) = %$entry;
        $t =~ s/^\.//;
        $types->type($t => $v) unless $types->type($t);
      }
    }
  }

  my $dbdir = $config->{DB} || '.db';
  mkdir $dbdir unless -d $dbdir;

  $self->plugin(Minion => {SQLite => "$dbdir/minion.db"});
  $self->plugin('bcrypt');
  
  $self->secrets([$config->{secret}]);


  $self->helper(users => sub { state $db = DBM::Deep->new("$dbdir/users.db") });
  $self->helper(groups => sub { state $db = DBM::Deep->new("$dbdir/groups.db") });
  
  $self->helper(send_email => sub {
    my ($job, $address, $subject, $body) = @_;

    eval {
      require Email::Simple;
      require Email::Sender::Simple;

      my $email = Email::Simple->create(
        header => [
          To      => $address,
          From    => 'ask.confirmation@bkit.pt',
          Subject => $subject,
        ],
        body => $body,
      );
      Email::Sender::Simple->send($email);
      print "Email sent to $address\n";
    } or $job->app->log->debug("error: $@");
  });

  $self->minion->add_task(email_task => sub { shift->app->send_email(@_) });

  $self->helper(jwt => sub {
    Mojo::JWT->new(secret => $config->{secret})
  });

  $self->helper(email => sub {
    shift->minion->enqueue(email_task => [@_])
  });

  $self->helper(answer => sub {
    shift->render(json => ref $_[0] ? shift : {msg => shift}, status => shift || 200)
  });
  
  $self->helper(error => sub {
    shift->render(json => ref $_[0] ? shift : {msg => shift}, status => shift || 400)
  });
  
  $self->helper(send_users => sub {
    my $c = shift;
    my $usernames = $c->stash('usernames') || [ keys %{$c->users} ];
    $c->answer([ @$usernames ]);
  });

  $self->helper(send_user => sub {
    my $c = shift;
    
    return $c->error("I need a user")
      unless my $username = $c->stash('username');
    
    return $c->error("Invalid user $username")
      unless my $user = $c->users->{$username};  
    
    my $info = $user->export();
    delete $info->{password};          #don't send password

    $c->answer($info);
  });
  
  $self->helper(send_groups => sub {
    my $c = shift;
    my $groups = $c->groups->export();
    $c->answer([
      map { {name => $_, %{$groups->{$_}}} } sort keys %$groups
    ]);
  });


  $self->hook(after_dispatch => sub {
    my $c = shift;
    #$c->app->log->debug('After dispatch');
    my $origin = $c->req->headers->origin;
    $c->res->headers->header('Access-Control-Allow-Origin' => $origin)
      if defined $origin and $c->req->headers->header('X-bKit-API'); 
  });

  print "Aqui estou eu!!!\n";
  print "Entrei em mode $self->{mode}\n";

  my $admin = $config->{admin}->{name} || 'admin';

  $self->groups->{admin} //= {users => ["$admin"]};
  $self->users->{$admin} //= {
    password => $self->bcrypt($config->{admin}->{pass} || 'admin'),
    email => $config->{admin}->{email} || 'admin@bkit.pt',
    groups => ['admin'],
    state => {
	enable => 1
    },
  };


  # Router
  my $r = $self->routes;

  $r->options('*')->to('options#default');

  $r->get('/info' => sub {
    my $c = shift;
    $c->answer({
      bKit => Mojo::JSON->true,
      baseUrl => $c->req->url->base,
      name => $config->{name},
      location => $config->{location},
      version => $config->{version}
    })
  });

  my $auth = $r->any('/auth')->to(controller => 'auth');
  
  $auth->post('/signup')              -> to('#signup'); 
  $auth->get('/confirm')              -> to('#confirm');
  $auth->get('/change_email')         -> to('#change_email');
  $auth->get('/reset_pass/#username') -> to('#reset_pass');
  $auth->get('/change_pass')          -> to('#change_pass');
  $auth->post('/set_pass')            -> to('#set_pass');
  $auth->post('/login')               -> to('#login');

  my $valid = $auth->under('/')       -> to('#validate');
  
  $valid->get('/logout')              -> to('#logout');
  $valid->get('/users'                => sub {shift->send_users});
  $valid->get('/groups'               => sub {shift->send_groups});

  my $user = $valid->any('/user')->to(controller => 'user');

  $user->get('/#username'             => sub {shift->send_user}); 
  $user->put('/#username/groups')     -> to('#add2groups');
  $user->delete('/#username')         -> to('#remove');
  $user->post('/set_email')           -> to('#set_email');
  $user->post('/:value/:state' => [
    value => ['set', 'reset'] 
  ])                                  -> to('#change_state');

  my $group = $valid->any('/group')->to(controller => 'group');

  $group->put('/#groupname')          -> to('#store');
  $group->delete('/#groupname')       -> to('#remove');

  
  my $clients = $valid->any('/clients') ->to(controller => 'clients');

  $clients->get('/')                    ->to('#default');

  { #client
    my $client = $valid->any('/client')         ->to(controller => 'client');

    $client->get('/*client/disks')              ->to('#disks');

    $client->get('/*client/disk/#disk/snaps')   ->to('#snaps');

    { #snap
      my $snap = $client->under('/*client/disk/#disk/snap/#snap' => [
        client => qr#[^/]+?/[^/]+?/[^/]+#,
        disk => qr#[^/.](?:[.][^/.]+){4}#,
        snap => qr#\@GMT-[^/]+#
      ] => sub{return 1});

      $snap->get('/dirs/*path'  => {path => ''})    ->to('#dirs');
      $snap->get('/files/*path' => {path => ''})    ->to('#files');
      $snap->get('/view/*path'  => {path => ''})    ->to('#view');
      $snap->get('/download/*path'  => {path => ''})->to('#download');
      $snap->get('/bkit/*path'  => {path => ''})    ->to('#bkit');
    }
  } #end of client

  $r->websocket('/ws/alerts')->to('websock#default');

  $r->any('/*whatever' => {whatever => ''} => sub {
    my $c        = shift;
    my $whatever = $c->param('whatever');
    $c->error("/$whatever did not match any route", 404)
  });

};

1;
