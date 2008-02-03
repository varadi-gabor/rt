#!/usr/bin/perl -w
use strict;
use HTTP::Cookies;

use RT::Test; use Test::More tests => 31;

my ($baseurl, $agent) = RT::Test->started_ok;

# Create a user with basically no rights, to start.
my $user_obj = RT::Model::User->new(current_user => RT->system_user);
my ($ret, $msg) = $user_obj->load_or_create_by_email('customer-'.$$.'@example.com');
ok($ret, 'ACL test user creation');
($ret,$msg) =$user_obj->set_name('customer-'.$$);
ok($ret,$msg);
($ret,$msg) = $user_obj->set_privileged(1);
ok($ret,$msg);
($ret, $msg) = $user_obj->set_password('customer');
ok($ret, "ACL test password set. $msg");

# Now test the web interface, making sure objects come and go as
# required.


my $cookie_jar = HTTP::Cookies->new;

# give the agent a place to stash the cookies

$agent->cookie_jar($cookie_jar);

no warnings 'once';
# get the top page
$agent->login($user_obj->name => 'customer');
# Test for absence of Configure and Preferences tabs.
ok(!$agent->find_link( url => "$RT::WebPath/Admin/",
		       text => 'Configuration'), "No config tab" );
ok(!$agent->find_link( url => "$RT::WebPath/User/Prefs.html",
		       text => 'Preferences'), "No prefs pane" );

# Now test for their presence, one at a time.  Sleep for a bit after
# ACL changes, thanks to the 10s ACL cache.
my ($grantid,$grantmsg) =$user_obj->principal_object->grant_right(right => 'ShowConfigTab', object => RT->system);

ok($grantid,$grantmsg);

$agent->reload;

like($agent->{'content'} , qr/Logout/i, "Reloaded page successfully");
ok($agent->find_link( url => "$RT::WebPath/Admin/",
		       text => 'Configuration'), "Found config tab" );
my ($revokeid,$revokemsg) =$user_obj->principal_object->revoke_right(right => 'ShowConfigTab');
ok ($revokeid,$revokemsg);
($grantid,$grantmsg) =$user_obj->principal_object->grant_right(right => 'ModifySelf');
ok ($grantid,$grantmsg);
$agent->reload();
like($agent->{'content'} , qr/Logout/i, "Reloaded page successfully");
ok($agent->find_link( url => "$RT::WebPath/User/Prefs.html",
		       text => 'Preferences'), "Found prefs pane" );
($revokeid,$revokemsg) = $user_obj->principal_object->revoke_right(right => 'ModifySelf');
ok ($revokeid,$revokemsg);
# Good.  Now load the search page and test Load/Save Search.
$agent->follow_link( url => "$RT::WebPath/Search/Build.html",
		     text => 'Tickets');
is($agent->{'status'}, 200, "Fetched search builder page");
ok($agent->{'content'} !~ /Load saved search/i, "No search loading box");
ok($agent->{'content'} !~ /Saved searches/i, "No saved searches box");

($grantid,$grantmsg) = $user_obj->principal_object->grant_right(right => 'LoadSavedSearch');
ok($grantid,$grantmsg);
$agent->reload();
like($agent->{'content'} , qr/Load saved search/i, "Search loading box exists");
ok($agent->{'content'} !~ /input\s+type=['"]submit['"][^>]+name=['"]SavedSearchSave['"]/i, 
   "Still no saved searches box");

($grantid,$grantmsg) =$user_obj->principal_object->grant_right(right => 'CreateSavedSearch');
ok ($grantid,$grantmsg);
$agent->reload();
like($agent->{'content'} , qr/Load saved search/i, 
   "Search loading box still exists");
like($agent->{'content'} , qr/input\s+type=['"]submit['"][^>]+name=['"]SavedSearchSave['"]/i, 
   "Saved searches box exists");

# Create a group, and a queue, so we can test limited user visibility
# via SelectOwner.

my $queue_obj = RT::Model::Queue->new(current_user => RT->system_user);
($ret, $msg) = $queue_obj->create(name => 'CustomerQueue-'.$$, 
				  description => 'queue for SelectOwner testing');
ok($ret, "SelectOwner test queue creation. $msg");
my $group_obj = RT::Model::Group->new(current_user => RT->system_user);
($ret, $msg) = $group_obj->create_user_defined_group(name => 'CustomerGroup-'.$$,
			      description => 'group for SelectOwner testing');
ok($ret, "SelectOwner test group creation. $msg");

# Add our customer to the customer group, and give it queue rights.
($ret, $msg) = $group_obj->add_member($user_obj->principal_object->id());
ok($ret, "Added customer to its group. $msg");
($grantid,$grantmsg) =$group_obj->principal_object->grant_right(right => 'OwnTicket',
				     object => $queue_obj);
                                     
ok($grantid,$grantmsg);
($grantid,$grantmsg) =$group_obj->principal_object->grant_right(right => 'SeeQueue',
				     object => $queue_obj);
ok ($grantid,$grantmsg);
# Now.  When we look at the search page we should be able to see
# ourself in the list of possible owners.

$agent->reload();
ok($agent->form_name('BuildQuery'), "Yep, form is still there");
my $input = $agent->current_form->find_input('value_of_actor');
ok(grep(/customer-$$/, $input->value_names()), "Found self in the actor listing");

die join(',',$input->value_names);
1;
