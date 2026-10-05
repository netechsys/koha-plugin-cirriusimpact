package Koha::Plugin::Com::CirriusImpact::InstallMessageTemplates;

# CirriusImpact notice template installer (callable from CLI and Configure UI).
# Upserts rows into Koha letter table.

use strict;
use warnings;

our $VERSION = '1.3.6';

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

# Wrap existing Koha notice text in CirriusImpact YAML for plugin export.
# SMS → sms.text; phone → call.script. Appends original as TT comments.
sub _wrap_existing_as_ci {
    my ( $original, $transport ) = @_;
    my $body = defined $original ? $original : '';
    $body =~ s/\A\s+//;
    $body =~ s/\s+\z//;

    my $quoted = _yaml_double_quote($body);
    my $yaml;
    # Build with single-quoted heredoc so Template Toolkit "[% %]" is literal Perl text.
    if ( ( $transport // '' ) eq 'phone' ) {
        $yaml = <<'YAML';
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: __CI_BODY__
---
YAML
    }
    else {
        $yaml = <<'YAML';
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: __CI_BODY__
---
YAML
    }
    $yaml =~ s/__CI_BODY__/$quoted/;
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
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
sms:
  text: "[% branch.branchcode %]: [% IF holds.size > 1 %][% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Hold ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]"
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
sms:
  text: "[% branch.branchcode %]: [% IF holds.size > 1 %][% holds.size %] reservas listas: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Reserva lista: [% biblio.title %][% END %]. Retire antes del [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] items ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]One item ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] articulos listos: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]Un articulo listo: [% biblio.title %][% END %]. Retire antes del [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Overdue: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Atraso: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Devuelva o renueve. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You have overdue items: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Please return or renew at your earliest convenience. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Tiene articulos atrasados: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Devuelva o renueve. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Second notice - Overdue: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: 2do aviso - Atraso: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Devuelva o renueve ya. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You have seriously overdue items: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Please return at your earliest convenience to avoid any additional fines. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Segundo aviso. Articulos atrasados: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Devuelva o renueve ya. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Final notice - Overdue: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Please return to avoid additional charges. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Aviso final - Atraso: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Devuelva o renueve ya para evitar cargos. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. This is the final overdue notice for: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Please return or renew at your earliest convenience to avoid any additional charges. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH o IN overdues %][% o.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Aviso final. Articulos atrasados: [% FOREACH o IN overdues %][% o.item.biblio.title | remove('[ /:;,.]+$') %] ([% o.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Devuelva o renueve ya para evitar cargos. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - [% biblio.title %] is due on [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Recordatorio - [% biblio.title %] vence [% issue.date_due | $KohaDates %]. Devuelva o renueve. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. This is a reminder that [% biblio.title %] is due on [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Recordatorio - [% biblio.title %] vence [% issue.date_due | $KohaDates %]. Devuelva o renueve. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Reminder - due soon: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Recordatorio - vencen pronto: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% UNLESS loop.last %]; [% END %][% END %]. Devuelva o renueve. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. This is a reminder that the following items are due soon: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Recordatorio - vencen pronto: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %] ([% c.date_due | $KohaDates %])[% UNLESS loop.last %], [% END %][% END %]. Devuelva o renueve. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold status changed for [% biblio.title %]. Check your account for details. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Estado de reserva cambiado para [% biblio.title %]. Revise su cuenta. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Due today: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %][% UNLESS loop.last %]; [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Vencen hoy: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %][% UNLESS loop.last %]; [% END %][% END %]. Devuelva o renueve. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. There has been a hold status change for [% biblio.title %]. Please check your account for details. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. El estado de su reserva cambio para [% biblio.title %]. Revise su cuenta. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. The following items are due today: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %][% UNLESS loop.last %], [% END %][% END %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Vencen hoy: [% FOREACH c IN checkouts %][% c.title | remove('[ /:;,.]+$') %][% UNLESS loop.last %], [% END %][% END %]. Devuelva o renueve. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - hold ready: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Recordatorio - Reserva lista: [% biblio.title %]. Retire antes del [% hold.expirationdate | $KohaDates %]. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. This is a reminder that a hold for [% biblio.title %] is ready for pickup by [% hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Recordatorio - Reserva lista: [% biblio.title %]. Retire antes del [% hold.expirationdate | $KohaDates %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold placed on [% biblio.title %]. You will be notified when ready for pickup. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reserva hecha para [% biblio.title %]. Le avisaremos cuando este lista. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. There is a hold placed for [% biblio.title %]. You will be notified when it is ready. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Reserva hecha para [% biblio.title %]. Le avisaremos cuando este lista. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Hold confirmed for [% biblio.title %]. You will be notified when ready for pickup. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reserva confirmada para [% biblio.title %]. Le avisaremos cuando este lista. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. There is a hold placed for [% biblio.title %]. You will be notified when it is ready. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Reserva confirmada para [% biblio.title %]. Le avisaremos cuando este lista. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
email:
  subject: "Hold Slip - [% biblio.title %]"
  body: "Hold slip for [% biblio.title %]. Patron: [% borrower.firstname %] [% borrower.surname %]. Pickup by: [% hold.expirationdate | $KohaDates %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
email:
  subject: "Comprobante de reserva - [% biblio.title %]"
  body: "Comprobante de reserva para [% biblio.title %]. Patron: [% borrower.firstname %] [% borrower.surname %]. Retiro antes del: [% hold.expirationdate | $KohaDates %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] auto-renewed. New due date: [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] renovado automaticamente. Nueva fecha: [% issue.date_due | $KohaDates %]. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. [% biblio.title %] has been auto renewed. The new due date is [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] fue renovado automaticamente. Nueva fecha: [% issue.date_due | $KohaDates %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Auto-renewal: [% FOREACH c IN checkouts %][% c.item.biblio.title | remove('[ /:;,.]+$') %][% IF c.auto_renew_error %] (not renewed)[% ELSE %] ([% c.date_due | $KohaDates %])[% END %][% UNLESS loop.last %]; [% END %][% END %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Renovacion automatica: [% FOREACH c IN checkouts %][% c.item.biblio.title | remove('[ /:;,.]+$') %][% IF c.auto_renew_error %] (no renovado)[% ELSE %] ([% c.date_due | $KohaDates %])[% END %][% UNLESS loop.last %]; [% END %][% END %]. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
sms:
  text: "[% branch.branchcode %]: Renouvellement automatique: [% FOREACH c IN checkouts %][% c.item.biblio.title | remove('[ /:;,.]+$') %][% IF c.auto_renew_error %] (non renouvele)[% ELSE %] ([% c.date_due | $KohaDates %])[% END %][% UNLESS loop.last %]; [% END %][% END %]. Appelez [% branch.branchphone %]."
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
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. Auto-renewal update: [% FOREACH c IN checkouts %][% c.item.biblio.title | remove('[ /:;,.]+$') %][% IF c.auto_renew_error %] (not renewed)[% ELSE %] ([% c.date_due | $KohaDates %])[% END %][% UNLESS loop.last %], [% END %][% END %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Renovacion automatica: [% FOREACH c IN checkouts %][% c.item.biblio.title | remove('[ /:;,.]+$') %][% IF c.auto_renew_error %] (no renovado)[% ELSE %] ([% c.date_due | $KohaDates %])[% END %][% UNLESS loop.last %], [% END %][% END %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
checkouts: "[% FOREACH c IN checkouts %][% c.issue_id %],[% END %]"
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Renouvellement automatique: [% FOREACH c IN checkouts %][% c.item.biblio.title | remove('[ /:;,.]+$') %][% IF c.auto_renew_error %] (non renouvele)[% ELSE %] ([% c.date_due | $KohaDates %])[% END %][% UNLESS loop.last %], [% END %][% END %]. Appelez le [% branch.branchphone %]."
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
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Membership expires [% borrower.dateexpiry | $KohaDates %]. Please renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Su membresia vence [% borrower.dateexpiry | $KohaDates %]. Renueve para seguir usando la biblioteca. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. Your membership is set to expire on [% borrower.dateexpiry | $KohaDates %]. Please check your account for details. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Su membresia vence [% borrower.dateexpiry | $KohaDates %]. Renueve para seguir usando la biblioteca. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Membership renewed. New expiry: [% borrower.dateexpiry | $KohaDates %]. Thank you!"
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Membresia renovada. Nueva fecha: [% borrower.dateexpiry | $KohaDates %]. Gracias!"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. Your membership has auto renewed. The new expiration date is [% borrower.dateexpiry | $KohaDates %]. Please check your account for details. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Su membresia fue renovada. Nueva fecha: [% borrower.dateexpiry | $KohaDates %]. Gracias!"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Welcome to the library, [% borrower.firstname %]! Your membership is active. Visit us soon!"
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Bienvenido a la biblioteca, [% borrower.firstname %]! Su membresia esta activa. Visitenos pronto!"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
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
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. Welcome to our library. Your membership is active. Please check your account for details. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Bienvenido a la biblioteca! Su membresia esta activa. Esperamos servirle. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Bienvenue a la bibliotheque! Votre abonnement est actif. Au plaisir de vous servir. Appelez le [% branch.branchphone %]."
---
},
        },
    },
);

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


    my $content_for_lang = sub {
        my ($template, $lang) = @_;
        my $key = ($lang eq 'default') ? $default_content_key : $lang;
        return $template->{content}{$key};
    };

    my $install_template = sub {
        my ($name, $template, $lang, $code_override, $branchcode, $wrap_existing) = @_;
        $branchcode     = '' unless defined $branchcode;
        $wrap_existing  = 0  unless $wrap_existing;

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

            unless ( defined $existing && $existing =~ /\S/ ) {
                _log(
                    \@log_lines,
                    "Skipped $name code=$code [$src] ($branch_label) — no existing notice text to wrap"
                );
                return 0;
            }
            if ( _already_ci_yaml($existing) ) {
                _log(
                    \@log_lines,
                    "Skipped $name code=$code [$src] ($branch_label) — already CirriusImpact YAML"
                );
                return 0;
            }
            $content = _wrap_existing_as_ci( $existing, $template->{transport} );
        }
        else {
            $content = $content_for_lang->( $template, $lang );
            unless ( defined $content && $content =~ /\S/ ) {
                _log( \@log_lines, "Skipping $name ($lang) — no canned content" );
                return 0;
            }
        }

        my $check_sth = $dbh->prepare(q{
            SELECT COUNT(*) FROM letter
            WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
              AND branchcode = ?
        });
        $check_sth->execute($template->{module}, $code, $template->{transport}, $lang, $branchcode);
        my ($exists) = $check_sth->fetchrow_array;
        $check_sth->finish();

        my $title = "$code - $template->{transport}";
        my $template_name = $code;

        if ($exists) {
            my $update_sth = $dbh->prepare(q{
                UPDATE letter
                SET content = ?, name = ?, title = ?
                WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
                  AND branchcode = ?
            });
            $update_sth->execute(
                $content, $template_name, $title,
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
            # Wrap mode never inserts (no source text). Canned CI-templates may insert.
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
        return 1;
    };

    my %want_service = map { $_ => 1 } @want_services;
    my $count = 0;
    # Each target: [code_mode, branchcode, wrap_existing]
    # code_mode undef = stock code; '__CI__' = CODE-CI (canned samples)
    # wrap_existing: read existing letter text and wrap in CirriusImpact YAML
    my @targets;
    if ($do_defaults) {
        push @targets, [ undef, '', 1 ];
    }
    if ($do_ci_templates) {
        push @targets, [ '__CI__', '', 0 ];
    }
    for my $b (@consortia_branches) {
        push @targets, [ undef, $b, 1 ];
    }

    eval {
        for my $lang (@want_langs) {
            _log(\@log_lines, "---- Language: $lang ----");
            for my $name (sort keys %templates) {
                my $tpl = $templates{$name};
                next unless $want_service{ $tpl->{transport} };
                for my $t (@targets) {
                    my ($code_mode, $branch, $wrap_existing) = @$t;
                    my $code_override;
                    if (defined $code_mode && $code_mode eq '__CI__') {
                        $code_override = $tpl->{code} . '-CI';
                    }
                    $count += $install_template->(
                        $name, $tpl, $lang, $code_override, $branch, $wrap_existing
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

    _log(\@log_lines, "=" x 50);
    _log(\@log_lines, "Installation complete! Installed/Updated $count template rows");
    _log(\@log_lines, "Notes: matching letter rows are overwritten; TranslateNotices + OPACLanguages for language tabs.");

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
            default_language   => $default_content_key,
        },
    };
}

# Reverse InstallMessageTemplates::run for the same mode selection.
# - defaults / consortia: restore stock letter content from archived TT comments
#   (fallback: sms.text / call.script body)
# - ci-templates: DELETE CODE-CI rows installed as canned samples
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

        # 2) Remove canned CODE-CI sample rows
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

# Plugin upgrade: rewrite untouched canned CirriusImpact templates (stock codes,
# CODE-CI and branch rows) to the v1.3.5 multi-item shape. Rows wrapping the
# library's own notice are left alone; hand-edited CirriusImpact rows are reported.
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

    my ( %new_template, %current_digest );
    for my $tpl ( values %TEMPLATES ) {
        next unless $LEGACY_TEMPLATE_DIGESTS{ $tpl->{code} } || $tpl->{code} eq 'DUEDGST';
        $new_template{ $tpl->{code} }{ $tpl->{transport} } = $tpl;
        $current_digest{ $tpl->{code} }{ _content_digest($_) } = 1 for values %{ $tpl->{content} };
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
            my $label = join '/', $row->{code}, $row->{message_transport_type}, $row->{lang},
              ( length( $row->{branchcode} // '' ) ? $row->{branchcode} : 'DEFAULT' );

            next if $content =~ /Original Notice Template/;
            my $digest = _content_digest($content);
            next if $current_digest{$base}{$digest};

            my $legacy = $LEGACY_TEMPLATE_DIGESTS{$base} ? $LEGACY_TEMPLATE_DIGESTS{$base}{$digest} : undef;
            unless ($legacy) {
                push @customized, $label;
                _log( \@log_lines, "Customized (left unchanged, review for multi-item support): $label" );
                next;
            }
            my ( undef, $lang ) = split /:/, $legacy, 2;
            my $tpl = $new_template{$base}{ $row->{message_transport_type} };
            my $new = $tpl ? $tpl->{content}{$lang} // $tpl->{content}{en} : undef;
            unless ( defined $new && $new =~ /\S/ ) {
                push @customized, $label;
                _log( \@log_lines, "No v$VERSION template for $label; left unchanged" );
                next;
            }
            $upd->execute( $new, $row->{id} ) unless $opts{dry_run};
            $updated++;
            _log( \@log_lines, ( $opts{dry_run} ? "Would update" : "Updated" ) . " $label [$lang]" );
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
