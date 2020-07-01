package Bkit::Controller::Auth;
use Mojo::Base 'Mojolicious::Controller';
use Mojo::JSON;
use Mojo::JWT;
use Data::Dumper;

sub _replaceAT {
  (my $t = shift) =~ s/ at .*//; 
  return $t
}

print "Auth\n";

sub signup {
  print "\tSignup\n";
  my $c = shift;
  
  my $req = $c->req->json // {
    username => $c->param('username'),
    email => $c->param('email'),
    password => $c->param('password')
  };

  return $c->error('Username cannot be blank')
    unless my $username = $req->{username};

  return $c->error("Username $username is taken")
    if $c->users->{$username};

  return $c->error('Password cannot be blank')
    unless my $password = $req->{password};

  return $c->error('Email cannot be blank')
    unless my $email = $req->{email};

  $c->users->{$username} = {
    email     => $email,
    password  => $c->bcrypt($password),
    state => {
      unconfirmed => 1,
    },
    signup => {
      date => time,
      ua => $c->req->headers->user_agent,
      from => $c->tx->remote_address      
    },
    groups => []
  };
  
  my $expires = time + 86400;
  my $jwt = $c->jwt->claims({username => $username})->expires($expires)->encode;
  my $url = $c->url_for('confirm')->to_abs->query(jwt => $jwt);

  my $until = (localtime $expires) . " (${\(POSIX::tzname())})";

  $c->email($email, 'Confirm registration', "Please visit $url to confirm until $until");
  $c->answer("Registration requested received, please check email $email to confirm");
}

sub confirm{
  my $c = shift;

  return $c->error("Token JWT not provided")
    unless my $token = $c->param('jwt');
  
  return $c->error('Invalid token: ' . _replaceAT($@))
    unless my $username = eval {$c->jwt->decode($token)->{username}};
  
  return $c->error("User $username not found. Please signup again")
    unless my $user = $c->users->{$username};
  
  $user->{state} //= {};

  return $c->error('User $username has been confirmed before')
    unless $user->{state}->{unconfirmed};
  
  delete $user->{state}->{unconfirmed};

  $user->{confirmed} = {
    date => time,
    ua => $c->req->headers->user_agent,
    from => $c->tx->remote_address     
  };

  #$c->redirect_to('http://localhost:8080/#/login');
  $c->stash(username => $username)->render('auth/confirmed');
}

sub reset_pass{
  my $c = shift;

  return $c->error('Username cannot be blank')
    unless my $username = $c->param('username');

  return $c->error("Username '$username' not found")
    unless $c->users->{$username};

  return $c->error("Email not defined for user $username")
    unless my $email = $c->users->{$username}->{email};

  my $expires = time + 3600;
  my $jwt = $c->jwt->claims({username => $username})->expires($expires)->encode;
  my $url = $c->url_for('change_pass')->to_abs->query(jwt => $jwt);
  
  my $until = (localtime $expires) . " (${\(POSIX::tzname())})";

  $c->email($email, "Change password for user $username", "Please visit $url to change it, until $until");
  $c->answer("Password for user $username will be reset. Please check your email $email");
}

sub change_pass {
  my $c = shift;

  return $c->error("Token JWT not provided") 
    unless my $token = $c->param('jwt');

  return $c->error('Invalid token: ' . _replaceAT($@)) 
    unless my $claim = eval { $c->jwt->decode($token) };

  return $c->error("Username must be provided")
    unless my $username = $claim->{username};  

  return $c->error("Username $username not found")
    unless $c->users->{$username};

  #my $redirect = Mojo::URL->new("http://localhost:8080/#/new_pass/$username");
  $c->stash(username => $username);
  $c->stash(url => $c->url_for('set_pass'));
  $c->session(targetuser => $username, expires => time + 600)->render('/auth/login');
}

sub set_pass{
  my $c = shift;

  return $c->error("Session expired")
    unless my $username = $c->session('targetuser');
  
  my $req = $c->req->json // {
    confirm => $c->param('confirm'),
    password => $c->param('password')
  };

  return $c->error("Password not provided")
    unless defined $req->{password};

  return $c->error("Password cannot be null")
    if $req->{password} eq '';

  return $c->error("Password and confirmation don't match")
    unless $req->{password} eq $req->{confirm};

  return $c->error("Username not found")
    unless defined $c->users->{$username};

  $c->users->{$username}->{password} = $c->bcrypt($req->{password});
  
  $c->answer("New password for user $username accepted")
}

sub change_email {
  my $c = shift;

  return $c->error("Token JWT not provided")
    unless my $token = $c->param('jwt');

  return $c->error("Invalid token: " . _replaceAT($@))
    unless my $claim = eval { $c->jwt->decode($token) };

  my ($username,$email) = @{$claim}{qw|username email|};

  return $c->error("Username not found")
    unless my $user = $c->users->{$username};

  return $c->error("Not a valid email address")
    unless defined $email and $email =~ /.*@.+\..{2,9}/;

   $user->{email} = $email;

  $c->answer("New email $email for user $username accepted.");
}

sub login {
  my $c = shift;

  my $req = $c->req->json // {
    username => $c->param('username'),
    password => $c->param('password')
  };

  my $username = $req->{username};
  
  return $c->error("Username not provided", 403) 
    unless $username;

  return $c->error("Password not provided", 403) 
    unless $req->{password};

  return $c->error("Username $username not found", 403)
    unless my $user = $c->users->{$username};

  return $c->error("Username $username has not been confirmed yet", 403)
    if defined $user->{state} and $user->{state}->{unconfirmed};

  return $c->error("Users with empty password are no allowed to login", 403)
    unless $user->{password};

  return $c->error('Invalid Password', 403)
    unless $c->bcrypt_validate($req->{password}, $user->{password});

  return $c->error('User is disable. Contact the bKit Administrator', 403)
    unless defined $user->{state} and defined $user->{state}->{enable};

  my $time = time;

  $user->{login} //= {cnt => 0, firstTime => $time};
  $user->{login}->{cnt}++;
  $user->{login}->{lastTime} = $time;
  $user->{login}->{lastAgent} = $c->req->headers->user_agent;
  $user->{login}->{lastOrigin} = $c->tx->remote_address;

  $user->{state} //= {}; #just in case
  $user->{state}->{login} = 1;
  delete $user->{state}->{logout};

  $c->answer({
    login => {
      msg => "You are now logged as $username",
      user => $username,
      token => $c->jwt->claims({username => $username})->expires($time + 3600)->encode
    }
  });
}

sub validate{
  my $c = shift;
  my $origin = $c->req->headers->origin;
  my $token = $c->req->headers->authorization // '';
  $token =~ s/^Bearer // or $token = $c->param('access_token') // do {
    my $req = $c->req->json;
    $req->{access_token} if defined $req;  
  };
  
  $c->res->headers->www_authenticate('Bearer realm="bKit"') 
    and $c->error("Please logon first", 401) and return undef unless $token;

  my $claim = eval { $c->jwt->decode($token) };
  
  unless ($claim) {
    my $desc = (split /\n/, $@)[0];
    $c->res->headers->www_authenticate(qq|Bearer realm="bKit", error="invalid_token", error_description="$desc"|);
    $c->error("Please revalidate your token", 401);
    return undef;
  };


  my $username = $claim->{username};

  $c->error("Invalid user") and return undef
    unless my $user = $c->users->{$username};

  $c->error("User account is disabled", 403) and return undef
    unless defined $user->{state} and $user->{state}->{enable};

  $c->error("User account is logoff", 401) and return undef
    unless defined $user->{state} and $user->{state}->{login};

  my $expires = $claim->{exp};
  my $time = time;
  my $age =  $time - ($expires - 3600); #now - last time a token was created = How old is token

  $user->{access} //= {cnt => 0, firstTime => $time};
  $user->{access}->{cnt}++;
  $user->{access}->{lastTime} = $time;
  $user->{access}->{lastAgent} = $c->req->headers->user_agent;
  $user->{access}->{lastOrigin} = $c->tx->remote_address;
  
  $c->res->headers->header(
    'X-bKit-RToken' => $c->jwt->claims({username => $username})->expires($time + 3600)->encode
  ) if $age > 1800;
  
  $c->res->headers->header('Access-Control-Allow-Origin' => $origin)
    if defined $origin;

  $c->stash(username => $username);
  return 1
}

sub logout{ 
  my $c = shift;

  return $c->error("You must provide an Username", 400) 
    unless my $username = $c->stash('username');  
  
  return $c->error("Username $username not found", 400) 
    unless my $user = $c->users->{$username};
  
  $user->{logout} //= {cnt => 0};
  $user->{logout}->{cnt}++;
  $user->{logout}->{lastTime} = time;
  $user->{logout}->{lastAgent} = $c->req->headers->user_agent // '';
  $user->{logout}->{lastOrigin} = $c->tx->remote_address;

  $user->{state} //= {}; #just in case
  $user->{state}->{logout} = 1;
  delete $user->{state}->{login};

  $c->answer("$username is now logoff");
}

1;
