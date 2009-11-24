#!/usr/bin/perl -w
use strict;

use RT::Test strict => 1, tests => 26, l10n => 1;

$RT::Test::SKIP_REQUEST_WORK_AROUND = 1;

my ($baseurl, $m) = RT::Test->started_ok;

use constant ImageFile => RT->static_path .'/images/bplogo.gif';
use constant ImageFileContent => RT::Test->file_content(ImageFile);

ok $m->login, 'logged in';

my $cf_moniker = 'edit-ticket-cfs';

diag "Create a CF" if $ENV{'TEST_VERBOSE'};
{
    $m->follow_link( text => 'Configuration' );
    $m->title_is(q/RT Administration/, 'admin screen');
    $m->follow_link( text => 'Custom Fields', url_regex =>
            qr!Admin/CustomFields! );
    $m->title_is(q/Select a Custom Field/, 'admin-cf screen');
    $m->follow_link( text => 'Create' );
    $m->submit_form(
        form_name => "modify_custom_field",
        fields => {
            type_composite =>   'Image-0',
            lookup_type => 'RT::Model::Queue-RT::Model::Ticket',
            name => 'img',
            description => 'img',
        },
    );
}

diag "apply the CF to General queue" if $ENV{'TEST_VERBOSE'};
my ( $cf, $cfid, $tid );
{
    $m->title_is(q/Created CustomField img/, 'admin-cf Created');
    $m->follow_link( text => 'Queues', url_regex => qr!/Admin/Queues! );
    $m->title_is(q/Admin queues/, 'admin-queues screen');
    $m->follow_link( text => 'General' );
    $m->title_is(q/Editing Configuration for queue General/, 'admin-queue: general');
    $m->follow_link( text => 'Ticket Custom Fields' );

    $m->title_is(q/Edit Custom Fields for General/, 'admin-queue: general cfid');
    $m->form_name('edit_custom_fields');

    # Sort by numeric IDs in names
    my @names = map  { $_->[1] }
                sort { $a->[0] <=> $b->[0] }
                map  { /object-1-CF-(\d+)/ ? [ $1 => $_ ] : () }
                grep defined, map $_->name, $m->current_form->inputs;
    $cf = pop(@names);
    $cf =~ /(\d+)$/ or die "Hey this is impossible dude";
    $cfid = $1;
    $m->field( $cf => 1 );         # Associate the new CF with this queue
    $m->field( $_ => undef ) for @names;    # ...and not any other. ;-)
    $m->submit;

    $m->content_like( qr/created/, 'TCF added to the queue' );

}

my $tester = RT::Test->load_or_create_user( name => 'tester', password => '123456' );
RT::Test->set_rights(
    { principal => $tester->principal,
      right => [qw(SeeQueue ShowTicket CreateTicket)],
    },
);
ok $m->login( $tester->name, 123456), 'logged in';

diag "check that we have no the CF on the create"
    ." ticket page when user has no SeeCustomField right"
        if $ENV{'TEST_VERBOSE'};
{
    $m->submit_form(
        form_name => "create_ticket_in_queue",
        fields => { queue => 'General' },
    );
    $m->content_unlike(qr/Upload multiple images/, 'has no upload image field');

    my $form = $m->form_name("ticket_create");

    ok !$form->find_input( "J:A:F-$cfid-$cf_moniker" ), 'no form field on the page';

    $m->submit_form(
        form_name => "ticket_create",
        fields => { subject => 'test' },
    );
    $m->content_like(qr/Created ticket #\d+/, "a ticket is Created succesfully");

    $m->content_unlike(qr/img:/, 'has no img field on the page');
    $m->follow_link( text => 'Custom Fields');
    $m->content_unlike(qr/Upload multiple images/, 'has no upload image field');
}

RT::Test->set_rights(
    { principal => $tester->principal,
      right => [qw(SeeQueue ShowTicket CreateTicket SeeCustomField)],
    },
);

diag "check that we have no the CF on the create"
    ." ticket page when user has no ModifyCustomField right"
        if $ENV{'TEST_VERBOSE'};
{
    $m->submit_form(
        form_name => "create_ticket_in_queue",
        fields => { queue => 'General' },
    );
    $m->content_unlike(qr/Upload multiple images/, 'has no upload image field');

    my $form = $m->form_name("ticket_create");
    ok !$form->find_input( "J:A:F-$cfid-$cf_moniker" ), 'no form field on the page';

    $m->submit_form(
        form_name => "ticket_create",
        fields => { subject => 'test' },
    );
    $tid = $1 if $m->content =~ /Created ticket #(\d+)/;
    ok $tid, "a ticket is Created succesfully";

    $m->follow_link( text => 'Custom Fields' );
    $m->content_unlike(qr/Upload multiple images/, 'has no upload image field');
    $form = $m->form_name('ticket_modify');
    ok !$form->find_input( "J:A:F-$cfid-$cf_moniker" ), 'no form field on the page';
}

RT::Test->set_rights(
    { principal => $tester->principal,
      right => [qw(SeeQueue ShowTicket CreateTicket SeeCustomField ModifyCustomField)],
    },
);

diag "create a ticket with an image" if $ENV{'TEST_VERBOSE'};
{
    $m->submit_form(
        form_name => "create_ticket_in_queue",
        fields => { queue => 'General' },
    );
    TODO: {
        local $TODO = "Multi-upload CFs not available yet";
        $m->content_like(qr/Upload multiple images/, 'has a upload image field');
    }

    $cfid =~ /(\d+)$/ or die "Hey this is impossible dude";
    $m->submit_form(
        form_name => "ticket_create",
        fields => {
            "J:A:F-$1-$cf_moniker" => ImageFile,
            subject => 'testing img cf creation',
        },
    );

    $m->content_like(qr/Created ticket #\d+/, "a ticket is Created succesfully");

    $tid = $1 if $m->content =~ /Created ticket #(\d+)/;

    TODO: {
        local $TODO = "Multi-upload CFs not available yet";
        $m->title_like(qr/testing img cf creation/, "its title is the subject");
    }

    $m->follow_link( text => 'bplogo.gif' );
    TODO: {
        local $TODO = "Multi-upload CFs not available yet";
        $m->content_is(ImageFileContent, "it links to the uploaded image");
    }
}

$m->get( $m->rt_base_url );
$m->follow_link( text => 'Tickets' );
$m->follow_link( text => 'New Query' );

$m->title_is(q/Query Builder/, 'Query building');
$m->submit_form(
    form_name => "build_query",
    fields => {
        id_op => '=',
        value_of_id => $tid,
        value_of_queue => 'General',
    },
    button => 'add_clause',
);

$m->form_name('build_query');

my $col = ($m->current_form->find_input('select_display_columns'))[-1];
$col->value( ($col->possible_values)[-1] );

$m->click('add_col');

$m->form_name('build_query');
$m->click('do_search');

$m->follow_link( text_regex => qr/bplogo\.gif/ );
TODO: {
    local $TODO = "Multi-upload CFs not available yet";
    $m->content_is(ImageFileContent, "it links to the uploaded image");
}

__END__
[FC] Bulk Update does not have custom fields.
