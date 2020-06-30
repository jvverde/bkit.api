package Bkit::Controller::User;
use Mojo::Base 'Mojolicious::Controller';
use List::MoreUtils qw|uniq|;

sub add2groups {
  my $c = shift;
  my $users = $c->users;
  my $groups = $c->groups;

  my $username = $c->param('username');
  
  return $c->error("Invalid user")
    unless my $user = $users->{$username};

  my $groupnames = [
    sort grep {defined $groups->{$_}} (uniq @{$c->req->json // $c->every_param('groupname')})
  ];

  my %rmgroups = map {$_ => 1} @{$user->{groups}};
  delete $rmgroups{$_} foreach (@$groupnames);

  foreach my $groupname (keys %rmgroups) {
    $c->app->log->info("Remove user $username from group $groupname");
    $groups->{$groupname}->{users} = [grep {$_ ne $username} @{$groups->{$groupname}->{users} // []}]
  }

  foreach my $groupname (@$groupnames) { #also add username to group->users list
    my $group = $groups->{$groupname};
    my $usernames = $group->{users} // [];
    push @$usernames, $username;
    $group->{users} = [(uniq sort @$usernames)];
  }

  $user->{groups} = $groupnames;  

  $c->answer($user->{groups}->export()); 
}

sub remove{
  my $c = shift;
  my $users = $c->users;
  my $groups = $c->groups;

  my $username = $c->param('username');

  return $c->error("Invalid user name <b>$username</b>")
    unless defined $users->{$username};

  my $groupnames = $users->{$username}->{groups} // [];

  foreach my $groupname (@$groupnames) { #remove group name from users
    my $group = $groups->{$groupname};
    my $usernames = $group->{users} // [];
    $group->{users} = [sort grep {$_ ne $username} (uniq @$usernames)];
  }

  delete $users->{$username};

  $c->answer("User $username deleted");
}

sub set_email{
  my $c = shift;
  
  my $req = $c->req->json // {
    username => $c->param('username'),
    email => $c->param('email')
  };

  my ($username, $email) = @{$req}{qw|username email|};

  return $c->error("Invalid user")
    unless defined $c->users->{$username};

  return $c->answer("Email still the same. Nothing to be done")
    if $c->users->{$username}->{email} eq $email;

  my $expires = time + 3600;
  my $jwt = $c->jwt->claims({username => $username, email=> $email})->expires($expires)->encode;
  my $url = $c->url_for('change_email')->to_abs->query(jwt => $jwt);

  my $until = (localtime $expires) . " (${\(POSIX::tzname())})";

  $c->email($email, "Change email for user $username", "Please visit $url to confirm it, until $until");
  $c->answer("New email address for user $username is waiting confirmation. Please check your email $email");
}

sub change_state{
  my $c = shift;
  
  my $value = $c->param('value');  
  my $state = $c->param('state');

  my $usernames = $c->req->json // $c->every_param('username');

  foreach my $username (grep {defined} @$usernames) {
    my $user = $c->users->{$username} or next;
    $user->{state} //= {};
    $user->{state}->{$state} = 1 if $value eq 'set';
    delete $user->{state}->{$state} if $value eq 'reset';
  }

  if ($#$usernames > 1) {
    $c->stash(usernames => $usernames);
    $c->send_users;
  } else {
    $c->stash(username => $usernames->[0] );
    $c->send_user;
  }
}

1;
