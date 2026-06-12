package Koha::Plugin::Com::CirriusImpact::API;

# This file is part of the CirriusImpact Koha plugin.
#
# Provides REST endpoints used by the remote CirriusImpact service to update
# the Koha-side status of an outbound notice after the plugin has SFTP'd the
# CSV payload. The plugin marks each transmitted row as 'transmitted'; the
# remote service then POSTs back to flip the status to 'inprogress', 'sent', or
# 'failed' once it knows delivery is underway or complete.

use Modern::Perl;

use Mojo::Base 'Mojolicious::Controller';

use Koha::Notice::Messages;
use C4::Context;

use Try::Tiny;

sub _resolve_message_for_status_update {
    my ($id) = @_;
    return unless defined $id && $id =~ /^\d+$/;

    my $message = Koha::Notice::Messages->find($id);
    return $message if $message;

    # Hold CSV rows put reserve_id in RequestID; CirriusImpact may call back with that id.
    my $dbh = C4::Context->dbh;
    return unless $dbh;

    for my $pattern (
        "%hold: $id%",
        "%hold:$id%",
        "%reserve_id: $id%",
        "%reserve_id:$id%",
    ) {
        my $sth = $dbh->prepare(q{
            SELECT message_id
              FROM message_queue
             WHERE status IN ('pending', 'transmitted', 'inprogress')
               AND content LIKE ?
             ORDER BY message_id DESC
             LIMIT 1
        });
        $sth->execute($pattern);
        my ($mid) = $sth->fetchrow_array;
        next unless $mid;
        $message = Koha::Notice::Messages->find($mid);
        return $message if $message;
    }

    return;
}

=head1 API

=head2 Class Methods

=head3 update_message_status

POST /api/v1/contrib/cirriusimpact/message/{message_id}/status

Updates the delivery status of an existing notice in Koha's C<message_queue>.
Accepted values for C<status>: C<sent>, C<inprogress>, C<failed>.

Use C<inprogress> (not C<pending>) when the notice file has been received and
delivery is underway. Setting C<pending> would cause Koha to re-queue the notice.

When C<failed> is supplied, the optional C<failure_code> query parameter is
written to C<message_queue.failure_code> if the running Koha version exposes
that accessor.

Optional C<subject> and C<content> query parameters overwrite the corresponding
fields on the message (useful when the remote service rendered a final body).

=cut

sub update_message_status {
    my $c = shift->openapi->valid_input or return;

    my $message_id   = $c->validation->param('message_id');
    my $status       = $c->validation->param('status');
    my $subject      = $c->validation->param('subject');
    my $content      = $c->validation->param('content');
    my $failure_code = $c->validation->param('failure_code');

    my $message = _resolve_message_for_status_update($message_id);
    unless ($message) {
        return $c->render(
            status  => 404,
            openapi => { error => "Message $message_id not found." }
        );
    }

    my %allowed = map { $_ => 1 } qw(sent inprogress failed);
    unless (defined $status && $allowed{$status}) {
        return $c->render(
            status  => 400,
            openapi => {
                error => "Invalid status value '" . ($status // '') . "'. "
                       . "Must be one of: 'sent', 'inprogress', 'failed'."
            }
        );
    }

    my $err;
    try {
        $message->status($status);
        $message->subject($subject) if defined $subject && length $subject && $message->can('subject');
        $message->content($content) if defined $content && length $content;
        if (defined $failure_code && length $failure_code && $message->can('failure_code')) {
            $message->failure_code($failure_code);
        }
        $message->store();
    } catch {
        $err = "Failed to update message " . $message->id . ": $_";
    };
    if ($err) {
        return $c->render(status => 500, openapi => { error => $err });
    }

    return $c->render(status => 204, text => q{});
}

=head3 update_message_content

POST /api/v1/contrib/cirriusimpact/message/{message_id}/content

Updates only the body (and optionally the subject) of an existing notice.
Useful when the remote rendering pipeline finalised the text after the
initial CSV was transmitted.

=cut

sub update_message_content {
    my $c = shift->openapi->valid_input or return;

    my $message_id = $c->validation->param('message_id');
    my $subject    = $c->validation->param('subject');
    my $content    = $c->validation->param('content');

    my $message = Koha::Notice::Messages->find($message_id);
    unless ($message) {
        return $c->render(
            status  => 404,
            openapi => { error => "Message $message_id not found." }
        );
    }

    unless (defined $content && length $content) {
        return $c->render(
            status  => 400,
            openapi => { error => "No message content provided" }
        );
    }

    my $err;
    try {
        $message->content($content);
        $message->subject($subject) if defined $subject && length $subject && $message->can('subject');
        $message->store();
    } catch {
        $err = "Failed to update message " . $message->id . ": $_";
    };
    if ($err) {
        return $c->render(status => 500, openapi => { error => $err });
    }

    return $c->render(status => 204, text => q{});
}

1;
