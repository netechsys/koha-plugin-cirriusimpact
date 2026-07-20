package Koha::Plugin::Com::CirriusImpact;

# Add plugins directory to @INC to ensure SMS::Send drivers can be found
BEGIN {
    use File::Basename;
    use Cwd qw(abs_path);
    # Get the plugins directory (parent of Koha/Plugin/Com/CirriusImpact)
    # File is at: plugins/Koha/Plugin/Com/CirriusImpact.pm
    # We need: plugins/
    my $plugin_file = __FILE__;
    my $plugin_dir = dirname(dirname(dirname(dirname(abs_path($plugin_file)))));
    # Add to @INC if not already present
    unshift @INC, $plugin_dir unless grep { $_ eq $plugin_dir } @INC;
}

use Modern::Perl;
use Koha::Database;
use Koha::Patrons;
use Koha::Libraries;

use Koha::Biblios;
use Koha::Items;
use Koha::Checkouts;
use Koha::Holds;
use Template;
use base qw(Koha::Plugins::Base);

use Koha::DateUtils qw(dt_from_string);
# use Koha::Issues;

use C4::Auth;
use C4::Context;
use C4::Log qw(logaction);
use Koha::DateUtils qw(dt_from_string);

use Data::Dumper;
use DateTime;
use File::Path qw(make_path);
use File::Slurp qw(write_file);
use File::Temp qw(tempdir);
use List::Util qw(any);
use Scalar::Util qw(blessed);
use Koha::Encryption;
use Koha::Logger;
use Mojo::JSON qw(encode_json decode_json);
use Net::SFTP::Foreign;
use POSIX;
use Try::Tiny;
use CGI qw(-utf8);
use YAML::XS qw(Load);

our $VERSION = "1.3.0-dev";
our $MINIMUM_VERSION = "24.05";

our $metadata = {
    name            => 'CI Management Services - CirriusImpact',
    author          => 'Terry Rossio',
    date_authored   => '2025-08-12',
    date_updated    => '2026-07-20',
    minimum_version => $MINIMUM_VERSION,
    maximum_version => undef,
    version         => $VERSION,
    description     => 'Plugin to forward messages to CirriusImpact for processing and sending',
};

our $instance = C4::Context->config('database'); $instance =~ s/koha_//;
our $default_archive_dir = $ENV{CirriusImpact_ARCHIVE_PATH} || "/var/lib/koha/$instance/CirriusImpact_archive";

sub _ci_render_tt {
    my ($s, $vars) = @_;
    return '' unless defined $s && length $s;
    my $tt = Template->new({ ENCODING => 'utf8' });
    my $out = '';
    $tt->process(\$s, $vars, \$out) or return '';
    return $out;
}

# Map Koha borrower/notice lang tags → CirriusImpact eng|spa|fre.
# Koha TranslateNotices uses IETF tags (es-ES, fr-CA); Notification Processor LANGUAGE_ALLOWED expects eng/spa/fre.
sub _ci_normalize_language {
    my ($raw) = @_;
    my $lang = defined $raw ? lc($raw) : '';
    $lang =~ s/^\s+|\s+$//g;
    return 'eng' if $lang eq '' || $lang eq 'default' || $lang eq 'eng' || $lang eq 'en' || $lang =~ /^en[-_]/;

    return 'spa' if $lang eq 'spa' || $lang eq 'es' || $lang eq 'spanish' || $lang =~ /^es[-_]/;
    return 'fre' if $lang eq 'fre' || $lang eq 'fra' || $lang eq 'fr' || $lang eq 'french' || $lang =~ /^fr[-_]/;

    # Unknown tag — pass through lowercased so TEXT_LANGUAGE_ALLOWED aliases can still match
    return $lang;
}

sub new {
    my ($class, $args) = @_;
    $args->{'metadata'}            = $metadata;
    $args->{'metadata'}->{'class'} = $class;
    my $self = $class->SUPER::new($args);
    return $self;
}

our $default_bootstrap_api_url = 'https://koha-bootstrap.cirriusimpact.com/v1/claim';

sub configure {
    my ($self, $args) = @_;
    my $cgi = $self->{'cgi'};

    my $claim_message;
    my $claim_error;

    if ( $cgi->param('claim') ) {
        my ( $ok, $msg ) = $self->_ci_claim_bootstrap($cgi);
        if ($ok) {
            $claim_message = $msg;
        } else {
            $claim_error = $msg;
        }
    }
    elsif ( $cgi->param('save') ) {
        $self->store_data({
            host                               => scalar $cgi->param('host'),
            username                           => scalar $cgi->param('username'),
            password                           => scalar $cgi->param('password'),
            archive_dir                        => scalar $cgi->param('archive_dir'),
            skip_odue_if_other_if_sms_or_email => scalar $cgi->param('skip_odue_if_other_if_sms_or_email'),
            enable_phone                       => scalar $cgi->param('enable_phone'),
            enable_sms                         => scalar $cgi->param('enable_sms'),
            enable_email                       => scalar $cgi->param('enable_email'),
            enable_whatsapp                    => scalar $cgi->param('enable_whatsapp'),
            include_messagetext                => scalar $cgi->param('include_messagetext'),
            production_data                    => scalar $cgi,
            section_order                      => scalar $cgi->param('section_order') || 'message_type,patron,items,call,sms,message',
            enabled_branches                   => $self->_ci_enabled_branches_from_cgi($cgi),
            bootstrap_api_url                  => scalar $cgi->param('bootstrap_api_url')
              || $self->retrieve_data('bootstrap_api_url')
              || $default_bootstrap_api_url,
            bootstrap_library_id               => scalar $cgi->param('bootstrap_library_id')
              || $self->retrieve_data('bootstrap_library_id'),
        });
        $self->go_home();
        return;
    }

    my $template = $self->get_template({ file => 'configure.tt' });
    $template->param(
        host                               => $self->retrieve_data('host'),
        username                           => $self->retrieve_data('username'),
        password                           => $self->retrieve_data('password'),
        archive_dir                        => $self->retrieve_data('archive_dir') || $default_archive_dir,
        skip_odue_if_other_if_sms_or_email => $self->retrieve_data('skip_odue_if_other_if_sms_or_email'),
        enable_phone                       => $self->retrieve_data('enable_phone'),
        enable_sms                         => $self->retrieve_data('enable_sms'),
        enable_email                       => $self->retrieve_data('enable_email'),
        enable_whatsapp                    => $self->retrieve_data('enable_whatsapp'),
        include_messagetext                => $self->retrieve_data('include_messagetext'),
        production_data                    => $self,
        section_order                      => $self->retrieve_data('section_order') || 'message_type,patron,items,call,sms,message',
        libraries                          => $self->_ci_libraries_for_configure,
        bootstrap_api_url                  => $self->retrieve_data('bootstrap_api_url') || $default_bootstrap_api_url,
        bootstrap_library_id               => $self->retrieve_data('bootstrap_library_id'),
        bootstrap_claimed_at               => $self->retrieve_data('bootstrap_claimed_at'),
        claim_message                      => $claim_message,
        claim_error                        => $claim_error,
    );
    $self->output_html($template->output());
}

# POST library_id + token to public bootstrap claim API; apply SFTP + features.
sub _ci_claim_bootstrap {
    my ( $self, $cgi ) = @_;

    my $api_url = scalar $cgi->param('bootstrap_api_url');
    $api_url = $api_url || $self->retrieve_data('bootstrap_api_url') || $default_bootstrap_api_url;
    $api_url =~ s/^\s+|\s+$//g;

    my $library_id = scalar $cgi->param('bootstrap_library_id');
    $library_id = $library_id // '';
    $library_id =~ s/^\s+|\s+$//g;

    my $token = scalar $cgi->param('bootstrap_token');
    $token = $token // '';
    $token =~ s/^\s+|\s+$//g;

    return ( 0, 'Bootstrap API URL is required.' ) unless length $api_url;
    return ( 0, 'Library ID is required.' )         unless length $library_id;
    return ( 0, 'Install token is required.' )      unless length $token;

    # Persist URL + library id even if claim fails (operator convenience)
    $self->store_data({
        bootstrap_api_url    => $api_url,
        bootstrap_library_id => $library_id,
    });

    my $payload = encode_json({
        library_id => $library_id,
        token      => $token,
    });

    my ( $code, $body, $err ) = $self->_ci_http_post_json( $api_url, $payload );
    if ($err) {
        return ( 0, "Claim request failed: $err" );
    }
    if ( !defined $code || $code !~ /^\d+$/ ) {
        return ( 0, 'Claim request failed: no HTTP status' );
    }
    if ( $code == 401 ) {
        return ( 0, 'Invalid or expired install token.' );
    }
    if ( $code == 429 ) {
        return ( 0, 'Too many claim attempts; try again later.' );
    }
    if ( $code < 200 || $code >= 300 ) {
        my $detail = '';
        try {
            my $j = decode_json( $body // '{}' );
            $detail = $j->{error} if ref($j) eq 'HASH' && $j->{error};
        } catch { };
        return ( 0, "Claim failed (HTTP $code)" . ( $detail ? ": $detail" : '' ) );
    }

    my $data;
    my $json_err;
    try {
        $data = decode_json( $body // '{}' );
    } catch {
        $json_err = $_;
    };
    return ( 0, 'Claim response was not valid JSON.' )
      if $json_err || ref($data) ne 'HASH';

    my $host = $data->{host} // '';
    my $user = $data->{username} // '';
    return ( 0, 'Claim response missing host or username.' )
      unless length($host) && length($user);

    my $now = POSIX::strftime( '%Y-%m-%d %H:%M:%S', gmtime() );
    $self->store_data({
        host                 => $host,
        username             => $user,
        password             => defined $data->{password} ? $data->{password} : '',
        enable_sms           => $data->{enable_sms}           ? 1 : 0,
        enable_phone         => $data->{enable_phone}         ? 1 : 0,
        enable_email         => $data->{enable_email}         ? 1 : 0,
        enable_whatsapp      => $data->{enable_whatsapp}      ? 1 : 0,
        include_messagetext  => $data->{include_messagetext}  ? 1 : 0,
        bootstrap_api_url    => $api_url,
        bootstrap_library_id => $data->{library_id} || $library_id,
        bootstrap_claimed_at => $now,
    });

    return ( 1, "Claim successful for library '" . ( $data->{library_id} || $library_id ) . "'. Connection and features updated." );
}

sub _ci_http_post_json {
    my ( $self, $url, $json_body ) = @_;

    try {
        require HTTP::Tiny;
        my $http = HTTP::Tiny->new(
            timeout         => 30,
            verify_SSL      => 1,
            default_headers => {
                'Content-Type' => 'application/json',
                'Accept'       => 'application/json',
            },
        );
        my $res = $http->request(
            'POST', $url,
            { content => $json_body }
        );
        return ( $res->{status}, $res->{content}, undef );
    } catch {
        my $http_tiny_err = $_;
        try {
            require LWP::UserAgent;
            require HTTP::Request;
            my $ua = LWP::UserAgent->new( timeout => 30, agent => 'CirriusImpact-Koha-Plugin/1.3' );
            my $req = HTTP::Request->new( POST => $url );
            $req->header( 'Content-Type' => 'application/json' );
            $req->header( 'Accept'       => 'application/json' );
            $req->content($json_body);
            my $res = $ua->request($req);
            return ( $res->code, $res->decoded_content, undef );
        } catch {
            return ( undef, undef, "HTTP client unavailable ($http_tiny_err / $_)" );
        };
    };
}

# List Koha libraries for Configure checkboxes (branchcode, branchname, enabled).
# Missing / "*" enabled_branches = all checked (no filter). Empty string = none checked.
sub _ci_libraries_for_configure {
    my ($self) = @_;
    my $raw = $self->retrieve_data('enabled_branches');
    my $all_mode = !defined $raw || $raw eq '*';
    my %selected;
    if ( !$all_mode && defined $raw && $raw ne '' ) {
        %selected = map { $_ => 1 } grep { length } split /\s*,\s*/, $raw;
    }

    my @libraries;
    try {
        my $rs = Koha::Libraries->search( {}, { order_by => ['branchname'] } );
        while ( my $lib = $rs->next ) {
            my $code = $lib->branchcode // next;
            push @libraries, {
                branchcode => $code,
                branchname => $lib->branchname // $code,
                enabled    => $all_mode ? 1 : ( $selected{$code} ? 1 : 0 ),
            };
        }
    } catch {
        warn "CirriusImpact: failed to load libraries for configure: $_\n";
    };
    return \@libraries;
}

# Persist Configure branch selection.
# "*" = all branches (no filter; new libraries included automatically).
# ""  = no branches enabled (export nothing).
# "A,B" = only those branchcodes.
sub _ci_enabled_branches_from_cgi {
    my ( $self, $cgi ) = @_;
    my @selected = $cgi->can('multi_param')
        ? $cgi->multi_param('enabled_branches')
        : $cgi->param('enabled_branches');
    @selected = grep { defined && length } @selected;

    my @all_codes;
    try {
        my $rs = Koha::Libraries->search( {}, { order_by => ['branchcode'] } );
        while ( my $lib = $rs->next ) {
            push @all_codes, $lib->branchcode if $lib->branchcode;
        }
    } catch { };

    return '' unless @selected;
    return '*' if @all_codes && @selected == @all_codes;

    my %want = map { $_ => 1 } @selected;
    if (@all_codes) {
        my $missing = grep { !$want{$_} } @all_codes;
        return '*' unless $missing;
    }
    return join( ',', @selected );
}

# Patron home branch filter for before_send_messages / CSV (matches CSV branch field).
# Never configured or "*" => allow all. Empty => allow none.
sub _ci_branch_enabled {
    my ( $self, $branchcode ) = @_;
    my $raw = $self->retrieve_data('enabled_branches');
    return 1 unless defined $raw;
    return 1 if $raw eq '*';
    return 0 if $raw eq '';
    return 0 unless defined $branchcode && length $branchcode;
    my %set = map { $_ => 1 } grep { length } split /\s*,\s*/, $raw;
    return $set{$branchcode} ? 1 : 0;
}

sub install {
    my ($self, $args) = @_;
    return $self->_ensure_message_status_values();
}

sub upgrade {
    my ($self, $args) = @_;
    return $self->_ensure_message_status_values();
}

sub uninstall { return 1; }

=head2 _ensure_message_status_values

Ensures the C<message_queue.status> ENUM column accepts plugin-specific values:

=over 4

=item C<'transmitted'> — set by the plugin when a notice is written into the outbound CSV.

=item C<'inprogress'> — set by the remote CirriusImpact service via the REST API when
the notice file has been received and delivery is underway. Using C<'inprogress'>
instead of C<'pending'> prevents Koha from re-queuing the notice for another pickup.

=back

The remote service may also set C<'sent'> or C<'failed'> via the REST API once final
delivery is known.

Idempotent: appends only missing values. Existing ENUM values are preserved.

=cut

sub _ensure_message_status_values {
    my ($self) = @_;

    my @required = qw(transmitted inprogress);

    my $log = eval { Koha::Logger->get({ interace => 'plugin', category => 'CirriusImpact', prefix => 0 }) };

    my $dbh = eval { C4::Context->dbh };
    unless ($dbh) {
        warn "CirriusImpact: no database handle available, skipping message_queue.status ENUM check\n";
        return 1;
    }

    my $col_info = eval {
        $dbh->selectrow_hashref(q{
            SELECT COLUMN_TYPE
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'message_queue'
              AND COLUMN_NAME = 'status'
        });
    };
    if ($@ || !$col_info || !$col_info->{COLUMN_TYPE}) {
        warn "CirriusImpact: could not introspect message_queue.status column ($@)\n" if $@;
        return 1;
    }

    my $type = $col_info->{COLUMN_TYPE};

    unless ($type =~ /^enum\((.*)\)\s*$/i) {
        warn "CirriusImpact: unexpected message_queue.status column type '$type', skipping ALTER\n";
        return 1;
    }
    my $values = $1;

    my @missing;
    for my $req (@required) {
        push @missing, $req unless $values =~ /'$req'/i;
    }
    if (!@missing) {
        $log && $log->info("CirriusImpact install/upgrade: message_queue.status already allows all plugin values");
        return 1;
    }

    my $new_values = $values;
    for my $m (@missing) {
        $new_values .= qq{,'$m'};
    }

    # Default 'pending' matches the schema shipped with Koha.
    my $sql = "ALTER TABLE message_queue MODIFY COLUMN status ENUM($new_values) NOT NULL DEFAULT 'pending'";

    eval { $dbh->do($sql) };
    if ($@) {
        my $msg = "CirriusImpact: failed to extend message_queue.status ENUM (@missing): $@";
        warn "$msg\n";
        $log && $log->error($msg);
        return 0;
    }

    $log && $log->info("CirriusImpact install/upgrade: extended message_queue.status ENUM to include: " . join(', ', @missing));
    return 1;
}

# --- Encrypted plugin configuration (all data in plugin_data is encrypted at rest)

=head2 _encrypt_plugin_value

Encrypts a scalar value for storage in plugin_data using Koha::Encryption (AES-256).
Used so that all plugin configuration written to the database is encrypted.

=cut

sub _encrypt_plugin_value {
    my ( $self, $value ) = @_;
    return '' if !defined $value;
    $value = '' if ref($value);    # e.g. CGI object passed as scalar
    my $str = length($value) ? $value : '';
    return '' if $str eq '';
    try {
        my $cipher = Koha::Encryption->new;
        return $cipher->encrypt_hex($str);
    } catch {
        return $str;              # fallback to plain if encryption fails
    };
}

=head2 _decrypt_plugin_value

Decrypts a value from plugin_data. Returns the original string if decryption
fails (backward compatibility with existing unencrypted data).

=cut

sub _decrypt_plugin_value {
    my ( $self, $raw ) = @_;
    return undef if !defined $raw;
    return '' if $raw eq '';
    try {
        my $cipher = Koha::Encryption->new;
        my $decrypted = $cipher->decrypt_hex($raw);
        return defined $decrypted ? $decrypted : $raw;
    } catch {
        return $raw;              # not encrypted or invalid
    };
}

=head2 store_data

Override: encrypt every value before storing so all plugin configuration is encrypted at rest.

=cut

sub store_data {
    my ( $self, $data ) = @_;
    return unless ref($data) eq 'HASH';
    my %encrypted;
    for my $key ( keys %$data ) {
        my $v = $data->{$key};
        $encrypted{$key} = $self->_encrypt_plugin_value($v);
    }
    $self->SUPER::store_data( \%encrypted );
}

=head2 retrieve_data

Override: decrypt values when reading. If called with no key, returns a hash of all
plugin key => decrypted value for this plugin.

=cut

sub retrieve_data {
    my ( $self, $key ) = @_;
    if ( !defined $key || $key eq '' ) {
        my $dbh = C4::Context->dbh;
        my $sql = "SELECT plugin_key, plugin_value FROM plugin_data WHERE plugin_class = ?";
        my $sth = $dbh->prepare($sql);
        $sth->execute( $self->{'class'} );
        my %all;
        while ( my $row = $sth->fetchrow_hashref() ) {
            $all{ $row->{'plugin_key'} } = $self->_decrypt_plugin_value( $row->{'plugin_value'} );
        }
        return \%all;
    }
    my $raw = $self->SUPER::retrieve_data($key);
    return $raw if !defined $raw;
    return $self->_decrypt_plugin_value($raw);
}

sub scrub_biblio  { my ($self,$b) = @_; delete $b->{abstract}; return $b; }
sub scrub_patron  { my ($self,$p) = @_; delete $p->{password}; delete $p->{borrowernotes}; return $p; }
sub scrub_message { my ($self,$m) = @_; delete $m->{content}; delete $m->{metadata}; return $m; }

# --- Token rendering: supports {{ var.path }} and [% var.path %]; preserves literal if unresolved
sub _resolve_path {
    my ($self, $path, $ctx) = @_;
    return undef unless defined $path && ref($ctx) eq 'HASH';
    $path =~ s/^\s+|\s+$//g;
    my @parts = split /\./, $path;
    my $cur = $ctx;
    for my $p (@parts) {
        if (ref($cur) eq 'ARRAY' && $p =~ /^\d+$/) {
            $cur = $cur->[$p];
        } elsif (ref($cur) eq 'HASH') {
            $cur = $cur->{$p};
        } else {
            return undef;
        }
        return undef unless defined $cur;
    }
    return (ref($cur)) ? undef : $cur;
}

sub _render_tpl {
    my ($self, $tpl, $ctx) = @_;
    return undef unless defined $tpl;
    $tpl =~ s/\{\{\s*([^}}]+?)\s*\}\}/
        my $val = $self->_resolve_path($1,$ctx); defined $val ? $val : "{{ $1 }}";
    /ge;
    $tpl =~ s/\[\%\s*([^%\]]+?)\s*\%\]/
        my $val = $self->_resolve_path($1,$ctx); defined $val ? $val : "[% $1 %]";
    /ge;
    return $tpl;
}



# Expand Koha-style << path >> placeholders too
# and provide a wrapper that can merge YAML-derived maps
sub _expand_template {
    my ($self, $tpl, $data, $yaml) = @_;
    return '' unless defined $tpl;
    my %ctx = ();
    if (ref($data) eq 'HASH') { %ctx = (%ctx, %$data); }
    if (ref($yaml) eq 'HASH') { $ctx{yaml} = $yaml; }
    # Reuse _render_tpl but extend it to also handle << >>
    $tpl =~ s/<<\s*([^>]+?)\s*>>/
        my $val = $self->_resolve_path($1, \%ctx); defined $val ? $val : "<<$1>>";
    /ge;
    return $self->_render_tpl($tpl, \%ctx);
}
# Recursively render any structure (scalar/array/hash) with TT context
sub _render_any {
    my ($self, $value, $ctx) = @_;
    my $ref = ref $value || '';
    if (!$ref) {
        my $r = $self->_render_tpl($value, $ctx);
        return defined $r ? $r : $value;
    } elsif ($ref eq 'ARRAY') {
        return [ map { $self->_render_any($_, $ctx) } @$value ];
    } elsif ($ref eq 'HASH') {
        my %out;
        for my $k (keys %$value) {
            $out{$k} = $self->_render_any($value->{$k}, $ctx);
        }
        return \%out;
    } else {
        return $value;
    }
}

# Koha sometimes stores CirriusImpact notice YAML on one line (invalid for YAML::XS).
# Re-break known keys onto separate lines before parsing.
sub _normalize_cirriusimpact_yaml_content {
    my ($content) = @_;
    return $content unless defined $content && $content =~ /\S/;
    return $content if $content =~ /\n/;
    return $content unless $content =~ /^\s*---\s+CirriusImpact:/;

    my $body = $content;
    $body =~ s/^\s*---\s*//;
    $body =~ s/\s*---\s*$//;
    $body =~ s/\s+(patron|hold|holds|sms|call|email|whatsapp):/\n$1:/g;
    $body =~ s/(sms|call|email|whatsapp):\s*(text|script|body|subject|reference|to):/$1:\n  $2:/g;
    return "---\n$body\n---\n";
}

sub _recover_inline_cirriusimpact_yaml {
    my ($content) = @_;
    return undef unless defined $content && $content =~ /CirriusImpact:\s*yes/i;

    my %doc = ( CirriusImpact => 'yes' );
    if ($content =~ /\bhold:\s*(\d+)/) {
        $doc{hold} = $1;
    }
    if ($content =~ /\bpatron:\s*(\d+)/) {
        $doc{patron} = $1;
    }
    if ($content =~ /\bsms:\s*text:\s*"((?:[^"\\]|\\.)*)"/s) {
        my $text = $1;
        $text =~ s/\\"/"/g;
        $doc{sms} = { text => $text };
    }
    if ($content =~ /\bcall:\s*script:\s*"((?:[^"\\]|\\.)*)"/s) {
        my $script = $1;
        $script =~ s/\\"/"/g;
        $doc{call} = { script => $script };
    }
    return \%doc if $doc{hold} || $doc{sms} || $doc{call};
    return undef;
}

sub _load_cirriusimpact_yaml_documents {
    my ($self, $content, $log, $message_id) = @_;
    $content = _normalize_cirriusimpact_yaml_content($content);

    my @yamls;
    my $parse_error;
    try { @yamls = Load $content; }
    catch { $parse_error = "$_"; @yamls = (); };

    @yamls = grep { ref($_) eq 'HASH' } @yamls;

    if (!@yamls) {
        my $recovered = _recover_inline_cirriusimpact_yaml($content);
        if ($recovered) {
            $log->warn(
                "CirriusImpact message $message_id: YAML parse failed; recovered sms/call/hold from inline content"
                . ($parse_error ? " ($parse_error)" : '')
            );
            push @yamls, $recovered;
        } elsif ($parse_error) {
            $log->error("CirriusImpact message $message_id: YAML parse failed: $parse_error");
        }
    }

    return @yamls;
}

sub _ci_notice_context_fields {
    my ($data) = @_;
    my $brname = $data->{library}->{branchname} // $data->{sms}->{branchname}
        // $data->{call}->{branchname} // '';
    my $fname  = $data->{patron}->{firstname} // $data->{sms}->{patronFirstName}
        // $data->{call}->{patronFirstName} // '';
    my $phone  = $data->{library}->{branchphone} // $data->{library}->{phone}
        // $data->{sms}->{phone} // '';
    my $title  = $data->{sms}->{title} // $data->{call}->{title} // '';
    return ($brname, $fname, $phone, $title);
}

sub _ci_sms_fallback_message {
    my ($self, $letter_code, $data) = @_;
    my ($brname, $fname, $phone, $title) = _ci_notice_context_fields($data);
    $brname ||= 'Your Library';
    $fname  ||= 'Patron';
    $title  ||= 'your item';
    my $lc = uc($letter_code || '');

    if ($lc =~ /^HOLD/) {
        return sprintf(
            '[%s] %s, Your hold for %s is available for pickup. Please pick up at %s. Questions? Call %s.',
            $brname, $fname, $title, $brname, ($phone || '')
        );
    }
    if ($lc =~ /^ODUE|^DUE/) {
        return sprintf(
            '[%s] %s, You have item(s) that are now overdue: %s. Please return them to %s. Questions? Call %s.',
            $brname, $fname, $title, $brname, ($phone || '')
        );
    }
    if ($lc =~ /^PREDUE/) {
        return sprintf(
            '[%s] %s, You have item(s) due soon: %s. Please return them to %s. Questions? Call %s.',
            $brname, $fname, $title, $brname, ($phone || '')
        );
    }
    if ($lc eq 'CHECKOUT') {
        return sprintf('[%s] %s, Thank you for checking out: %s.', $brname, $fname, $title);
    }
    if ($lc eq 'CHECKIN') {
        return sprintf('[%s] %s, Thank you for returning: %s.', $brname, $fname, $title);
    }
    return sprintf(
        '[%s] %s, Library notice regarding: %s. Questions? Call %s.',
        $brname, $fname, $title, ($phone || '')
    );
}

sub _ci_call_fallback_message {
    my ($self, $letter_code, $data) = @_;
    my ($brname, $fname, $phone, $title) = _ci_notice_context_fields($data);
    $brname ||= 'your library';
    $fname  ||= 'Patron';
    $title  ||= 'your item';
    my $lc = uc($letter_code || '');

    if ($lc =~ /^HOLD/) {
        return sprintf(
            'Hello %s. %s. Your hold is ready for pickup. Title: %s. Call %s for help.',
            $fname, $brname, $title, ($phone || $brname)
        );
    }
    if ($lc =~ /^ODUE|^DUE/) {
        return sprintf(
            'Hello %s. %s. You have overdue items. Title: %s. Please return them soon. Call %s.',
            $fname, $brname, $title, ($phone || $brname)
        );
    }
    if ($lc =~ /^PREDUE/) {
        return sprintf(
            'Hello %s. %s. You have items due soon. Title: %s. Call %s.',
            $fname, $brname, $title, ($phone || $brname)
        );
    }
    return sprintf(
        'Hello %s. %s. Library notice. Title: %s. Call %s.',
        $fname, $brname, $title, ($phone || $brname)
    );
}

sub _ci_apply_transport_fallback_text {
    my ($self, $data, $letter_code, $transport) = @_;
    my ($brname, $fname, $phone, $title) = _ci_notice_context_fields($data);
    $letter_code ||= $data->{message_type}->{letter_code} // '';

    if ($transport eq 'sms') {
        return if defined $data->{sms}->{text} && $data->{sms}->{text} ne '';

        my $tpl = $self->_get_notice_template($letter_code, 'sms');
        if ($tpl) {
            my $rendered = $self->_render_notice_template($tpl, $data);
            if (defined $rendered && $rendered ne '') {
                $data->{sms}->{text} = $rendered;
                return;
            }
        }

        my $fallback = $self->_ci_sms_fallback_message($letter_code, $data);
        $data->{sms}->{text} = $self->_ci_insert_title_into_text($fallback, $title);
        return;
    }

    if ($transport eq 'phone') {
        $data->{call} //= {};
        return if defined $data->{call}->{script} && $data->{call}->{script} ne '';

        my $tpl = $self->_get_notice_template($letter_code, 'phone');
        if ($tpl) {
            my $rendered = $self->_render_notice_template($tpl, $data);
            if (defined $rendered && $rendered ne '') {
                $data->{call}->{script} = $rendered;
                return;
            }
        }

        my $fallback = $self->_ci_call_fallback_message($letter_code, $data);
        $data->{call}->{script} = $self->_ci_insert_title_into_text($fallback, $title);
    }
}

# Generate CSV output from message data
sub _generate_csv_output {
    my ($self, $message_data) = @_;
    
    my $log = Koha::Logger->get({ interace => 'plugin', category => 'CirriusImpact', prefix => 0 });
    
    # HOLDDGST digest grouping: Group individual HOLDDGST messages by patron and transport
    $log->info("Starting HOLDDGST digest grouping with " . scalar @$message_data . " messages");
    my @grouped_message_data;
    my %holddgst_groups;
    
    # First pass: group HOLDDGST messages by patron and transport
    for my $msg (@$message_data) {
        my $mt = $msg->{message_type} || {};
        my $letter_code = $mt->{letter_code} || '';
        
        if ($letter_code eq 'HOLDDGST') {
            $log->info("Processing HOLDDGST message for digest grouping");
            # Debug: show message structure
            $log->info("Message structure keys: " . join(', ', keys %$msg));
            if ($msg->{sms}) { $log->info("SMS keys: " . join(', ', keys %{$msg->{sms}})); }
            if ($msg->{call}) { $log->info("Call keys: " . join(', ', keys %{$msg->{call}})); }
            
            # Find the transport section with data
            my $transport = '';
            my $patron_id = '';
            
            if ($mt->{sms} && $mt->{sms}->{PatronID}) {
                $transport = 'sms';
                $patron_id = $mt->{sms}->{PatronID};
                $log->info("Found SMS transport for patron $patron_id");
            } elsif ($mt->{call} && $mt->{call}->{PatronID}) {
                $transport = 'phone';
                $patron_id = $mt->{call}->{PatronID};
                $log->info("Found Phone transport for patron $patron_id");
            } elsif ($mt->{email} && $mt->{email}->{PatronID}) {
                $transport = 'email';
                $patron_id = $mt->{email}->{PatronID};
                $log->info("Found Email transport for patron $patron_id");
            }
            
            if ($patron_id && $transport) {
                my $key = $patron_id . '_' . $transport;
                push @{$holddgst_groups{$key}}, $msg;
                $log->info("Added HOLDDGST message to group: $key");
            } else {
                # If we can't determine patron/transport, keep as individual message
                $log->info("Could not determine patron/transport for HOLDDGST message, keeping as individual");
                push @grouped_message_data, $msg;
            }
        } else {
            # Non-HOLDDGST messages go through unchanged
            push @grouped_message_data, $msg;
        }
    }
    
    # Second pass: create digest messages for grouped HOLDDGST messages
    for my $key (keys %holddgst_groups) {
        my @group = @{$holddgst_groups{$key}};
        
        # Helper function to extract titles and dates from a message
        my $extract_titles_dates = sub {
            my ($msg) = @_;
            my @titles;
            my @dates;
            my $mt = $msg->{message_type} || {};
            
            # Check all transport sections for titles
            TRANSPORT: for my $transport (qw(sms call email whatsapp)) {
                if ($mt->{$transport}) {
                    my $section = $mt->{$transport};
                    # First, check if title_list is already populated (from backfill)
                    if ($section->{title_list} && ref($section->{title_list}) eq 'ARRAY' && @{$section->{title_list}}) {
                        # Use title_list directly - dedupe and add
                        my %seen;
                        for my $t (@{$section->{title_list}}) {
                            push @titles, $t if defined $t && $t ne '' && !$seen{$t}++;
                        }
                        if ($section->{date_list} && ref($section->{date_list}) eq 'ARRAY') {
                            my %seen;
                            for my $d (@{$section->{date_list}}) {
                                push @dates, $d if defined $d && $d ne '' && !$seen{$d}++;
                            }
                        } elsif ($section->{date} && $section->{date} ne '') {
                            push @dates, $section->{date};
                        }
                        next TRANSPORT; # Skip text extraction if we have title_list
                    }
                    
                    # Fallback: extract from explicit title field
                    my $explicit_title = $section->{title} || '';
                    if ($explicit_title) {
                        # Check if title already contains multiple titles (semicolon-separated)
                        if ($explicit_title =~ /;/) {
                            my @split_titles = split(/\s*;\s*/, $explicit_title);
                            my %seen;
                            for my $t (@split_titles) {
                                $t =~ s/^\s+|\s+$//g;
                                push @titles, $t if $t ne '' && !$seen{$t}++;
                            }
                        } else {
                            push @titles, $explicit_title if $explicit_title ne '';
                        }
                    }
                    
                    # Also collect dates
                    push @dates, $section->{date} if $section->{date} && $section->{date} ne '';
                }
            }
            
            return (\@titles, \@dates);
        };
        
        if (@group == 1) {
            # Single message - but still need to ensure title and messageText are correct
            my $msg = $group[0];
            my ($titles_ref, $dates_ref) = $extract_titles_dates->($msg);
            my @titles = @$titles_ref;
            my @dates = @$dates_ref;
            
            # Dedupe
            my %seen_title;
            @titles = grep { defined $_ && $_ ne '' && !$seen_title{$_}++ } @titles;
            my %seen_date;
            @dates = grep { defined $_ && $_ ne '' && !$seen_date{$_}++ } @dates;
            
            if (@titles > 1) {
                # Multiple titles - update title field but preserve template content from Koha
                my $combined_title = join('; ', @titles);
                my $mt = $msg->{message_type} || {};
                
                # Also extract and combine itemsID_list if present
                my @items_ids;
                for my $transport (qw(sms call email whatsapp)) {
                    if ($mt->{$transport} && $mt->{$transport}->{itemsID_list} && ref($mt->{$transport}->{itemsID_list}) eq 'ARRAY') {
                        my %seen;
                        for my $id (@{$mt->{$transport}->{itemsID_list}}) {
                            push @items_ids, $id if defined $id && $id ne '' && !$seen{$id}++;
                        }
                        last; # Use first transport section found
                    }
                }
                my $combined_itemsID = @items_ids > 1 ? join('; ', @items_ids) : (@items_ids ? $items_ids[0] : '');
                
                # Update title and itemsID fields, but preserve template text from Koha
                for my $transport (qw(sms call email whatsapp)) {
                    if ($mt->{$transport}) {
                        my $section = $mt->{$transport};
                        $section->{title} = $combined_title;
                        if ($combined_itemsID) {
                            $section->{itemsID} = $combined_itemsID;
                        }
                        # DO NOT override text/script/body - use template content from Koha
                    }
                }
            }
            
            push @grouped_message_data, $msg;
        } else {
            # Multiple messages, create digest
            my $digest_msg = { %{$group[0]} };  # Start with first message
            
            # Combine titles and dates from all messages
            my @titles;
            my @dates;
            for my $msg (@group) {
                my ($titles_ref, $dates_ref) = $extract_titles_dates->($msg);
                push @titles, @$titles_ref;
                push @dates, @$dates_ref;
            }
            
            # Dedupe while preserving order
            my %seen_title;
            @titles = grep { defined $_ && $_ ne '' && !$seen_title{$_}++ } @titles;
            my %seen_date;
            @dates = grep { defined $_ && $_ ne '' && !$seen_date{$_}++ } @dates;

            # Update the digest message with combined titles and rebuild message text
            # Koha creates separate messages per hold, so we need to rebuild the text for multiple holds
            my $combined_title = join('; ', @titles);
            my $digest_mt = $digest_msg->{message_type} || {};
            my $count = scalar @titles;
            
            # Get the first date (soonest pickup date)
            my $first_date = '';
            if (@dates) {
                my @filtered = grep { defined && $_ ne '' } @dates;
                $first_date = $filtered[0] // '';
            }
            # Convert date to US format (m/d/y) for messageText
            my $us_date = $self->_format_date_us($first_date);
            
            # Get branch info from first message - check multiple sources
            my $branchname = '';
            my $branchphone = '';
            if ($digest_msg->{library} && ref($digest_msg->{library}) eq 'HASH') {
                $branchname = $digest_msg->{library}->{name} || $digest_msg->{library}->{branchname} || '';
                $branchphone = $digest_msg->{library}->{phone} || $digest_msg->{library}->{branchphone} || '';
            }
            # Also check transport sections for branch info
            if (!$branchname && $digest_mt->{sms}) {
                $branchname = $digest_mt->{sms}->{branchname} || $digest_mt->{sms}->{branch} || '';
            }
            if (!$branchname && $digest_mt->{call}) {
                $branchname = $digest_mt->{call}->{branchname} || $digest_mt->{call}->{branch} || '';
            }
            if (!$branchphone && $digest_mt->{call}) {
                $branchphone = $digest_mt->{call}->{branchphone} || '';
            }
            # If still no branchname, try to get from any message in the group
            if (!$branchname) {
                for my $msg (@group) {
                    my $mt = $msg->{message_type} || {};
                    if ($mt->{call} && $mt->{call}->{branchname}) {
                        $branchname = $mt->{call}->{branchname};
                        last;
                    } elsif ($mt->{sms} && $mt->{sms}->{branchname}) {
                        $branchname = $mt->{sms}->{branchname};
                        last;
                    }
                }
            }
            
            # Get patron firstname
            my $firstname = '';
            if ($digest_msg->{patron} && ref($digest_msg->{patron}) eq 'HASH') {
                $firstname = $digest_msg->{patron}->{firstname} || '';
            }
            if (!$firstname && $digest_mt->{call}) {
                $firstname = $digest_mt->{call}->{patronFirstName} || '';
            }
            
            # Try to fetch and re-render template from Koha, otherwise fall back to hardcoded format
            # This ensures template updates in Koha are reflected in digest messages
            my $sms_template = $self->_get_notice_template('HOLDDGST', 'sms');
            my $call_template = $self->_get_notice_template('HOLDDGST', 'phone');
            
            # Build combined holds data for template rendering
            my @combined_holds;
            for my $msg (@group) {
                if ($msg->{holds} && ref($msg->{holds}) eq 'ARRAY') {
                    push @combined_holds, @{$msg->{holds}};
                }
            }
            
            # Update SMS text - use template if available, otherwise hardcoded format
            if ($digest_mt->{sms}) {
                $digest_mt->{sms}->{title} = $combined_title;
                if ($sms_template && @combined_holds) {
                    # Re-render template with combined holds data
                    my $template_data = {
                        branch => $digest_msg->{library} || {},
                        borrower => $digest_msg->{patron} || {},
                        holds => \@combined_holds,
                        biblio => $combined_holds[0]->{biblio} || {},
                        hold => $combined_holds[0]->{hold} || {},
                    };
                    $digest_mt->{sms}->{text} = $self->_render_notice_template($sms_template, $template_data);
                } else {
                    # Fallback to hardcoded format matching template structure
                    if ($count > 1) {
                        my $title_list = join('; ', @titles);
                        $digest_mt->{sms}->{text} = sprintf(
                            "%s: You have %d holds ready for pickup: %s. Pickup by %s.",
                            $branchname || 'Library',
                            $count,
                            $title_list,
                            $us_date || $first_date
                        );
                    } else {
                        $digest_mt->{sms}->{text} = sprintf(
                            "%s: Hold ready: %s. Pickup by %s.",
                            $branchname || 'Library',
                            $combined_title,
                            $us_date || $first_date
                        );
                    }
                }
            }
            
            # Update call script - use template if available, otherwise hardcoded format
            if ($digest_mt->{call}) {
                $digest_mt->{call}->{title} = $combined_title;
                if ($call_template && @combined_holds) {
                    # Re-render template with combined holds data
                    # Build data structure matching Koha's template expectations
                    my $template_data = {
                        branch => {
                            %{$digest_msg->{library} || {}},
                            branchname => $branchname,
                            branchphone => $branchphone,
                        },
                        borrower => {
                            %{$digest_msg->{patron} || {}},
                            firstname => $firstname,
                        },
                        holds => \@combined_holds,
                        biblio => $combined_holds[0]->{biblio} || {},
                        hold => $combined_holds[0]->{hold} || {},
                    };
                    my $rendered = $self->_render_notice_template($call_template, $template_data);
                    if ($rendered && $rendered ne '') {
                        $digest_mt->{call}->{script} = $rendered;
                        $log->info("HOLDDGST digest: Used template for call script");
                    } else {
                        $log->info("HOLDDGST digest: Template rendering failed, using fallback");
                        # Fall through to hardcoded format
                        goto FALLBACK_CALL;
                    }
                } else {
                    $log->info("HOLDDGST digest: Template not found (call_template=" . ($call_template ? "found" : "not found") . ", holds=" . scalar(@combined_holds) . "), using fallback");
                    FALLBACK_CALL:
                    # Fallback to hardcoded format matching template structure
                    if ($count > 1) {
                        my $title_list = join(', ', @titles);
                        # Match template format: "Hello [name]. You have [count] holds ready for pickup: [titles] at [branch]. Please pickup by [date]. Call [phone]."
                        $digest_mt->{call}->{script} = sprintf(
                            "Hello %s. You have %d holds ready for pickup: %s at %s. Please pickup by %s. Call %s.",
                            $firstname || 'Patron',
                            $count,
                            $title_list,
                            $branchname || 'Library',
                            $us_date || $first_date,
                            $branchphone || ''
                        );
                    } else {
                        $digest_mt->{call}->{script} = sprintf(
                            "Hello %s. a hold ready for pickup: %s at %s. Please pickup by %s. Call %s.",
                            $firstname || 'Patron',
                            $combined_title,
                            $branchname || 'Library',
                            $us_date || $first_date,
                            $branchphone || ''
                        );
                    }
                }
            } elsif ($digest_msg->{library} && ref($digest_msg->{library}) eq 'HASH' && $count > 1) {
                # If call section missing but library data available, create it
                my $library = $digest_msg->{library};
                my $title_list = join(', ', @titles);
                $digest_mt->{call} = {
                    patronFirstName => $digest_msg->{patron}->{firstname} || 'Patron',
                    branchname      => $library->{name} || $library->{branchname} || 'Library',
                    branchphone     => $library->{phone} || $library->{branchphone} || '',
                    script          => sprintf(
                        "Hello %s. You have %d holds ready for pickup: %s. Pickup by %s. Call %s.",
                        $digest_msg->{patron}->{firstname} || 'Patron',
                        $count,
                        $title_list,
                        $us_date || $first_date,
                        ($library->{phone} || $library->{branchphone}) || ''
                    ),
                };
            }
            
            # Update email body if present
            if ($digest_mt->{email}) {
                $digest_mt->{email}->{title} = $combined_title;
                # Email body can stay as-is from template or be updated similarly if needed
            }
            
            push @grouped_message_data, $digest_msg;
            $log->info("Created HOLDDGST digest for $key with " . scalar @group . " messages, titles: $combined_title");
        }
    }
    
    # Use grouped messages for CSV generation
    $message_data = \@grouped_message_data;
    
    # Define the required CSV headers in the exact order requested
    # messageText conditionally added at the end for message content
    my @headers = qw(
        commType language notificationType notificationLevel patronBarCode 
        STAB_userSalutation patronFirstName patronLastName phone email 
        LibraryCode branch branchname itemsID date title DeliveryOptionID LanguageID 
        NotificationTypeID ReportingOrgID PatronID ItemRecordID RequestID 
        PickupAreaDescription TxnID AccountBalance kohaNotificationType
    );
    
    # Add messageText column if enabled in configuration
    if ($self->retrieve_data('include_messagetext')) {
        push @headers, 'messageText';
    }
    
    my @csv_lines;
    push @csv_lines, join(',', @headers);
    
    # Process each message
    for my $message (@$message_data) {
        # Extract data from the nested structure - data is under message_type
        my $message_type = $message->{message_type} || {};
        
        # Find the actual transport section that has data (sms, call, email, whatsapp)
        my $transport_section = undef;
        my $transport = '';
        my $commType = '';
        my $original_transport = $message_type->{transport} || '';
        
        # Skip print transport messages - they're not supported by CirriusImpact
        if ($original_transport eq 'print') {
            next;
        }
        
        # Check which transport section has meaningful data (patron data fields)
        if ($message_type->{sms} && ref($message_type->{sms}) eq 'HASH' && 
            ($message_type->{sms}->{PatronID} || $message_type->{sms}->{patronFirstName} || $message_type->{sms}->{patronBarCode})) {
            $transport_section = $message_type->{sms};
            $transport = 'sms';
            $commType = 'T';
        } elsif ($message_type->{call} && ref($message_type->{call}) eq 'HASH' && 
            ($message_type->{call}->{PatronID} || $message_type->{call}->{patronFirstName} || $message_type->{call}->{patronBarCode})) {
            $transport_section = $message_type->{call};
            $transport = 'phone';
            $commType = 'V';
        } elsif ($message_type->{email} && ref($message_type->{email}) eq 'HASH' && 
            ($message_type->{email}->{PatronID} || $message_type->{email}->{patronFirstName} || $message_type->{email}->{patronBarCode})) {
            $transport_section = $message_type->{email};
            $transport = 'email';
            $commType = 'E';
        } elsif ($message_type->{whatsapp} && ref($message_type->{whatsapp}) eq 'HASH' && 
            ($message_type->{whatsapp}->{PatronID} || $message_type->{whatsapp}->{patronFirstName} || $message_type->{whatsapp}->{patronBarCode})) {
            $transport_section = $message_type->{whatsapp};
            $transport = 'whatsapp';
            $commType = 'W';
        }
        
        # Skip if no transport section found
        next unless $transport_section;
        
        # Build row data from the transport section
        my %row_data;
        $row_data{commType} = $commType;
        $row_data{language} = _ci_normalize_language($transport_section->{language});
        # Get notification type and level from configurable mapping
        my $letter_code = $transport_section->{meta}->{letter_code} || $message_type->{letter_code} || '';
        my $notification_info = $self->_get_notification_type_and_level($letter_code);
        $row_data{notificationType} = $notification_info->{type} || '';
        $row_data{notificationLevel} = $notification_info->{level} || '';
        $row_data{patronBarCode} = $transport_section->{patronBarCode} || '';
        $row_data{STAB_userSalutation} = $transport_section->{STAB_userSaluation} || '';
        $row_data{patronFirstName} = $transport_section->{patronFirstName} || '';
        $row_data{patronLastName} = $transport_section->{patronLastName} || '';
        $row_data{phone} = $transport_section->{phone} || '';
        $row_data{email} = $transport_section->{email} || '';
        $row_data{LibraryCode} = $transport_section->{branch} || '';
        $row_data{branch} = $transport_section->{branch} || '';
        $row_data{branchname} = $transport_section->{branchname} || '';
        $row_data{itemsID} = $transport_section->{itemsID} || '';
        $row_data{date} = $self->_format_date($transport_section->{date} || '');
        $row_data{title} = $transport_section->{title} || '';
        $row_data{DeliveryOptionID} = $transport_section->{DeliveryOptionID} || '';
        $row_data{LanguageID} = $transport_section->{LanguageID} || '';
        $row_data{NotificationTypeID} = $transport_section->{NotificationTypeID} || '';
        $row_data{ReportingOrgID} = $transport_section->{ReportingOrgID} || '';
        $row_data{PatronID} = $transport_section->{PatronID} || '';
        $row_data{ItemRecordID} = $transport_section->{ItemRecordID} || '';
        $row_data{RequestID} = $transport_section->{RequestID} || '';
        $row_data{PickupAreaDescription} = $transport_section->{PickupAreaDescription} || '';
        my $mq_id = $message_type->{message_id} || '';
        $row_data{TxnID} = (defined $transport_section->{TxnID} && $transport_section->{TxnID} ne '')
            ? $transport_section->{TxnID}
            : $mq_id;
        $row_data{AccountBalance} = $transport_section->{AccountBalance} || '';
        # kohaNotificationType is the Koha letter code (moved to end)
        $row_data{kohaNotificationType} = $letter_code;
        
        # Add message text based on transport type (if enabled in configuration)
        if ($self->retrieve_data('include_messagetext')) {
            my $message_text = '';
            if ($transport eq 'sms') {
                $message_text = $transport_section->{text} || '';
            } elsif ($transport eq 'phone') {
                $message_text = $transport_section->{script} || '';
            } elsif ($transport eq 'email') {
                $message_text = $transport_section->{body} || $transport_section->{subject} || '';
            } elsif ($transport eq 'whatsapp') {
                $message_text = $transport_section->{text} || '';
            }
            # Convert dates in messageText to US format (m/d/y)
            $message_text = $self->_convert_dates_in_text_to_us_format($message_text);
            $row_data{messageText} = $message_text;
        }
        
        # Create CSV row
        my @row_values;
        for my $header (@headers) {
            my $value = $row_data{$header} || '';
            # Escape CSV values (handle commas and quotes)
            if ($value =~ /[,"\n\r]/) {
                $value =~ s/"/""/g;  # Escape quotes
                $value = "\"$value\"";  # Wrap in quotes
            }
            push @row_values, $value;
        }
        push @csv_lines, join(',', @row_values);
    }
    
    return join("\n", @csv_lines) . "\n";
}

sub before_send_messages {
    my ($self, $params) = @_;

    my $is_cronjob = $0 =~ /process_message_queue\.pl$/;
    logaction('CirriusImpact', 'STARTED', undef, undef, 'cron') if $is_cronjob;

    if (ref($params->{type}) eq 'ARRAY' && grep(/^skip_CirriusImpact$/, @{ $params->{type} })) {
        logaction('CirriusImpact', 'SKIPPED', undef, undef, 'cron') if $is_cronjob;
        return;
    }

    my $test_mode = $ENV{CirriusImpact_TEST_MODE};
    my $verbose   = $ENV{CirriusImpact_VERBOSE} || $params->{verbose};

    my $library_name = C4::Context->preference('LibraryName') // '';
    (my $libname_sane = $library_name) =~ s/ /_/g;
    my $dir      = tempdir(CLEANUP => 0);
    my $ts       = strftime("%Y-%m-%dT%H-%M-%S", gmtime(time()));
    my $filename = "$ts-Notices-$libname_sane.csv";
    my $realpath = "$dir/$filename";

    my $archive_dir = $self->retrieve_data('archive_dir') || $default_archive_dir;
    my $info        = {
        archive_dir  => $archive_dir,
        test_mode    => $test_mode,
        library_name => $libname_sane,
        timestamp    => $ts,
        filename     => $filename,
        filepath     => $realpath,
    };

    # Create archive directory
    if ($archive_dir && !-d $archive_dir) { 
        make_path($archive_dir, { mode => 0755 }) or die "Failed to create archive directory: $archive_dir - $!"; 
    }

    # Log4Perl example:
    # log4perl.logger.plugin.CirriusImpact = WARN, CIRRIUSIMPACT
    # log4perl.appender.CIRRIUSIMPACT=Log::Log4perl::Appender::File
    # log4perl.appender.CIRRIUSIMPACT.filename=/var/log/koha/kohadev/cirriusimpact.log
    # log4perl.appender.CIRRIUSIMPACT.mode=append
    # log4perl.appender.CIRRIUSIMPACT.layout=PatternLayout
    # log4perl.appender.CIRRIUSIMPACT.layout.ConversionPattern=[%d] [%p] %m%n
    # log4perl.appender.CIRRIUSIMPACT.utf8=1
    my $log = Koha::Logger->get({ interace => 'plugin', category => 'CirriusImpact', prefix => 0 });
    
    $log->info("Running CirriusImpact before_send_messages hook");

    my $search_params = { status => 'pending', 
    content => { -like => '%CirriusImpact: yes%'},
    '-or' => [
        { letter_code => { -in => _odue_codes() } },
        { letter_code => { -in => _hold_codes() } },
        { letter_code => { -in => _predue_codes() } },
        { letter_code => { -in => _circulation_codes() } },
        { letter_code => { -in => _renewal_codes() } },
        { letter_code => { -in => _membership_codes() } },
    ]};
    my $other_params  = {};
    $other_params->{rows} = $params->{limit} if $params->{limit};

    $log->info("SEARCH PARAMETERS: " . Data::Dumper::Dumper($search_params));
    $log->info("OTHER PARAMETERS: " . Data::Dumper::Dumper($other_params));

    my @message_data;
    while (1) {
        my @messages = Koha::Notice::Messages->search($search_params, $other_params)->as_list;
        $log->info("FOUND " . scalar @messages . " MESSAGES TO PROCESS");
        last unless @messages;

        # Leave notices for disabled branches as pending (do not claim/delete).
        # Filter uses patron home branchcode — same value exported in CSV branch.
        my @to_process;
        for my $m (@messages) {
            my $branchcode = '';
            try {
                my $patron = Koha::Patrons->find( $m->borrowernumber );
                $branchcode = $patron->branchcode // '' if $patron;
            } catch { };
            if ( $self->_ci_branch_enabled($branchcode) ) {
                push @to_process, $m;
            } else {
                $log->info(
                    "Leaving message "
                      . $m->id
                      . " pending — home branch '$branchcode' not enabled for CirriusImpact"
                );
            }
        }
        last unless @to_process;
        $log->info( "PROCESSING " . scalar(@to_process) . " MESSAGES AFTER BRANCH FILTER" );

        unless ($test_mode) { $_->update({ status => 'deleted' }) for @to_process; }

        for my $m (@to_process) {
            $log->info("WORKING ON MESSAGE " . $m->id);
            my $content = $m->content // '';

            # Fix invalid YAML separators: replace ------ with ---
            # Koha sometimes concatenates multiple notices with ------
            $content =~ s/------/---/g;

            my @yamls = $self->_load_cirriusimpact_yaml_documents($content, $log, $m->id);

            @yamls = ({ 'CirriusImpact' => 'yes' }) unless @yamls;

            my $yaml_doc_index = 0;
            for my $yaml (@yamls) {
                next unless ref($yaml) eq 'HASH' && ($yaml->{CirriusImpact} // '') eq 'yes';

                my $data = {};
                $data->{message_type} = {
                    letter_code => $m->letter_code,
                    message_id  => $m->id,
                    yaml_doc_index => $yaml_doc_index,  # Track which YAML doc this is
                    time_queued => $m->time_queued,
                    transport   => $m->message_transport_type,
                };
                $yaml_doc_index++;
                $data->{message} = $self->scrub_message($m->unblessed);

                my $patron;
                try {
                    if ($yaml->{patron}) { $patron = Koha::Patrons->find($yaml->{patron}); }
                    else { $patron = Koha::Patrons->find($m->borrowernumber); }
                    $data->{patron} = $self->scrub_patron($patron->unblessed) if $patron;
                } catch { };

                # Holds (for titles/pickup library)
                if ($yaml->{hold}) {
                    my $hold = Koha::Holds->find($yaml->{hold});
                    _add_hold($self, $data, $hold);
                }
                if ($yaml->{holds}) {
                    my @ids = split /,/, $yaml->{holds};
                    for my $hid (@ids) { my $hold = Koha::Holds->find($hid); _add_hold($self, $data, $hold); }
                }

                # Library context (for phone/name)
                unless ($data->{library}) {
                    try {
                        if ($patron && $patron->branchcode) {
                            my $lib = Koha::Libraries->find($patron->branchcode);
                            if ($lib) {
                                my $raw = $lib->unblessed;
                                $data->{library} = { %$raw, name => $raw->{branchname}, code => $raw->{branchcode}, phone => $raw->{branchphone} };
                            }
                        } else {
                            $data->{library} = { name => $library_name };
                        }
                    } catch { };
                }

                my $ctx = { %$data, message_id => $m->id };

                my $enable_sms   = $self->retrieve_data('enable_sms')   ? 1 : 0;
                my $enable_phone = $self->retrieve_data('enable_phone') ? 1 : 0;
                my $enable_email = $self->retrieve_data('enable_email') ? 1 : 0;
                my $enable_whatsapp = $self->retrieve_data('enable_whatsapp') ? 1 : 0;
                
                my $transport = lc($m->message_transport_type // '');

                my $yaml_has_sms  = (defined $yaml->{sms_text} || defined $yaml->{sms_to_numbers} || defined $yaml->{sms_to} || defined $yaml->{sms_reference} || (ref($yaml->{sms})||'') eq 'HASH');
                my $yaml_has_call = (defined $yaml->{call_script} || defined $yaml->{call_to_numbers} || defined $yaml->{call_to} || defined $yaml->{call_reference} || (ref($yaml->{call})||'') eq 'HASH');
                my $yaml_has_email = (defined $yaml->{email_subject} || defined $yaml->{email_to} || (ref($yaml->{email})||'') eq 'HASH');
                my $yaml_has_whatsapp = (defined $yaml->{whatsapp_text} || defined $yaml->{whatsapp_to} || (ref($yaml->{whatsapp})||'') eq 'HASH');

                # Process all message types - removed transport filtering
                # ---- SMS (nested or flat)
                if ($transport eq 'sms' || $yaml_has_sms) {

        # meta (ensure letter_code/message_id are present from message_type)
        my $letter_code = $data->{message_type}->{letter_code};
        my $message_id  = $data->{message_type}->{message_id};
        $data->{sms}->{meta} = {
            letter_code => $letter_code,
            message_id  => $message_id,
        };

        # Support WhatsApp as an alternate SMS-style section
        my $using_whatsapp = 0;
        my $wh_map  = (ref($yaml->{whatsapp}) eq 'HASH') ? $yaml->{whatsapp} : {};
        my $sms_map = (ref($yaml->{sms})       eq 'HASH') ? $yaml->{sms}       : {};
        my $map     = (keys %$wh_map) ? do { $using_whatsapp = 1; $wh_map } : $sms_map;

        # Inputs (flat overrides take precedence over nested map)
        my $sms_text_in = defined $yaml->{sms_text}      ? $yaml->{sms_text}      : $map->{text};
        my $sms_ref_in  = defined $yaml->{sms_reference} ? $yaml->{sms_reference} : $map->{reference};
        my $sms_to_in   = defined $yaml->{sms_to}        ? $yaml->{sms_to}        : ($map->{to_numbers} // $map->{to});

        # --- text
        if (defined $sms_text_in && $sms_text_in ne '') {
            $data->{sms}->{text} = $self->_expand_template($sms_text_in, $data, $yaml);
        } else {
            $data->{sms}->{text} = '';
        }

        # --- reference
        if (defined $sms_ref_in && $sms_ref_in ne '') {
            $data->{sms}->{reference} = $self->_expand_template($sms_ref_in, $data, $yaml);
        } else {
            $data->{sms}->{reference} = '';
        }

        # --- recipients
        my @to_numbers = ();
        if (defined $sms_to_in && $sms_to_in ne '') {
            my $expanded = $self->_expand_template($sms_to_in, $data, $yaml);
            @to_numbers = grep { $_ ne '' } split(/\s*,\s*|\s+/, $expanded);
        } else {
            # default fallback: patron smsalertnumber then phone
            push @to_numbers, grep { $_ && $_ ne '' } (
                $data->{patron}->{smsalertnumber},
                $data->{patron}->{phone}
            );
        }
        $data->{sms}->{to_numbers} = \@to_numbers;
       # --- Ensure unique recipients (dedupe to_numbers)
if (ref $data->{sms}->{to_numbers} eq 'ARRAY') {
    my %seen;
    my @uniq = grep { !$seen{$_}++ } @{ $data->{sms}->{to_numbers} };
    $data->{sms}->{to_numbers} = \@uniq;
}

# --- Backfill ODUE, CHECKOUT, CHECKIN, PREDUE, and additional message types IDs/title/date if YAML couldn't provide them
eval { $self->_ci_backfill_odue_identifiers($data) };
eval { $self->_ci_backfill_checkout_identifiers($data) };
eval { $self->_ci_backfill_checkin_identifiers($data) };
eval { $self->_ci_backfill_predue_identifiers($data) };
eval { $self->_ci_backfill_additional_identifiers($data) };

# --- Fill SMS text if still blank (letter-aware fallback; ODUE wording only for overdue notices)
$self->_ci_apply_transport_fallback_text(
    $data, $data->{message_type}->{letter_code} // $m->letter_code, 'sms'
);

        # ---- Merge additional keys from YAML 'sms' into $data->{sms}
        # We already handled text/reference/to/to_numbers above, so skip those
        if (ref($yaml->{sms}) eq 'HASH') {
            my $sms_map = $yaml->{sms};
            my %rendered;
            for my $k (keys %{$sms_map}) {
                next if $k =~ /^(text|reference|to|to_numbers)$/;  # already handled
                my $val = $sms_map->{$k};
                # Render scalar templates (ignore nested structures here)
                if (!ref($val)) {
                    my $out = eval { $self->_expand_template($val, $data, $yaml) };
                    $out = $val if $@;  # fall back to raw if rendering fails
                    $rendered{$k} = $out;
                }
            }
            # Non-destructive merge (don't clobber anything already set)
            for my $k (keys %rendered) {
                $data->{sms}{$k} = $rendered{$k} if !defined $data->{sms}{$k};
            }
        }

        # ---- With IDs merged, try to enrich/fill title from Koha
        # (_ci_fill_titles should safely no-op if nothing to fill)
        if ($self->can('_ci_fill_titles')) {
            eval { $self->_ci_fill_titles($data) };
        }
        # ---- Merge additional flat export fields into the active transport (here: SMS/WhatsApp)
        {
            my $msgt = $data->{message_type} || {};
            my $pat  = $data->{patron}       || {};
            my $lib  = $data->{library}      || {};
            my $hold0   = (ref($data->{holds}) eq 'ARRAY' && @{$data->{holds}}) ? $data->{holds}->[0] : undef;
            my $h_hold  = ($hold0 && ref($hold0->{hold})   eq 'HASH') ? $hold0->{hold}   : {};
            my $h_biblio= ($hold0 && ref($hold0->{biblio}) eq 'HASH') ? $hold0->{biblio} : {};

            my $transport = lc($msgt->{transport} // '');
            my $letter_code = $msgt->{letter_code} || '';
	    # With IDs merged (or not), make sure ODUE, CHECKOUT, CHECKIN, PREDUE, and additional message types have identifiers + title/date
		eval { $self->_ci_backfill_odue_identifiers($data) };
		eval { $self->_ci_backfill_checkout_identifiers($data) };
		eval { $self->_ci_backfill_checkin_identifiers($data) };
		eval { $self->_ci_backfill_predue_identifiers($data) };
		eval { $self->_ci_backfill_additional_identifiers($data) };
    
            my $commType  = $transport eq 'phone' ? 'V'
                          : $transport eq 'email' ? 'E'
                          : $transport eq 'sms'   ? 'T'
                          : '';
            $commType = 'W' if $using_whatsapp;

            my %mf = (
                msgid              => defined $h_hold->{reserve_id}       ? $h_hold->{reserve_id}       : '',
                commType           => $commType,
                language           => _ci_normalize_language($pat->{lang}),
                # Get notification type and level from configurable mapping
                notificationType   => $self->_get_notification_type_and_level($msgt->{letter_code})->{type} || '',
                notificationLevel  => $self->_get_notification_type_and_level($msgt->{letter_code})->{level} || '',
                patronBarCode      => defined $pat->{cardnumber}          ? $pat->{cardnumber}          : '',
                STAB_userSaluation => _get_patron_title($pat),
                patronFirstName    => defined $pat->{firstname}           ? $pat->{firstname}           : '',
                patronLastName     => defined $pat->{surname}             ? $pat->{surname}             : '',
                phone              => defined $pat->{smsalertnumber}      ? $pat->{smsalertnumber}      : '',
                email              => defined $pat->{email}               ? $pat->{email}               : '',
                branch             => defined $lib->{code}                ? $lib->{code}                : '',
                branchname         => defined $lib->{name}                ? $lib->{name}                : '',
                itemsID            => defined $h_hold->{itemnumber}       ? $h_hold->{itemnumber}       : '',
                biblionumber       => defined $h_hold->{biblionumber}     ? $h_hold->{biblionumber}     : '',
                date               => $self->_format_date(defined $h_hold->{notificationdate} ? $h_hold->{notificationdate} : ''),
                title              => defined $h_biblio->{title}          ? $h_biblio->{title}          : '',
                DeliveryOptionID   => '',
                LanguageID         => '',
                NotificationTypeID => '',
                ReportingOrgID     => '',
                PatronID           => defined $pat->{borrowernumber}      ? $pat->{borrowernumber}      : '',
                ItemRecordID       => '',
                RequestID          => defined $h_hold->{reserve_id}       ? $h_hold->{reserve_id}       : '',
                PickupAreaDescription => '',
                # TxnID carries message_queue.message_id for CirriusImpact status callbacks (RequestID may be reserve_id).
                TxnID              => defined $data->{message_type}->{message_id} ? $data->{message_type}->{message_id} : '',
                AccountBalance     => '',
                # kohaNotificationType is the Koha letter code (moved to end)
                kohaNotificationType => defined $msgt->{letter_code}        ? $msgt->{letter_code}        : '',
            );
            
            use Data::Dumper;
            warn "CI SMS after merge: " . Dumper($data->{sms});

            while (my ($k,$v) = each %mf) {
                # Replace undefined OR empty string values
                $data->{sms}->{$k} = $v if (!defined $data->{sms}->{$k} || $data->{sms}->{$k} eq '');
            }
            
            # Debug: Show SMS data after merge
            warn "CI SMS FINAL: " . Dumper($data->{sms}) if $data->{sms};
        }

        # ---- If WhatsApp YAML was used, move populated SMS struct under 'whatsapp' and remove 'sms' (strict)
        if ($using_whatsapp) {
            $data->{whatsapp} //= {};
            for my $k (keys %{ $data->{sms} || {} }) {
                $data->{whatsapp}->{$k} = $data->{sms}->{$k} if !exists $data->{whatsapp}->{$k};
            }
            delete $data->{sms};
        }
    }

                # ---- CALL (nested or flat)
                if ($transport eq 'phone' || $yaml_has_call) {
                    $data->{call} //= {};
                    $data->{call}->{meta} //= { letter_code => $m->letter_code, message_id => $m->id };

                    my $call_map = (eval { ref($yaml->{call}) eq 'HASH' } ) ? $yaml->{call} : {};
                    my $call_script_in = defined $yaml->{call_script} ? $yaml->{call_script} : $call_map->{script};
                    my $call_ref_in    = defined $yaml->{call_reference} ? $yaml->{call_reference} : $call_map->{reference};
                    my $call_to_in     = defined $yaml->{call_to_numbers} ? $yaml->{call_to_numbers} : (defined $yaml->{call_to} ? $yaml->{call_to} : $call_map->{to_numbers});

                    if (defined $call_script_in) {
                        my $rendered = $self->_render_tpl($call_script_in, $ctx);
                        $data->{call}->{script} = defined $rendered ? $rendered : $call_script_in;
                    } else {
                        $data->{call}->{script} //= '';
                    }

                    if (defined $call_ref_in) {
                        my $rendered = $self->_render_tpl($call_ref_in, $ctx);
                        $data->{call}->{reference} = defined $rendered ? $rendered : $call_ref_in;
                    } else {
                        $data->{call}->{reference} //= '';
                    }

                    if (defined $call_to_in) {
                        my $rendered = $self->_render_tpl($call_to_in, $ctx);
                        $data->{call}->{to_numbers} = defined $rendered ? $rendered : $call_to_in;
                        # Also store in phone field for CSV compatibility
                        $data->{call}->{phone} = $data->{call}->{to_numbers};
                    
                    # Merge any additional fields under call:
                    my $rendered_call_map = eval { $self->_render_any($call_map, $ctx) } // $call_map;
                    for my $k (keys %$rendered_call_map) {
                        next if $k =~ /^(script|reference|to_numbers)$/;
                        $data->{call}->{$k} = $rendered_call_map->{$k};
                    }
                } else {
                        $data->{call}->{to_numbers} //= ($patron && $patron->phone) ? [ $patron->phone ] : [];
                    }
                    
                    # Backfill CALL section data after it's created
                    eval { $self->_ci_backfill_odue_identifiers($data) };
                    eval { $self->_ci_backfill_checkout_identifiers($data) };
                    eval { $self->_ci_backfill_checkin_identifiers($data) };
                    eval { $self->_ci_backfill_predue_identifiers($data) };
                    eval { $self->_ci_backfill_additional_identifiers($data) };
                    $self->_ci_apply_transport_fallback_text(
                        $data, $data->{message_type}->{letter_code} // $m->letter_code, 'phone'
                    );
                }

                # ---- EMAIL (nested or flat)
                if ($transport eq 'email' || $yaml_has_email) {
                    $data->{email} //= {};
                    $data->{email}->{meta} //= { letter_code => $m->letter_code, message_id => $m->id };

                    my $email_map = (eval { ref($yaml->{email}) eq 'HASH' } ) ? $yaml->{email} : {};
                    my $email_subject_in = defined $yaml->{email_subject} ? $yaml->{email_subject} : $email_map->{subject};
                    my $email_to_in = defined $yaml->{email_to} ? $yaml->{email_to} : $email_map->{to};
                    my $email_body_in = defined $yaml->{email_body} ? $yaml->{email_body} : $email_map->{body};

                    if (defined $email_subject_in) {
                        my $rendered = $self->_render_tpl($email_subject_in, $ctx);
                        $data->{email}->{subject} = defined $rendered ? $rendered : $email_subject_in;
                    } else {
                        $data->{email}->{subject} //= '';
                    }

                    if (defined $email_to_in) {
                        $data->{email}->{to} = $self->_render_tpl($email_to_in, $ctx);
                    } else {
                        $data->{email}->{to} //= ($patron && $patron->email) ? $patron->email : '';
                    }

                    if (defined $email_body_in) {
                        my $rendered = $self->_render_tpl($email_body_in, $ctx);
                        $data->{email}->{body} = defined $rendered ? $rendered : $email_body_in;
                    } else {
                        $data->{email}->{body} //= '';
                    }

                    # Merge any additional fields under email:
                    my $rendered_email_map = eval { $self->_render_any($email_map, $ctx) } // $email_map;
                    for my $k (keys %$rendered_email_map) {
                        next if $k =~ /^(subject|to|body)$/;
                        $data->{email}->{$k} = $rendered_email_map->{$k};
                    }
                    
                    # Backfill EMAIL section data after it's created
                    eval { $self->_ci_backfill_odue_identifiers($data) };
                    eval { $self->_ci_backfill_checkout_identifiers($data) };
                    eval { $self->_ci_backfill_checkin_identifiers($data) };
                    eval { $self->_ci_backfill_predue_identifiers($data) };
                    eval { $self->_ci_backfill_additional_identifiers($data) };
                }

                # ---- WHATSAPP (nested or flat)
                if ($transport eq 'whatsapp' || $yaml_has_whatsapp) {
                    $data->{whatsapp} //= {};
                    $data->{whatsapp}->{meta} //= { letter_code => $m->letter_code, message_id => $m->id };

                    my $whatsapp_map = (eval { ref($yaml->{whatsapp}) eq 'HASH' } ) ? $yaml->{whatsapp} : {};
                    my $whatsapp_text_in = defined $yaml->{whatsapp_text} ? $yaml->{whatsapp_text} : $whatsapp_map->{text};
                    my $whatsapp_to_in = defined $yaml->{whatsapp_to} ? $yaml->{whatsapp_to} : $whatsapp_map->{to};

                    if (defined $whatsapp_text_in) {
                        my $rendered = $self->_render_tpl($whatsapp_text_in, $ctx);
                        $data->{whatsapp}->{text} = defined $rendered ? $rendered : $whatsapp_text_in;
                    } else {
                        $data->{whatsapp}->{text} //= '';
                    }

                    if (defined $whatsapp_to_in) {
                        $data->{whatsapp}->{to} = $self->_render_tpl($whatsapp_to_in, $ctx);
                    } else {
                        $data->{whatsapp}->{to} //= ($patron && $patron->smsalertnumber) ? $patron->smsalertnumber : '';
                    }

                    # Merge any additional fields under whatsapp:
                    my $rendered_whatsapp_map = eval { $self->_render_any($whatsapp_map, $ctx) } // $whatsapp_map;
                    for my $k (keys %$rendered_whatsapp_map) {
                        next if $k =~ /^(text|to)$/;
                        $data->{whatsapp}->{$k} = $rendered_whatsapp_map->{$k};
                    }
                    
                    # Backfill WHATSAPP section data after it's created
                    eval { $self->_ci_backfill_odue_identifiers($data) };
                    eval { $self->_ci_backfill_checkout_identifiers($data) };
                    eval { $self->_ci_backfill_checkin_identifiers($data) };
                    eval { $self->_ci_backfill_predue_identifiers($data) };
                    eval { $self->_ci_backfill_additional_identifiers($data) };
                }

                # ODUE suppression: skip phone if patron has SMS or Email (config-gated)
                # Check for all ODUE variants (ODUE, ODUE2, ODUE3, etc.)
                # This must happen AFTER all transport sections are created
                my $check_letter_code = $data->{message_type}->{letter_code} || ($data->{call} && $data->{call}->{meta} && $data->{call}->{meta}->{letter_code}) || '';
                if (($transport||'') eq 'phone' && ($check_letter_code||'') =~ /^ODUE/) {
                    my $pid = $data->{PatronID} || ($data->{call} && $data->{call}->{PatronID}) || ($data->{sms} && $data->{sms}->{PatronID});
                    if ($self->_ci_should_suppress_phone_for_odue($pid)) {
                        delete $data->{call};
                        $log->info("ODUE suppression: Deleted phone call for patron $pid (has SMS or Email)");
                    }
                }

                # Order sections
                
                # ---- Additional flat export fields (JSON) ----
                # Build a flattened "export_fields" block as requested.
                my $mf = {};

                # Helpers to read from nested structs safely
                my $pat  = $data->{patron} || {};
                my $lib  = $data->{library} || {};
                my $msgt = $data->{message_type} || {};
                my $hold0 = do {
                    my $h;
                    if (ref($data->{holds}) eq 'ARRAY' && @{$data->{holds}}) { $h = $data->{holds}->[0]; }
                    $h;
                };
                my $h_hold   = ($hold0 && ref($hold0->{hold})   eq 'HASH') ? $hold0->{hold}   : {};
                my $h_biblio = ($hold0 && ref($hold0->{biblio}) eq 'HASH') ? $hold0->{biblio} : {};

                # commType mapping: V=phone, E=email, T=sms
                my $commType  = $transport eq 'phone' ? 'V' :
                                $transport eq 'email' ? 'E' :
                                $transport eq 'sms'   ? 'T' : '';

                $mf->{msgid}              = defined $h_hold->{reserve_id}       ? $h_hold->{reserve_id}       : '';
                $mf->{commType}           = $commType;
                $mf->{language}           = _ci_normalize_language($pat->{lang});
                # Get notification type and level from configurable mapping
                $mf->{notificationType}   = $self->_get_notification_type_and_level($msgt->{letter_code})->{type} || '';
                $mf->{notificationLevel}  = $self->_get_notification_type_and_level($msgt->{letter_code})->{level} || '';

                $mf->{patronBarCode}      = defined $pat->{cardnumber}          ? $pat->{cardnumber}          : '';
                $mf->{STAB_userSaluation} = _get_patron_title($pat);
                $mf->{patronFirstName}    = defined $pat->{firstname}           ? $pat->{firstname}           : '';
                $mf->{patronLastName}     = defined $pat->{surname}             ? $pat->{surname}             : '';
                # Use appropriate phone field based on transport type
                $mf->{phone}              = $transport eq 'phone' 
                                            ? (defined $pat->{phone} ? $pat->{phone} : (defined $pat->{smsalertnumber} ? $pat->{smsalertnumber} : ''))
                                            : (defined $pat->{smsalertnumber} ? $pat->{smsalertnumber} : (defined $pat->{phone} ? $pat->{phone} : ''));
                $mf->{email}              = defined $pat->{email}               ? $pat->{email}               : '';

                $mf->{branch}             = defined $lib->{code}                ? $lib->{code}                : '';
                $mf->{branchname}         = defined $lib->{name}                ? $lib->{name}                : '';

                $mf->{itemsID}            = defined $h_hold->{biblionumber}     ? $h_hold->{biblionumber}     : '';
                $mf->{date}               = $self->_format_date(defined $h_hold->{notificationdate} ? $h_hold->{notificationdate} : '');
                $mf->{title}              = defined $h_biblio->{title}          ? $h_biblio->{title}          : '';

                $mf->{DeliveryOptionID}   = '';
                $mf->{LanguageID}         = '';
                # Get notification type from configurable mapping
                $mf->{NotificationTypeID} = $self->_get_notification_type_and_level($msgt->{letter_code})->{type} || '';
                $mf->{ReportingOrgID}     = '';

                $mf->{PatronID}           = defined $pat->{borrowernumber}      ? $pat->{borrowernumber}      : '';
                $mf->{ItemRecordID}       = '';
                $mf->{RequestID}          = defined $h_hold->{reserve_id}       ? $h_hold->{reserve_id}       : '';
                $mf->{TxnID}              = defined $data->{message_type}->{message_id} ? $data->{message_type}->{message_id} : '';

                
# Merge into the transport section so it appears in-order without changing section_order
my $is_phone_transport = ($transport || '') eq 'phone';
my $is_sms_transport = ($transport || '') eq 'sms';
my $is_email_transport = ($transport || '') eq 'email';
my $is_whatsapp_transport = ($transport || '') eq 'whatsapp';
my $target = $is_phone_transport ? 'call' : ($is_sms_transport ? 'sms' : ($is_email_transport ? 'email' : ($is_whatsapp_transport ? 'whatsapp' : 'message')));
$data->{$target} //= {};
for my $k (keys %$mf) {
    $data->{$target}->{$k} //= $mf->{$k};
}

                # Debug: Show all transport data after merge
                use Data::Dumper;
                warn "CI CALL/PHONE after merge: " . Dumper($data->{call}) if $data->{call};
                warn "CI EMAIL after merge: " . Dumper($data->{email}) if $data->{email};
                warn "CI WHATSAPP after merge: " . Dumper($data->{whatsapp}) if $data->{whatsapp};

                # Ensure all comm types are fully populated (title/branch/phone, etc.)
                $self->_ci_postfill_all($data);
                # Keep all transport blocks for CSV export - no filtering

		# ---- NEST COMM BLOCKS UNDER message_type, CLEAN UP TOP LEVEL ----
		# Ensure structure scaffolding
		$data->{message_type} //= {};
		
		# Move any remaining comm blocks (only one should remain after pruning) under message_type
		for my $chan (qw(sms call email whatsapp)) {
		    if (exists $data->{$chan} && ref $data->{$chan} eq 'HASH') {
		        $data->{message_type}{$chan} = delete $data->{$chan};
		    }
		}
		
		# Drop top-level patron and message per new export schema
		delete $data->{patron};
		delete $data->{message};
		
		# Optional: if you also stored library/biblio/holds and want a minimal payload,
		# you can drop them here too — otherwise keep them if the downstream needs them.
		# delete $data->{library};
		# delete $data->{biblio};
		# delete $data->{holds};
		# ---------------------------------------------------------------

                my $order = $self->retrieve_data('section_order') || 'message_type,patron,items,call,whatsapp,sms,message';
                my @sections = map { s/^\s+|\s+$//gr } split /,/, $order;
                @sections = grep { exists $data->{$_} } @sections;
                my %ordered; @ordered{@sections} = @{$data}{@sections};
                push @message_data, \%ordered;

                # Mark each message as 'transmitted' once it has been added to
                # the outbound CSV payload. The CirriusImpact remote service is
                # expected to call back into the plugin REST API (see
                # Koha::Plugin::Com::CirriusImpact::API) to flip the status to
                # 'inprogress', 'sent', or 'failed' once delivery is underway or complete.
                unless ($test_mode) { $m->update({ status => 'transmitted' }); }
            }

            $log->info("FINISHED PROCESSING MESSAGE " . $m->id);
        }
    }

    # ODUE suppression: Remove phone messages if corresponding SMS messages exist
    # This checks across all messages after collection
    my @filtered_message_data;
    my %sms_odue_by_patron;  # Track which patrons have SMS ODUE messages
    
    # First pass: identify patrons with SMS ODUE messages and their original transport
    for my $msg (@message_data) {
        my $mt = $msg->{message_type} || {};
        my $original_transport = $mt->{transport} || '';  # Original Koha message transport
        
        if ($mt->{sms}) {
            my $letter_code = $mt->{sms}->{meta}->{letter_code} || $mt->{sms}->{notificationType} || '';
            my $patron_id = $mt->{sms}->{PatronID} || '';
            if ($letter_code =~ /^ODUE/ && $patron_id) {
                $sms_odue_by_patron{$patron_id}{$letter_code} = $original_transport;  # Store original transport
            }
        }
    }
    
    # Second pass: filter out duplicate ODUE messages - keep only the originally requested transport
    for my $msg (@message_data) {
        my $mt = $msg->{message_type} || {};
        my $should_skip = 0;
        my $original_transport = $mt->{transport} || '';
        
        # Check if this is a phone ODUE message
        if ($mt->{call}) {
            my $letter_code = $mt->{call}->{meta}->{letter_code} || $mt->{call}->{notificationType} || '';
            my $patron_id = $mt->{call}->{PatronID} || '';
            
            $log->info("Checking phone message: letter_code=$letter_code, patron_id=$patron_id, original_transport=$original_transport");
            
            if ($letter_code =~ /^ODUE/ && $patron_id) {
                $log->info("Phone message is ODUE for patron $patron_id");
                
                # Check if suppression config is enabled
                my $cfg = eval { $self->retrieve_data } || {};
                my $suppress_enabled = 1;  # Default ON
                if ($cfg && ref($cfg) eq 'HASH') {
                    my $flag = $cfg->{skip_odue_if_other_if_sms_or_email};
                    $suppress_enabled = $flag if defined $flag;
                }
                
                $log->info("Suppression config enabled: $suppress_enabled");
                
                if ($suppress_enabled && $original_transport eq 'phone') {
                    # Check if there's an SMS ODUE message for this patron that was originally requested as SMS
                    $log->info("Checking for SMS ODUE messages for patron $patron_id");
                    for my $lc (keys %{$sms_odue_by_patron{$patron_id} || {}}) {
                        my $sms_orig_transport = $sms_odue_by_patron{$patron_id}{$lc};
                        $log->info("Found SMS ODUE message with letter_code: $lc, original_transport: $sms_orig_transport");
                        if ($lc =~ /^ODUE/ && $sms_orig_transport eq 'sms') {
                            $should_skip = 1;
                            $log->info("ODUE suppression: Skipping phone message for patron $patron_id (has SMS ODUE message $lc)");
                            last;
                        }
                    }
                } else {
                    $log->info("Suppression not applicable: config=$suppress_enabled, transport=$original_transport");
                }
            }
        }
        
        push @filtered_message_data, $msg unless $should_skip;
    }
    
    # Generate CSV output instead of JSON
    my $csv_data = $self->_generate_csv_output(\@filtered_message_data);

    if ($archive_dir) {
        my $archive_path = $archive_dir . "/$filename";
        write_file($archive_path, $csv_data);
        $log->info("CI - FILE WRITTEN TO $archive_path");
    }

    unless ($test_mode) {
        write_file($realpath, $csv_data);
        $log->info("CI - FILE WRITTEN TO $realpath");
        my $host      = $self->retrieve_data('host');
        my $username  = $self->retrieve_data('username');
        my $password  = $self->retrieve_data('password');
        my $directory = $ENV{CirriusImpact_SFTP_DIR} || '';
        if ($host && $username && $password) {
            try {
                my %opts = (
                    host     => $host,
                    user     => $username,
                    port     => 222,
                    password => $password,
                    more     => ['-o','StrictHostKeyChecking=accept-new']
                );
                my $sftp = Net::SFTP::Foreign->new(%opts);
                $sftp->setcwd($directory) if $directory;
                my $remote = ($directory ? "$directory/" : '') . $filename;
                $sftp->put($realpath, $remote) or die "put failed: " . $sftp->error;
                $log->info("CI - SFTP PUT $remote");
            } catch {
                $log->warn("CI - SFTP FAILED: $_");
            };
        }
    };

    logaction('CirriusImpact','DONE',               undef, undef, 'cron') if $is_cronjob;
    logaction('CirriusImpact','MESSAGES_PROCESSED', undef, JSON->new->pretty->encode($info), 'cron') if $is_cronjob;
}

sub _odue_codes {
    my $dbh = C4::Context->dbh;
    my $letter1 = $dbh->selectcol_arrayref(q{SELECT DISTINCT(letter1) FROM overduerules});
    my $letter2 = $dbh->selectcol_arrayref(q{SELECT DISTINCT(letter2) FROM overduerules});
    my $letter3 = $dbh->selectcol_arrayref(q{SELECT DISTINCT(letter3) FROM overduerules});
    my @codes = ((@$letter1), (@$letter2), (@$letter3));
    @codes = grep { defined $_ && length $_ } @codes;
    return \@codes;
}

sub _hold_codes {
    # Return common hold-related letter codes that should be processed
    return ['HOLD', 'HOLDDGST', 'HOLDPLACED', 'HOLDPLACED_PATRON', 'HOLD_CHANGED', 'HOLD_REMINDER',
            'HOLD_CHANGEDGST', 'HOLD_REMINDERGST', 'HOLDPLACEDGST', 'HOLDPLACED_PATRONGST',
            'HOLD_SLIP'];
}

sub _predue_codes {
    # Return pre-due notice letter codes that should be processed
    return ['PREDUE', 'PREDUEDGST'];
}

sub _circulation_codes {
    # Return circulation-related letter codes (item checkout/checkin) that should be processed
    return ['CHECKOUT', 'CHECKIN'];
}

sub _renewal_codes {
    # Return renewal-related letter codes that should be processed
    return ['RENEWAL', 'AUTO_RENEWALS', 'AUTO_RENEWALS_DGST'];
}

sub _membership_codes {
    # Return membership/account-related letter codes that should be processed
    # (account expiring/renewed/welcome notifications)
    return ['MEMBERSHIP_EXPIRY', 'MEMBERSHIP_RENEWED', 'WELCOME'];
}

sub _get_notification_type_and_level {
    my ($self, $letter_code) = @_;
    
    # Load notification mapping from configurable YAML file
    my $mapping = $self->_load_notification_mapping();
    
    return $mapping->{$letter_code} || { type => 0, level => 0 };
}

# Format date to %d/%m/%Y format
sub _format_date {
    my ($self, $date_string) = @_;
    return '' unless $date_string;
    
    # If it's already in the correct format, return as-is
    if ($date_string =~ /^\d{2}\/\d{2}\/\d{4}$/) {
        return $date_string;
    }
    
    # Try to parse various date formats and convert to dd/mm/yyyy
    my $formatted_date = '';
    
    # Handle MySQL date format (YYYY-MM-DD)
    if ($date_string =~ /^(\d{4})-(\d{2})-(\d{2})/) {
        $formatted_date = sprintf("%02d/%02d/%04d", $3, $2, $1);
    }
    # Handle MySQL datetime format (YYYY-MM-DD HH:MM:SS)
    elsif ($date_string =~ /^(\d{4})-(\d{2})-(\d{2})\s/) {
        $formatted_date = sprintf("%02d/%02d/%04d", $3, $2, $1);
    }
    # Handle other common formats
    elsif ($date_string =~ /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/) {
        $formatted_date = sprintf("%02d/%02d/%04d", $1, $2, $3);
    }
    # If we can't parse it, return the original string
    else {
        $formatted_date = $date_string;
    }
    
    return $formatted_date;
}

# Format date in US format (m/d/y) for messageText
sub _format_date_us {
    my ($self, $date_string) = @_;
    return '' unless $date_string;
    
    # Handle dd/mm/yyyy format (from _format_date output) - most common case
    if ($date_string =~ /^(\d{2})\/(\d{2})\/(\d{4})$/) {
        my ($d, $m, $y) = ($1, $2, $3);
        # If first number > 12, it's definitely dd/mm format, swap to m/d/y
        if ($d > 12) {
            # Remove leading zeros
            $m =~ s/^0+//;
            $m = '1' if $m eq '';
            $d =~ s/^0+//;
            $d = '1' if $d eq '';
            return "$m/$d/$y";
        }
        # If first number <= 12, could be either format
        # Check if second number > 12 - if so, first must be month (US format)
        if ($m > 12) {
            # First is month, already US format, just remove leading zeros
            $d =~ s/^0+//;
            $d = '1' if $d eq '';
            $m =~ s/^0+//;
            $m = '1' if $m eq '';
            return "$m/$d/$y";
        }
        # Both <= 12, assume dd/mm format (from _format_date) and swap
        $d =~ s/^0+//;
        $d = '1' if $d eq '';
        $m =~ s/^0+//;
        $m = '1' if $m eq '';
        return "$m/$d/$y";
    }
    
    # Handle single-digit format (d/m/yyyy or m/d/yyyy)
    if ($date_string =~ /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/) {
        my ($first, $second, $y) = ($1, $2, $3);
        # If first > 12, must be dd/mm, swap
        if ($first > 12) {
            return "$second/$first/$y";
        }
        # If second > 12, first is month (US format)
        if ($second > 12) {
            return "$first/$second/$y";
        }
        # Both <= 12, assume dd/mm format and swap
        return "$second/$first/$y";
    }
    
    # Handle MySQL date format (YYYY-MM-DD)
    if ($date_string =~ /^(\d{4})-(\d{2})-(\d{2})/) {
        my ($y, $m, $d) = ($1, $2, $3);
        $m =~ s/^0+//;
        $m = '1' if $m eq '';
        $d =~ s/^0+//;
        $d = '1' if $d eq '';
        return "$m/$d/$y";
    }
    
    # Handle MySQL datetime format (YYYY-MM-DD HH:MM:SS)
    if ($date_string =~ /^(\d{4})-(\d{2})-(\d{2})\s/) {
        my ($y, $m, $d) = ($1, $2, $3);
        $m =~ s/^0+//;
        $m = '1' if $m eq '';
        $d =~ s/^0+//;
        $d = '1' if $d eq '';
        return "$m/$d/$y";
    }
    
    # If we can't parse it, return the original string
    return $date_string;
}

# Convert all dates in text from dd/mm/yyyy to m/d/yyyy format (US format)
sub _convert_dates_in_text_to_us_format {
    my ($self, $text) = @_;
    return '' unless $text;
    
    # Pattern to match dates in dd/mm/yyyy format (4-digit year only)
    # _format_date outputs dates as dd/mm/yyyy (e.g., "19/11/2025")
    # We need to convert these to m/d/yyyy (e.g., "11/19/2025")
    my $converted_text = $text;
    
    # Match dates with 4-digit year to avoid false positives with phone numbers
    # Convert dd/mm/yyyy to m/d/yyyy
    $converted_text =~ s{
        \b(\d{1,2})/(\d{1,2})/(\d{4})\b
    }{
        my ($first, $second, $year) = ($1, $2, $3);
        my $first_num = int($first);
        my $second_num = int($second);
        
        # If first number > 12, it's definitely a day (dd/mm format), swap to m/d
        if ($first_num > 12) {
            # Remove leading zeros from month and day
            $second =~ s/^0+//;
            $second = '1' if $second eq '';
            $first =~ s/^0+//;
            $first = '1' if $first eq '';
            "$second/$first/$year";  # Swap: month/day/year
        }
        # If second number > 12, it's already month/day format (US format), leave as-is
        elsif ($second_num > 12) {
            # Already in US format, just remove leading zeros if present
            $first =~ s/^0+//;
            $first = '1' if $first eq '';
            $second =~ s/^0+//;
            $second = '1' if $second eq '';
            "$first/$second/$year";
        }
        # Both <= 12 - ambiguous case
        # Dates from _format_date are dd/mm/yyyy (e.g., "19/11/2025")
        # Dates from our digest grouping use _format_date_us and are m/d/yyyy (e.g., "11/19/2025")
        # Since _format_date always outputs 2-digit day and month with leading zeros,
        # dates from it will be like "09/11/2025" or "19/11/2025"
        # Dates already in US format from digest logic won't have leading zeros
        else {
            my $orig_first = $1;
            my $orig_second = $2;
            my $orig_first_len = length($orig_first);
            my $orig_second_len = length($orig_second);
            
            # If original first part has 2 digits (with or without leading zero),
            # and original second part also has 2 digits, it likely matches _format_date pattern (dd/mm/yyyy)
            # So assume it's dd/mm format and swap
            # Exception: if both parts are single digit, it might already be US format, so be cautious
            if ($orig_first_len == 2 && $orig_second_len == 2) {
                # Matches _format_date pattern (dd/mm/yyyy), swap to m/d/yyyy
                $second =~ s/^0+//;
                $second = '1' if $second eq '';
                $first =~ s/^0+//;
                $first = '1' if $first eq '';
                "$second/$first/$year";  # Swap: month/day/year
            } elsif ($orig_first_len == 2 && $orig_second_len == 1) {
                # First is 2 digits, second is 1 digit - likely dd/m/yyyy, swap
                $second =~ s/^0+//;
                $second = '1' if $second eq '';
                $first =~ s/^0+//;
                $first = '1' if $first eq '';
                "$second/$first/$year";
            } else {
                # Both are single digit or other pattern - likely already US format, leave as-is
                $first =~ s/^0+//;
                $first = '1' if $first eq '';
                $second =~ s/^0+//;
                $second = '1' if $second eq '';
                "$first/$second/$year";
            }
        }
    }gex;
    
    return $converted_text;
}

# Get notice template from Koha database for a specific letter code and transport
sub _get_notice_template {
    my ($self, $letter_code, $transport) = @_;
    
    return undef unless $letter_code && $transport;
    
    # Map transport to Koha's message_transport_type
    my %transport_map = (
        'sms' => 'sms',
        'phone' => 'phone',
        'call' => 'phone',
        'email' => 'email',
    );
    my $koha_transport = $transport_map{lc($transport)} || $transport;
    
    # Query Koha's letter table for the template
    my $dbh = C4::Context->dbh;
    my $sth = $dbh->prepare("
        SELECT content 
        FROM letter 
        WHERE module = 'circulation' 
        AND code = ? 
        AND message_transport_type = ?
        LIMIT 1
    ");
    $sth->execute($letter_code, $koha_transport);
    my ($template) = $sth->fetchrow_array();
    
    return $template;
}

# Render a notice template using Template Toolkit with provided data
sub _render_notice_template {
    my ($self, $template, $data) = @_;
    
    return '' unless $template;
    
    my $log = Koha::Logger->get({ interace => 'plugin', category => 'CirriusImpact', prefix => 0 });
    
    # Use Template Toolkit to render with Koha-compatible settings
    my $tt = Template->new({
        ENCODING => 'utf8',
        INTERPOLATE => 0,
        POST_CHOMP => 1,
        # Add Koha date filter support
        FILTERS => {
            'KohaDates' => sub {
                my $date = shift;
                return $self->_format_date_us($date) || $date;
            },
        },
    });
    
    my $output = '';
    $tt->process(\$template, $data, \$output) or do {
        my $error = $tt->error();
        $log->warn("Failed to render template: $error");
        $log->info("Template was: " . substr($template, 0, 200));
        $log->info("Data keys: " . join(', ', keys %$data));
        return '';
    };
    
    return $output;
}

sub _load_notification_mapping {
    my $self = shift;
    
    # Cache the mapping to avoid reloading on every call
    return $self->{_notification_mapping} if $self->{_notification_mapping};
    
    my $mapping_file = $self->bundle_path() . '/notification_mapping.yml';
    
    # Check if mapping file exists
    unless (-f $mapping_file) {
        warn "CirriusImpact: notification_mapping.yml not found at $mapping_file, using defaults\n";
        return $self->{_notification_mapping} = _get_default_notification_mapping();
    }
    
    # Load YAML file
    eval {
        my $yaml_content = do {
            local $/;
            open my $fh, '<', $mapping_file or die "Cannot open $mapping_file: $!";
            <$fh>;
        };
        
        $self->{_notification_mapping} = Load($yaml_content);
    };
    
    if ($@) {
        warn "CirriusImpact: Error loading notification_mapping.yml: $@, using defaults\n";
        return $self->{_notification_mapping} = _get_default_notification_mapping();
    }
    
    return $self->{_notification_mapping};
}

sub _get_default_notification_mapping {
    # Fallback default mapping if YAML file is not available
    return {
        # Overdue Notices - Type 1
        'ODUE'  => { type => 1, level => 1 },
        'ODUE2' => { type => 1, level => 2 },
        'ODUE3' => { type => 1, level => 3 },
        'DUE'      => { type => 1, level => 4 },
        'DUEDGST'  => { type => 1, level => 4 },
        
        # Hold Notices - Type 2
        'HOLD'              => { type => 2, level => 1 },
        'HOLDDGST'          => { type => 2, level => 1 },
        'HOLD_CHANGED'      => { type => 2, level => 2 },
        'HOLD_REMINDER'     => { type => 2, level => 3 },
        'HOLDPLACED'        => { type => 2, level => 4 },
        'HOLDPLACED_PATRON' => { type => 2, level => 5 },
        'HOLD_SLIP'         => { type => 2, level => 6 },
        
        # Circulation Notices - Type 3
        'CHECKOUT' => { type => 3, level => 1 },
        'CHECKIN'  => { type => 3, level => 2 },
        
        # Pre-due Notices - Type 4
        'PREDUE'      => { type => 4, level => 1 },
        'PREDUEDGST'  => { type => 4, level => 1 },
        
        # Renewal Notices - Type 5
        'RENEWAL'           => { type => 5, level => 1 },
        'AUTO_RENEWALS'     => { type => 5, level => 2 },
        'AUTO_RENEWALS_DGST' => { type => 5, level => 2 },
        
        # Membership Notices - Type 6
        'MEMBERSHIP_EXPIRY'  => { type => 6, level => 1 },
        'MEMBERSHIP_RENEWED' => { type => 6, level => 2 },
        'WELCOME'            => { type => 6, level => 3 },
    };
}

sub _get_patron_title {
    my ($pat) = @_;
    return '' unless $pat && ref($pat) eq 'HASH';
    
    # First try to get the patron's title field
    my $title = $pat->{title} || '';
    if ($title && $title ne '') {
        return $title;
    }
    
    # If title is empty, generate based on sex field
    my $sex = $pat->{sex} || '';
    if ($sex eq 'M') {
        return 'Mr.';
    } elsif ($sex eq 'F') {
        return 'Ms.';
    }
    
    # Return empty for unknown/other
    return '';
}

sub _add_hold {
    my ($self, $data, $hold) = @_;
    return unless $hold;
    my $biblio = $hold->biblio;
    my $branch_obj = eval { $hold->branch };
    my $pickup_lib;
    if ($branch_obj) {
        my $raw = $branch_obj->unblessed;
        $pickup_lib = { %$raw, name => $raw->{branchname}, code => $raw->{branchcode}, phone => $raw->{branchphone} };
    }
    my $sub = { hold => $hold->unblessed };
    $sub->{pickup_library} = $pickup_lib if $pickup_lib;
    if ($biblio) {
        $sub->{biblio} = $self->scrub_biblio($biblio->unblessed);
        $sub->{title}  = $biblio->title if $biblio->can('title');
    }
    $data->{holds} //= [];
    push @{ $data->{holds} }, $sub;
    $data->{items} //= [];
    push @{ $data->{items} }, { title => $sub->{title} } if $sub->{title};
}

# --- Plugin REST API -------------------------------------------------------
#
# Exposes endpoints used by the remote CirriusImpact service to update the
# Koha-side status of a notice after it has been transmitted out via the
# nightly SFTP push.
#
# Mounted at /api/v1/contrib/cirriusimpact/...
#
#   POST /message/{message_id}/status   - set status to sent | inprogress | failed
#   POST /message/{message_id}/content  - update message subject / content
#
# OpenAPI spec lives next to this file at
#   Koha/Plugin/Com/CirriusImpact/openapi.json
# Implementation lives at
#   Koha/Plugin/Com/CirriusImpact/API.pm
# ---------------------------------------------------------------------------

sub api_routes {
    my ($self, $args) = @_;

    my $spec_str = $self->mbf_read('openapi.json');
    return {} unless $spec_str;

    my $spec;
    eval { $spec = decode_json($spec_str); };
    if ($@ || !$spec) {
        warn "CirriusImpact: failed to load openapi.json: $@\n";
        return {};
    }
    return $spec;
}

sub api_namespace {
    return 'cirriusimpact';
}


# Post-fill SMS fields if TT didn't resolve them in notice config
sub _ci_postfill_sms {

    my ($self, $data, $args) = @_;
    return unless ref($data) eq 'HASH';
    $data->{sms} //= {};

    my $patron = $data->{patron} // {};
    my $lib    = $data->{library} // {};
    my $biblio = $data->{biblio}  // {};
    my $items  = $data->{items};
    my $holdsA = $data->{holds};

    my $hold   = (ref($holdsA) eq 'ARRAY' && @$holdsA) ? $holdsA->[0] : {};
    my $hraw   = $hold->{raw} // {};

    my $get = sub { my ($h, $k, $fb) = @_; return defined $h->{$k} && $h->{$k} ne '' ? $h->{$k} : ($fb // ''); };
    my $fill = sub { my ($hash, $key, $val) = @_; $hash->{$key} = (defined $hash->{$key} && $hash->{$key} ne '') ? $hash->{$key} : (defined $val ? $val : ''); };

    my $title = $get->($hold,'title',$get->($biblio,'title',''));
    if (!$title && ref($items) eq 'ARRAY' && @$items) { $title = $items->[0]{title} // ''; }

    my $branch_code  = $get->($lib, 'code', $get->($lib,'branchcode',''));
    my $branch_name  = $get->($lib, 'name', $get->($lib,'branchname',''));
    my $branch_phone = $get->($lib, 'phone', $get->($lib,'branchphone',''));

    my $msgid        = $get->($hraw, 'reserve_id', $data->{message}{message_id});
    my $itemsID      = $get->($hraw, 'biblionumber', $get->($biblio, 'biblionumber',''));

    my $lang         = _ci_normalize_language($get->($patron, 'lang', ''));
    my $transport    = $data->{message}{transport} // $data->{message_type}{transport} // 'sms';

    my $s = ($data->{sms} //= {});
    $fill->($s, 'to',                    $get->($patron, 'smsalertnumber', ''));
    $fill->($s, 'reference',             $data->{message}{message_id});
    $fill->($s, 'text',                  '');
    $fill->($s, 'msgid',                 $msgid);
    $fill->($s, 'commType',              ($s->{commType} && $s->{commType} =~ /\S/ ? $s->{commType} : 'sms'));
    $fill->($s, 'language',              $lang);
    # Use letter code from meta instead of transport type
    my $letter_code = $data->{message}{letter_code} || ($s->{meta} && $s->{meta}->{letter_code}) || '';
    $fill->($s, 'notificationType',      $letter_code);
    _ci_filter_channels_by_transport($data, $transport);
    $fill->($s, 'notificationLevel',     '');
    $fill->($s, 'patronBarCode',         $get->($patron,'cardnumber',''));
    # Populate STAB_userSaluation based on patron's sex field if title is empty
    my $patron_title = $get->($patron,'title','');
    if (!$patron_title || $patron_title eq '') {
        my $sex = $get->($patron,'sex','');
        if ($sex eq 'M') {
            $patron_title = 'Mr.';
        } elsif ($sex eq 'F') {
            $patron_title = 'Ms.';
        } else {
            $patron_title = '';  # Keep empty for unknown/other
        }
    }
    $fill->($s, 'STAB_userSaluation', $patron_title);
    $fill->($s, 'patronFirstName',       $get->($patron,'firstname',''));
    $fill->($s, 'patronLastName',        $get->($patron,'surname',''));
    $fill->($s, 'phone',                 $get->($patron,'smsalertnumber',''));
    $fill->($s, 'email',                 $get->($patron,'email',''));
    $fill->($s, 'branch',                $branch_code);
    $fill->($s, 'branchname',            $branch_name);
    $fill->($s, 'itemsID',               $itemsID);
    $fill->($s, 'date',                  $get->($hraw,'waitingdate',$get->($hraw,'notificationdate','')));
    $fill->($s, 'title',                 $title);
    $fill->($s, 'DeliveryOptionID',      '');
    $fill->($s, 'LanguageID',            '');
    $fill->($s, 'NotificationTypeID',    '');
    $fill->($s, 'ReportingOrgID',        '');
    $fill->($s, 'PatronID',              $get->($patron,'borrowernumber',''));
    $fill->($s, 'ItemRecordID',          '');
    $fill->($s, 'RequestID',             $msgid);
    $fill->($s, 'PickupAreaDescription', ($get->($lib,'pickup_location','') || $get->($hraw,'branchcode','')));
    $fill->($s, 'TxnID',                 $get->($s, 'TxnID', $data->{message}{message_id}));
    $fill->($s, 'AccountBalance',        '');

    if ( !defined $s->{title} || $s->{title} eq '' ) {
        my $derived = _ci_extract_title_from_text( $s->{text}, $s->{branchname} );
    _ci_fill_titles($data); # Ensure titles filled from Koha where possible
        $s->{title} = $derived if defined $derived && $derived ne '';
    }

    if (defined $s->{text} && $s->{text} =~ /Call\s*\.\s*$/ && $branch_phone ne '') {
        $s->{text} =~ s/Call\s*\.\s*$/Call $branch_phone./;
    }
    if ((!defined $s->{branchname} || $s->{branchname} eq '') && defined $s->{text} && $s->{text} =~ /\[([^\]]+)\]/) {
        $s->{branchname} = $1 if $1;
    }
    if (!defined $s->{branch} || $s->{branch} eq '') {
        $s->{branch} = $get->($patron,'branchcode','');
    }
    return $data;

}

sub _ci_extract_title_from_text {

    my ($text, $branchname) = @_;
    return '' unless defined $text && $text ne '';

    if ( $text =~ /ready\s*:\s*(.+?)\s+at\s+\S/iu ) {
        my $t = $1; $t =~ s/\s+[.?!]\s*$//; return $t;
    }
    if ( $text =~ /ready\s+at\s+.+?\s*:\s*(.+?)(?:\s+Questions\b|[.?!]\s*|$)/iu ) {
        my $t = $1; $t =~ s/\s+[.?!]\s*$//; return $t;
    }
    if ( $text =~ /ready\s+for\s+pickup\s*:\s*(.+?)(?:[.?!]\s*|$)/iu ) {
        my $t = $1; $t =~ s/\s+[.?!]\s*$//; return $t;
    }
    return '';

}

# Extracts a title from biblio.title if present; otherwise falls back to the
# outgoing rendered strings (sms.text or call.script).
sub _ci_extract_title {
    my ($self, $payload) = @_;

    # 1) Prefer the direct biblio title if present
    my $title = '';
    if (exists $payload->{biblio}
        && defined $payload->{biblio}->{title}
        && $payload->{biblio}->{title} ne '') {
        $title = $payload->{biblio}->{title};
    }

    # 2) If still blank, parse from SMS text or Phone script
    if (!$title) {
        my $text = '';
        if (exists $payload->{sms}
            && defined $payload->{sms}->{text}
            && $payload->{sms}->{text} ne '') {
            $text = $payload->{sms}->{text};
        }
        if (!$text && exists $payload->{call}
            && defined $payload->{call}->{script}
            && $payload->{call}->{script} ne '') {
            $text = $payload->{call}->{script};
        }

        if ($text) {
            # Pattern A: "... ready: TITLE at BRANCH ..."
            if ($text =~ /ready\s*:\s*(.+?)\s+at\s+\S/iu) {
                my $t = $1; $t =~ s/\s+[.?!]\s*$//; $title = $t;
            }
            # Pattern B: "... ready at BRANCH : TITLE  Questions?/."
            elsif ($text =~ /ready\s+at\s+.+?\s*:\s*(.+?)(?:\s+Questions\b|[.?!]\s*|$)/iu) {
                my $t = $1; $t =~ s/\s+[.?!]\s*$//; $title = $t;
            }
            # Pattern C: "... ready for pickup: TITLE . Please ..."
            elsif ($text =~ /ready\s+for\s+pickup\s*:\s*(.+?)(?:[.?!]\s*|$)/iu) {
                my $t = $1; $t =~ s/\s+[.?!]\s*$//; $title = $t;
            }
            else {
                # Fallback: take text after first colon, then clean common tails
                if ($text =~ /:\s*(.+)$/u) {
                    my $t = $1;
                    $t =~ s/\s+at\s+[^.?!]+$//;     # drop trailing " at Branch"
                    $t =~ s/\s+Questions\?.*$//i;   # drop trailing Questions?
                    $t =~ s/\s*[\.\?!]\s*$//;       # drop trailing punctuation
                    $title = $t;
                }
            }
        }
    }

    # 3) Normalize/trim
    $title //= '';
    $title =~ s/^\s+|\s+$//g;
    return $title;
}

sub _ci_postfill_all {

    my ($self, $data) = @_;
    return unless ref($data) eq 'HASH';

    $self->_ci_postfill_sms($data);

    my $patron = $data->{patron} // {};
    my $lib    = $data->{library} // {};
    my $biblio = $data->{biblio}  // {};
    my $holdsA = $data->{holds};
    my $hold   = (ref($holdsA) eq 'ARRAY' && @$holdsA) ? $holdsA->[0] : {};
    my $hraw   = $hold->{raw} // {};

    my $get = sub { my ($h, $k, $fb) = @_; return defined $h->{$k} && $h->{$k} ne '' ? $h->{$k} : ($fb // ''); };

    my $title = $get->($hold,'title',$get->($biblio,'title',''));
    $title ||= $data->{sms}{title};
    if ( !$title || $title eq '' ) {
        my $maybe = _ci_extract_title_from_text( $data->{sms}{text}, $data->{sms}{branchname} );
        $title = $maybe if defined $maybe && $maybe ne '';
    _ci_fill_titles($data);
    }

    my $branch_code  = $get->($lib,'code',$get->($lib,'branchcode',''));
    my $branch_name  = $get->($lib,'name',$get->($lib,'branchname',''));
    my $branch_phone = $get->($lib,'phone',$get->($lib,'branchphone',''));
    my $msgid        = $get->($hraw,'reserve_id',$data->{message}{message_id});

    if ( ( !defined $data->{call}{title} || $data->{call}{title} eq '' )
     && length( $data->{call}{script} // '' ) ) {

    my $ct = $self->_ci_extract_title({
        call   => { script => $data->{call}{script} },
        sms    => { text   => $data->{sms}{text} // '' },
        biblio => { title  => $data->{biblio}{title} // '' },
    });

    $data->{call}{title} = $ct if defined $ct && $ct ne '';
}
    $data->{whatsapp} //= {};
    for my $k (qw(to reference text msgid commType language notificationType notificationLevel patronBarCode STAB_userSaluation patronFirstName patronLastName phone email branch branchname itemsID date title DeliveryOptionID LanguageID NotificationTypeID ReportingOrgID PatronID ItemRecordID RequestID PickupAreaDescription TxnID AccountBalance)) {
        $data->{whatsapp}{$k} = $data->{whatsapp}{$k} // $data->{sms}{$k} // '';
    }
    $data->{whatsapp}{commType} = ($data->{whatsapp}{commType} && $data->{whatsapp}{commType} =~ /\S/) ? $data->{whatsapp}{commType} : 'whatsapp';

    $data->{email} //= {};
    my $e = $data->{email};
    $e->{to}          = $e->{to}          // $get->($patron,'email','');
    $e->{subject}     = $e->{subject}     // ($data->{message}{subject} // '');
    $e->{title}       = $e->{title}       || $title || '';
    $e->{branch}      = $e->{branch}      // $branch_code;
    $e->{branchname}  = $e->{branchname}  // $branch_name;
    $e->{branchphone} = $e->{branchphone} // $branch_phone;
    $e->{PatronID}    = $e->{PatronID}    // $get->($patron,'borrowernumber','');
    $e->{RequestID}   = $e->{RequestID}   // $msgid;

    $data->{call} //= {};
    my $c = $data->{call};
    $c->{to}          = $c->{to}          // $get->($patron,'phone',$get->($patron,'smsalertnumber',''));
    $c->{phone}       = $c->{phone}       // $c->{to} // $get->($patron,'phone',$get->($patron,'smsalertnumber',''));
    $c->{branch}      = $c->{branch}      // $branch_code;
    $c->{branchname}  = $c->{branchname}  // $branch_name;
    $c->{branchphone} = $c->{branchphone} // $branch_phone;
    $c->{title}       = $c->{title}       || $title || '';
    $c->{RequestID}   = $c->{RequestID}   // $msgid;

    return $data;

}

# --- CirriusImpact: keep only one channel matching Koha transport ---
sub _ci_filter_channels_by_transport {
    my ($data, $transport) = @_;
    return unless $data && ref($data) eq 'HASH';
    return unless $transport;

    my %map = (
        phone    => 'call',
        sms      => 'sms',
        email    => 'email',
        whatsapp => 'whatsapp',
    );
    my $keep = $map{lc $transport} // '';
    return unless $keep;

    for my $k (qw/call sms email whatsapp/) {
        next if $k eq $keep;
        delete $data->{$k} if exists $data->{$k};
    }
}
# --- end ---



sub _ci_overdue_title_for_patron {
    my ($borrowernumber) = @_;
    return '' unless $borrowernumber;

    my $schema = Koha::Database->new->schema;
    my $dbh = $schema->storage->dbh;
    my $sql = q{
        SELECT b.title
        FROM issues i
        JOIN items it ON it.itemnumber = i.itemnumber
        JOIN biblio b ON b.biblionumber = it.biblionumber
        WHERE i.borrowernumber = ?
          AND i.returndate IS NULL
          AND i.date_due < NOW()
        ORDER BY i.date_due ASC
        LIMIT 1
    };
    my $sth = $dbh->prepare($sql);
    $sth->execute($borrowernumber);
    my ($title) = $sth->fetchrow_array;
    $sth->finish;
    return $title // '';
}




sub _ci_should_suppress_phone_for_odue {
    my ($self, $borrowernumber) = @_;
    my $log = Koha::Logger->get({ interace => 'plugin', category => 'CirriusImpact', prefix => 0 });
    
    my $cfg = eval { $self->retrieve_data } || {};
    my $on  = 1;
    if ($cfg && ref($cfg) eq 'HASH') {
        my $flag = $cfg->{skip_odue_if_other_if_sms_or_email};
        $on = $flag if defined $flag; # default ON if missing
    }
    
    $log->info("Suppression config check: on=$on, borrowernumber=" . ($borrowernumber || 'undef'));
    
    return 0 unless $on;
    return 0 unless $borrowernumber;

    my $pat = Koha::Patrons->find($borrowernumber);
    return 0 unless $pat;
    
    $log->info("Patron found: " . $pat->firstname . " " . $pat->surname);

    # Check messaging preferences using database directly for reliability
    my $dbh = C4::Context->dbh;
    my $sql = q{
        SELECT ma.message_name, bmp.wants_digest, bmt.message_transport_type
        FROM borrower_message_preferences bmp
        JOIN message_attributes ma ON bmp.message_attribute_id = ma.message_attribute_id
        LEFT JOIN borrower_message_transport_preferences bmt ON bmp.borrower_message_preference_id = bmt.borrower_message_preference_id
        WHERE bmp.borrowernumber = ?
    };
    
    my $sth = $dbh->prepare($sql);
    $sth->execute($borrowernumber);
    
    my $has_sms = 0;
    my $has_email = 0;
    
    while (my ($message_name, $wants_digest, $transport) = $sth->fetchrow_array) {
        $log->info("DB Pref: letter_code=$message_name, wants_digest=$wants_digest, transport=$transport");
        
        # Check for all ODUE variants (ODUE, ODUE2, ODUE3, etc.)
        if (($message_name || '') =~ /^ODUE/ && ($wants_digest || 0) == 0) {
            $has_sms   ||= (($transport || '') eq 'sms');
            $has_email ||= (($transport || '') eq 'email');
        }
    }
    $sth->finish;
    
    $log->info("Final suppression decision: has_sms=$has_sms, has_email=$has_email");
    return ($has_sms || $has_email) ? 1 : 0;
}
# --- helper: backfill CHECKOUT identifiers ---
sub _ci_backfill_checkout_identifiers {
    my ($self, $data) = @_;
    my $log = Koha::Logger->get({ interace => 'plugin', category => 'CirriusImpact', prefix => 0 });
    
    # Determine which sections actually exist (not just what transport says)
    # Check all possible transport sections
    my @sections_to_check = ();
    push @sections_to_check, ['call', $data->{call}] if $data->{call} && ref($data->{call}) eq 'HASH';
    push @sections_to_check, ['sms', $data->{sms}] if $data->{sms} && ref($data->{sms}) eq 'HASH';
    push @sections_to_check, ['email', $data->{email}] if $data->{email} && ref($data->{email}) eq 'HASH';
    push @sections_to_check, ['whatsapp', $data->{whatsapp}] if $data->{whatsapp} && ref($data->{whatsapp}) eq 'HASH';
    
    # Process each section that exists
    for my $section_info (@sections_to_check) {
        my ($section_name, $section) = @$section_info;
        
        # Get letter code from the section
        my $letter = $section->{meta} && $section->{meta}->{letter_code} ? $section->{meta}->{letter_code} : ($data->{meta} && $data->{meta}->{letter_code} || '');
        
        $log->info("_ci_backfill_checkout_identifiers: section=$section_name, letter=$letter");
        
        # Only work with CHECKOUT notices
        next unless (($letter||'') eq 'CHECKOUT');

    my $has_all = sub {
        my $result = ($section->{itemsID} && $section->{biblionumber} && $section->{title});
        $log->info("has_all check: itemsID=" . ($section->{itemsID}||'') . ", biblionumber=" . ($section->{biblionumber}||'') . ", title=" . ($section->{title}||'') . " -> result=" . ($result ? '1' : '0'));
        return $result;
    };

    # If we already have all data, nothing to do
    return if $has_all->();

    # Get patron ID
    my $pid = $data->{PatronID}
        || ($data->{patron} && $data->{patron}->{borrowernumber})
        || ($data->{call} && $data->{call}->{PatronID})
        || ($section->{PatronID});

    $log->info("Attempting to query Checkouts for patron: " . ($pid || 'NO PID'));

    if ($pid) {
        $log->info("Querying Checkouts for borrowernumber=$pid");
        
        # Use direct SQL query to get checkout info
        my $dbh = C4::Context->dbh;
        my $sql = q{
            SELECT i.itemnumber, it.biblionumber, b.title, i.date_due, i.issue_id
            FROM issues i
            JOIN items it ON it.itemnumber = i.itemnumber
            JOIN biblio b ON b.biblionumber = it.biblionumber
            WHERE i.borrowernumber = ?
              AND i.returndate IS NULL
            ORDER BY i.issuedate DESC
        };
        my $sth = $dbh->prepare($sql);
        $sth->execute($pid);
        
        my @checkouts;
        while (my ($itemnumber, $biblionumber, $title, $date_due, $issue_id) = $sth->fetchrow_array) {
            push @checkouts, {
                itemnumber => $itemnumber,
                biblionumber => $biblionumber,
                title => $title,
                date_due => $date_due,
                issue_id => $issue_id
            };
        }
        $sth->finish;
        
        $log->info("Found " . scalar(@checkouts) . " checkouts for patron $pid");
        
        if (@checkouts) {
            # Try to match title from the script/text if available
            my $title_from_message = '';
            if ($section->{script}) {
                # Extract title from: "You checked out [TITLE] due..."
                if ($section->{script} =~ /You checked out\s+(.+?)\s+due/i) {
                    $title_from_message = $1;
                    $title_from_message =~ s/\s+$//;  # trim trailing space
                    $log->info("Extracted title from script: '$title_from_message'");
                }
            } elsif ($section->{text}) {
                # Extract title from SMS text if present
                if ($section->{text} =~ /Checked out:\s+(.+?)\.\s+Due/i) {
                    $title_from_message = $1;
                    $title_from_message =~ s/\s+$//;
                    $log->info("Extracted title from text: '$title_from_message'");
                }
            }
            
            # Find matching checkout by title
            my $checkout_data;
            if ($title_from_message) {
                for my $c (@checkouts) {
                    my $db_title = $c->{title} || '';
                    $db_title =~ s/\s*[\/\:]?\s*$//;  # Trim trailing / : and spaces
                    if ($db_title eq $title_from_message || $db_title =~ /^\Q$title_from_message\E/) {
                        $checkout_data = $c;
                        $log->info("Matched title '$title_from_message' to checkout item " . $c->{itemnumber});
                        last;
                    }
                }
            }
            
            # Fallback: use yaml_doc_index if no match found
            unless ($checkout_data) {
                my $yaml_doc_index = $data->{message_type}->{yaml_doc_index} // 0;
                my $index = $yaml_doc_index % scalar(@checkouts);
                $checkout_data = $checkouts[$index];
                $log->info("No title match, using index $index (yaml_doc $yaml_doc_index)");
            }
            
            if ($checkout_data) {
                my $title = $checkout_data->{title} || '';

                $section->{itemsID}      ||= $checkout_data->{itemnumber} || '';
                $section->{biblionumber} ||= $checkout_data->{biblionumber} || '';
                $section->{title}        ||= $title;
                $section->{date}         ||= $checkout_data->{date_due} || '';
                
                my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                $log->info("Backfill CHECKOUT: Set title to '$title' for message $message_id section=$section_name");
            }
        }
    }
    } # end for each section

    return;
}

# --- helper: backfill CHECKIN identifiers ---
sub _ci_backfill_checkin_identifiers {
    my ($self, $data) = @_;
    my $log = Koha::Logger->get({ interace => 'plugin', category => 'CirriusImpact', prefix => 0 });
    
    # Determine which sections actually exist
    my @sections_to_check = ();
    push @sections_to_check, ['call', $data->{call}] if $data->{call} && ref($data->{call}) eq 'HASH';
    push @sections_to_check, ['sms', $data->{sms}] if $data->{sms} && ref($data->{sms}) eq 'HASH';
    push @sections_to_check, ['email', $data->{email}] if $data->{email} && ref($data->{email}) eq 'HASH';
    push @sections_to_check, ['whatsapp', $data->{whatsapp}] if $data->{whatsapp} && ref($data->{whatsapp}) eq 'HASH';
    
    # Process each section that exists
    for my $section_info (@sections_to_check) {
        my ($section_name, $section) = @$section_info;
        
        # Get letter code from the section
        my $letter = $section->{meta} && $section->{meta}->{letter_code} ? $section->{meta}->{letter_code} : ($data->{meta} && $data->{meta}->{letter_code} || '');
        
        $log->info("_ci_backfill_checkin_identifiers: section=$section_name, letter=$letter");
        
        # Only work with CHECKIN notices
        next unless (($letter||'') eq 'CHECKIN');

    my $has_all = sub {
        my $result = ($section->{itemsID} && $section->{biblionumber} && $section->{title});
        $log->info("has_all check: itemsID=" . ($section->{itemsID}||'') . ", biblionumber=" . ($section->{biblionumber}||'') . ", title=" . ($section->{title}||'') . " -> result=" . ($result ? '1' : '0'));
        return $result;
    };

    # If we already have all data, nothing to do
    return if $has_all->();

    # Get patron ID
    my $pid = $data->{PatronID}
        || ($data->{patron} && $data->{patron}->{borrowernumber})
        || ($data->{call} && $data->{call}->{PatronID})
        || ($section->{PatronID});

    $log->info("Attempting to query Check-ins (old_issues) for patron: " . ($pid || 'NO PID'));

    if ($pid) {
        $log->info("Querying old_issues for borrowernumber=$pid");
        
        # Use direct SQL query to get recent check-in info from old_issues
        my $dbh = C4::Context->dbh;
        my $sql = q{
            SELECT oi.itemnumber, it.biblionumber, b.title, oi.returndate
            FROM old_issues oi
            JOIN items it ON it.itemnumber = oi.itemnumber
            JOIN biblio b ON b.biblionumber = it.biblionumber
            WHERE oi.borrowernumber = ?
              AND oi.returndate IS NOT NULL
              AND oi.returndate >= DATE_SUB(NOW(), INTERVAL 1 DAY)
            ORDER BY oi.returndate DESC
        };
        my $sth = $dbh->prepare($sql);
        $sth->execute($pid);
        
        my @checkins;
        while (my ($itemnumber, $biblionumber, $title, $returndate) = $sth->fetchrow_array) {
            push @checkins, {
                itemnumber => $itemnumber,
                biblionumber => $biblionumber,
                title => $title,
                returndate => $returndate
            };
        }
        $sth->finish;
        
        $log->info("Found " . scalar(@checkins) . " recent check-ins for patron $pid");
        
        if (@checkins) {
            # Try to match title from the script/text if available
            my $title_from_message = '';
            if ($section->{script}) {
                # Extract title from: "...item was checked in: [TITLE]. Thank you!"
                if ($section->{script} =~ /checked in:\s+(.+?)\.\s+Thank you/i) {
                    $title_from_message = $1;
                    $title_from_message =~ s/^\s+|\s+$//g;  # trim whitespace
                    $log->info("Extracted title from script: '$title_from_message'");
                }
            } elsif ($section->{text}) {
                # Extract title from SMS text if present
                if ($section->{text} =~ /checked in:\s+(.+?)\.\s+Thank you/i) {
                    $title_from_message = $1;
                    $title_from_message =~ s/^\s+|\s+$//g;
                    $log->info("Extracted title from text: '$title_from_message'");
                }
            }
            
            # Find matching check-in by title
            my $checkin_data;
            if ($title_from_message) {
                for my $c (@checkins) {
                    my $db_title = $c->{title} || '';
                    $db_title =~ s/\s*[\/\:]?\s*$//;  # Trim trailing / : and spaces
                    if ($db_title eq $title_from_message || $db_title =~ /^\Q$title_from_message\E/) {
                        $checkin_data = $c;
                        $log->info("Matched title '$title_from_message' to check-in item " . $c->{itemnumber});
                        last;
                    }
                }
            }
            
            # Fallback: use yaml_doc_index if no match found
            unless ($checkin_data) {
                my $yaml_doc_index = $data->{message_type}->{yaml_doc_index} // 0;
                my $index = $yaml_doc_index % scalar(@checkins);
                $checkin_data = $checkins[$index];
                $log->info("No title match, using index $index (yaml_doc $yaml_doc_index)");
            }
            
            if ($checkin_data) {
                my $title = $checkin_data->{title} || '';

                $section->{itemsID}      ||= $checkin_data->{itemnumber} || '';
                $section->{biblionumber} ||= $checkin_data->{biblionumber} || '';
                $section->{title}        ||= $title;
                $section->{date}         ||= $checkin_data->{returndate} || '';
                
                my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                $log->info("Backfill CHECKIN: Set title to '$title' for message $message_id section=$section_name");
            }
        }
    }
    } # end for each section

    return;
}

# --- helper: ensure title appears in text/script ---

sub _ci_insert_title_into_text {
    my ($self_or_text, $title_or_text, $maybe_title) = @_;
    
    # Handle both method and function call styles
    my ($text, $title);
    if (ref($self_or_text)) {
        # Called as method: $self->_ci_insert_title_into_text($text, $title)
        $text = $title_or_text;
        $title = $maybe_title;
    } else {
        # Called as function: _ci_insert_title_into_text($text, $title)
        $text = $self_or_text;
        $title = $title_or_text;
    }
    
    return $text unless defined $text;
    return $text unless defined $title && $title ne '';
    return $text if index($text, $title) >= 0;   # don't double-insert

    # squeeze repeat spaces
    $text =~ s/\s{2,}/ /g;

    # Replace literal placeholder if present
    if ($text =~ /<<\s*biblio\.title\s*>>/) {
        $text =~ s/<<\s*biblio\.title\s*>>/$title/g;
        return $text;
    }

    # Insert right after 'overdue:' (handles 'overdue :' too)
    if ($text =~ /(overdue\s*:\s*)/i) {
        $text =~ s/(overdue\s*:\s*)/$1$title /i;
        return $text;
    }

    # Fallback: append
    $text .= " Title: $title";
    return $text;
}


1;
# --- CirriusImpact: direct title lookup helpers ---
sub _ci_get_title {
    my (%args) = @_;

    if ( my $itemnumber = $args{itemnumber} ) {
        my $item = Koha::Items->find($itemnumber);
        return $item ? ($item->biblio->title // '') : '';
    }
    if ( my $biblionumber = $args{biblionumber} ) {
        my $biblio = Koha::Biblios->find($biblionumber);
        return $biblio ? ($biblio->title // '') : '';
    }
    if ( my $issue_id = $args{issue_id} ) {
        my $issue = Koha::Checkouts->find($issue_id);
        return $issue ? ($issue->item->biblio->title // '') : '';
    }
    if ( my $reserve_id = $args{reserve_id} ) {
        my $hold = Koha::Holds->find($reserve_id);
        return $hold ? ($hold->biblio->title // '') : '';
    }
    return '';
}

sub _ci_guess_ids_from_channel {
    my ($ch) = @_;
    my %h;
    # Try common keys in various casings used by the plugin
    for my $k (qw/biblionumber biblioNumber biblio_id biblioId BiblioNumber/) {
        $h{biblionumber} ||= $ch->{$k} if defined $ch->{$k} && $ch->{$k} ne '';
    }
    for my $k (qw/itemnumber itemNumber itemsID ItemRecordID ItemNumber/) {
        $h{itemnumber} ||= $ch->{$k} if defined $ch->{$k} && $ch->{$k} ne '';
    }
    for my $k (qw/issue_id issueId issueID/){
        $h{issue_id} ||= $ch->{$k} if defined $ch->{$k} && $ch->{$k} ne '';
    }
    for my $k (qw/reserve_id request_id ReserveId RequestID/) {
        $h{reserve_id} ||= $ch->{$k} if defined $ch->{$k} && $ch->{$k} ne '';
    }
    return %h;
}

sub _ci_fill_titles {
    my ($data) = @_;
    return unless $data && ref($data) eq 'HASH';

    # Inherit IDs from top-level biblio if channels lack them
    my $b = $data->{biblio};
    if ($b && ref($b) eq 'HASH') {
        for my $k (qw/call sms email whatsapp/) {
            next unless exists $data->{$k} && ref($data->{$k}) eq 'HASH';
            $data->{$k}->{biblionumber} ||= $b->{biblionumber} if defined $b->{biblionumber};
        }
    }

    for my $k (qw/call sms email whatsapp/) {
        next unless exists $data->{$k} && ref($data->{$k}) eq 'HASH';
        my $ch = $data->{$k};
        next if defined $ch->{title} && $ch->{title} ne '';

        # Try direct Koha lookups first (preferred)
        my %ids = _ci_guess_ids_from_channel($ch);
        my $title = '';
        $title ||= _ci_get_title( itemnumber   => $ids{itemnumber} )   if $ids{itemnumber};
        $title ||= _ci_get_title( biblionumber => $ids{biblionumber} ) if $ids{biblionumber};
        $title ||= _ci_get_title( issue_id     => $ids{issue_id} )     if $ids{issue_id};
        $title ||= _ci_get_title( reserve_id   => $ids{reserve_id} )   if $ids{reserve_id};

        # If still blank, fall back to top-level biblio info
        if (!$title || $title eq '') {
            if ($b && ref($b) eq 'HASH' && defined $b->{title} && $b->{title} ne '') {
                $title = $b->{title};
            } elsif ($b && ref($b) eq 'HASH' && $b->{biblionumber}) {
                my $t = _ci_get_title( biblionumber => $b->{biblionumber} );
                $title = $t if defined $t && $t ne '';
            }
        }

# Patron-level overdue fallback (ODUE): if still empty and we have PatronID
if ((!defined $title || $title eq '') && ($data->{PatronID} || ($data->{sms} && $data->{sms}->{PatronID}) || ($data->{call} && $data->{call}->{PatronID}))) {
    my $pid = $data->{PatronID} || ($data->{sms} && $data->{sms}->{PatronID}) || ($data->{call} && $data->{call}->{PatronID});
    my $t2 = _ci_overdue_title_for_patron($pid);
    $title = $t2 if defined $t2 && $t2 ne '';
}
# Only set title if it's not already set (don't overwrite titles from _ci_backfill_odue_identifiers)
$ch->{title} = $title if (defined $title && $title ne '' && (!defined $ch->{title} || $ch->{title} eq ''));

    }
}


# --- end helpers ---
# Needs: use Koha::DateUtils qw(dt_from_string);
#        use Koha::Issues;

sub _ci_backfill_odue_identifiers {
    my ($self, $data) = @_;
    my $log = Koha::Logger->get({ interace => 'plugin', category => 'CirriusImpact', prefix => 0 });
    
    # Determine which sections actually exist (not just what transport says)
    my @sections_to_check = ();
    push @sections_to_check, ['call', $data->{call}] if $data->{call} && ref($data->{call}) eq 'HASH';
    push @sections_to_check, ['sms', $data->{sms}] if $data->{sms} && ref($data->{sms}) eq 'HASH';
    
    # Process each section that exists
    for my $section_info (@sections_to_check) {
        my ($section_name, $section) = @$section_info;
        
        # Get letter code from the section
        my $letter = $section->{meta} && $section->{meta}->{letter_code} ? $section->{meta}->{letter_code} : ($data->{meta} && $data->{meta}->{letter_code} || '');
        
        $log->info("_ci_backfill_odue_identifiers: section=$section_name, letter=$letter");
        
        # Work with all ODUE variants (ODUE, ODUE2, ODUE3, etc.)
        next unless (($letter||'') =~ /^ODUE/);

    my $has_all = sub {
        my $result = ($section->{itemsID} && $section->{biblionumber} && $section->{title});
        $log->info("has_all check: itemsID=" . ($section->{itemsID}||'') . ", biblionumber=" . ($section->{biblionumber}||'') . ", title=" . ($section->{title}||'') . " -> result=" . ($result ? '1' : '0'));
        return $result;
    };

    # 1) Try existing items array (if earlier code built one)
    if (!$has_all->() && ref($data->{items}) eq 'ARRAY' && @{$data->{items}}) {
        # pick the earliest due if present, else first
        my @items = @{$data->{items}};
        @items = sort {
            (($a->{date_due} // $a->{due_date} // '') cmp ($b->{date_due} // $b->{due_date} // ''))
        } @items if (defined $items[0]{date_due} || defined $items[0]{due_date});

        my $it0 = $items[0] || {};
        $section->{itemsID}      ||= $it0->{itemnumber} || '';
        $section->{biblionumber} ||= $it0->{biblionumber} || ($it0->{biblio} && $it0->{biblio}->{biblionumber}) || '';
        $section->{title}        ||= $it0->{title} || ($it0->{biblio} && $it0->{biblio}->{title}) || '';
        $section->{date}         ||= $it0->{date_due} || $it0->{due_date} || '';
    }

    # 2) If still missing, query Issues for overdue items for this patron
    if (!$has_all->()) {
        my $pid = $data->{PatronID}
            || ($data->{patron} && $data->{patron}->{borrowernumber})
            || ($data->{call} && $data->{call}->{PatronID})
            || ($section->{PatronID});

        $log->info("Attempting to query Issues for patron: " . ($pid || 'NO PID'));

        if ($pid) {
            $log->info("Querying Issues directly for borrowernumber=$pid");
            
            # Use direct SQL query like _ci_overdue_title_for_patron does
            my $dbh = C4::Context->dbh;
            my $sql = q{
                SELECT i.itemnumber, it.biblionumber, b.title, i.date_due
                FROM issues i
                JOIN items it ON it.itemnumber = i.itemnumber
                JOIN biblio b ON b.biblionumber = it.biblionumber
                WHERE i.borrowernumber = ?
                  AND i.returndate IS NULL
                  AND i.date_due < NOW()
                ORDER BY i.date_due ASC
            };
            my $sth = $dbh->prepare($sql);
            $sth->execute($pid);
            
            my @overdue_issues;
            while (my ($itemnumber, $biblionumber, $title, $date_due) = $sth->fetchrow_array) {
                push @overdue_issues, {
                    itemnumber => $itemnumber,
                    biblionumber => $biblionumber,
                    title => $title,
                    date_due => $date_due
                };
            }
            $sth->finish;
            
            $log->info("Found " . scalar(@overdue_issues) . " overdue issues for patron $pid");
            
            if (@overdue_issues) {
                # Use yaml_doc_index to distribute titles across different overdue items
                # This ensures each YAML document gets a different overdue item
                my $yaml_doc_index = $data->{message_type}->{yaml_doc_index} // 0;
                my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                
                # Map different YAML docs to different items (for multi-document YAML)
                my $index = $yaml_doc_index % scalar(@overdue_issues);
                
                $log->info("Message $message_id, YAML doc $yaml_doc_index -> using overdue item at index $index");
                
                my $issue_data = $overdue_issues[$index];
                
                if ($issue_data) {
                    my $title = $issue_data->{title} || '';

                    $section->{itemsID}      ||= $issue_data->{itemnumber} || '';
                    $section->{biblionumber} ||= $issue_data->{biblionumber} || '';
                    $section->{title}        ||= $title;
                    # also useful to surface the actual due date
                    $section->{date}         ||= $issue_data->{date_due} || '';
                    
                    $log->info("Backfill ODUE: Set title to '$title' for message section=$section_name");
                }
            }
        }
    }
    } # end for each section

    return;
}

# --- Added by CirriusImpact v1.1.3 ---
sub _ci_postprocess_messages_with_titles {
    my ($export) = @_;
    return unless $export && ref($export) eq 'HASH';
    my $msgs = $export->{messages} // [];
    for my $m (@$msgs) {
        my $mt = $m->{message_type} || {};
        if (my $sms = $mt->{sms}) {
            if (defined $sms->{title} && $sms->{title} ne '') {
                $sms->{text} = _ci_insert_title_into_text($sms->{text} // '', $sms->{title});
            }
        }
        if (my $call = $mt->{call}) {
            if (defined $call->{title} && $call->{title} ne '') {
                $call->{script} = _ci_insert_title_into_text($call->{script} // '', $call->{title});
            }
        }
    }
}

# Guarded helper definition (avoid "redefined" warnings across reloads)
BEGIN {
    no warnings 'redefine';
    my $fq = 'Koha::Plugin::Com::CirriusImpact::_ci_insert_title_into_text';
    unless (defined &{$fq}) {
        *{$fq} = sub {
            my ($self, $text, $title) = @_;
            return $text if !defined $text || $text eq '';
            return $text if !defined $title || $title eq '';
            # simple placeholder replacement: {{TITLE}} or legacy marker
            $text =~ s/\{\{TITLE\}\}/$title/g;
            $text =~ s/<<biblio\.title>>/$title/g;   # legacy fallback
            return $text;
        };
    }
}

BEGIN {
    no warnings 'redefine';
    if (defined &Koha::Plugin::Com::CirriusImpact::_ci_emit_json && !defined &Koha::Plugin::Com::CirriusImpact::_ci_emit_json_original) {
        *Koha::Plugin::Com::CirriusImpact::_ci_emit_json_original = \&Koha::Plugin::Com::CirriusImpact::_ci_emit_json;
        *Koha::Plugin::Com::CirriusImpact::_ci_emit_json = sub {
            my ($self, $export) = @_;
            _ci_postprocess_messages_with_titles($export);
            return $self->_ci_emit_json_original($export);
        };
    }
}
# --- end added v1.1.3 ---

# --- PREDUE title helpers (match rendered messageText to DB item) ---
sub _ci_normalize_title_for_backfill {
    my ($title) = @_;
    return '' unless defined $title && $title ne '';
    $title =~ s/\s*[\/\:]?\s*$//;
    $title =~ s/^\s+|\s+$//g;
    return $title;
}

sub _ci_titles_match_for_backfill {
    my ($a, $b) = @_;
    $a = _ci_normalize_title_for_backfill($a);
    $b = _ci_normalize_title_for_backfill($b);
    return 0 unless $a ne '' && $b ne '';
    return 1 if $a eq $b;
    return 1 if $a =~ /^\Q$b\E/ || $b =~ /^\Q$a\E/;
    return 0;
}

sub _ci_extract_predue_title_from_message {
    my ($section) = @_;
    return '' unless ref($section) eq 'HASH';

    my $text = '';
    if (defined $section->{script} && $section->{script} ne '') {
        $text = $section->{script};
    } elsif (defined $section->{text} && $section->{text} ne '') {
        $text = $section->{text};
    }
    return '' unless $text ne '';

    my $take = sub {
        my ($candidate) = @_;
        return _ci_normalize_title_for_backfill($candidate);
    };

    if ($text =~ /will be due soon:\s*(.+?)\s*\.(?:\s|$)/iu) {
        return $take->($1);
    }
    if ($text =~ /due soon:\s*(.+?)\s*\.(?:\s|$)/iu) {
        return $take->($1);
    }
    if ($text =~ /(?:is\s+)?now due:\s*(.+?)\s*\.(?:\s|$)/iu) {
        return $take->($1);
    }
    if ($text =~ /:\s*(.+?)\s+is due\b/iu) {
        return $take->($1);
    }
    if ($text =~ /\b(.+?)\s+is due\s+[\d\/\-]/iu) {
        return $take->($1);
    }
    if ($text =~ /:\s*(.+?)\s*\.(?:\s*(?:Thank you|Please|Call|Questions).*)?$/iu) {
        return $take->($1);
    }
    return '';
}

sub _ci_match_predue_upcoming_item {
    my ($upcoming_items, $section, $data, $log) = @_;
    my $title_from_message = _ci_extract_predue_title_from_message($section);
    if ($title_from_message) {
        $log->info("Extracted PREDUE title from message: '$title_from_message'");
        for my $item (@$upcoming_items) {
            if (_ci_titles_match_for_backfill($title_from_message, $item->{title})) {
                $log->info("Matched PREDUE title '$title_from_message' to item " . ($item->{itemnumber} // ''));
                return $item;
            }
        }
        $log->info("No PREDUE DB match for extracted title '$title_from_message'");
    }

    my $yaml_doc_index = $data->{message_type}->{yaml_doc_index} // 0;
    my $index = $yaml_doc_index % scalar(@$upcoming_items);
    my $fallback = $upcoming_items->[$index];
    $log->info("PREDUE fallback to upcoming item index $index (yaml_doc $yaml_doc_index)");
    return $fallback;
}

# --- helper: backfill PREDUE identifiers ---
sub _ci_backfill_predue_identifiers {
    my ($self, $data) = @_;
    my $log = Koha::Logger->get({ interace => 'plugin', category => 'CirriusImpact', prefix => 0 });
    
    # Determine which sections actually exist (not just what transport says)
    # Check all possible transport sections
    my @sections_to_check = ();
    push @sections_to_check, ['call', $data->{call}] if $data->{call} && ref($data->{call}) eq 'HASH';
    push @sections_to_check, ['sms', $data->{sms}] if $data->{sms} && ref($data->{sms}) eq 'HASH';
    push @sections_to_check, ['email', $data->{email}] if $data->{email} && ref($data->{email}) eq 'HASH';
    push @sections_to_check, ['whatsapp', $data->{whatsapp}] if $data->{whatsapp} && ref($data->{whatsapp}) eq 'HASH';
    
    # Process each section that exists
    for my $section_info (@sections_to_check) {
        my ($section_name, $section) = @$section_info;
        
        # Get letter code from the section
        my $letter = $section->{meta} && $section->{meta}->{letter_code} ? $section->{meta}->{letter_code} : ($data->{meta} && $data->{meta}->{letter_code} || '');
        
        $log->info("_ci_backfill_predue_identifiers: section=$section_name, letter=$letter");
        
        # Only work with PREDUE notices (PREDUE and PREDUEDGST)
        next unless (($letter||'') =~ /^PREDUE/);

        my $has_all = sub {
            my $result = ($section->{itemsID} && $section->{biblionumber} && $section->{title});
            $log->info("has_all check: itemsID=" . ($section->{itemsID}||'') . ", biblionumber=" . ($section->{biblionumber}||'') . ", title=" . ($section->{title}||'') . " -> result=" . ($result ? '1' : '0'));
            return $result;
        };

        # If we already have all data, nothing to do for this transport section
        next if $has_all->();

        # Get patron ID
        my $pid = $data->{PatronID}
            || ($data->{patron} && $data->{patron}->{borrowernumber})
            || ($data->{call} && $data->{call}->{PatronID})
            || ($section->{PatronID});

        $log->info("Attempting to query upcoming due items for patron: " . ($pid || 'NO PID'));

        if ($pid) {
            $log->info("Querying upcoming due items for borrowernumber=$pid");
            
            # Use direct SQL query to get upcoming due items (similar to advance_notices.pl)
            my $dbh = C4::Context->dbh;
            my $sql = q{
                SELECT i.itemnumber, it.biblionumber, b.title, i.date_due, i.issue_id
                FROM issues i
                JOIN items it ON it.itemnumber = i.itemnumber
                JOIN biblio b ON b.biblionumber = it.biblionumber
                WHERE i.borrowernumber = ?
                  AND i.date_due IS NOT NULL
                ORDER BY i.date_due ASC
                LIMIT 10
            };
            my $sth = $dbh->prepare($sql);
            $sth->execute($pid);
            my @upcoming_items;
            while (my ($itemnumber, $biblionumber, $title, $date_due, $issue_id) = $sth->fetchrow_array) {
                push @upcoming_items, {
                    itemnumber => $itemnumber,
                    biblionumber => $biblionumber,
                    title => $title,
                    date_due => $date_due,
                    issue_id => $issue_id
                };
                $log->info("Found item: $itemnumber, title: $title, due: $date_due");
            }
            $sth->finish;
            
            $log->info("Found " . scalar(@upcoming_items) . " upcoming due items for patron $pid");
            
            if (@upcoming_items) {
                # For PREDUE messages, populate the data directly from the database
                # since the template variables are often empty
                
                # Check if this is a digest message (PREDUEDGST) or single message (PREDUE)
                if ($letter =~ /DGST$/) {
                    # For digest messages, use the first item but try to build a proper digest message
                    my $matched_item = $upcoming_items[0];
                    $log->info("Using first upcoming item " . $matched_item->{itemnumber} . " for PREDUEDGST backfill");
                    
                    if ($matched_item) {
                        my $title = $matched_item->{title} || '';
                        $section->{itemsID}      ||= $matched_item->{itemnumber} || '';
                        $section->{biblionumber} ||= $matched_item->{biblionumber} || '';
                        $section->{title}        ||= $title;
                        $section->{date}         ||= $matched_item->{date_due} || '';
                        
                        my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                        $log->info("Backfill PREDUEDGST: Set title to '$title' for message $message_id section=$section_name");
                        
                        # For digest messages, try to build a proper message with all items
                        if ($section->{text} && $section->{text} =~ /is due \./) {
                            my $new_text = $section->{text};
                            if (scalar(@upcoming_items) > 1) {
                                # Build digest message with multiple items
                                my @titles = map { $_->{title} } @upcoming_items;
                                my $titles_str = join('; ', @titles);
                                $new_text =~ s/is due \./are due $matched_item->{date_due}/;
                                $new_text =~ s/:\s+are due/: $titles_str are due/;
                            } else {
                                # Single item message
                                $new_text =~ s/is due \./is due $matched_item->{date_due}/;
                                $new_text =~ s/:\s+is due/: $title is due/;
                            }
                            $section->{text} = $new_text;
                            $log->info("Updated digest message text to: '$new_text'");
                        }
                    }
                } else {
                    # Single PREDUE: match rendered text/script to the correct upcoming item
                    my $matched_item = _ci_match_predue_upcoming_item(\@upcoming_items, $section, $data, $log);
                    $log->info("Using upcoming item " . ($matched_item->{itemnumber} // '') . " for PREDUE backfill");
                    
                    if ($matched_item) {
                        my $title = $matched_item->{title} || '';
                        $section->{itemsID}      ||= $matched_item->{itemnumber} || '';
                        $section->{biblionumber} ||= $matched_item->{biblionumber} || '';
                        $section->{title}        ||= $title;
                        $section->{date}         ||= $matched_item->{date_due} || '';
                        
                        my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                        $log->info("Backfill PREDUE: Set title to '$title' for message $message_id section=$section_name");
                        
                        # Also try to update the message text if it's empty or has empty variables
                        if ($section->{text} && $section->{text} =~ /is due \./) {
                            my $new_text = $section->{text};
                            $new_text =~ s/is due \./is due $matched_item->{date_due}/;
                            $new_text =~ s/:\s+is due/: $title is due/;
                            $section->{text} = $new_text;
                            $log->info("Updated message text to: '$new_text'");
                        }
                    }
                }
            }
        }
    }
    return;
}

# --- helper: backfill additional message types ---
sub _ci_backfill_additional_identifiers {
    my ($self, $data) = @_;
    my $log = Koha::Logger->get({ interace => 'plugin', category => 'CirriusImpact', prefix => 0 });
    
    # Determine which sections actually exist (not just what transport says)
    # Check all possible transport sections
    my @sections_to_check = ();
    push @sections_to_check, ['call', $data->{call}] if $data->{call} && ref($data->{call}) eq 'HASH';
    push @sections_to_check, ['sms', $data->{sms}] if $data->{sms} && ref($data->{sms}) eq 'HASH';
    push @sections_to_check, ['email', $data->{email}] if $data->{email} && ref($data->{email}) eq 'HASH';
    push @sections_to_check, ['whatsapp', $data->{whatsapp}] if $data->{whatsapp} && ref($data->{whatsapp}) eq 'HASH';
    
    # Process each section that exists
    for my $section_info (@sections_to_check) {
        my ($section_name, $section) = @$section_info;
        
        # Get letter code from the section
        my $letter = $section->{meta} && $section->{meta}->{letter_code} ? $section->{meta}->{letter_code} : ($data->{meta} && $data->{meta}->{letter_code} || '');
        
        $log->info("_ci_backfill_additional_identifiers: section=$section_name, letter=$letter");
        
        # Only work with the new message types
        next unless (($letter||'') =~ /^(HOLD|HOLD_CHANGED|HOLD_REMINDER|HOLD_SLIP|MEMBERSHIP_EXPIRY|MEMBERSHIP_RENEWED|RENEWAL|AUTO_RENEWALS|AUTO_RENEWALS_DGST|WELCOME|ACCOUNT_CREDIT|ACCOUNT_DEBIT|ACCOUNT_PAYMENT|ACCOUNT_WRITEOFF|ACCOUNTS_SUMMARY|HOLDPLACED|HOLDPLACED_PATRON|HOLDDGST)$/);
        
        $log->info("Processing $letter message in _ci_backfill_additional_identifiers");

        my $has_all = sub {
            my $result = ($section->{itemsID} && $section->{biblionumber} && $section->{title});
            $log->info("has_all check: itemsID=" . ($section->{itemsID}||'') . ", biblionumber=" . ($section->{biblionumber}||'') . ", title=" . ($section->{title}||'') . " -> result=" . ($result ? '1' : '0'));
            return $result;
        };

        # If we already have all data, nothing to do
        return if $has_all->();

        # Get patron ID
        my $pid = $data->{PatronID}
            || ($data->{patron} && $data->{patron}->{borrowernumber})
            || ($data->{call} && $data->{call}->{PatronID})
            || ($section->{PatronID});

        $log->info("Attempting to query data for patron: " . ($pid || 'NO PID') . " for message type: $letter");

        if ($pid) {
            my $dbh = C4::Context->dbh;
            my $matched_item;
            
            # Handle different message types
            if ($letter eq 'HOLD' || $letter eq 'HOLD_SLIP' || $letter =~ /^HOLD_(CHANGED|REMINDER)$/) {
                # For HOLD / HOLD_SLIP messages, query the reserves table
                $log->info("Querying holds for borrowernumber=$pid");
                # Try to get reserve_id from the message content by querying the database
                my $reserve_id = '';
                my $message_id = $section->{meta}->{message_id} || '';
                
                if ($message_id) {
                    # Query the message_queue table to get the original content
                    my $content_sql = q{SELECT content FROM message_queue WHERE message_id = ?};
                    my $content_sth = $dbh->prepare($content_sql);
                    $content_sth->execute($message_id);
                    if (my ($content) = $content_sth->fetchrow_array) {
                        if ($content && $content =~ /hold:\s*(\d+)/) {
                            $reserve_id = $1;
                        }
                        $log->info("Extracted reserve_id: $reserve_id from message_id: $message_id");
                    } else {
                        $log->info("No content found for message_id $message_id");
                    }
                    $content_sth->finish;
                } else {
                    $log->info("No message_id available for reserve_id extraction");
                }
                
                my $sql;
                my @params;
                
                if ($reserve_id) {
                    # If we have a specific reserve_id, query for that specific hold
                    $sql = q{
                        SELECT r.reserve_id, r.biblionumber, b.title, r.reservedate, r.expirationdate, r.itemnumber
                        FROM reserves r
                        JOIN biblio b ON b.biblionumber = r.biblionumber
                        WHERE r.borrowernumber = ?
                          AND r.reserve_id = ?
                          AND r.found = 'W'
                    };
                    @params = ($pid, $reserve_id);
                } else {
                    # Fallback to getting the first hold if no reserve_id
                    $sql = q{
                        SELECT r.reserve_id, r.biblionumber, b.title, r.reservedate, r.expirationdate, r.itemnumber
                        FROM reserves r
                        JOIN biblio b ON b.biblionumber = r.biblionumber
                        WHERE r.borrowernumber = ?
                          AND r.found = 'W'
                        ORDER BY r.reservedate ASC
                        LIMIT 1
                    };
                    @params = ($pid);
                }
                
                my $sth = $dbh->prepare($sql);
                $sth->execute(@params);
                if (my ($reserve_id, $biblionumber, $title, $reservedate, $expirationdate, $itemnumber) = $sth->fetchrow_array) {
                    $matched_item = {
                        itemnumber => $itemnumber,
                        biblionumber => $biblionumber,
                        title => $title,
                        date => $expirationdate,
                        expirationdate => $expirationdate
                    };
                    $log->info("Found hold: $reserve_id, itemnumber: $itemnumber, title: $title, hold till: $expirationdate");
                } else {
                    $log->info("No hold found for borrowernumber=$pid" . ($reserve_id ? " with reserve_id=$reserve_id" : ""));
                }
                $sth->finish;
                
            } elsif ($letter =~ /^MEMBERSHIP_(EXPIRY|RENEWED)$/) {
                # For membership messages, query the borrowers table
                $log->info("Querying membership info for borrowernumber=$pid");
                my $sql = q{
                    SELECT b.borrowernumber, b.cardnumber, b.firstname, b.surname, b.dateexpiry, b.dateenrolled
                    FROM borrowers b
                    WHERE b.borrowernumber = ?
                };
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                if (my ($borrowernumber, $cardnumber, $firstname, $surname, $dateexpiry, $dateenrolled) = $sth->fetchrow_array) {
                    $matched_item = {
                        itemnumber => $borrowernumber,
                        biblionumber => $borrowernumber,
                        title => "$firstname $surname",
                        date => $dateexpiry,
                        cardnumber => $cardnumber,
                        dateenrolled => $dateenrolled
                    };
                    $log->info("Found membership: $borrowernumber, name: $firstname $surname, expires: $dateexpiry");
                }
                $sth->finish;
                
            } elsif ($letter eq 'RENEWAL' || $letter eq 'AUTO_RENEWALS' || $letter eq 'AUTO_RENEWALS_DGST') {
                # For renewal / auto-renewal messages, query current issues.
                # Digest variants pull multiple items; single variants pull one.
                my $is_digest = ($letter =~ /DGST$/) ? 1 : 0;
                $log->info("Querying current issues for borrowernumber=$pid (letter=$letter, digest=$is_digest)");
                my $sql = q{
                    SELECT i.itemnumber, it.biblionumber, b.title, i.date_due, i.issue_id
                    FROM issues i
                    JOIN items it ON it.itemnumber = i.itemnumber
                    JOIN biblio b ON b.biblionumber = it.biblionumber
                    WHERE i.borrowernumber = ?
                    ORDER BY i.date_due ASC
                };
                $sql .= $is_digest ? ' LIMIT 50' : ' LIMIT 1';
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                my @rows;
                while (my ($itemnumber, $biblionumber, $title, $date_due, $issue_id) = $sth->fetchrow_array) {
                    push @rows, {
                        itemnumber   => $itemnumber,
                        biblionumber => $biblionumber,
                        title        => $title,
                        date_due     => $date_due,
                        issue_id     => $issue_id,
                    };
                }
                $sth->finish;

                if (@rows) {
                    my $first = $rows[0];
                    if ($is_digest && @rows > 1) {
                        my @titles      = grep { defined && $_ ne '' } map { $_->{title} } @rows;
                        my @itemnumbers = grep { defined && $_ ne '' } map { $_->{itemnumber} } @rows;
                        my @raw_dates   = grep { defined && $_ ne '' } map { $_->{date_due} } @rows;
                        $matched_item = {
                            itemnumber      => $first->{itemnumber},
                            biblionumber    => $first->{biblionumber},
                            title           => $first->{title},
                            date            => $first->{date_due},
                            issue_id        => $first->{issue_id},
                            all_titles      => \@titles,
                            all_itemnumbers => \@itemnumbers,
                            all_dates       => \@raw_dates,
                        };
                        $log->info("Found " . scalar(@rows) . " renewal items for digest message, first: " . $first->{itemnumber});
                    } else {
                        $matched_item = {
                            itemnumber   => $first->{itemnumber},
                            biblionumber => $first->{biblionumber},
                            title        => $first->{title},
                            date         => $first->{date_due},
                            issue_id     => $first->{issue_id},
                        };
                        $log->info("Found renewal item: " . $first->{itemnumber} . ", title: " . $first->{title} . ", due: " . $first->{date_due});
                    }
                } else {
                    $log->info("No current issues found for borrowernumber=$pid");
                }

            } elsif ($letter eq 'WELCOME') {
                # For welcome messages, query borrower info
                $log->info("Querying borrower info for borrowernumber=$pid");
                my $sql = q{
                    SELECT b.borrowernumber, b.cardnumber, b.firstname, b.surname, b.dateenrolled, b.branchcode
                    FROM borrowers b
                    WHERE b.borrowernumber = ?
                };
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                if (my ($borrowernumber, $cardnumber, $firstname, $surname, $dateenrolled, $branchcode) = $sth->fetchrow_array) {
                    $matched_item = {
                        itemnumber => $borrowernumber,
                        biblionumber => $borrowernumber,
                        title => "$firstname $surname",
                        date => $dateenrolled,
                        cardnumber => $cardnumber,
                        branchcode => $branchcode
                    };
                    $log->info("Found welcome patron: $borrowernumber, name: $firstname $surname, enrolled: $dateenrolled");
                }
                $sth->finish;
                
            } elsif ($letter =~ /^ACCOUNT_(CREDIT|DEBIT|PAYMENT|WRITEOFF)$/) {
                # For account messages, query accountlines table
                $log->info("Querying account info for borrowernumber=$pid");
                my $sql = q{
                    SELECT al.accountlines_id, al.borrowernumber, al.amount, al.description, al.date, al.amountoutstanding
                    FROM accountlines al
                    WHERE al.borrowernumber = ?
                    ORDER BY al.date DESC
                    LIMIT 1
                };
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                if (my ($accountlines_id, $borrowernumber, $amount, $description, $date, $amountoutstanding) = $sth->fetchrow_array) {
                    $matched_item = {
                        itemnumber => $accountlines_id,
                        biblionumber => $borrowernumber,
                        title => $description || "Account transaction",
                        date => $date,
                        amount => $amount,
                        amountoutstanding => $amountoutstanding
                    };
                    $log->info("Found account transaction: $accountlines_id, amount: $amount, description: $description");
                }
                $sth->finish;
                
            } elsif ($letter eq 'ACCOUNTS_SUMMARY') {
                # For accounts summary, query total outstanding balance
                $log->info("Querying accounts summary for borrowernumber=$pid");
                my $sql = q{
                    SELECT SUM(al.amountoutstanding) as total_balance, COUNT(al.accountlines_id) as transaction_count
                    FROM accountlines al
                    WHERE al.borrowernumber = ? AND al.amountoutstanding > 0
                };
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                if (my ($total_balance, $transaction_count) = $sth->fetchrow_array) {
                    $matched_item = {
                        itemnumber => $pid,
                        biblionumber => $pid,
                        title => "Account Summary",
                        date => scalar(localtime()),
                        total_balance => $total_balance || 0,
                        transaction_count => $transaction_count || 0
                    };
                    $log->info("Found accounts summary: total balance: $total_balance, transactions: $transaction_count");
                }
                $sth->finish;
                
            } elsif ($letter =~ /^HOLDPLACED(_PATRON)?$/) {
                # For hold placed messages, query the most recent hold
                $log->info("Querying recent hold for borrowernumber=$pid");
                my $sql = q{
                    SELECT r.reserve_id, r.biblionumber, b.title, r.reservedate, r.expirationdate, r.itemnumber
                    FROM reserves r
                    JOIN biblio b ON b.biblionumber = r.biblionumber
                    WHERE r.borrowernumber = ?
                    ORDER BY r.reservedate DESC
                    LIMIT 1
                };
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                if (my ($reserve_id, $biblionumber, $title, $reservedate, $expirationdate, $itemnumber) = $sth->fetchrow_array) {
                    $matched_item = {
                        itemnumber => $itemnumber,
                        biblionumber => $biblionumber,
                        title => $title,
                        date => $expirationdate,
                        expirationdate => $expirationdate
                    };
                    $log->info("Found hold placed: $reserve_id, itemnumber: $itemnumber, title: $title, hold till: $expirationdate");
                }
                $sth->finish;
                
            } elsif ($letter eq 'HOLDDGST') {
                # For HOLDDGST messages, query all waiting holds (holds that are ready for pickup)
                $log->info("Querying waiting holds for borrowernumber=$pid");
                my $sql = q{
                    SELECT r.reserve_id, r.biblionumber, b.title, r.waitingdate, r.expirationdate, r.itemnumber
                    FROM reserves r
                    JOIN biblio b ON b.biblionumber = r.biblionumber
                    WHERE r.borrowernumber = ? AND r.found = 'W'
                    ORDER BY r.waitingdate DESC
                };
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                my @rows;
                while (my ($reserve_id, $biblionumber, $title, $waitingdate, $expirationdate, $itemnumber) = $sth->fetchrow_array) {
                    my $use_date = $expirationdate || $waitingdate || '';
                    push @rows, {
                        reserve_id         => $reserve_id,
                        biblionumber       => $biblionumber,
                        title              => $title,
                        waitingdate        => $waitingdate,
                        expirationdate     => $expirationdate,
                        itemnumber         => $itemnumber,
                        selected_date      => $use_date,
                    };
                }
                $sth->finish;

                if (@rows) {
                    my $first = $rows[0];
                    my @titles       = grep { defined && $_ ne '' } map { $_->{title} } @rows;
                    my @itemnumbers  = grep { defined && $_ ne '' } map { $_->{itemnumber} } @rows;
                    my @raw_dates    = grep { defined && $_ ne '' } map { $_->{selected_date} } @rows;
                    my $primary_date = $raw_dates[0] // '';

                    $matched_item = {
                        itemnumber        => $itemnumbers[0] // $first->{itemnumber},
                        biblionumber      => $first->{biblionumber},
                        title             => $first->{title},
                        date              => $primary_date,
                        expirationdate    => $first->{expirationdate},
                        all_titles        => \@titles,
                        all_itemnumbers   => \@itemnumbers,
                        all_dates         => \@raw_dates,
                    };

                    $log->info("Found " . scalar(@rows) . " waiting holds for borrowernumber=$pid");
                } else {
                    $log->info("No waiting holds found for borrowernumber=$pid");
                }
            }
            
            # Populate the section with found data
            if ($matched_item) {
                my $primary_title = $matched_item->{title} || '';
                my $items_id_value = '';
                my $has_multiple_items = $matched_item->{all_itemnumbers} && ref($matched_item->{all_itemnumbers}) eq 'ARRAY' && @{$matched_item->{all_itemnumbers}} > 1;
                my $has_multiple_titles = $matched_item->{all_titles} && ref($matched_item->{all_titles}) eq 'ARRAY' && @{$matched_item->{all_titles}} > 1;
                my $has_multiple_dates = $matched_item->{all_dates} && ref($matched_item->{all_dates}) eq 'ARRAY' && @{$matched_item->{all_dates}} > 1;

                if ($has_multiple_items) {
                    $items_id_value = join('; ', @{$matched_item->{all_itemnumbers}});
                } else {
                    $items_id_value = $matched_item->{itemnumber} || '';
                }

                my $title_value = '';
                if ($has_multiple_titles) {
                    $title_value = join('; ', @{$matched_item->{all_titles}});
                } else {
                    $title_value = $matched_item->{title} || '';
                }

                my $date_value = '';
                if ($has_multiple_dates) {
                    my @candidates;
                    for my $raw (@{$matched_item->{all_dates}}) {
                        next unless defined $raw && $raw ne '';
                        my $dt;
                        eval { $dt = dt_from_string($raw); };
                        my $formatted = $self->_format_date($raw);
                        push @candidates, {
                            raw       => $raw,
                            dt        => $dt,
                            formatted => $formatted,
                        } if defined $formatted && $formatted ne '';
                    }
                    if (@candidates) {
                        @candidates = sort {
                            ($a->{dt} && $b->{dt}) ? DateTime->compare($a->{dt}, $b->{dt})
                                                   : ($a->{raw} cmp $b->{raw})
                        } @candidates;
                        $date_value = $candidates[0]->{formatted};
                    } else {
                        my $fallback_raw = $matched_item->{date} || '';
                        $date_value = $self->_format_date($fallback_raw);
                    }
                } else {
                    my $raw_date = $matched_item->{date} || '';
                    $date_value = $self->_format_date($raw_date);
                }

                if ($has_multiple_items) {
                    $section->{itemsID} = $items_id_value;
                } else {
                    $section->{itemsID} ||= $items_id_value;
                }
                $section->{biblionumber} ||= $matched_item->{biblionumber} || '';
                if ($has_multiple_titles) {
                    $section->{title} = $title_value;
                } else {
                    $section->{title} ||= $title_value;
                }
                if ($has_multiple_dates) {
                    $section->{date} = $date_value;
                } else {
                    $section->{date} ||= $date_value;
                }

                if ($matched_item->{all_itemnumbers} && ref($matched_item->{all_itemnumbers}) eq 'ARRAY' && @{$matched_item->{all_itemnumbers}}) {
                    $section->{itemsID_list} = [ @{$matched_item->{all_itemnumbers}} ];
                }
                if ($matched_item->{all_titles} && ref($matched_item->{all_titles}) eq 'ARRAY' && @{$matched_item->{all_titles}}) {
                    $section->{title_list} = [ @{$matched_item->{all_titles}} ];
                }
                if ($matched_item->{all_dates} && ref($matched_item->{all_dates}) eq 'ARRAY' && @{$matched_item->{all_dates}}) {
                    my @formatted = map { $self->_format_date($_) } @{$matched_item->{all_dates}};
                    @formatted = grep { defined $_ && $_ ne '' } @formatted;
                    $section->{date_list} = \@formatted if @formatted;
                }
                
                my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                my $raw_log_date = $matched_item->{date} || '';
                $log->info("Backfill $letter: Set title to '$title_value', date to '$date_value' (raw: '$raw_log_date') for message $message_id section=$section_name");
                
                # Try to update message text if it has empty variables
                if ($section->{text} && $section->{text} =~ /(is due|expires|renewed|welcome)/i) {
                    my $new_text = $section->{text};
                    # Replace common empty patterns
                    $new_text =~ s/:\s+is due/: $primary_title is due/;
                    $new_text =~ s/:\s+expires/: $primary_title expires/;
                    $new_text =~ s/:\s+renewed/: $primary_title renewed/;
                    $new_text =~ s/:\s+welcome/: $primary_title welcome/;
                    $section->{text} = $new_text;
                    $log->info("Updated $letter message text to: '$new_text'");
                }
            }
        }
    }
    return;
}

1;
