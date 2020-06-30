package Bkit::Controller::Group;
use Mojo::Base 'Mojolicious::Controller';
use List::MoreUtils qw|uniq|;

sub store {
  my $c = shift;
  my $users = $c->users;

  my $usernames = [
    sort grep {defined $users->{$_}} (uniq @{$c->req->json // $c->every_param('username')})
  ];

  my $groupname = $c->param('groupname');

  my $group = $c->groups->{$groupname} //= {  # define a new group if it not exists yet
    users => $usernames
  };

  my %rmusers = map {$_ => 1} @{$group->{users}};
  delete $rmusers{$_} foreach (@$usernames); 

  foreach my $username (keys %rmusers) {
    print "Remove group $groupname from user $username\n";
    $users->{$username}->{groups} = [grep {$_ ne $groupname} @{$users->{$username}->{groups} // []}]
  }

  foreach my $username (@$usernames) { #also add groupname to user->groups list
    my $user = $users->{$username};
    my $groupnames = $user->{groups} // [];
    push @$groupnames, $groupname;
    $user->{groups} = [(uniq sort @$groupnames)];
  }

  $group->{users} = $usernames;  

  $c->answer($group->{users}->export()); 
}

sub remove {
  my $c = shift;
  my $users = $c->users;
  my $groups = $c->groups;

  my $groupname = $c->param('groupname');

  return $c->error("Invalid group name")
    unless defined $groups->{$groupname};

  my $usernames = $groups->{$groupname}->{users} // [];

  foreach my $username (@$usernames) { #remove group name from users
    my $user = $users->{$username};
    my $groupnames = $user->{groups} // [];
    $user->{groups} = [sort grep {$_ ne $groupname} (uniq @$groupnames)];
  }

  delete $groups->{$groupname};

  $c->send_groups;
};

1;
