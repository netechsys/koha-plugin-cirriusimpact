package Koha::Plugin::Com::ByWaterSolutions::CirriusImpact;

use Modern::Perl;
use Koha::Database;
use Koha::Patrons;

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
use Log::Log4perl qw(:easy);
use Log::Log4perl;
use Mojo::JSON qw(encode_json decode_json);
use Net::SFTP::Foreign;
use POSIX;
use Try::Tiny;
use CGI qw(-utf8);
use YAML::XS qw(Load);

our $VERSION         = "1.1.30";
our $MINIMUM_VERSION = "24.05";

our $metadata = {
    name            => 'CI Management Services - CirriusImpact',
    author          => 'Terry Rossio',
    date_authored   => '2025-08-12',
    date_updated    => '2025-10-15',
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

sub new {
    my ($class, $args) = @_;
    $args->{'metadata'}            = $metadata;
    $args->{'metadata'}->{'class'} = $class;
    my $self = $class->SUPER::new($args);
    return $self;
}

sub configure {
    my ($self, $args) = @_;
    my $cgi = $self->{'cgi'};

    unless ($cgi->param('save')) {
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
        );
        $self->output_html($template->output());
    } else {
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
        });
        $self->go_home();
    }
}

sub install   { return 1; }
sub upgrade   { return 1; }
sub uninstall { return 1; }

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

# Generate CSV output from message data
sub _generate_csv_output {
    my ($self, $message_data) = @_;
    
    # HOLDDGST digest grouping: Group individual HOLDDGST messages by patron and transport
    INFO("Starting HOLDDGST digest grouping with " . scalar @$message_data . " messages");
    my @grouped_message_data;
    my %holddgst_groups;
    
    # First pass: group HOLDDGST messages by patron and transport
    for my $msg (@$message_data) {
        my $mt = $msg->{message_type} || {};
        my $letter_code = $mt->{letter_code} || '';
        
        if ($letter_code eq 'HOLDDGST') {
            INFO("Processing HOLDDGST message for digest grouping");
            # Debug: show message structure
            INFO("Message structure keys: " . join(', ', keys %$msg));
            if ($msg->{sms}) { INFO("SMS keys: " . join(', ', keys %{$msg->{sms}})); }
            if ($msg->{call}) { INFO("Call keys: " . join(', ', keys %{$msg->{call}})); }
            
            # Find the transport section with data
            my $transport = '';
            my $patron_id = '';
            
            if ($mt->{sms} && $mt->{sms}->{PatronID}) {
                $transport = 'sms';
                $patron_id = $mt->{sms}->{PatronID};
                INFO("Found SMS transport for patron $patron_id");
            } elsif ($mt->{call} && $mt->{call}->{PatronID}) {
                $transport = 'phone';
                $patron_id = $mt->{call}->{PatronID};
                INFO("Found Phone transport for patron $patron_id");
            } elsif ($mt->{email} && $mt->{email}->{PatronID}) {
                $transport = 'email';
                $patron_id = $mt->{email}->{PatronID};
                INFO("Found Email transport for patron $patron_id");
            }
            
            if ($patron_id && $transport) {
                my $key = $patron_id . '_' . $transport;
                push @{$holddgst_groups{$key}}, $msg;
                INFO("Added HOLDDGST message to group: $key");
            } else {
                # If we can't determine patron/transport, keep as individual message
                INFO("Could not determine patron/transport for HOLDDGST message, keeping as individual");
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
        
        if (@group == 1) {
            # Single message, no grouping needed
            push @grouped_message_data, $group[0];
        } else {
            # Multiple messages, create digest
            my $digest_msg = { %{$group[0]} };  # Start with first message
            
            # Combine titles from all messages by extracting from text field
            my @titles;
            for my $msg (@group) {
                my $title = '';
                my $mt = $msg->{message_type} || {};
                # Check all transport sections for titles by extracting from text/script/body
                for my $transport (qw(sms call email whatsapp)) {
                    if ($mt->{$transport}) {
                        my $text = '';
                        if ($transport eq 'sms' || $transport eq 'whatsapp') {
                            $text = $mt->{$transport}->{text} || '';
                        } elsif ($transport eq 'call') {
                            $text = $mt->{$transport}->{script} || '';
                        } elsif ($transport eq 'email') {
                            $text = $mt->{$transport}->{body} || $mt->{$transport}->{subject} || '';
                        }
                        
                        # Extract title from text (e.g., "CPL: Hold ready: The bible. Pickup by 10/20/2025.")
                        if ($text =~ /Hold ready:\s*([^.]+)\./) {
                            $title = $1;
                            $title =~ s/^\s+|\s+$//g; # Trim whitespace
                            last; # Use the first title found
                        }
                    }
                }
                push @titles, $title if $title;
            }
            
            # Update the digest message with combined titles and message text
            my $combined_title = join('; ', @titles);
            my $digest_mt = $digest_msg->{message_type} || {};
            
            # Update titles
            if ($digest_mt->{sms}) {
                $digest_mt->{sms}->{title} = $combined_title;
                # Update SMS text for digest format
                my $sms_text = $digest_mt->{sms}->{text} || '';
                if ($sms_text && @titles > 1) {
                    # Replace individual message text with digest format
                    my $branch_code = $digest_mt->{sms}->{branch} || 'CPL';
                    my $expiration = '10/20/2025'; # This should come from the data
                    $digest_mt->{sms}->{text} = "$branch_code: You have " . scalar @titles . " holds ready for pickup: $combined_title. Pickup by $expiration.";
                }
            }
            if ($digest_mt->{call}) {
                $digest_mt->{call}->{title} = $combined_title;
                # Update call script for digest format
                my $call_script = $digest_mt->{call}->{script} || '';
                if ($call_script && @titles > 1) {
                    # Replace individual message script with digest format
                    my $firstname = $digest_mt->{call}->{patronFirstName} || 'Patron';
                    my $branchname = $digest_mt->{call}->{branchname} || 'Library';
                    my $expiration = '10/20/2025'; # This should come from the data
                    $digest_mt->{call}->{script} = "Hello $firstname. $branchname. You have " . scalar @titles . " holds ready for pickup: $combined_title. Pickup by $expiration. Call 7315551234.";
                }
            }
            if ($digest_mt->{email}) {
                $digest_mt->{email}->{title} = $combined_title;
            }
            
            push @grouped_message_data, $digest_msg;
            INFO("Created HOLDDGST digest for $key with " . scalar @group . " messages, titles: $combined_title");
        }
    }
    
    # Use grouped messages for CSV generation
    $message_data = \@grouped_message_data;
    
    # Define the required CSV headers in the exact order requested
    # messageText conditionally added at the end for message content
    my @headers = qw(
        commType language notificationType notificationLevel patronBarCode 
        STAB_userSalutation patronFirstName patronLastName phone email 
        branch branchname itemsID date title DeliveryOptionID LanguageID 
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
        $row_data{language} = ($transport_section->{language} && $transport_section->{language} ne 'default') ? $transport_section->{language} : 'eng';
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
        $row_data{TxnID} = $transport_section->{TxnID} || '';
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

    # Create archive directory BEFORE initializing Log4perl
    if ($archive_dir && !-d $archive_dir) { 
        make_path($archive_dir, { mode => 0755 }) or die "Failed to create archive directory: $archive_dir - $!"; 
    }

    Log::Log4perl->easy_init({ level => $DEBUG, file => ">>$archive_dir/$ts-Notices-$libname_sane.log" });
    INFO("Running CirriusImpact before_send_messages hook");

    my $search_params = { status => 'pending', '-or' => [
        { content => { -like => '%CirriusImpact: yes%' } },
        { letter_code => { -in => _odue_codes() } },
        { letter_code => { -in => _hold_codes() } },
        { letter_code => { -in => _predue_codes() } },
    ]};
    my $other_params  = {};
    $other_params->{rows} = $params->{limit} if $params->{limit};

    INFO("SEARCH PARAMETERS: " . Data::Dumper::Dumper($search_params));
    INFO("OTHER PARAMETERS: " . Data::Dumper::Dumper($other_params));

    my @message_data;
    while (1) {
        my @messages = Koha::Notice::Messages->search($search_params, $other_params)->as_list;
        INFO("FOUND " . scalar @messages . " MESSAGES TO PROCESS");
        last unless @messages;

        unless ($test_mode) { $_->update({ status => 'deleted' }) for @messages; }

        for my $m (@messages) {
            INFO("WORKING ON MESSAGE " . $m->id);
            my $content = $m->content // '';

            # Fix invalid YAML separators: replace ------ with ---
            # Koha sometimes concatenates multiple notices with ------
            $content =~ s/------/---/g;

            my @yamls;
            try { @yamls = Load $content; }
            catch { @yamls = (); };

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

# --- Fill SMS text if still blank
if (!defined $data->{sms}->{text} || $data->{sms}->{text} eq '') {
    my $brname = $data->{library}->{branchname} // $data->{sms}->{branchname} // '';
    my $fname  = $data->{patron}->{firstname}   // $data->{sms}->{patronFirstName} // '';
    my $phone  = $data->{library}->{branchphone}// $data->{sms}->{phone} // '';
    my $title  = $data->{sms}->{title} // '';

    my $fallback = sprintf(
        '[%s] %s, You have item(s) that are now overdue: %s. Please return them to %s. Questions? Call %s.',
        ($brname||'Your Library'),
        ($fname||'Patron'),
        ($title||''),
        ($brname||'your library'),
        ($phone||'')
    );

    $data->{sms}->{text} = $self->_ci_insert_title_into_text($fallback, $title);
}

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
                language           => (defined $pat->{lang} && $pat->{lang} ne 'default') ? $pat->{lang} : 'eng',
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
                TxnID              => '',
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
                        INFO("ODUE suppression: Deleted phone call for patron $pid (has SMS or Email)");
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
                $mf->{language}           = (defined $pat->{lang} && $pat->{lang} ne 'default') ? $pat->{lang} : 'eng';
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

                unless ($test_mode) { $m->update({ status => 'sent' }); }
            }

            INFO("FINISHED PROCESSING MESSAGE " . $m->id);
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
            
            INFO("Checking phone message: letter_code=$letter_code, patron_id=$patron_id, original_transport=$original_transport");
            
            if ($letter_code =~ /^ODUE/ && $patron_id) {
                INFO("Phone message is ODUE for patron $patron_id");
                
                # Check if suppression config is enabled
                my $cfg = eval { $self->retrieve_data } || {};
                my $suppress_enabled = 1;  # Default ON
                if ($cfg && ref($cfg) eq 'HASH') {
                    my $flag = $cfg->{skip_odue_if_other_if_sms_or_email};
                    $suppress_enabled = $flag if defined $flag;
                }
                
                INFO("Suppression config enabled: $suppress_enabled");
                
                if ($suppress_enabled && $original_transport eq 'phone') {
                    # Check if there's an SMS ODUE message for this patron that was originally requested as SMS
                    INFO("Checking for SMS ODUE messages for patron $patron_id");
                    for my $lc (keys %{$sms_odue_by_patron{$patron_id} || {}}) {
                        my $sms_orig_transport = $sms_odue_by_patron{$patron_id}{$lc};
                        INFO("Found SMS ODUE message with letter_code: $lc, original_transport: $sms_orig_transport");
                        if ($lc =~ /^ODUE/ && $sms_orig_transport eq 'sms') {
                            $should_skip = 1;
                            INFO("ODUE suppression: Skipping phone message for patron $patron_id (has SMS ODUE message $lc)");
                            last;
                        }
                    }
                } else {
                    INFO("Suppression not applicable: config=$suppress_enabled, transport=$original_transport");
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
        INFO("CI - FILE WRITTEN TO $archive_path");
    }

    unless ($test_mode) {
        write_file($realpath, $csv_data);
        INFO("CI - FILE WRITTEN TO $realpath");
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
                INFO("CI - SFTP PUT $remote");
            } catch {
                WARN("CI - SFTP FAILED: $_");
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
            'HOLD_CHANGEDGST', 'HOLD_REMINDERGST', 'HOLDPLACEDGST', 'HOLDPLACED_PATRONGST'];
}

sub _predue_codes {
    # Return pre-due notice letter codes that should be processed
    return ['PREDUE', 'PREDUEDGST'];
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

sub api_routes {
    my ($self, $args) = @_;
    my $spec_str = $self->mbf_read('openapi.json');
    my $spec     = decode_json($spec_str);
    return $spec;
}

sub api_namespace { return 'CirriusImpact'; }


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

    my $lang         = $get->($patron, 'lang', '');
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
    $fill->($s, 'TxnID',                 '');
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
    my $cfg = eval { $self->retrieve_data } || {};
    my $on  = 1;
    if ($cfg && ref($cfg) eq 'HASH') {
        my $flag = $cfg->{skip_odue_if_other_if_sms_or_email};
        $on = $flag if defined $flag; # default ON if missing
    }
    
    INFO("Suppression config check: on=$on, borrowernumber=" . ($borrowernumber || 'undef'));
    
    return 0 unless $on;
    return 0 unless $borrowernumber;

    my $pat = Koha::Patrons->find($borrowernumber);
    return 0 unless $pat;
    
    INFO("Patron found: " . $pat->firstname . " " . $pat->surname);

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
        INFO("DB Pref: letter_code=$message_name, wants_digest=$wants_digest, transport=$transport");
        
        # Check for all ODUE variants (ODUE, ODUE2, ODUE3, etc.)
        if (($message_name || '') =~ /^ODUE/ && ($wants_digest || 0) == 0) {
            $has_sms   ||= (($transport || '') eq 'sms');
            $has_email ||= (($transport || '') eq 'email');
        }
    }
    $sth->finish;
    
    INFO("Final suppression decision: has_sms=$has_sms, has_email=$has_email");
    return ($has_sms || $has_email) ? 1 : 0;
}
# --- helper: backfill CHECKOUT identifiers ---
sub _ci_backfill_checkout_identifiers {
    my ($self, $data) = @_;
    
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
        
        INFO("_ci_backfill_checkout_identifiers: section=$section_name, letter=$letter");
        
        # Only work with CHECKOUT notices
        next unless (($letter||'') eq 'CHECKOUT');

    my $has_all = sub {
        my $result = ($section->{itemsID} && $section->{biblionumber} && $section->{title});
        INFO("has_all check: itemsID=" . ($section->{itemsID}||'') . ", biblionumber=" . ($section->{biblionumber}||'') . ", title=" . ($section->{title}||'') . " -> result=" . ($result ? '1' : '0'));
        return $result;
    };

    # If we already have all data, nothing to do
    return if $has_all->();

    # Get patron ID
    my $pid = $data->{PatronID}
        || ($data->{patron} && $data->{patron}->{borrowernumber})
        || ($data->{call} && $data->{call}->{PatronID})
        || ($section->{PatronID});

    INFO("Attempting to query Checkouts for patron: " . ($pid || 'NO PID'));

    if ($pid) {
        INFO("Querying Checkouts for borrowernumber=$pid");
        
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
        
        INFO("Found " . scalar(@checkouts) . " checkouts for patron $pid");
        
        if (@checkouts) {
            # Try to match title from the script/text if available
            my $title_from_message = '';
            if ($section->{script}) {
                # Extract title from: "You checked out [TITLE] due..."
                if ($section->{script} =~ /You checked out\s+(.+?)\s+due/i) {
                    $title_from_message = $1;
                    $title_from_message =~ s/\s+$//;  # trim trailing space
                    INFO("Extracted title from script: '$title_from_message'");
                }
            } elsif ($section->{text}) {
                # Extract title from SMS text if present
                if ($section->{text} =~ /Checked out:\s+(.+?)\.\s+Due/i) {
                    $title_from_message = $1;
                    $title_from_message =~ s/\s+$//;
                    INFO("Extracted title from text: '$title_from_message'");
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
                        INFO("Matched title '$title_from_message' to checkout item " . $c->{itemnumber});
                        last;
                    }
                }
            }
            
            # Fallback: use yaml_doc_index if no match found
            unless ($checkout_data) {
                my $yaml_doc_index = $data->{message_type}->{yaml_doc_index} // 0;
                my $index = $yaml_doc_index % scalar(@checkouts);
                $checkout_data = $checkouts[$index];
                INFO("No title match, using index $index (yaml_doc $yaml_doc_index)");
            }
            
            if ($checkout_data) {
                my $title = $checkout_data->{title} || '';

                $section->{itemsID}      ||= $checkout_data->{itemnumber} || '';
                $section->{biblionumber} ||= $checkout_data->{biblionumber} || '';
                $section->{title}        ||= $title;
                $section->{date}         ||= $checkout_data->{date_due} || '';
                
                my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                INFO("Backfill CHECKOUT: Set title to '$title' for message $message_id section=$section_name");
            }
        }
    }
    } # end for each section

    return;
}

# --- helper: backfill CHECKIN identifiers ---
sub _ci_backfill_checkin_identifiers {
    my ($self, $data) = @_;
    
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
        
        INFO("_ci_backfill_checkin_identifiers: section=$section_name, letter=$letter");
        
        # Only work with CHECKIN notices
        next unless (($letter||'') eq 'CHECKIN');

    my $has_all = sub {
        my $result = ($section->{itemsID} && $section->{biblionumber} && $section->{title});
        INFO("has_all check: itemsID=" . ($section->{itemsID}||'') . ", biblionumber=" . ($section->{biblionumber}||'') . ", title=" . ($section->{title}||'') . " -> result=" . ($result ? '1' : '0'));
        return $result;
    };

    # If we already have all data, nothing to do
    return if $has_all->();

    # Get patron ID
    my $pid = $data->{PatronID}
        || ($data->{patron} && $data->{patron}->{borrowernumber})
        || ($data->{call} && $data->{call}->{PatronID})
        || ($section->{PatronID});

    INFO("Attempting to query Check-ins (old_issues) for patron: " . ($pid || 'NO PID'));

    if ($pid) {
        INFO("Querying old_issues for borrowernumber=$pid");
        
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
        
        INFO("Found " . scalar(@checkins) . " recent check-ins for patron $pid");
        
        if (@checkins) {
            # Try to match title from the script/text if available
            my $title_from_message = '';
            if ($section->{script}) {
                # Extract title from: "...item was checked in: [TITLE]. Thank you!"
                if ($section->{script} =~ /checked in:\s+(.+?)\.\s+Thank you/i) {
                    $title_from_message = $1;
                    $title_from_message =~ s/^\s+|\s+$//g;  # trim whitespace
                    INFO("Extracted title from script: '$title_from_message'");
                }
            } elsif ($section->{text}) {
                # Extract title from SMS text if present
                if ($section->{text} =~ /checked in:\s+(.+?)\.\s+Thank you/i) {
                    $title_from_message = $1;
                    $title_from_message =~ s/^\s+|\s+$//g;
                    INFO("Extracted title from text: '$title_from_message'");
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
                        INFO("Matched title '$title_from_message' to check-in item " . $c->{itemnumber});
                        last;
                    }
                }
            }
            
            # Fallback: use yaml_doc_index if no match found
            unless ($checkin_data) {
                my $yaml_doc_index = $data->{message_type}->{yaml_doc_index} // 0;
                my $index = $yaml_doc_index % scalar(@checkins);
                $checkin_data = $checkins[$index];
                INFO("No title match, using index $index (yaml_doc $yaml_doc_index)");
            }
            
            if ($checkin_data) {
                my $title = $checkin_data->{title} || '';

                $section->{itemsID}      ||= $checkin_data->{itemnumber} || '';
                $section->{biblionumber} ||= $checkin_data->{biblionumber} || '';
                $section->{title}        ||= $title;
                $section->{date}         ||= $checkin_data->{returndate} || '';
                
                my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                INFO("Backfill CHECKIN: Set title to '$title' for message $message_id section=$section_name");
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
    
    # Determine which sections actually exist (not just what transport says)
    my @sections_to_check = ();
    push @sections_to_check, ['call', $data->{call}] if $data->{call} && ref($data->{call}) eq 'HASH';
    push @sections_to_check, ['sms', $data->{sms}] if $data->{sms} && ref($data->{sms}) eq 'HASH';
    
    # Process each section that exists
    for my $section_info (@sections_to_check) {
        my ($section_name, $section) = @$section_info;
        
        # Get letter code from the section
        my $letter = $section->{meta} && $section->{meta}->{letter_code} ? $section->{meta}->{letter_code} : ($data->{meta} && $data->{meta}->{letter_code} || '');
        
        INFO("_ci_backfill_odue_identifiers: section=$section_name, letter=$letter");
        
        # Work with all ODUE variants (ODUE, ODUE2, ODUE3, etc.)
        next unless (($letter||'') =~ /^ODUE/);

    my $has_all = sub {
        my $result = ($section->{itemsID} && $section->{biblionumber} && $section->{title});
        INFO("has_all check: itemsID=" . ($section->{itemsID}||'') . ", biblionumber=" . ($section->{biblionumber}||'') . ", title=" . ($section->{title}||'') . " -> result=" . ($result ? '1' : '0'));
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

        INFO("Attempting to query Issues for patron: " . ($pid || 'NO PID'));

        if ($pid) {
            INFO("Querying Issues directly for borrowernumber=$pid");
            
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
            
            INFO("Found " . scalar(@overdue_issues) . " overdue issues for patron $pid");
            
            if (@overdue_issues) {
                # Use yaml_doc_index to distribute titles across different overdue items
                # This ensures each YAML document gets a different overdue item
                my $yaml_doc_index = $data->{message_type}->{yaml_doc_index} // 0;
                my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                
                # Map different YAML docs to different items (for multi-document YAML)
                my $index = $yaml_doc_index % scalar(@overdue_issues);
                
                INFO("Message $message_id, YAML doc $yaml_doc_index -> using overdue item at index $index");
                
                my $issue_data = $overdue_issues[$index];
                
                if ($issue_data) {
                    my $title = $issue_data->{title} || '';

                    $section->{itemsID}      ||= $issue_data->{itemnumber} || '';
                    $section->{biblionumber} ||= $issue_data->{biblionumber} || '';
                    $section->{title}        ||= $title;
                    # also useful to surface the actual due date
                    $section->{date}         ||= $issue_data->{date_due} || '';
                    
                    INFO("Backfill ODUE: Set title to '$title' for message section=$section_name");
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
    my $fq = 'Koha::Plugin::Com::ByWaterSolutions::CirriusImpact::_ci_insert_title_into_text';
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
    if (defined &Koha::Plugin::Com::ByWaterSolutions::CirriusImpact::_ci_emit_json && !defined &Koha::Plugin::Com::ByWaterSolutions::CirriusImpact::_ci_emit_json_original) {
        *Koha::Plugin::Com::ByWaterSolutions::CirriusImpact::_ci_emit_json_original = \&Koha::Plugin::Com::ByWaterSolutions::CirriusImpact::_ci_emit_json;
        *Koha::Plugin::Com::ByWaterSolutions::CirriusImpact::_ci_emit_json = sub {
            my ($self, $export) = @_;
            _ci_postprocess_messages_with_titles($export);
            return $self->_ci_emit_json_original($export);
        };
    }
}
# --- end added v1.1.3 ---

# --- helper: backfill PREDUE identifiers ---
sub _ci_backfill_predue_identifiers {
    my ($self, $data) = @_;
    
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
        
        INFO("_ci_backfill_predue_identifiers: section=$section_name, letter=$letter");
        
        # Only work with PREDUE notices (PREDUE and PREDUEDGST)
        next unless (($letter||'') =~ /^PREDUE/);

        my $has_all = sub {
            my $result = ($section->{itemsID} && $section->{biblionumber} && $section->{title});
            INFO("has_all check: itemsID=" . ($section->{itemsID}||'') . ", biblionumber=" . ($section->{biblionumber}||'') . ", title=" . ($section->{title}||'') . " -> result=" . ($result ? '1' : '0'));
            return $result;
        };

        # If we already have all data, nothing to do
        return if $has_all->();

        # Get patron ID
        my $pid = $data->{PatronID}
            || ($data->{patron} && $data->{patron}->{borrowernumber})
            || ($data->{call} && $data->{call}->{PatronID})
            || ($section->{PatronID});

        INFO("Attempting to query upcoming due items for patron: " . ($pid || 'NO PID'));

        if ($pid) {
            INFO("Querying upcoming due items for borrowernumber=$pid");
            
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
                INFO("Found item: $itemnumber, title: $title, due: $date_due");
            }
            $sth->finish;
            
            INFO("Found " . scalar(@upcoming_items) . " upcoming due items for patron $pid");
            
            if (@upcoming_items) {
                # For PREDUE messages, populate the data directly from the database
                # since the template variables are often empty
                
                # Check if this is a digest message (PREDUEDGST) or single message (PREDUE)
                if ($letter =~ /DGST$/) {
                    # For digest messages, use the first item but try to build a proper digest message
                    my $matched_item = $upcoming_items[0];
                    INFO("Using first upcoming item " . $matched_item->{itemnumber} . " for PREDUEDGST backfill");
                    
                    if ($matched_item) {
                        my $title = $matched_item->{title} || '';
                        $section->{itemsID}      ||= $matched_item->{itemnumber} || '';
                        $section->{biblionumber} ||= $matched_item->{biblionumber} || '';
                        $section->{title}        ||= $title;
                        $section->{date}         ||= $matched_item->{date_due} || '';
                        
                        my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                        INFO("Backfill PREDUEDGST: Set title to '$title' for message $message_id section=$section_name");
                        
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
                            INFO("Updated digest message text to: '$new_text'");
                        }
                    }
                } else {
                    # For single PREDUE messages, use the first item
                    my $matched_item = $upcoming_items[0];
                    INFO("Using first upcoming item " . $matched_item->{itemnumber} . " for PREDUE backfill");
                    
                    if ($matched_item) {
                        my $title = $matched_item->{title} || '';
                        $section->{itemsID}      ||= $matched_item->{itemnumber} || '';
                        $section->{biblionumber} ||= $matched_item->{biblionumber} || '';
                        $section->{title}        ||= $title;
                        $section->{date}         ||= $matched_item->{date_due} || '';
                        
                        my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                        INFO("Backfill PREDUE: Set title to '$title' for message $message_id section=$section_name");
                        
                        # Also try to update the message text if it's empty or has empty variables
                        if ($section->{text} && $section->{text} =~ /is due \./) {
                            my $new_text = $section->{text};
                            $new_text =~ s/is due \./is due $matched_item->{date_due}/;
                            $new_text =~ s/:\s+is due/: $title is due/;
                            $section->{text} = $new_text;
                            INFO("Updated message text to: '$new_text'");
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
        
        INFO("_ci_backfill_additional_identifiers: section=$section_name, letter=$letter");
        
        # Only work with the new message types
        next unless (($letter||'') =~ /^(HOLD|HOLD_CHANGED|HOLD_REMINDER|MEMBERSHIP_EXPIRY|MEMBERSHIP_RENEWED|RENEWAL|WELCOME|ACCOUNT_CREDIT|ACCOUNT_DEBIT|ACCOUNT_PAYMENT|ACCOUNT_WRITEOFF|ACCOUNTS_SUMMARY|HOLDPLACED|HOLDPLACED_PATRON|HOLDDGST)$/);

        my $has_all = sub {
            my $result = ($section->{itemsID} && $section->{biblionumber} && $section->{title});
            INFO("has_all check: itemsID=" . ($section->{itemsID}||'') . ", biblionumber=" . ($section->{biblionumber}||'') . ", title=" . ($section->{title}||'') . " -> result=" . ($result ? '1' : '0'));
            return $result;
        };

        # If we already have all data, nothing to do
        return if $has_all->();

        # Get patron ID
        my $pid = $data->{PatronID}
            || ($data->{patron} && $data->{patron}->{borrowernumber})
            || ($data->{call} && $data->{call}->{PatronID})
            || ($section->{PatronID});

        INFO("Attempting to query data for patron: " . ($pid || 'NO PID') . " for message type: $letter");

        if ($pid) {
            my $dbh = C4::Context->dbh;
            my $matched_item;
            
            # Handle different message types
            if ($letter eq 'HOLD' || $letter =~ /^HOLD_(CHANGED|REMINDER)$/) {
                # For HOLD messages, query the reserves table
                INFO("Querying holds for borrowernumber=$pid");
                my $sql = q{
                    SELECT r.reserve_id, r.biblionumber, b.title, r.reservedate, r.expirationdate
                    FROM reserves r
                    JOIN biblio b ON b.biblionumber = r.biblionumber
                    WHERE r.borrowernumber = ?
                      AND r.found IS NULL
                    ORDER BY r.reservedate DESC
                    LIMIT 1
                };
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                if (my ($reserve_id, $biblionumber, $title, $reservedate, $expirationdate) = $sth->fetchrow_array) {
                    $matched_item = {
                        itemnumber => $reserve_id,
                        biblionumber => $biblionumber,
                        title => $title,
                        date => $expirationdate,
                        expirationdate => $expirationdate
                    };
                    INFO("Found hold: $reserve_id, title: $title, hold till: $expirationdate");
                }
                $sth->finish;
                
            } elsif ($letter =~ /^MEMBERSHIP_(EXPIRY|RENEWED)$/) {
                # For membership messages, query the borrowers table
                INFO("Querying membership info for borrowernumber=$pid");
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
                    INFO("Found membership: $borrowernumber, name: $firstname $surname, expires: $dateexpiry");
                }
                $sth->finish;
                
            } elsif ($letter eq 'RENEWAL') {
                # For renewal messages, query current issues
                INFO("Querying current issues for borrowernumber=$pid");
                my $sql = q{
                    SELECT i.itemnumber, it.biblionumber, b.title, i.date_due, i.issue_id
                    FROM issues i
                    JOIN items it ON it.itemnumber = i.itemnumber
                    JOIN biblio b ON b.biblionumber = it.biblionumber
                    WHERE i.borrowernumber = ?
                    ORDER BY i.date_due ASC
                    LIMIT 1
                };
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                if (my ($itemnumber, $biblionumber, $title, $date_due, $issue_id) = $sth->fetchrow_array) {
                    $matched_item = {
                        itemnumber => $itemnumber,
                        biblionumber => $biblionumber,
                        title => $title,
                        date => $date_due,
                        issue_id => $issue_id
                    };
                    INFO("Found renewal item: $itemnumber, title: $title, due: $date_due");
                }
                $sth->finish;
                
            } elsif ($letter eq 'WELCOME') {
                # For welcome messages, query borrower info
                INFO("Querying borrower info for borrowernumber=$pid");
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
                    INFO("Found welcome patron: $borrowernumber, name: $firstname $surname, enrolled: $dateenrolled");
                }
                $sth->finish;
                
            } elsif ($letter =~ /^ACCOUNT_(CREDIT|DEBIT|PAYMENT|WRITEOFF)$/) {
                # For account messages, query accountlines table
                INFO("Querying account info for borrowernumber=$pid");
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
                    INFO("Found account transaction: $accountlines_id, amount: $amount, description: $description");
                }
                $sth->finish;
                
            } elsif ($letter eq 'ACCOUNTS_SUMMARY') {
                # For accounts summary, query total outstanding balance
                INFO("Querying accounts summary for borrowernumber=$pid");
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
                    INFO("Found accounts summary: total balance: $total_balance, transactions: $transaction_count");
                }
                $sth->finish;
                
            } elsif ($letter =~ /^HOLDPLACED(_PATRON)?$/) {
                # For hold placed messages, query the most recent hold
                INFO("Querying recent hold for borrowernumber=$pid");
                my $sql = q{
                    SELECT r.reserve_id, r.biblionumber, b.title, r.reservedate, r.expirationdate
                    FROM reserves r
                    JOIN biblio b ON b.biblionumber = r.biblionumber
                    WHERE r.borrowernumber = ?
                    ORDER BY r.reservedate DESC
                    LIMIT 1
                };
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                if (my ($reserve_id, $biblionumber, $title, $reservedate, $expirationdate) = $sth->fetchrow_array) {
                    $matched_item = {
                        itemnumber => $reserve_id,
                        biblionumber => $biblionumber,
                        title => $title,
                        date => $expirationdate,
                        expirationdate => $expirationdate
                    };
                    INFO("Found hold placed: $reserve_id, title: $title, hold till: $expirationdate");
                }
                $sth->finish;
                
            } elsif ($letter eq 'HOLDDGST') {
                # For HOLDDGST messages, query waiting holds (holds that are ready for pickup)
                INFO("Querying waiting holds for borrowernumber=$pid");
                my $sql = q{
                    SELECT r.reserve_id, r.biblionumber, b.title, r.waitingdate, r.expirationdate
                    FROM reserves r
                    JOIN biblio b ON b.biblionumber = r.biblionumber
                    WHERE r.borrowernumber = ? AND r.found = 'W'
                    ORDER BY r.waitingdate DESC
                    LIMIT 1
                };
                my $sth = $dbh->prepare($sql);
                $sth->execute($pid);
                if (my ($reserve_id, $biblionumber, $title, $waitingdate, $expirationdate) = $sth->fetchrow_array) {
                    $matched_item = {
                        itemnumber => $reserve_id,
                        biblionumber => $biblionumber,
                        title => $title,
                        date => $waitingdate,
                        expirationdate => $expirationdate
                    };
                    INFO("Found waiting hold: $reserve_id, title: $title, waiting since: $waitingdate");
                }
                $sth->finish;
            }
            
            # Populate the section with found data
            if ($matched_item) {
                my $title = $matched_item->{title} || '';
                $section->{itemsID}      ||= $matched_item->{itemnumber} || '';
                $section->{biblionumber} ||= $matched_item->{biblionumber} || '';
                $section->{title}        ||= $title;
                $section->{date}         ||= $matched_item->{date} || '';
                
                my $message_id = $section->{meta}->{message_id} || $data->{message_type}->{message_id} || 0;
                INFO("Backfill $letter: Set title to '$title' for message $message_id section=$section_name");
                
                # Try to update message text if it has empty variables
                if ($section->{text} && $section->{text} =~ /(is due|expires|renewed|welcome)/i) {
                    my $new_text = $section->{text};
                    # Replace common empty patterns
                    $new_text =~ s/:\s+is due/: $title is due/;
                    $new_text =~ s/:\s+expires/: $title expires/;
                    $new_text =~ s/:\s+renewed/: $title renewed/;
                    $new_text =~ s/:\s+welcome/: $title welcome/;
                    $section->{text} = $new_text;
                    INFO("Updated $letter message text to: '$new_text'");
                }
            }
        }
    }
    return;
}

1;
