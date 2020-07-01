use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use Mojo::JWT;
use Test::Mojo::Session;
use Data::Dumper;

use FindBin;
BEGIN { unshift @INC, "$FindBin::Bin/../lib" }

$\ = "\n";
sub random {
  return sprintf("%X", 0|rand(0xFFFFFFFF))
}
my $t = Test::Mojo::Session->new('Bkit');
my $randJWT = Mojo::JWT->new(secret => random());
#print Dumper $t->app->users;
#exit;

my $usersnames = [grep {defined $t->app->users->{$_}->{state}->{enable}} keys %{$t->app->users}];
my $randIndex = 0|rand 1 + $#$usersnames;
my $existUsr = $usersnames->[$randIndex];
my $notExistUsr = random();
my $newUsr = random();

my $expires = time + 3600;
my $encrypUser      = $t->app->jwt->claims({username => $existUsr})     ->expires($expires) ->encode;
my $encrypNewUser   = $t->app->jwt->claims({username => $newUsr})       ->expires($expires) ->encode;
my $encrypNoUser    = $t->app->jwt->claims({username => $notExistUsr})  ->expires($expires) ->encode;
my $timeoutUser     = $t->app->jwt->claims({username => $existUsr})     ->expires(time-1)   ->encode;
my $invalidUser     = $randJWT->    claims({username => $existUsr})     ->expires($expires) ->encode;

$t->get_ok('/')                                   ->status_is(404)->json_has('/msg');
$t->get_ok('/info')                               ->status_is(200)->json_is('/bKit' => Mojo::JSON->true);
$t->get_ok('/auth')                               ->status_is(404)->json_has('/msg');

$t->post_ok('/auth/signup' => form => {})         ->status_is(400)->json_has('/msg');
$t->post_ok('/auth/signup' => json => {})         ->status_is(400)->json_has('/msg');
$t->post_ok('/auth/signup'              )         ->status_is(400)->json_has('/msg');

my $upload = {username => $existUsr, password => $existUsr, email => 'test@bkit.pt'};
$t->post_ok('/auth/signup' => form => $upload)    ->status_is(400)->json_like('/msg' => qr/taken/i);
$t->post_ok('/auth/signup' => json => $upload)    ->status_is(400)->json_like('/msg' => qr/taken/i);

$upload = {username => $notExistUsr, password => $notExistUsr};
$t->post_ok('/auth/signup' => form => $upload)    ->status_is(400)->json_like('/msg' => qr/email/i);
$t->post_ok('/auth/signup' => json => $upload)    ->status_is(400)->json_like('/msg' => qr/email/i);

$upload = {username => $notExistUsr, email => 'jvv@bkit.pt'};
$t->post_ok('/auth/signup' => form => $upload)    ->status_is(400)->json_like('/msg' => qr/password/i);
$t->post_ok('/auth/signup' => json => $upload)    ->status_is(400)->json_like('/msg' => qr/password/i);

$t->get_ok('/auth/confirm')                       ->status_is(400)->json_like('/msg' => qr/not provided/i);
$t->get_ok('/auth/confirm?jwt=abc')               ->status_is(400)->json_like('/msg' => qr/invalid token/i);
$t->get_ok("/auth/confirm?jwt=$timeoutUser")      ->status_is(400)->json_like('/msg' => qr/token.*expired/i);
$t->get_ok("/auth/confirm?jwt=$invalidUser")      ->status_is(400)->json_like('/msg' => qr/Failed.+validation/i);
$t->get_ok("/auth/confirm?jwt=$encrypNoUser")     ->status_is(400)->json_like('/msg' => qr/not found/i);

$t->get_ok('/auth/reset_pass')                    ->status_is(404)->json_has('/msg');
$t->get_ok("/auth/reset_pass/$notExistUsr")       ->status_is(400)->json_like('/msg' => qr/not found/i);
#If uncomment line bellow you will trigger an email to the user
#$t->get_ok("/auth/reset_pass/$existUsr")->status_is(200)->json_like('/msg' => qr/was reset/i);

$t->get_ok("/auth/change_pass")                   ->status_is(400)->json_like('/msg' => qr/not provided/i);
$t->get_ok("/auth/change_pass?jwt=abc")           ->status_is(400)->json_like('/msg' => qr/invalid/i);
$t->get_ok("/auth/change_pass?jwt=$timeoutUser")  ->status_is(400)->json_like('/msg' => qr/token.*expired/i);
$t->get_ok("/auth/change_pass?jwt=$invalidUser")  ->status_is(400)->json_like('/msg' => qr/Failed.+validation/i);
$t->get_ok("/auth/change_pass?jwt=$encrypNoUser") ->status_is(400)->json_like('/msg' => qr/not found/i);

$t->post_ok('/auth/set_pass')                     ->status_is(400)->json_like('/msg' => qr/session/i);

$t->get_ok('/auth/change_email')                  ->status_is(400)->json_like('/msg' => qr/not provided/i);
$t->get_ok('/auth/change_email?jwt=abc')          ->status_is(400)->json_like('/msg' => qr/invalid token/i);
$t->get_ok("/auth/change_email?jwt=$timeoutUser") ->status_is(400)->json_like('/msg' => qr/token.*expired/i);
$t->get_ok("/auth/change_email?jwt=$invalidUser") ->status_is(400)->json_like('/msg' => qr/Failed.+validation/i);
$t->get_ok("/auth/change_email?jwt=$encrypNoUser")->status_is(400)->json_like('/msg' => qr/not found/i);

#$upload = {username => $newUsr, password => $newUsr, email => 'test@bkit.pt'};
$t->post_ok('/auth/login')                        ->status_is(403)->json_has('/msg');
$t->post_ok('/auth/login' => form => {})          ->status_is(403)->json_like('/msg' => qr/username/i);
my $cred = {username => $notExistUsr};
$t->post_ok('/auth/login' => form => $cred)       ->status_is(403)->json_like('/msg' => qr/password/i);
$cred->{password} = $notExistUsr;
$t->post_ok('/auth/login' => form => $cred)       ->status_is(403)->json_like('/msg' => qr/username.*not found/i);
$cred->{username} = $existUsr;
$t->post_ok('/auth/login' => form => $cred)       ->status_is(403)->json_like('/msg' => qr/invalid password/i);

$t->get_ok('/auth/logout')                        ->status_is(401)->json_like('/msg' => qr/logon.+first/i);

#full cycle
$upload = {email => 'jvv@bkit.pt', password => $newUsr , username => $newUsr};
$t->post_ok('/auth/signup' => form => $upload)    ->status_is(200)->json_like('/msg' => qr/registration.+received/i);
$t->get_ok("/auth/confirm?jwt=$encrypNewUser")    ->status_is(200)->content_like(qr/you.+are.+registered/i);

$t->app->users->{$newUsr}->{state}->{enable} = 1; #Enable user
$t->get_ok("/auth/reset_pass/$newUsr")            ->status_is(200)->json_like('/msg' => qr/password.*reset/i);
$t->get_ok("/auth/change_pass?jwt=$encrypNewUser")->status_is(200)->element_exists('input[name=password][type=password]')
                                                                  ->session_has('/targetuser',$newUsr);

$t->post_ok('/auth/set_pass')                     ->status_is(400)->json_like('/msg' => qr/password.*not provided/i);
$cred = {password => '', confirm => ''};
$t->post_ok('/auth/set_pass' => json => $cred)    ->status_is(400)->json_like('/msg' => qr/password.*null/i);
$cred = {password => 'abc', confirm => '123'};
$t->post_ok('/auth/set_pass' => json => $cred)    ->status_is(400)->json_like('/msg' => qr/password.*don't match/i);
$cred = {password => $newUsr, confirm => $newUsr};
$t->post_ok('/auth/set_pass' => json => $cred)    ->status_is(200)->json_like('/msg' => qr/accepted/i);


$t->get_ok("/auth/change_email?jwt=$encrypNewUser")->status_is(400)->json_like('/msg' => qr/not.*valid.*email/i);

my $eEmail = $t->app->jwt->claims({username => $newUsr, email => 'jvv@bkit.com'}) ->expires($expires) ->encode;
$t->get_ok("/auth/change_email?jwt=$eEmail")      ->status_is(200)->json_like('/msg' => qr/accepted/i);

$t->get_ok("/auth/users")                         ->status_is(401)->json_like('/msg' => qr/Logon.*first/i);

$t->post_ok("/auth/login")                        ->status_is(403)->json_like('/msg' => qr/username.*not.*provided/i);
$cred = { username => $newUsr};
$t->post_ok("/auth/login" => json => $cred)       ->status_is(403)->json_like('/msg' => qr/password.*not.*provided/i);

$cred = { username => $newUsr, password => '123'};
$t->post_ok("/auth/login" => json => $cred)       ->status_is(403)->json_like('/msg' => qr/invalid.*password/i);

$cred = { username => $newUsr, password => $newUsr};
$t->post_ok("/auth/login" => json => $cred)       ->status_is(200)->json_like('/login/msg' => qr/logged/i);

$t->get_ok("/auth/users?access_token=$encrypNewUser")                 ->status_is(200);
$t->get_ok("/auth/groups?access_token=$encrypNewUser")                ->status_is(200);
$t->get_ok("/auth/user/$newUsr?access_token=$encrypNewUser")          ->status_is(200)->json_is('/email', 'jvv@bkit.com');

$t->delete_ok("/auth/user/$newUsr?access_token=$encrypNewUser")       ->status_is(200)->json_like('/msg', qr/deleted/);

done_testing();
