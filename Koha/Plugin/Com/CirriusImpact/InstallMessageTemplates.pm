package Koha::Plugin::Com::CirriusImpact::InstallMessageTemplates;

# CirriusImpact notice template installer (callable from CLI and Configure UI).
# Upserts rows into Koha letter table.

use strict;
use warnings;

our $VERSION = '1.3.11';

my %DEFAULT_LANG_ALIASES = (
    default => 'en',
    en      => 'en',
    eng     => 'en',
    english => 'en',
    'es-ES' => 'es-ES',
    es      => 'es-ES',
    spa     => 'es-ES',
    spanish => 'es-ES',
    'fr-CA' => 'fr-CA',
    fr      => 'fr-CA',
    fre     => 'fr-CA',
    french  => 'fr-CA',
);

my %SERVICE_ALIASES = (
    sms   => 'sms',
    text  => 'sms',
    phone => 'phone',
    voice => 'phone',
    call  => 'phone',
    email => 'email',
);

sub _log {
    my ( $lines, $msg ) = @_;
    $msg .= "\n" unless $msg =~ /\n\z/;
    push @$lines, $msg;
    return;
}

# True when letter.content is already CirriusImpact YAML.
sub _already_ci_yaml {
    my ($content) = @_;
    return 0 unless defined $content && length $content;
    return ( $content =~ /CirriusImpact\s*:\s*yes/i ) ? 1 : 0;
}

# Escape a string as a YAML double-quoted scalar (single logical line).
sub _yaml_double_quote {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/\r\n/\n/g;
    $s =~ s/\r/\n/g;
    $s =~ s/\\/\\\\/g;
    $s =~ s/"/\\"/g;
    $s =~ s/\n/\\n/g;
    $s =~ s/\t/\\t/g;
    return qq{"$s"};
}

# Preserve original notice as Template Toolkit comments (hidden at render time).
# Neutralize "%]" so a comment cannot be closed early by notice text.
sub _tt_comment_block {
    my ($original) = @_;
    $original = '' unless defined $original;
    $original =~ s/\r\n/\n/g;
    $original =~ s/\r/\n/g;
    my @lines = split /\n/, $original, -1;
    # Avoid writing literal [%# ... %] inside Perl quotes (parser hazard).
    my $open  = '[%' . '#';
    my $close = '%]';
    my @out = ( $open . ' Original Notice Template ' . $close );
    for my $line (@lines) {
        my $safe = $line;
        # Insert a space so embedded Template Toolkit closers cannot end this comment early.
        $safe =~ s/%\]/% ]/g;
        push @out, $open . ' ' . $safe . ' ' . $close;
    }
    return join( "\n", @out );
}

# Koha splits CHECKOUT, CHECKIN, RENEWAL and HOLDDGST on a literal "----".
# The repeat body has to be the id the plugin collects; the sentence stays outside.
sub _incremental_list_for_code {
    my ($code) = @_;
    $code = '' unless defined $code;
    $code =~ s/-CI\z//;
    return ( 'checkouts',     'checkout.issue_id' )     if $code eq 'CHECKOUT' || $code eq 'RENEWAL';
    return ( 'old_checkouts', 'old_checkout.issue_id' ) if $code eq 'CHECKIN';
    return ( 'holds',         'hold.reserve_id' )       if $code eq 'HOLDDGST';
    return;
}

# Wrap existing Koha notice text in CirriusImpact YAML for plugin export.
# SMS → sms.text; phone → call.script. Appends original as TT comments.
# Incremental notices are rebuilt so the ---- markers stay outside the sentence.
sub _wrap_existing_as_ci {
    my ( $original, $transport, $code ) = @_;
    my $body = defined $original ? $original : '';
    $body =~ s/\A\s+//;
    $body =~ s/\s+\z//;

    my $yaml;
    my ( $list_key, $id_path ) = _incremental_list_for_code($code);
    if ( $list_key && $body =~ /----/ ) {
        my ( $header, undef, $footer ) = split( /----\r?\n?/, $body, 3 );
        $header = '' unless defined $header;
        $footer = '' unless defined $footer;
        $header =~ s/\s+\z//;
        $footer =~ s/\A\s+//;
        $footer =~ s/\s+\z//;
        my $sentence = $header;
        if ( $sentence !~ /\{\{\s*ci\.titles/ ) {
            $sentence .= ( $sentence =~ /\S/ ? ' ' : '' ) . '{{ ci.titles }}';
        }
        if ( $footer =~ /\S/ ) {
            $sentence .= ( $sentence =~ /[.!?]\s*\z/ ? ' ' : '. ' ) . $footer;
        }
        my $quoted  = _yaml_double_quote($sentence);
        my $field   = ( ( $transport // '' ) eq 'phone' ) ? 'script' : 'text';
        my $section = ( ( $transport // '' ) eq 'phone' ) ? 'call'    : 'sms';
        $yaml = <<"YAML";
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
$section:
  $field: $quoted
$list_key:
----
  - [% $id_path %]
----
---
YAML
    }
    else {
        my $quoted = _yaml_double_quote($body);
        if ( ( $transport // '' ) eq 'phone' ) {
            $yaml = <<"YAML";
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: $quoted
---
YAML
        }
        else {
            $yaml = <<"YAML";
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: $quoted
---
YAML
        }
    }
    $yaml .= "\n" . _tt_comment_block($original) . "\n";
    return $yaml;
}

# Unescape a YAML double-quoted scalar produced by _yaml_double_quote.
sub _yaml_unescape_double {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/\\n/\n/g;
    $s =~ s/\\t/\t/g;
    $s =~ s/\\"/"/g;
    $s =~ s/\\\\/\\/g;
    return $s;
}

# Recover pre-wrap notice text from a CirriusImpact-wrapped letter.
# Prefers the TT comment archive; falls back to sms.text / call.script.
sub _extract_original_from_wrapped {
    my ($content) = @_;
    return undef unless defined $content && length $content;

    if ( $content =~ /\[%#\s*Original Notice Template\s*%\]\s*\n(.*)\z/s ) {
        my $block = $1;
        my @lines;
        for my $line ( split /\n/, $block ) {
            next unless defined $line;
            if ( $line =~ /^\s*\[%#\s?(.*?)\s*%\]\s*$/ ) {
                my $body = $1;
                $body =~ s/% \]/%]/g;  # reverse neutralization from _tt_comment_block
                push @lines, $body;
            }
            elsif ( $line =~ /\S/ ) {
                last;
            }
        }
        return join( "\n", @lines ) if @lines;
    }

    # Fallback when comments were stripped or notice was hand-edited CI YAML.
    if ( $content =~ /(?:^|\n)[ \t]*(?:text|script):[ \t]*"((?:\\.|[^"\\])*)"/s ) {
        return _yaml_unescape_double($1);
    }
    if ( $content =~ /(?:^|\n)[ \t]*(?:text|script):[ \t]*'((?:\\.|[^'\\])*)'/s ) {
        my $s = $1;
        $s =~ s/\\'/'/g;
        $s =~ s/\\\\/\\/g;
        return $s;
    }
    return undef;
}

sub _resolve_services {
    my ($services) = @_;
    $services //= [ 'sms', 'phone' ];
    my @raw = ref $services eq 'ARRAY' ? @$services : split /,/, $services;
    my @resolved;
    my %seen;
    for my $s (@raw) {
        $s = lc( $s // '' );
        $s =~ s/^\s+|\s+$//g;
        next unless length $s;
        my $t = $SERVICE_ALIASES{$s};
        die "Unknown service '$s' (use sms and/or phone)\n" unless defined $t;
        next if $seen{$t}++;
        push @resolved, $t;
    }
    die "At least one service required (sms and/or phone)\n" unless @resolved;
    return @resolved;
}

sub _resolve_languages {
    my ($languages) = @_;
    $languages //= [ 'default', 'en', 'es-ES', 'fr-CA' ];
    my @raw = ref $languages eq 'ARRAY' ? @$languages : split /,/, $languages;
    my @out;
    for my $l (@raw) {
        $l =~ s/^\s+|\s+$//g if defined $l;
        push @out, $l if defined $l && length $l;
    }
    die "At least one language required\n" unless @out;
    return @out;
}

sub _plugin_enabled_branches {
    my ($plugin, $dbh, $log) = @_;
    my @codes;
    if ($plugin) {
        my $raw = eval { $plugin->retrieve_data('enabled_branches') };
        if ( defined $raw ) {
            $raw =~ s/^\s+|\s+$//g;
            if ( $raw ne '' && $raw ne '*' ) {
                for my $b ( split /,/, $raw ) {
                    $b =~ s/^\s+|\s+$//g;
                    push @codes, $b if length $b;
                }
            }
            return @codes;
        }
        _log( $log, "Could not read enabled_branches via plugin: $@" ) if $@;
    }
    return @codes unless $dbh;
    my $sth = $dbh->prepare(q{
        SELECT plugin_value FROM plugin_data
        WHERE plugin_key = 'enabled_branches'
          AND plugin_class LIKE '%CirriusImpact%'
        ORDER BY plugin_class
        LIMIT 1
    });
    eval { $sth->execute(); };
    return @codes if $@;
    my ($raw) = $sth->fetchrow_array;
    $sth->finish();
    return @codes unless defined $raw;
    $raw =~ s/^\s+|\s+$//g;
    if ( $raw =~ /^53616c7465645f5f/ || $raw =~ /^Salted__/ || $raw =~ /[^A-Za-z0-9_,\-\s\*]/ ) {
        _log( $log, "enabled_branches looks encrypted; pass plugin object to decrypt." );
        return @codes;
    }
    return @codes if $raw eq '' || $raw eq '*';
    for my $b ( split /,/, $raw ) {
        $b =~ s/^\s+|\s+$//g;
        push @codes, $b if length $b;
    }
    return @codes;
}

# run(
#   defaults => 1,
#   ci_templates => 0,
#   consortia_branches => ['CPL'],
#   consortia_from_plugin => 0,
#   services => ['sms','phone'],
#   languages => ['default','en','es-ES','fr-CA'],
#   default_language => 'en',
#   plugin => $plugin_obj,   # optional; for consortia_from_plugin
#   dbh => $dbh,             # optional; defaults to C4::Context->dbh
# )
# returns { ok => 1|0, count => N, log => '...', error => '...' }
# Canned CirriusImpact templates (key => {module, code, transport, content => {lang => text}}).
my %TEMPLATES = (
    'HOLD_SMS' => {
        module => 'reserves',
        code => 'HOLD',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
hold: [% hold.reserve_id %]
sms:
  text: "[% branch.branchcode %]: [% IF holds.size > 1 %][% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Hold ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]"
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
hold: [% hold.reserve_id %]
sms:
  text: "[% branch.branchcode %]: [% IF holds.size > 1 %][% holds.size %] reservas listas: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Reserva lista: [% biblio.title %][% END %]. Retire antes del [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
hold: [% hold.reserve_id %]
sms:
  text: "[% branch.branchcode %]: [% IF holds.size > 1 %][% holds.size %] reserves pretes: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Reserve prete: [% biblio.title %][% END %]. Retirer avant le [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]"
---
},
        },
    },
    'HOLD_PHONE' => {
        module => 'reserves',
        code => 'HOLD',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
hold: [% hold.reserve_id %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] items ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]One item ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
hold: [% hold.reserve_id %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] articulos listos: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]Un articulo listo: [% biblio.title %][% END %]. Retire antes del [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
hold: [% hold.reserve_id %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] documents prets: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]Un document pret: [% biblio.title %][% END %]. A retirer avant le [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'HOLDDGST_SMS' => {
        module => 'reserves',
        code => 'HOLDDGST',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Ready for pickup: {{ ci.titles }}. Pickup by {{ ci.due }}."
holds:
----
  - [% hold.reserve_id %]
----
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Listo para retirar: {{ ci.titles }}. Retire antes del {{ ci.due }}."
holds:
----
  - [% hold.reserve_id %]
----
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Pret a retirer: {{ ci.titles }}. Retirer avant le {{ ci.due }}."
holds:
----
  - [% hold.reserve_id %]
----
---
},
        },
    },
    'HOLDDGST_PHONE' => {
        module => 'reserves',
        code => 'HOLDDGST',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. The following items are ready for pickup: {{ ci.titles_comma }}. Pickup by {{ ci.due }}. Call [% branch.branchphone %]."
holds:
----
  - [% hold.reserve_id %]
----
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Listo para retirar: {{ ci.titles_comma }}. Retire antes del {{ ci.due }}. Llame al [% branch.branchphone %]."
holds:
----
  - [% hold.reserve_id %]
----
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Pret a retirer: {{ ci.titles_comma }}. A retirer avant le {{ ci.due }}. Appelez le [% branch.branchphone %]."
holds:
----
  - [% hold.reserve_id %]
----
---
},
        },
    },
    'CHECKOUT_SMS' => {
        module => 'circulation',
        code => 'CHECKOUT',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Checked out: {{ ci.titles }}. Due {{ ci.due }}."
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Prestamo: {{ ci.titles }}. Vence {{ ci.due }}."
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Pret: {{ ci.titles }}. Echeance {{ ci.due }}."
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        },
    },
    'CHECKOUT_PHONE' => {
        module => 'circulation',
        code => 'CHECKOUT',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You checked out: {{ ci.titles_comma }}. Due {{ ci.due }}. Thank you!"
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Prestamo de: {{ ci.titles_comma }}. Vence {{ ci.due }}. Gracias!"
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Pret de: {{ ci.titles_comma }}. Echeance {{ ci.due }}. Merci!"
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        },
    },
    'CHECKIN_SMS' => {
        module => 'circulation',
        code => 'CHECKIN',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Checked in: {{ ci.titles }}. Thank you!"
old_checkouts:
----
  - [% old_checkout.issue_id %]
----
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Devolucion: {{ ci.titles }}. Gracias!"
old_checkouts:
----
  - [% old_checkout.issue_id %]
----
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Retour: {{ ci.titles }}. Merci!"
old_checkouts:
----
  - [% old_checkout.issue_id %]
----
---
},
        },
    },
    'CHECKIN_PHONE' => {
        module => 'circulation',
        code => 'CHECKIN',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. The following items were checked in: {{ ci.titles_comma }}. Thank you!"
old_checkouts:
----
  - [% old_checkout.issue_id %]
----
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Se devolvio: {{ ci.titles_comma }}. Gracias!"
old_checkouts:
----
  - [% old_checkout.issue_id %]
----
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Retour enregistre: {{ ci.titles_comma }}. Merci!"
old_checkouts:
----
  - [% old_checkout.issue_id %]
----
---
},
        },
    },
    'ODUE_SMS' => {
        module => 'circulation',
        code => 'ODUE',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Overdue: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Atraso: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Devuelva o renueve. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: En retard: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Retournez ou renouvelez. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'ODUE_PHONE' => {
        module => 'circulation',
        code => 'ODUE',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You have overdue items: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Please return or renew at your earliest convenience. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Tiene articulos atrasados: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Devuelva o renueve. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Documents en retard: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Retournez ou renouvelez. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'ODUE2_SMS' => {
        module => 'circulation',
        code => 'ODUE2',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Second notice - Overdue: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: 2do aviso - Atraso: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Devuelva o renueve ya. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: 2e avis - En retard: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Retournez ou renouvelez maintenant. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'ODUE2_PHONE' => {
        module => 'circulation',
        code => 'ODUE2',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You have seriously overdue items: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Please return at your earliest convenience to avoid any additional fines. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Segundo aviso. Articulos atrasados: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Devuelva o renueve ya. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Deuxieme avis. Documents en retard: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Retournez ou renouvelez maintenant. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'ODUE3_SMS' => {
        module => 'circulation',
        code => 'ODUE3',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Final notice - Overdue: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Please return to avoid additional charges. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Aviso final - Atraso: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Devuelva o renueve ya para evitar cargos. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Avis final - En retard: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Retournez ou renouvelez maintenant pour eviter des frais. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'ODUE3_PHONE' => {
        module => 'circulation',
        code => 'ODUE3',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. This is the final overdue notice for: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Please return or renew at your earliest convenience to avoid any additional charges. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Aviso final. Articulos atrasados: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Devuelva o renueve ya para evitar cargos. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Avis final. Documents en retard: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Retournez ou renouvelez maintenant pour eviter des frais. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'PREDUE_SMS' => {
        module => 'circulation',
        code => 'PREDUE',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - [% biblio.title %] is due on [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Recordatorio - [% biblio.title %] vence [% issue.date_due | $KohaDates %]. Devuelva o renueve. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Rappel - [% biblio.title %] echeance [% issue.date_due | $KohaDates %]. Retournez ou renouvelez. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'PREDUE_PHONE' => {
        module => 'circulation',
        code => 'PREDUE',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. This is a reminder that [% biblio.title %] is due on [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Recordatorio - [% biblio.title %] vence [% issue.date_due | $KohaDates %]. Devuelva o renueve. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Rappel - [% biblio.title %] echeance [% issue.date_due | $KohaDates %]. Retournez ou renouvelez. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'PREDUEDGST_SMS' => {
        module => 'circulation',
        code => 'PREDUEDGST',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Reminder - due soon: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Recordatorio - vencen pronto: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Devuelva o renueve. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Rappel - echeance proche: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Retournez ou renouvelez. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'PREDUEDGST_PHONE' => {
        module => 'circulation',
        code => 'PREDUEDGST',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. This is a reminder that the following items are due soon: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Recordatorio - vencen pronto: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Devuelva o renueve. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Rappel - echeance proche: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Retournez ou renouvelez. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'HOLD_CHANGED_SMS' => {
        module => 'reserves',
        code => 'HOLD_CHANGED',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold status changed for [% biblio.title %]. Check your account for details. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Estado de reserva cambiado para [% biblio.title %]. Revise su cuenta. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Statut de reserve change pour [% biblio.title %]. Verifiez votre compte. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'DUEDGST_SMS' => {
        module => 'circulation',
        code => 'DUEDGST',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Due today: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %][% UNLESS loop.last %]; [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Vencen hoy: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %][% UNLESS loop.last %]; [% END %][% END %]. Devuelva o renueve. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Echeance aujourd'hui: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %][% UNLESS loop.last %]; [% END %][% END %]. Retournez ou renouvelez. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'HOLD_CHANGED_PHONE' => {
        module => 'reserves',
        code => 'HOLD_CHANGED',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. There has been a hold status change for [% biblio.title %]. Please check your account for details. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. El estado de su reserva cambio para [% biblio.title %]. Revise su cuenta. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Le statut de votre reserve a change pour [% biblio.title %]. Verifiez votre compte. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'DUEDGST_PHONE' => {
        module => 'circulation',
        code => 'DUEDGST',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. The following items are due today: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %][% UNLESS loop.last %], [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Vencen hoy: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %][% UNLESS loop.last %], [% END %][% END %]. Devuelva o renueve. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Echeance aujourd'hui: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %][% UNLESS loop.last %], [% END %][% END %]. Retournez ou renouvelez. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'HOLD_REMINDER_SMS' => {
        module => 'reserves',
        code => 'HOLD_REMINDER',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - hold ready: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Recordatorio - Reserva lista: [% biblio.title %]. Retire antes del [% hold.expirationdate | $KohaDates %]. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Rappel - Reserve prete: [% biblio.title %]. Retirer avant le [% hold.expirationdate | $KohaDates %]. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'HOLD_REMINDER_PHONE' => {
        module => 'reserves',
        code => 'HOLD_REMINDER',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. This is a reminder that a hold for [% biblio.title %] is ready for pickup by [% hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Recordatorio - Reserva lista: [% biblio.title %]. Retire antes del [% hold.expirationdate | $KohaDates %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Rappel - Reserve prete: [% biblio.title %]. Retirer avant le [% hold.expirationdate | $KohaDates %]. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'HOLDPLACED_SMS' => {
        module => 'reserves',
        code => 'HOLDPLACED',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold placed on [% biblio.title %]. You will be notified when ready for pickup. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reserva hecha para [% biblio.title %]. Le avisaremos cuando este lista. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reserve placee pour [% biblio.title %]. Nous vous aviserons quand elle sera prete. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'HOLDPLACED_PHONE' => {
        module => 'reserves',
        code => 'HOLDPLACED',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. There is a hold placed for [% biblio.title %]. You will be notified when it is ready. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Reserva hecha para [% biblio.title %]. Le avisaremos cuando este lista. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Reserve placee pour [% biblio.title %]. Nous vous aviserons quand elle sera prete. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'HOLDPLACED_PATRON_SMS' => {
        module => 'reserves',
        code => 'HOLDPLACED_PATRON',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold confirmed for [% biblio.title %]. You will be notified when ready for pickup. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reserva confirmada para [% biblio.title %]. Le avisaremos cuando este lista. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reserve confirmee pour [% biblio.title %]. Nous vous aviserons quand elle sera prete. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'HOLDPLACED_PATRON_PHONE' => {
        module => 'reserves',
        code => 'HOLDPLACED_PATRON',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. There is a hold placed for [% biblio.title %]. You will be notified when it is ready. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Reserva confirmada para [% biblio.title %]. Le avisaremos cuando este lista. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Reserve confirmee pour [% biblio.title %]. Nous vous aviserons quand elle sera prete. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'HOLD_SLIP_EMAIL' => {
        module => 'circulation',
        code => 'HOLD_SLIP',
        transport => 'email',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
email:
  subject: "Hold Slip - [% biblio.title %]"
  body: "Hold slip for [% biblio.title %]. Patron: [% borrower.firstname %] [% borrower.surname %]. Pickup by: [% hold.expirationdate | $KohaDates %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
email:
  subject: "Comprobante de reserva - [% biblio.title %]"
  body: "Comprobante de reserva para [% biblio.title %]. Patron: [% borrower.firstname %] [% borrower.surname %]. Retiro antes del: [% hold.expirationdate | $KohaDates %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
email:
  subject: "Bon de reserve - [% biblio.title %]"
  body: "Bon de reserve pour [% biblio.title %]. Usager: [% borrower.firstname %] [% borrower.surname %]. A retirer avant le: [% hold.expirationdate | $KohaDates %]."
---
},
        },
    },
    'RENEWAL_SMS' => {
        module => 'circulation',
        code => 'RENEWAL',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Renewed: {{ ci.titles }}. New due date: {{ ci.due }}. Call [% branch.branchphone %]."
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Renovado: {{ ci.titles }}. Nueva fecha: {{ ci.due }}. Llame [% branch.branchphone %]."
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Renouvele: {{ ci.titles }}. Nouvelle echeance: {{ ci.due }}. Appelez [% branch.branchphone %]."
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        },
    },
    'RENEWAL_PHONE' => {
        module => 'circulation',
        code => 'RENEWAL',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. The following items have been renewed: {{ ci.titles_comma }}. The new due date is {{ ci.due }}. Call [% branch.branchphone %]."
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Se renovo: {{ ci.titles_comma }}. Nueva fecha: {{ ci.due }}. Llame al [% branch.branchphone %]."
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Renouvellement: {{ ci.titles_comma }}. Nouvelle echeance: {{ ci.due }}. Appelez le [% branch.branchphone %]."
checkouts:
----
  - [% checkout.issue_id %]
----
---
},
        },
    },
    'AUTO_RENEWALS_SMS' => {
        module => 'circulation',
        code => 'AUTO_RENEWALS',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] auto-renewed. New due date: [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] renovado automaticamente. Nueva fecha: [% issue.date_due | $KohaDates %]. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] renouvele automatiquement. Nouvelle echeance: [% issue.date_due | $KohaDates %]. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'AUTO_RENEWALS_PHONE' => {
        module => 'circulation',
        code => 'AUTO_RENEWALS',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. [% biblio.title %] has been auto renewed. The new due date is [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] fue renovado automaticamente. Nueva fecha: [% issue.date_due | $KohaDates %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] a ete renouvele automatiquement. Nouvelle echeance: [% issue.date_due | $KohaDates %]. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'AUTO_RENEWALS_DGST_SMS' => {
        module => 'circulation',
        code => 'AUTO_RENEWALS_DGST',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF idsep %],[% END %][% c.issue_id %][% idsep = 1 %][% END %][% END %]"
sms:
  text: "[% sep = '' %][% branch.branchcode %]: Auto-renewal: [% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF sep %]; [% END %][% c.item.biblio.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% sep = 1 %][% END %][% END %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF idsep %],[% END %][% c.issue_id %][% idsep = 1 %][% END %][% END %]"
sms:
  text: "[% sep = '' %][% branch.branchcode %]: Renovacion automatica: [% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF sep %]; [% END %][% c.item.biblio.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% sep = 1 %][% END %][% END %]. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF idsep %],[% END %][% c.issue_id %][% idsep = 1 %][% END %][% END %]"
sms:
  text: "[% sep = '' %][% branch.branchcode %]: Renouvellement automatique: [% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF sep %]; [% END %][% c.item.biblio.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% sep = 1 %][% END %][% END %]. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'AUTO_RENEWALS_DGST_PHONE' => {
        module => 'circulation',
        code => 'AUTO_RENEWALS_DGST',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF idsep %],[% END %][% c.issue_id %][% idsep = 1 %][% END %][% END %]"
call:
  script: "[% sep = '' %]Hello [% borrower.firstname %]. This is [% branch.branchname %]. Auto-renewal update: [% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF sep %], [% END %][% c.item.biblio.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% sep = 1 %][% END %][% END %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF idsep %],[% END %][% c.issue_id %][% idsep = 1 %][% END %][% END %]"
call:
  script: "[% sep = '' %]Hola [% borrower.firstname %]. [% branch.branchname %]. Renovacion automatica: [% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF sep %], [% END %][% c.item.biblio.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% sep = 1 %][% END %][% END %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF idsep %],[% END %][% c.issue_id %][% idsep = 1 %][% END %][% END %]"
call:
  script: "[% sep = '' %]Bonjour [% borrower.firstname %]. [% branch.branchname %]. Renouvellement automatique: [% FOREACH c IN checkouts %][% IF !c.auto_renew_error %][% IF sep %], [% END %][% c.item.biblio.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% sep = 1 %][% END %][% END %]. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'MEMBERSHIP_EXPIRY_SMS' => {
        module => 'members',
        code => 'MEMBERSHIP_EXPIRY',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Membership expires [% borrower.dateexpiry | $KohaDates %]. Please renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Su membresia vence [% borrower.dateexpiry | $KohaDates %]. Renueve para seguir usando la biblioteca. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Votre abonnement expire le [% borrower.dateexpiry | $KohaDates %]. Renouvelez pour continuer. Appelez [% branch.branchphone %]."
---
},
        },
    },
    'MEMBERSHIP_EXPIRY_PHONE' => {
        module => 'members',
        code => 'MEMBERSHIP_EXPIRY',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. Your membership is set to expire on [% borrower.dateexpiry | $KohaDates %]. Please check your account for details. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Su membresia vence [% borrower.dateexpiry | $KohaDates %]. Renueve para seguir usando la biblioteca. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Votre abonnement expire le [% borrower.dateexpiry | $KohaDates %]. Renouvelez pour continuer. Appelez le [% branch.branchphone %]."
---
},
        },
    },
    'MEMBERSHIP_RENEWED_SMS' => {
        module => 'members',
        code => 'MEMBERSHIP_RENEWED',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Membership renewed. New expiry: [% borrower.dateexpiry | $KohaDates %]. Thank you!"
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Membresia renovada. Nueva fecha: [% borrower.dateexpiry | $KohaDates %]. Gracias!"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Abonnement renouvele. Nouvelle echeance: [% borrower.dateexpiry | $KohaDates %]. Merci!"
---
},
        },
    },
    'MEMBERSHIP_RENEWED_PHONE' => {
        module => 'members',
        code => 'MEMBERSHIP_RENEWED',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. Your membership has auto renewed. The new expiration date is [% borrower.dateexpiry | $KohaDates %]. Please check your account for details. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Su membresia fue renovada. Nueva fecha: [% borrower.dateexpiry | $KohaDates %]. Gracias!"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Votre abonnement a ete renouvele. Nouvelle echeance: [% borrower.dateexpiry | $KohaDates %]. Merci!"
---
},
        },
    },
    'WELCOME_SMS' => {
        module => 'members',
        code => 'WELCOME',
        transport => 'sms',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Welcome to the library, [% borrower.firstname %]! Your membership is active. Visit us soon!"
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Bienvenido a la biblioteca, [% borrower.firstname %]! Su membresia esta activa. Visitenos pronto!"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Bienvenue a la bibliotheque, [% borrower.firstname %]! Votre abonnement est actif. A bientot!"
---
},
        },
    },
    'WELCOME_PHONE' => {
        module => 'members',
        code => 'WELCOME',
        transport => 'phone',
        content => {
        'en' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. Welcome to our library. Your membership is active. Please check your account for details. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Bienvenido a la biblioteca! Su membresia esta activa. Esperamos servirle. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrower.borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Bienvenue a la bibliotheque! Votre abonnement est actif. Au plaisir de vous servir. Appelez le [% branch.branchphone %]."
---
},
        },
    },
);

# Koha groups every transport of a letter code under one name. Prefer the
# library's original name over a name that is just the code.
sub _harmonize_letter_name {
    my ( $dbh, $module, $code, $branchcode ) = @_;
    return unless $dbh && defined $code && $code ne '';
    $branchcode = '' unless defined $branchcode;
    my $sth = $dbh->prepare(q{
        SELECT name FROM letter
        WHERE module = ? AND code = ? AND branchcode = ?
          AND name IS NOT NULL AND name <> ''
    });
    $sth->execute( $module, $code, $branchcode );
    my @names;
    while ( my ($name) = $sth->fetchrow_array ) {
        push @names, $name;
    }
    $sth->finish();
    return unless @names;
    my ($chosen) = grep { $_ ne $code } @names;
    $chosen = $names[0] unless defined $chosen && $chosen ne '';
    my $upd = $dbh->prepare(q{
        UPDATE letter SET name = ?
        WHERE module = ? AND code = ? AND branchcode = ?
          AND (name IS NULL OR name <> ?)
    });
    $upd->execute( $chosen, $module, $code, $branchcode, $chosen );
    $upd->finish();
}

sub run {
    my (%opts) = @_;
    my @log_lines;

    my $default_language_opt = $opts{default_language} // 'en';
    my $default_content_key = $DEFAULT_LANG_ALIASES{$default_language_opt};
    unless ( defined $default_content_key ) {
        return { ok => 0, count => 0, log => '', error => "Unknown default_language='$default_language_opt'" };
    }

    my @want_langs;
    my @want_services;
    eval {
        @want_langs    = _resolve_languages( $opts{languages} );
        @want_services = _resolve_services( $opts{services} );
        1;
    } or do {
        my $err = $@ // 'option error';
        chomp $err;
        return { ok => 0, count => 0, log => '', error => $err };
    };

    my $do_defaults     = $opts{defaults} ? 1 : 0;
    my $do_ci_templates = $opts{ci_templates} ? 1 : 0;
    my @consortia_branches;
    if ( ref $opts{consortia_branches} eq 'ARRAY' ) {
        @consortia_branches = @{ $opts{consortia_branches} };
    }
    elsif ( defined $opts{consortia_branches} && length $opts{consortia_branches} ) {
        @consortia_branches = split /,/, $opts{consortia_branches};
    }
    @consortia_branches = map { s/^\s+|\s+$//gr } @consortia_branches;
    @consortia_branches = grep { length } @consortia_branches;

    my $dbh = $opts{dbh};
    unless ($dbh) {
        eval {
            require C4::Context;
            $dbh = C4::Context->dbh;
            1;
        } or do {
            return { ok => 0, count => 0, log => '', error => "Database unavailable: $@" };
        };
    }

    if ( $opts{consortia_from_plugin} ) {
        my @from_plugin = _plugin_enabled_branches( $opts{plugin}, $dbh, \@log_lines );
        if (@from_plugin) {
            _log( \@log_lines, "Plugin enabled_branches: " . join( ', ', @from_plugin ) );
            push @consortia_branches, @from_plugin;
        }
        else {
            _log( \@log_lines, "consortia_from_plugin: no concrete branches in enabled_branches (unset/*/empty)." );
        }
    }

    {
        my %seen;
        @consortia_branches = grep { !$seen{$_}++ } @consortia_branches;
    }

    unless ( $do_defaults || $do_ci_templates || @consortia_branches ) {
        $do_defaults = 1;
        _log( \@log_lines, "No install mode given; assuming defaults." );
    }

    _log( \@log_lines, "CirriusImpact Message Template Installer" );
    _log( \@log_lines, "Default letter.lang content: $default_content_key" );
    _log( \@log_lines, "Services: " . join( ', ', @want_services ) );
    _log( \@log_lines, "Languages: " . join( ', ', @want_langs ) );
    my $modes = '';
    $modes .= " defaults" if $do_defaults;
    $modes .= " ci-templates" if $do_ci_templates;
    $modes .= " consortia-branch=" . join( ',', @consortia_branches ) if @consortia_branches;
    _log( \@log_lines, "Modes:$modes" );

    my %templates = %TEMPLATES;
    my @incompatible;


    my $content_for_lang = sub {
        my ($template, $lang) = @_;
        my $key = ($lang eq 'default') ? $default_content_key : $lang;
        return $template->{content}{$key};
    };

    my $install_template = sub {
        my ($name, $template, $lang, $code_override, $branchcode, $wrap_existing, $canned_on_stock) = @_;
        $branchcode      = '' unless defined $branchcode;
        $wrap_existing   = 0  unless $wrap_existing;
        $canned_on_stock = 0  unless $canned_on_stock;

        my $code = defined $code_override ? $code_override : $template->{code};
        my $src  = ($lang eq 'default') ? "default<-$default_content_key" : $lang;
        my $branch_label = length($branchcode) ? "branch=$branchcode" : "branch=DEFAULT";

        my $content;
        if ($wrap_existing) {
            my $fetch_sth = $dbh->prepare(q{
                SELECT content FROM letter
                WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
                  AND branchcode = ?
                LIMIT 1
            });
            $fetch_sth->execute(
                $template->{module}, $code, $template->{transport}, $lang, $branchcode
            );
            my ($existing) = $fetch_sth->fetchrow_array;
            $fetch_sth->finish();

            if ( defined $existing && $existing =~ /\S/ ) {
                my $review_label = join '/', $code, $template->{transport}, $lang,
                  ( length($branchcode) ? $branchcode : 'DEFAULT' );
                my @problems = _notice_problems( $existing, $code );
                if ( _already_ci_yaml($existing) ) {
                    if (@problems) {
                        push @incompatible, $review_label;
                        _log(
                            \@log_lines,
                            "Needs review $name code=$code [$src] ($branch_label) — "
                              . join( ' ', @problems )
                        );
                    }
                    else {
                        _log(
                            \@log_lines,
                            "Skipped $name code=$code [$src] ($branch_label) — already CirriusImpact YAML"
                        );
                    }
                    return 0;
                }
                my $wrapped = _wrap_existing_as_ci( $existing, $template->{transport}, $code );
                my @after = _notice_problems( $wrapped, $code );
                if (@after) {
                    push @incompatible, $review_label;
                    _log(
                        \@log_lines,
                        "Left unchanged $name code=$code [$src] ($branch_label) — "
                          . join( ' ', ( @problems ? @problems : @after ) )
                    );
                    return 0;
                }
                $content = $wrapped;
                if (@problems) {
                    _log(
                        \@log_lines,
                        "Rebuilt repeat for $name code=$code [$src] ($branch_label) so each item is included"
                    );
                }
            }
            else {
                # No SMS/phone row yet. Install the canned notice so the library
                # can start sending this transport without writing it from scratch.
                $content = $content_for_lang->( $template, $lang );
                unless ( defined $content && $content =~ /\S/ ) {
                    _log(
                        \@log_lines,
                        "Skipped $name code=$code [$src] ($branch_label) — no existing notice and no canned content"
                    );
                    return 0;
                }
                $wrap_existing = 0;
            }
        }
        else {
            $content = $content_for_lang->( $template, $lang );
            unless ( defined $content && $content =~ /\S/ ) {
                _log( \@log_lines, "Skipping $name ($lang) — no canned content" );
                return 0;
            }
        }

        my $check_sth = $dbh->prepare(q{
            SELECT content FROM letter
            WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
              AND branchcode = ?
            LIMIT 1
        });
        $check_sth->execute($template->{module}, $code, $template->{transport}, $lang, $branchcode);
        my ($existing_content) = $check_sth->fetchrow_array;
        $check_sth->finish();
        my $exists = defined $existing_content;

        if ($canned_on_stock) {
            # Keep the library's previous text recoverable, and mark the row so
            # Remove can tell a CI Default apart from a wrapped notice.
            my $previous = $existing_content;
            if ( defined $previous && $previous =~ /CirriusImpact Default/ ) {
                $previous = _extract_original_from_wrapped($previous);
            }
            my $canned = $content;
            $canned =~ s/\s+\z//;
            $content = $canned . "\n" . '[%' . '# CirriusImpact Default %]' . "\n";
            if ( defined $previous && $previous =~ /\S/ ) {
                $content .= _tt_comment_block($previous) . "\n";
            }
        }

        if ($exists) {
            # Leave letter.name and letter.title alone. Koha shows one name for
            # every transport of a code; rewriting it per install splits the UI.
            my $update_sth = $dbh->prepare(q{
                UPDATE letter
                SET content = ?
                WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
                  AND branchcode = ?
            });
            $update_sth->execute(
                $content,
                $template->{module}, $code, $template->{transport}, $lang, $branchcode
            );
            $update_sth->finish();
            _log(
                \@log_lines,
                ( $wrap_existing ? "Wrapped" : "Updated" )
                  . " $name code=$code [$src] ($branch_label)"
            );
        }
        else {
            my $name_sth = $dbh->prepare(q{
                SELECT name, title FROM letter
                WHERE module = ? AND code = ? AND branchcode = ?
                  AND name IS NOT NULL AND name <> ''
                ORDER BY (name = ?) ASC
                LIMIT 1
            });
            $name_sth->execute( $template->{module}, $code, $branchcode, $code );
            my ( $sibling_name, $sibling_title ) = $name_sth->fetchrow_array;
            $name_sth->finish();
            my $template_name = ( defined $sibling_name && $sibling_name ne '' ) ? $sibling_name : $code;
            my $title = ( defined $sibling_title && $sibling_title ne '' ) ? $sibling_title : $template_name;
            my $insert_sth = $dbh->prepare(q{
                INSERT INTO letter (module, code, message_transport_type, content, title, name, branchcode, lang)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            });
            $insert_sth->execute(
                $template->{module}, $code, $template->{transport},
                $content, $title, $template_name, $branchcode, $lang
            );
            $insert_sth->finish();
            _log(\@log_lines, "Installed $name code=$code [$src] ($branch_label)");
        }
        _harmonize_letter_name( $dbh, $template->{module}, $code, $branchcode );
        return 1;
    };

    my %want_service = map { $_ => 1 } @want_services;
    my $count = 0;
    # Each target: [code_mode, branchcode, wrap_existing, canned_on_stock]
    # code_mode undef = the normal letter code (CHECKOUT, CHECKIN, ...).
    # wrap_existing: read existing letter text and wrap in CirriusImpact YAML.
    # canned_on_stock: write the canned CI default onto that same normal notice.
    my @targets;
    if ($do_defaults) {
        push @targets, [ undef, '', 1, 0 ];
    }
    if ($do_ci_templates) {
        push @targets, [ undef, '', 0, 1 ];
    }
    for my $b (@consortia_branches) {
        push @targets, [ undef, $b, 1, 0 ];
    }

    eval {
        for my $lang (@want_langs) {
            _log(\@log_lines, "---- Language: $lang ----");
            for my $name (sort keys %templates) {
                my $tpl = $templates{$name};
                next unless $want_service{ $tpl->{transport} };
                for my $t (@targets) {
                    my ( undef, $branch, $wrap_existing, $canned_on_stock ) = @$t;
                    $count += $install_template->(
                        $name, $tpl, $lang, undef, $branch, $wrap_existing, $canned_on_stock
                    );
                }
            }
        }
        1;
    } or do {
        my $err = $@ // 'install failed';
        chomp $err;
        return {
            ok    => 0,
            count => $count,
            log   => join( '', @log_lines ),
            error => $err,
        };
    };

    my %seen_incompatible;
    @incompatible = grep { length && !$seen_incompatible{$_}++ } @incompatible;
    if (@incompatible) {
        _log( \@log_lines, "Incompatible notices left for review: " . join( ', ', @incompatible ) );
        _log( \@log_lines, "Download the comparison on Configure to see what each notice would send." );
    }

    _log(\@log_lines, "=" x 50);
    _log(\@log_lines, "Installation complete! Installed/Updated $count template rows");
    _log(\@log_lines, "Notes: matching letter rows are overwritten; TranslateNotices + OPACLanguages for language tabs.");

    return {
        ok           => 1,
        count        => $count,
        incompatible => \@incompatible,
        log          => join( '', @log_lines ),
        error        => '',
        modes        => {
            defaults           => $do_defaults,
            ci_templates       => $do_ci_templates,
            consortia_branches => \@consortia_branches,
            services           => \@want_services,
            languages          => \@want_langs,
            default_language   => $default_content_key,
        },
    };
}

# Reverse InstallMessageTemplates::run for the same mode selection.
# - defaults / consortia: restore stock letter content from archived TT comments
#   (fallback: sms.text / call.script body)
# - ci-templates: restore the normal notice (or delete a row this install created)
#   and delete any older CODE-CI sample rows
#
# run_remove(%same_opts_as_run)
sub run_remove {
    my (%opts) = @_;
    my @log_lines;

    my @want_langs;
    my @want_services;
    eval {
        @want_langs    = _resolve_languages( $opts{languages} );
        @want_services = _resolve_services( $opts{services} );
        1;
    } or do {
        my $err = $@ // 'option error';
        chomp $err;
        return { ok => 0, count => 0, log => '', error => $err };
    };

    my $do_defaults     = $opts{defaults} ? 1 : 0;
    my $do_ci_templates = $opts{ci_templates} ? 1 : 0;
    my @consortia_branches;
    if ( ref $opts{consortia_branches} eq 'ARRAY' ) {
        @consortia_branches = @{ $opts{consortia_branches} };
    }
    elsif ( defined $opts{consortia_branches} && length $opts{consortia_branches} ) {
        @consortia_branches = split /,/, $opts{consortia_branches};
    }
    @consortia_branches = map { s/^\s+|\s+$//gr } @consortia_branches;
    @consortia_branches = grep { length } @consortia_branches;

    my $dbh = $opts{dbh};
    unless ($dbh) {
        eval {
            require C4::Context;
            $dbh = C4::Context->dbh;
            1;
        } or do {
            return { ok => 0, count => 0, log => '', error => "Database unavailable: $@" };
        };
    }

    if ( $opts{consortia_from_plugin} ) {
        my @from_plugin = _plugin_enabled_branches( $opts{plugin}, $dbh, \@log_lines );
        if (@from_plugin) {
            _log( \@log_lines, "Plugin enabled_branches: " . join( ', ', @from_plugin ) );
            push @consortia_branches, @from_plugin;
        }
        else {
            _log( \@log_lines, "consortia_from_plugin: no concrete branches in enabled_branches (unset/*/empty)." );
        }
    }

    {
        my %seen;
        @consortia_branches = grep { !$seen{$_}++ } @consortia_branches;
    }

    unless ( $do_defaults || $do_ci_templates || @consortia_branches ) {
        $do_defaults = 1;
        _log( \@log_lines, "No remove mode given; assuming defaults." );
    }

    _log( \@log_lines, "CirriusImpact Message Template Remover / Revert" );
    _log( \@log_lines, "Services: " . join( ', ', @want_services ) );
    _log( \@log_lines, "Languages: " . join( ', ', @want_langs ) );
    my $modes = '';
    $modes .= " defaults" if $do_defaults;
    $modes .= " ci-templates" if $do_ci_templates;
    $modes .= " consortia-branch=" . join( ',', @consortia_branches ) if @consortia_branches;
    _log( \@log_lines, "Modes:$modes" );

    my %want_service = map { $_ => 1 } @want_services;
    my %want_lang    = map { $_ => 1 } @want_langs;
    my $count        = 0;

    my @branch_targets;
    push @branch_targets, '' if $do_defaults;
    push @branch_targets, @consortia_branches;

    eval {
        # 1) Revert wrapped stock / branch notices
        for my $branch (@branch_targets) {
            my $branch_label = length($branch) ? "branch=$branch" : "branch=DEFAULT";
            my $sth = $dbh->prepare(q{
                SELECT module, code, message_transport_type, lang, content
                FROM letter
                WHERE branchcode = ?
                  AND content LIKE '%CirriusImpact%'
            });
            $sth->execute($branch);
            while ( my $row = $sth->fetchrow_hashref ) {
                my $code      = $row->{code} // '';
                my $transport = $row->{message_transport_type} // '';
                my $lang      = $row->{lang} // '';
                next unless $want_service{$transport};
                next unless $want_lang{$lang};
                # Stock/consortia revert never touches CODE-CI samples
                next if $code =~ /-CI\z/;
                next unless _already_ci_yaml( $row->{content} );

                my $original = _extract_original_from_wrapped( $row->{content} );
                unless ( defined $original && $original =~ /\S/ ) {
                    _log(
                        \@log_lines,
                        "Skipped revert $code/$transport [$lang] ($branch_label) — cannot recover original text"
                    );
                    next;
                }

                my $upd = $dbh->prepare(q{
                    UPDATE letter
                    SET content = ?
                    WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
                      AND branchcode = ?
                });
                $upd->execute(
                    $original,
                    $row->{module}, $code, $transport, $lang, $branch
                );
                $upd->finish();
                $count++;
                _log( \@log_lines, "Reverted $code/$transport [$lang] ($branch_label)" );
            }
            $sth->finish();
        }

        # 2) CI Defaults were written onto the normal letter code. Restore the
        #    archived notice, or delete the row when this install created it.
        if ($do_ci_templates) {
            my $sth = $dbh->prepare(q{
                SELECT module, code, message_transport_type, lang, branchcode, content
                FROM letter
                WHERE branchcode = ''
                  AND content LIKE '%CirriusImpact Default%'
            });
            $sth->execute();
            while ( my $row = $sth->fetchrow_hashref ) {
                my $code      = $row->{code} // '';
                my $transport = $row->{message_transport_type} // '';
                my $lang      = $row->{lang} // '';
                next if $code =~ /-CI\z/;
                next unless $want_service{$transport};
                next unless $want_lang{$lang};
                my $original = _extract_original_from_wrapped( $row->{content} );
                if ( defined $original && $original =~ /\S/ ) {
                    my $upd = $dbh->prepare(q{
                        UPDATE letter
                        SET content = ?
                        WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
                          AND branchcode = ?
                    });
                    $upd->execute(
                        $original, $row->{module}, $code, $transport, $lang, ''
                    );
                    $upd->finish();
                    $count++;
                    _log( \@log_lines, "Reverted CI default $code/$transport [$lang] (branch=DEFAULT)" );
                }
                else {
                    my $del = $dbh->prepare(q{
                        DELETE FROM letter
                        WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
                          AND branchcode = ?
                    });
                    $del->execute( $row->{module}, $code, $transport, $lang, '' );
                    $del->finish();
                    $count++;
                    _log( \@log_lines, "Deleted CI default $code/$transport [$lang] (branch=DEFAULT)" );
                }
            }
            $sth->finish();
        }

        # 3) Remove older canned CODE-CI sample rows from previous installs
        if ($do_ci_templates) {
            my $sth = $dbh->prepare(q{
                SELECT module, code, message_transport_type, lang, branchcode, content
                FROM letter
                WHERE code LIKE '%-CI'
                  AND branchcode = ''
                  AND content LIKE '%CirriusImpact%'
            });
            $sth->execute();
            while ( my $row = $sth->fetchrow_hashref ) {
                my $transport = $row->{message_transport_type} // '';
                my $lang      = $row->{lang} // '';
                next unless $want_service{$transport};
                next unless $want_lang{$lang};
                next unless _already_ci_yaml( $row->{content} );

                my $del = $dbh->prepare(q{
                    DELETE FROM letter
                    WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
                      AND branchcode = ?
                });
                $del->execute(
                    $row->{module}, $row->{code}, $transport, $lang, $row->{branchcode} // ''
                );
                $del->finish();
                $count++;
                _log(
                    \@log_lines,
                    "Deleted CI sample $row->{code}/$transport [$lang] (branch=DEFAULT)"
                );
            }
            $sth->finish();
        }
        1;
    } or do {
        my $err = $@ // 'remove failed';
        chomp $err;
        return {
            ok    => 0,
            count => $count,
            log   => join( '', @log_lines ),
            error => $err,
        };
    };

    _log( \@log_lines, "=" x 50 );
    _log( \@log_lines, "Remove/revert complete! Changed $count letter row(s)" );

    return {
        ok    => 1,
        count => $count,
        log   => join( '', @log_lines ),
        error => '',
        modes => {
            defaults           => $do_defaults,
            ci_templates       => $do_ci_templates,
            consortia_branches => \@consortia_branches,
            services           => \@want_services,
            languages          => \@want_langs,
        },
    };
}

# Canned CirriusImpact templates shipped by v1.1.43 - v1.3.4 for the notices whose
# shape changed in v1.3.5 (normalized content sha1 => "transport:content language").
my %LEGACY_TEMPLATE_DIGESTS = (
    AUTO_RENEWALS_DGST => {
        '044a23192f1c0865206c9d3865a6330be449f9d8' => 'sms:fr-CA',
        '28ea54e2f5f2c8cbf1313566f89964e7e23a3f73' => 'phone:fr-CA',
        '293fbe8d809514f2da44f878e4331c08979ef135' => 'phone:en',
        '55edd3f29dd4da4b3278fd078ea5226a0b9a9843' => 'sms:en',
        '69ba41a8c8b5d8c35aa0cb7c7a6cfd49916523f6' => 'phone:en',
        'b3ac36791ded6542aa6da34982e97af871875709' => 'phone:es-ES',
        'e4fc64364ec5181d69745a8da6ede6a7c2e16b03' => 'sms:en',
        'ee8a196fde3b146d15aaabc54fd26145aebcc053' => 'sms:es-ES',
        # v1.3.5–v1.3.10 digest text listed items that were not renewed
        '324a23a25c5c8eb6e22bc2abb0935e90c9cb5391' => 'sms:en',
        '6b07a3217c75942229012a93acf771070666c940' => 'sms:en',
        '391fed3df5f72a000340a1fd9f008e116b1316ee' => 'sms:es-ES',
        '1e9e2ef266a6e8bc4c4deb702cbdd596a3d5b4e3' => 'sms:es-ES',
        '2e6539c47532193fbfc626e058990b41c99c6150' => 'sms:fr-CA',
        'a6c5a7cd1f5de64fbaead9128e8e87e370ad969a' => 'sms:fr-CA',
        '02fc1cb8694392913964590ee3e3aff7b435069c' => 'phone:en',
        '49cee08fb1e21d3d568e3814c91373fafbd1d6b2' => 'phone:en',
        '43cf4196bd1ba744b7102276f0417a4afecd8f3b' => 'phone:es-ES',
        'b448382bd553b00b8684457e5f72c04ac01e5762' => 'phone:es-ES',
        'b7d30add5e89611d2d8da535c4defe23b525291c' => 'phone:fr-CA',
        '7e525b51778f59075a79eff524858fb7d39da68e' => 'phone:fr-CA',
    },
    CHECKIN => {
        '22c133b5f7634fefdddc2509dd82e8a7bb104e35' => 'sms:fr-CA',
        '4411f9af9e9001d57215cf8408b1c6c0ada222cc' => 'phone:en',
        '44d4466a0e9287c16d9a240528644b944f60cb45' => 'sms:en',
        '86faec4ffa2acf23137d0dd8cfb446d0a4ed1517' => 'phone:fr-CA',
        '8a197997ddbcca78e68f7dd522da2b633676f5c8' => 'phone:en',
        '8cb05aacc72a06492b155903dfa00720e2c413a3' => 'phone:es-ES',
        'e1d28733912828f920118616b33b5de3b23c858b' => 'sms:es-ES',
    },
    CHECKOUT => {
        '1718f474b26a2897c064ffca6cdfc99480d8f633' => 'phone:fr-CA',
        '63e2ee36f0097b1c78928c8f75cbbdcff63fb5bd' => 'phone:es-ES',
        '81184e21bf3f1534e9ed898b6cc82bef75d22079' => 'sms:es-ES',
        'c0283493456e936a4393928bfdaec3943120230f' => 'sms:fr-CA',
        'f255b485bea0febec76693b6ff4acc93638f7978' => 'sms:en',
        'f6d7fed2d5c45029d33164c797a730218c4ccf23' => 'phone:en',
        'fe438a53cdce26190e3db790d3ba697940f341c3' => 'phone:en',
    },
    HOLDDGST => {
        '353651cf539d69ba4ef4e360f279061db8ae6bd6' => 'sms:en',
        '71d33c72f7d0fe66d8eb91966ca6c683dcb7c581' => 'sms:fr-CA',
        '79b5f26db7ffc74cd79ce05ab8de9a7f2d66e989' => 'phone:en',
        '7b5a1157c1a75b12b773de97f1dcc6ef9bed12a1' => 'phone:fr-CA',
        '97e1ae3892451ae3f2664ed43599fd93458e781e' => 'phone:es-ES',
        'b85322ae17bfb86b7a36aff9095f59499c66729b' => 'sms:es-ES',
        'cf7e531fee4d773022d77c45112c98a98fedb5bf' => 'sms:en',
        'd808f7bf3fe12d2fa2160dbdaf858f46440d286a' => 'phone:en',
    },
    ODUE => {
        '0c88f20f58204c591aa078f850157eec39d1be74' => 'phone:en',
        '1143ae5e1a7b921271c54000abc7938deff2f332' => 'sms:en',
        '62ef2f5f5c9d5b93a50a928f4d7290f3edddfb71' => 'phone:es-ES',
        '90f1d30dc6b2f8c3d3f31759d3ac836886060d30' => 'sms:es-ES',
        '95587b476caefa8adfeb8f4c17e63d3dd35ad952' => 'phone:fr-CA',
        'b306b036f1ac64c1279cce80873b208061bd4a53' => 'sms:fr-CA',
        'fd2cc5a8b33f104296d5abe6aee69141c5fdc10d' => 'phone:en',
    },
    ODUE2 => {
        '0fa460ee9bec63a931037df5d2754ad355493165' => 'sms:fr-CA',
        '31cc5fb4951f02ed85db12dd223ed8e50b52c041' => 'sms:en',
        '4c591ec04aca47ecfd98f68451189b8538377632' => 'phone:en',
        '55cc4a7de12770a73d2e59ff2f5498331e6b403f' => 'sms:es-ES',
        '65c72a2afff1d6668032c613ff9bd2e08a8d77dc' => 'phone:es-ES',
        '6e2d93ac33a9ada14c531c79e91a7a53c5385179' => 'phone:fr-CA',
        'c8fd97805b43cab520ce74effc90c691fd211f6b' => 'phone:en',
        'fb4de53424f58bb22ce42a1929c99c54385e4358' => 'sms:en',
    },
    ODUE3 => {
        '17b0d2553523e48846e056501ab3105569cb32ac' => 'phone:es-ES',
        '1c68c04e600ef64b39ddb284e94c0c52ce8dd12f' => 'sms:es-ES',
        '260ebd69dea2c9fc2dcc7192a51311ab03168876' => 'sms:en',
        '3474a2c92ec0aac48dc22da42c136f2f7c70c004' => 'phone:en',
        '505740fe0feb7bfcfd5e68e97238218d0ab2c3bc' => 'phone:fr-CA',
        '63f09d8a76b09313faea76bac77a35a09dd701a9' => 'phone:en',
        '99eabd4aa94e1d15d70410b989567dbc12d20322' => 'sms:en',
        'df8a54ba4b285fbe79459da1d6ad6b22bf55f885' => 'sms:fr-CA',
    },
    PREDUEDGST => {
        '146385dbe7a588b6ebeeb7605cac3dd46999c8c8' => 'phone:en',
        '3eca8cb396e8a0e1cce29143a81f4510ce4be5c8' => 'sms:en',
        '54e37d9d50beebd781a1650c999d881c3d9a2da6' => 'phone:en',
        '56686d2a8064a82137bc2ecca8612bbaa3b47438' => 'sms:fr-CA',
        '575e9466e14e1f471b02a273c5de7b3eaa4be5e3' => 'phone:es-ES',
        '7c724a03c61cca765b174207fbd2da97f53b23af' => 'phone:fr-CA',
        'a2e1dbcec1b8e28686592d09a2981ba6ab53a8ba' => 'sms:es-ES',
        'acd781ebbfda1d5ea4673ce47dd2bc6a9ff63009' => 'sms:en',
    },
    RENEWAL => {
        '4f68db2e59a310d4b24d359f69f6ac1bf379441c' => 'phone:es-ES',
        '5833cda3600597ef9204bab2b651d8e30607c88c' => 'phone:en',
        '5c9f10a7d3763424900616c5c1f8a04cfd3fcae1' => 'phone:en',
        '78121e2ca1f2e3c82ab7bc0e0f870c5a3527510a' => 'sms:es-ES',
        '7defdef9b9d83f83e1ad428628dd3bdc29c0e05d' => 'sms:en',
        'a7a41d8ce5d64351549d0fa9442c3ecf27eaa583' => 'sms:fr-CA',
        'aadaf2db3ba3ba50534c534458556cb565f079a2' => 'phone:fr-CA',
    },
);

sub _normalize_for_digest {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/\r//g;
    $s =~ s/[ \t]+$//mg;
    $s =~ s/\A\s+//;
    $s =~ s/\s+\z//;
    return $s;
}

sub _content_digest {
    my ($content) = @_;
    require Digest::SHA;
    require Encode;
    my $norm = _normalize_for_digest($content);
    $norm = Encode::encode_utf8($norm) if utf8::is_utf8($norm);
    return Digest::SHA::sha1_hex($norm);
}

# v1.3.5–v1.3.7 canned notices match the current text except this patron tag.
sub _with_legacy_patron_token {
    my ($content) = @_;
    $content = '' unless defined $content;
    $content =~ s/\[%\s*borrower\.borrowernumber\s*%\]/[% borrowernumber %]/g;
    return $content;
}

sub _with_current_patron_token {
    my ($content) = @_;
    $content = '' unless defined $content;
    $content =~ s/\[%\s*borrowernumber\s*%\]/[% borrower.borrowernumber %]/g;
    return $content;
}

my %_REVIEW_CODE_NAME = (
    CHECKIN             => 'Check-in',
    CHECKOUT            => 'Checkout',
    RENEWAL             => 'Renewal',
    HOLDDGST            => 'Hold ready for pickup',
    PREDUEDGST          => 'Advance notice',
    DUEDGST             => 'Items due',
    AUTO_RENEWALS_DGST  => 'Automatic renewal',
    ODUE                => 'Overdue',
    ODUE2               => 'Second overdue',
    ODUE3               => 'Third overdue',
);

my %_REVIEW_TRANSPORT_NAME = (
    sms   => 'text message',
    phone => 'phone call',
    email => 'email',
);

my %_REVIEW_LANG_NAME = (
    default => 'default language',
    en      => 'English',
    eng     => 'English',
    'es-ES' => 'Spanish',
    es      => 'Spanish',
    spa     => 'Spanish',
    'fr-CA' => 'French',
    fr      => 'French',
    fre     => 'French',
);

# "CHECKIN/sms/default/DEFAULT" -> "Check-in, text message, default language, all libraries"
sub review_label_text {
    my ($label) = @_;
    my ( $code, $transport, $lang, $branch ) = _parse_review_label($label);
    my $base = $code;
    $base =~ s/-CI\z//;
    my $name = $_REVIEW_CODE_NAME{$base} || $base;
    my $how  = $_REVIEW_TRANSPORT_NAME{$transport} || ( $transport || 'notice' );
    my $language = $_REVIEW_LANG_NAME{$lang} || ( $lang || 'default language' );
    my $where = ( !defined $branch || $branch eq '' || $branch eq 'DEFAULT' )
      ? 'all libraries'
      : "library $branch";
    return "$name, $how, $language, $where";
}

sub _parse_review_label {
    my ($label) = @_;
    $label = '' unless defined $label;
    my ( $code, $transport, $lang, $branch ) = split m{/}, $label, 4;
    $code      = '' unless defined $code;
    $transport = '' unless defined $transport;
    $lang      = 'default' unless defined $lang && $lang ne '';
    $branch    = 'DEFAULT' unless defined $branch && $branch ne '';
    return ( $code, $transport, $lang, $branch );
}

sub _html_escape {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/&/&amp;/g;
    $s =~ s/</&lt;/g;
    $s =~ s/>/&gt;/g;
    $s =~ s/"/&quot;/g;
    return $s;
}

sub _quoted_message {
    my ($content) = @_;
    return '' unless defined $content && length $content;
    if ( $content =~ /(?:^|\n)[ \t]*(?:text|script|body):[ \t]*"((?:\\.|[^"\\])*)"/s ) {
        return _yaml_unescape_double($1);
    }
    if ( $content =~ /(?:^|\n)[ \t]*(?:text|script|body):[ \t]*'((?:\\.|[^'\\])*)'/s ) {
        my $s = $1;
        $s =~ s/\\'/'/g;
        $s =~ s/\\\\/\\/g;
        return $s;
    }
    return '';
}

sub _recommended_for {
    my ( $code, $transport, $lang ) = @_;
    $code = '' unless defined $code;
    $code =~ s/-CI\z//;
    $transport = '' unless defined $transport;
    my $content_lang = $DEFAULT_LANG_ALIASES{ $lang // '' } || 'en';
    for my $tpl ( values %TEMPLATES ) {
        next unless ( $tpl->{code} // '' ) eq $code;
        next unless ( $tpl->{transport} // '' ) eq $transport;
        my $body = $tpl->{content}{$content_lang};
        my $used = $content_lang;
        if ( !defined $body || $body !~ /\S/ ) {
            $body = $tpl->{content}{en};
            $used = 'en';
        }
        return ( $body, $used, $tpl->{module} );
    }
    return;
}

sub _fill_sample_tags {
    my ( $s, $one_title, $all_titles ) = @_;
    $s = '' unless defined $s;
    $one_title = 'The stolen queen' unless defined $one_title;
    $all_titles = 'The stolen queen; Kite Day' unless defined $all_titles;
    $s =~ s/\[%\s*branch\.branchcode\s*%\]/MAIN/g;
    $s =~ s/\[%\s*branch\.branchname\s*%\]/Your library/g;
    $s =~ s/\[%\s*borrower\.firstname\s*%\]/Patron/g;
    $s =~ s/\[%\s*borrower\.borrowernumber\s*%\]/13542/g;
    $s =~ s/\[%\s*biblio\.title\s*%\]/$one_title/g;
    $s =~ s/\{\{\s*ci\.titles_comma\s*\}\}/The stolen queen, Kite Day/g;
    $s =~ s/\{\{\s*ci\.titles\s*\}\}/$all_titles/g;
    $s =~ s/\{\{\s*ci\.due\s*\}\}/10\/30\/2026/g;
    $s =~ s/\{\{\s*ci\.count\s*\}\}/2/g;
    $s =~ s/\[%\s*[^\]]+\|\s*\$KohaDates[^%]*%\]/10\/30\/2026/g;
    $s =~ s/\[%\s*[^\]]*date_due[^\]]*%\]/2026-10-30 23:59:00/g;
    $s =~ s/[ \t]+/ /g;
    $s =~ s/\A\s+|\s+\z//g;
    return $s;
}

# What a two-item event would put in the exported message.
# Returns (sentence, note). Sample items are The stolen queen and Kite Day.
sub _preview_send {
    my ( $content, $code, $transport ) = @_;
    my $base = $code // '';
    $base =~ s/-CI\z//;
    my $msg = _quoted_message($content);
    $msg = $content unless length $msg;
    $msg = '' unless defined $msg;
    my $phone = ( $transport // '' ) eq 'phone';
    my $both = $phone ? 'The stolen queen, Kite Day' : 'The stolen queen; Kite Day';
    my ( $list_key ) = _incremental_list_for_code($base);

    if ( $msg =~ /^(.*)\[%\s*IF\s+[^\]]*checkins\b.*?\[%\s*ELSE\s*%\](.*?)\[%\s*END\s*%\](.*)\z/s ) {
        my $sentence = _fill_sample_tags( $1 . $2 . $3, 'The stolen queen', 'The stolen queen' );
        return (
            $sentence,
            'Two items were returned: The stolen queen and Kite Day. This notice sends only The stolen queen. Koha does not provide a checkins list, so the multiple-item branch is skipped, and the second item is not added to the waiting message.'
        );
    }

    my $quoted = _quoted_message($content);
    if ( length $quoted && $quoted =~ /----/ ) {
        return (
            '',
            'The dashed lines sit inside the message, so Koha cuts the sentence apart. The stolen queen and Kite Day are not sent as one message.'
        );
    }

    if ( $msg =~ /\{\{\s*ci\.titles/ ) {
        return (
            _fill_sample_tags( $msg, 'The stolen queen', $both ),
            'Both titles are in this one message.'
        );
    }

    if ( $msg =~ /\[%\s*FOREACH\s+\w+\s+IN\s+(?!checkins\b)(\w+)\s*%\](.*?)\[%\s*END\s*%\]/s ) {
        my $inner = $2;
        my @bits;
        for my $title ( 'The stolen queen', 'Kite Day' ) {
            my $bit = $inner;
            $bit =~ s/\[%\s*UNLESS\s+loop\.last\s*%\](.*?)\[%\s*END\s*%\]/; /sg;
            $bit =~ s/\[%\s*IF\s+loop\.last\s*%\](.*?)\[%\s*END\s*%\]//sg;
            $bit =~ s/\[%\s*[\w.]+\.title[^%]*%\]/$title/g;
            $bit =~ s/\[%\s*[\w.]+\.biblio\.title[^%]*%\]/$title/g;
            $bit =~ s/\[%\s*[\w.]*date_due[^%]*%\]/10\/30\/2026/g;
            push @bits, $bit;
        }
        my $looped = join( '', @bits );
        $msg =~ s/\[%\s*FOREACH\s+\w+\s+IN\s+\w+\s*%\].*?\[%\s*END\s*%\]/$looped/s;
        return (
            _fill_sample_tags( $msg, 'The stolen queen', $both ),
            'Both titles are in this one message.'
        );
    }

    if ( $list_key || $msg =~ /\[%\s*biblio\.title\s*%\]/ ) {
        my $sentence = _fill_sample_tags( $msg, 'The stolen queen', 'The stolen queen' );
        my $verb = $base eq 'CHECKIN' ? 'returned' : ( $base eq 'HOLDDGST' ? 'ready' : 'included' );
        return (
            $sentence,
            "Two items were $verb: The stolen queen and Kite Day. This notice sends only The stolen queen. A second item is not added to the waiting message."
        );
    }

    return (
        _fill_sample_tags( $msg, 'The stolen queen', $both ),
        'Compare this sentence with the recommended notice.'
    );
}

sub _notice_problems {
    my ( $content, $code ) = @_;
    return () unless defined $content && $content =~ /\S/;
    my $base = $code // '';
    $base =~ s/-CI\z//;
    my $msg = _quoted_message($content);
    my $look = length $msg ? $msg : $content;
    my @problems;
    my ($list_key) = _incremental_list_for_code($base);

    if ( $content =~ /\[%\s*borrowernumber\s*%\]/ && $content !~ /borrower\.borrowernumber/ ) {
        push @problems, 'The patron line uses [% borrowernumber %]. Koha leaves that blank. Use [% borrower.borrowernumber %].';
    }
    if ($list_key) {
        if ( $look =~ /\bcheckins\b/ ) {
            push @problems, 'This notice loops over checkins. Koha does not provide that list for a check-in, so only one title is sent.';
        }
        if ( length $msg && $msg =~ /----/ ) {
            push @problems, 'The dashed lines (----) are inside the message. Koha cuts the message at those dashes, so the title is dropped.';
        }
        my $has_titles = $look =~ /\{\{\s*ci\.titles/;
        my $delim_outside = length $msg
          ? ( $content =~ /----/ && $msg !~ /----/ )
          : ( $content =~ /----/ );
        if ( !$has_titles && !$delim_outside && $look !~ /\bcheckins\b/ ) {
            push @problems, 'This notice does not collect every item into one message. Koha handles it one item at a time, and a second item is not added while the message is waiting.';
        }
        if ( ( $base eq 'CHECKOUT' || $base eq 'RENEWAL' )
            && $look =~ /date_due/
            && $look !~ /\{\{\s*ci\.due/
            && $look !~ /\$KohaDates/ )
        {
            push @problems, 'The due date includes the time (for example 23:59:00). Use {{ ci.due }} for the date only.';
        }
    }
    elsif ( $base =~ /DGST\z/ || $base =~ /^ODUE/ ) {
        if ( $content !~ /FOREACH/ && $look !~ /FOREACH/ ) {
            push @problems, 'This notice has to name every item in one message. A single title tag covers only one item.';
        }
        if ( $look =~ /date_due/ && $look !~ /\$KohaDates/ && $look !~ /\{\{\s*ci\.due/ ) {
            push @problems, 'A due date in this message includes the time. Use the KohaDates filter so patrons see the date only.';
        }
    }
    return @problems;
}

sub _review_changes {
    my ( $current, $recommended, $code ) = @_;
    my @out;
    my $base = $code // '';
    $base =~ s/-CI\z//;
    my $cur_msg = _quoted_message($current);
    my $rec_msg = _quoted_message($recommended);
    my ( $list_key, $id_path ) = _incremental_list_for_code($base);

    if ( !defined $current || $current !~ /\S/ ) {
        push @out, 'This notice has no text in Koha. Paste the recommended notice into Notices and slips.';
        return @out;
    }

    if ( $current !~ /CirriusImpact\s*:\s*yes/i ) {
        push @out, 'This notice is not set up for CirriusImpact, so the message text is left out of the export. Paste the recommended notice, or add the line CirriusImpact: yes at the top.';
    }

    if ( $current =~ /\[%\s*borrowernumber\s*%\]/ && $current !~ /borrower\.borrowernumber/ ) {
        push @out, 'The patron line uses [% borrowernumber %]. Koha leaves that blank. Change it to [% borrower.borrowernumber %].';
    }

    if ( $current =~ /^[ \t]*patron:\s*(?:sms|call|email|whatsapp):/m ) {
        push @out, 'The patron line is joined to the next line. Put the patron number on its own line, then start the message on the following line.';
    }

        if ($list_key) {
        my $item_word = $base eq 'HOLDDGST' ? 'hold' : 'item';
        if ( $cur_msg =~ /\bcheckins\b/ || ( $current // '' ) =~ /\bcheckins\b/ ) {
            push @out, 'This notice loops over checkins. Koha does not provide that list on a check-in, so only one title is sent. Use {{ ci.titles }} and the item list in the recommended notice.';
        }
        if ( !length $cur_msg ) {
            push @out, 'The message sentence could not be read. In the recommended notice the sentence is in quotes, and the item list sits outside the quotes.';
        }
        else {
            if ( $cur_msg =~ /----/ ) {
                push @out, "The dashed lines (----) are inside the message. Koha cuts the message at those dashes, so the title is dropped. Move the dashes outside the quotes. Only the item id belongs between them: [% $id_path %].";
            }
            if ( $cur_msg =~ /\[%\s*biblio\.title\s*%\]/ ) {
                push @out, "The message uses [% biblio.title %], which is a single title. Put {{ ci.titles }} in the sentence so every $item_word is named.";
            }
            if ( $cur_msg !~ /\{\{\s*ci\.titles/ ) {
                push @out, 'The message does not include {{ ci.titles }}, so the titles are not filled in. Add {{ ci.titles }} where the titles should appear.';
            }
            if ( ( $base eq 'CHECKOUT' || $base eq 'RENEWAL' ) && $cur_msg =~ /date_due/ && $cur_msg !~ /\{\{\s*ci\.due/ ) {
                push @out, 'The due date comes from the checkout record and includes the time (for example 23:59:00). Use {{ ci.due }} where the date should appear. That follows the library date format and leaves the time off.';
            }
            elsif ( ( $base eq 'CHECKOUT' || $base eq 'RENEWAL' ) && $cur_msg !~ /\{\{\s*ci\.due/ ) {
                push @out, 'The message does not include {{ ci.due }}. Add it where the due date should appear.';
            }
            if ( $current !~ /^\s*\Q$list_key\E\s*:/m ) {
                push @out, "The notice is missing the $list_key list. That list is how each $item_word is repeated. Copy that section from the recommended notice.";
            }
        }
    }
    elsif ( $base =~ /DGST\z/ || $base =~ /^ODUE/ ) {
        if ( $current !~ /FOREACH/ ) {
            push @out, 'This notice has to name every item in one message. The recommended notice repeats the title for each item. Paste that notice, or add the same repeat. A single [% biblio.title %] covers only one item.';
        }
        if ( length $cur_msg && $cur_msg =~ /date_due/ && $cur_msg !~ /\$KohaDates/ && $cur_msg !~ /\{\{\s*ci\.due/ ) {
            push @out, 'A due date in this message includes the time. The recommended notice uses the KohaDates filter so patrons see the date only.';
        }
    }

    if ( length $cur_msg && length $rec_msg && $cur_msg ne $rec_msg && !@out ) {
        push @out, 'The shape of this notice is already one CirriusImpact can send. The sentences are the library\'s own, so they were left in place. Compare the two messages below. Keep yours if a test message looks right. To use the standard wording, replace the notice with the recommended one.';
    }
    elsif ( !@out ) {
        push @out, 'Compare the two notices below. Keep yours if patrons already receive the title and the date you want. Otherwise paste the recommended notice into Koha.';
    }
    else {
        push @out, 'You can paste the recommended notice over this one. To keep your own sentences, leave your words in the quoted message and apply the changes above.';
    }
    return @out;
}

sub _letter_for_review_label {
    my ( $dbh, $label ) = @_;
    return unless $dbh;
    my ( $code, $transport, $lang, $branch ) = _parse_review_label($label);
    my $branchcode = ( $branch eq 'DEFAULT' ) ? '' : $branch;
    my $sth = $dbh->prepare(q{
        SELECT id, name, module, code, branchcode, lang, message_transport_type, content
        FROM letter
        WHERE code = ? AND message_transport_type = ? AND lang = ?
          AND COALESCE(branchcode, '') = ?
        LIMIT 1
    });
    $sth->execute( $code, $transport, $lang, $branchcode );
    my $row = $sth->fetchrow_hashref;
    $sth->finish();
    return $row;
}

# HTML download: current Koha notice beside the recommended CirriusImpact notice.
# build_review_document(labels => [...], dbh => $dbh)
sub build_review_document {
    my (%opts) = @_;
    my @labels = @{ $opts{labels} || [] };
    my $dbh = $opts{dbh};
    if ( !$dbh ) {
        my $ok = eval { require C4::Context; $dbh = C4::Context->dbh; 1 };
        $dbh = undef unless $ok && $dbh;
    }

    my $html = <<"HTML";
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>CirriusImpact notice comparison</title>
<style>
  body { font-family: Georgia, "Times New Roman", serif; max-width: 52em; margin: 2em auto; padding: 0 1em; color: #222; line-height: 1.45; }
  h1 { font-size: 1.7em; margin-bottom: 0.2em; }
  h2 { font-size: 1.25em; margin-top: 2em; border-top: 1px solid #ddd; padding-top: 0.8em; }
  h3 { font-size: 1.05em; margin-bottom: 0.3em; }
  .meta { color: #444; }
  ol.changes li { margin: 0.45em 0; }
  pre { border: 1px solid #ccc; padding: 0.8em 1em; white-space: pre-wrap; word-wrap: break-word; font-family: Consolas, "Courier New", monospace; font-size: 0.92em; background: #fafafa; }
  pre.yours { border-color: #b8860b; background: #fffaf0; }
  pre.recommended { border-color: #2e7d32; background: #f4fbf4; }
  .steps { background: #f6f6f6; padding: 0.2em 1.2em 0.8em; }
</style>
</head>
<body>
<h1>CirriusImpact notice comparison</h1>
<p class="meta">Plugin v$VERSION. This report lists notices the upgrade left as they are written in Koha.</p>
<div class="steps">
<h3>How to update a notice</h3>
<ol>
<li>In Koha, open <strong>Tools &rarr; Notices and slips</strong>.</li>
<li>Find the notice by the name and code shown below.</li>
<li>Open the <strong>SMS</strong> tab for a text message, or the <strong>Phone</strong> tab for a call.</li>
<li>Select the same language as this report (the default language is the library fallback).</li>
<li>Paste the recommended notice if you want the standard message, or edit your notice using the changes listed for it.</li>
<li>Save, then send a test notice and confirm the title and the date in the CirriusImpact file.</li>
</ol>
<p>The yellow box on the CirriusImpact configuration page stays until the next plugin upgrade. Saving the notice in Koha does not clear that box.</p>
</div>
HTML

    if ( !@labels ) {
        $html .= "<p>There are no notices waiting for review.</p></body></html>\n";
        return $html;
    }

    my $n = 0;
    for my $label (@labels) {
        $n++;
        my ( $code, $transport, $lang, $branch ) = _parse_review_label($label);
        my $friendly = review_label_text($label);
        my ( $recommended, $used_lang, $module ) = _recommended_for( $code, $transport, $lang );
        $recommended = '' unless defined $recommended;
        my $row = _letter_for_review_label( $dbh, $label );
        my $current = $row && defined $row->{content} ? $row->{content} : undef;
        my $notice_name = ( $row && ( $row->{name} // '' ) ne '' ) ? $row->{name} : $code;
        my $lang_note = $_REVIEW_LANG_NAME{$used_lang} || $used_lang;
        my $cur_msg = defined $current ? _quoted_message($current) : '';
        my $rec_msg = _quoted_message($recommended);
        my @changes = _review_changes( $current, $recommended, $code );

        $html .= '<h2>' . _html_escape("$n. $friendly") . "</h2>\n";
        $html .= '<p class="meta">Koha notice name: <strong>' . _html_escape($notice_name) . '</strong>';
        $html .= ' &middot; code <strong>' . _html_escape($code) . '</strong>';
        $html .= ' &middot; ' . _html_escape( $_REVIEW_TRANSPORT_NAME{$transport} || $transport );
        if ( $module ) {
            $html .= ' &middot; module ' . _html_escape($module);
        }
        $html .= "</p>\n";
        if ( $lang eq 'default' ) {
            $html .= '<p>The recommended text below is the ' . _html_escape($lang_note) . " notice. Koha uses the default-language copy when a patron has no other language.</p>\n";
        }

        $html .= "<h3>What to change</h3>\n<ol class=\"changes\">\n";
        if ( !defined $current ) {
            $html .= "<li>The notice text could not be read from Koha for this entry. The recommended notice is still shown below.</li>\n";
        }
        for my $change (@changes) {
            $html .= '<li>' . _html_escape($change) . "</li>\n";
        }
        $html .= "</ol>\n";

        my ( $sent_now, $sent_now_note ) = _preview_send( $current, $code, $transport );
        my ( $sent_rec, $sent_rec_note ) = _preview_send( $recommended, $code, $transport );
        $html .= "<h3>What this notice would send</h3>\n";
        $html .= "<p>Example with two items, The stolen queen and Kite Day, at library MAIN.</p>\n";
        if ( length $sent_now ) {
            $html .= '<pre class="yours">' . _html_escape($sent_now) . "</pre>\n";
        }
        if ( length $sent_now_note ) {
            $html .= '<p>' . _html_escape($sent_now_note) . "</p>\n";
        }
        $html .= "<h3>What the recommended notice would send</h3>\n";
        if ( length $sent_rec ) {
            $html .= '<pre class="recommended">' . _html_escape($sent_rec) . "</pre>\n";
        }
        if ( length $sent_rec_note ) {
            $html .= '<p>' . _html_escape($sent_rec_note) . "</p>\n";
        }

        $html .= "<h3>Your message</h3>\n";
        if ( length $cur_msg ) {
            $html .= '<pre class="yours">' . _html_escape($cur_msg) . "</pre>\n";
        }
        elsif ( !defined $current ) {
            $html .= "<p>Not loaded.</p>\n";
        }
        else {
            $html .= "<p>No quoted message was found. The full notice is below.</p>\n";
        }

        $html .= "<h3>Recommended message</h3>\n";
        if ( length $rec_msg ) {
            $html .= '<pre class="recommended">' . _html_escape($rec_msg) . "</pre>\n";
        }
        elsif ( length $recommended ) {
            $html .= "<p>The recommended notice has no single quoted sentence. Use the full notice below.</p>\n";
        }
        else {
            $html .= "<p>There is no standard CirriusImpact notice for this code and transport.</p>\n";
        }

        $html .= "<h3>Your full notice in Koha</h3>\n";
        if ( defined $current && $current =~ /\S/ ) {
            $html .= '<pre class="yours">' . _html_escape($current) . "</pre>\n";
            if ( $current =~ /Original Notice Template/ ) {
                $html .= "<p>The comments at the bottom are your earlier notice. Koha does not send those comments.</p>\n";
            }
        }
        else {
            $html .= "<p>No notice text was found in Koha for this entry.</p>\n";
        }

        $html .= "<h3>Recommended full notice</h3>\n";
        if ( length $recommended ) {
            $html .= '<pre class="recommended">' . _html_escape($recommended) . "</pre>\n";
            $html .= "<p>Paste this into the same tab in Notices and slips if you want the standard message.</p>\n";
        }
    }

    $html .= "</body></html>\n";
    return $html;
}

# Plugin upgrade: rewrite shipped CirriusImpact templates (stock codes,
# CODE-CI and branch rows) to the current shape, including the v1.3.5–v1.3.7
# canned text and older legacy hashes. Wrapped notices keep the library's
# wording; the patron id is corrected and incremental wraps are rebuilt.
# Hand-edited wording is reported and not replaced.
#
# run_upgrade(dbh => $dbh, dry_run => 0|1)
# Returns { ok, updated => N, customized => [ "CODE/transport/lang/branch", ... ], log, error }
sub run_upgrade {
    my (%opts) = @_;
    my @log_lines;
    my $dbh = $opts{dbh};
    unless ($dbh) {
        eval { require C4::Context; $dbh = C4::Context->dbh; 1 }
          or return { ok => 0, updated => 0, customized => [], log => '', error => "Database unavailable: $@" };
    }

    my ( %new_template, %current_digest, %previous_digest, %review_codes );
    for my $tpl ( values %TEMPLATES ) {
        my $code = $tpl->{code};
        $new_template{$code}{ $tpl->{transport} } = $tpl;
        $review_codes{$code} = 1 if $LEGACY_TEMPLATE_DIGESTS{$code} || $code eq 'DUEDGST';
        for my $lang ( keys %{ $tpl->{content} } ) {
            my $body = $tpl->{content}{$lang};
            $current_digest{$code}{ $tpl->{transport} }{ _content_digest($body) } = $lang;
            $previous_digest{$code}{ $tpl->{transport} }{ _content_digest( _with_legacy_patron_token($body) ) } = $lang;
        }
    }

    my ( $updated, @customized );
    my $ok = eval {
        my $sth = $dbh->prepare(q{
            SELECT id, module, code, branchcode, lang, message_transport_type, content
            FROM letter
            WHERE content LIKE '%CirriusImpact%'
            ORDER BY code, message_transport_type, lang, branchcode
        });
        $sth->execute;
        my $upd = $dbh->prepare(q{UPDATE letter SET content = ? WHERE id = ?});
        while ( my $row = $sth->fetchrow_hashref ) {
            my $content = $row->{content};
            next unless _already_ci_yaml($content);
            ( my $base = $row->{code} ) =~ s/-CI\z//;
            next unless $new_template{$base};
            my $transport = $row->{message_transport_type} // '';
            my $label = join '/', $row->{code}, $transport, $row->{lang},
              ( length( $row->{branchcode} // '' ) ? $row->{branchcode} : 'DEFAULT' );
            my $digest = _content_digest($content);

            if ( $content =~ /Original Notice Template/ ) {
                my $new;
                my ($list_key) = _incremental_list_for_code($base);
                my $original = _extract_original_from_wrapped($content);
                if ( $list_key && defined $original && $original =~ /----/ ) {
                    $new = _wrap_existing_as_ci( $original, $transport, $base );
                }
                elsif ( $content =~ /\[%\s*borrowernumber\s*%\]/ ) {
                    $new = _with_current_patron_token($content);
                }
                if ( defined $new && $new =~ /\S/ && _content_digest($new) ne $digest ) {
                    $upd->execute( $new, $row->{id} ) unless $opts{dry_run};
                    $updated++;
                    _log( \@log_lines, ( $opts{dry_run} ? "Would update" : "Updated" ) . " wrapped $label" );
                }
                next;
            }

            next if $current_digest{$base}{$transport}{$digest};

            my $lang = $previous_digest{$base}{$transport}{$digest};
            if ( !defined $lang || $lang eq '' ) {
                my $legacy = $LEGACY_TEMPLATE_DIGESTS{$base} ? $LEGACY_TEMPLATE_DIGESTS{$base}{$digest} : undef;
                ( undef, $lang ) = split /:/, $legacy, 2 if $legacy;
            }
            if ( defined $lang && $lang ne '' ) {
                my $tpl = $new_template{$base}{$transport};
                my $new = $tpl ? ( $tpl->{content}{$lang} // $tpl->{content}{en} ) : undef;
                if ( defined $new && $new =~ /\S/ ) {
                    $upd->execute( $new, $row->{id} ) unless $opts{dry_run};
                    $updated++;
                    _log( \@log_lines, ( $opts{dry_run} ? "Would update" : "Updated" ) . " $label [$lang]" );
                    next;
                }
            }

            my $token_fixed = _with_current_patron_token($content);
            if ( _content_digest($token_fixed) ne $digest ) {
                $upd->execute( $token_fixed, $row->{id} ) unless $opts{dry_run};
                $updated++;
                $digest  = _content_digest($token_fixed);
                $content = $token_fixed;
                _log( \@log_lines, ( $opts{dry_run} ? "Would update" : "Updated" ) . " patron id in $label" );
            }
            next if $current_digest{$base}{$transport}{$digest};
            next unless $review_codes{$base};
            push @customized, $label;
            _log( \@log_lines, "Customized (wording kept): $label" );
        }
        1;
    };
    unless ($ok) {
        my $err = $@ // 'upgrade failed';
        chomp $err;
        return { ok => 0, updated => $updated // 0, customized => \@customized, log => join( '', @log_lines ), error => $err };
    }
    _log( \@log_lines, "Template upgrade to v$VERSION: " . ( $updated // 0 ) . " row(s) updated, "
          . scalar(@customized) . " customized row(s) need review" );
    return { ok => 1, updated => $updated // 0, customized => \@customized, log => join( '', @log_lines ), error => '' };
}

1;
