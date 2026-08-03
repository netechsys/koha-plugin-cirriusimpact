package Koha::Plugin::Com::CirriusImpact::InstallMessageTemplates;

# CirriusImpact notice template installer (callable from CLI and Configure UI).
# Upserts rows into Koha letter table.

use strict;
use warnings;

our $VERSION = '1.3.2';

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

my %templates = (
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
  text: "[% branch.branchcode %]: [% IF holds && holds.size > 1 %][% holds.size %] holds ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Pickup by [% holds.0.expirationdate | $KohaDates %][% ELSE %]Hold ready: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %][% END %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF holds && holds.size > 1 %]Tiene [% holds.size %] reservas listas: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Retire antes del [% holds.0.expirationdate | $KohaDates %][% ELSE %]Reserva lista: [% biblio.title %]. Retire antes del [% hold.expirationdate | $KohaDates %][% END %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF holds && holds.size > 1 %]Vous avez [% holds.size %] reserves pretes: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Retirer avant le [% holds.0.expirationdate | $KohaDates %][% ELSE %]Reserve prete: [% biblio.title %]. Retirer avant le [% hold.expirationdate | $KohaDates %][% END %]."
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
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. [% IF holds && holds.size > 1 %]You have [% holds.size %] holds ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Pickup by [% holds.0.expirationdate | $KohaDates %][% ELSE %]One item ready: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %][% END %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. [% IF holds && holds.size > 1 %]Tiene [% holds.size %] reservas listas: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Retire antes del [% holds.0.expirationdate | $KohaDates %][% ELSE %]Tiene una reserva lista: [% biblio.title %]. Retire antes del [% hold.expirationdate | $KohaDates %][% END %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. [% IF holds && holds.size > 1 %]Vous avez [% holds.size %] reserves pretes: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Retirer avant le [% holds.0.expirationdate | $KohaDates %][% ELSE %]Vous avez une reserve prete: [% biblio.title %]. Retirer avant le [% hold.expirationdate | $KohaDates %][% END %]. Appelez le [% branch.branchphone %]."
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
  text: "[% branch.branchcode %]: [% IF checkouts.size > 1 %]Checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %][% ELSE %]Checked out: [% biblio.title %]. Due [% checkout.date_due | $KohaDates %][% END %]"
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF checkouts.size > 1 %]Prestamo de [% checkouts.size %] articulos: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Vencen [% checkouts.0.date_due | $KohaDates %][% ELSE %]Prestamo: [% biblio.title %]. Vence [% checkout.date_due | $KohaDates %][% END %]"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF checkouts.size > 1 %]Pret de [% checkouts.size %] documents: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Echeance [% checkouts.0.date_due | $KohaDates %][% ELSE %]Pret: [% biblio.title %]. Echeance [% checkout.date_due | $KohaDates %][% END %]"
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
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. [% IF checkouts.size > 1 %]You checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %][% ELSE %]You checked out [% biblio.title %] due [% checkout.date_due | $KohaDates %][% END %]. Thank you!"
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. [% IF checkouts.size > 1 %]Prestamo de [% checkouts.size %] articulos: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Vencen [% checkouts.0.date_due | $KohaDates %][% ELSE %]Prestamo de [% biblio.title %] con vencimiento [% checkout.date_due | $KohaDates %][% END %]. Gracias!"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. [% IF checkouts.size > 1 %]Pret de [% checkouts.size %] documents: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Echeance [% checkouts.0.date_due | $KohaDates %][% ELSE %]Pret de [% biblio.title %] echeance [% checkout.date_due | $KohaDates %][% END %]. Merci!"
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
  text: "[% branch.branchcode %]: [% IF checkins.size > 1 %]Checked in [% checkins.size %] items: [% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Checked in: [% biblio.title %][% END %]. Thank you!"
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF checkins.size > 1 %]Devolucion de [% checkins.size %] articulos: [% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Devolucion: [% biblio.title %][% END %]. Gracias!"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF checkins.size > 1 %]Retour de [% checkins.size %] documents: [% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %]Retour: [% biblio.title %][% END %]. Merci!"
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
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. The following item was checked in: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Thank you!"
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Se devolvio: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Gracias!"
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Retour enregistre: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Merci!"
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
sms:
  text: "[% branch.branchcode %]: Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Atraso: [% biblio.title %]. Vencio [% issue.date_due | $KohaDates %]. Devuelva o renueve. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: En retard: [% biblio.title %]. Echu le [% issue.date_due | $KohaDates %]. Retournez ou renouvelez. Appelez [% branch.branchphone %]."
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
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You have an overdue item: [% biblio.title %]. It was due [% issue.date_due | $KohaDates %]. Please return or renew at your earliest convenience. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Tiene un articulo atrasado: [% biblio.title %]. Vencio [% issue.date_due | $KohaDates %]. Devuelva o renueve. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Document en retard: [% biblio.title %]. Echu le [% issue.date_due | $KohaDates %]. Retournez ou renouvelez. Appelez le [% branch.branchphone %]."
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
sms:
  text: "[% branch.branchcode %]: Second notice - Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: 2do aviso - Atraso: [% biblio.title %]. Vencio [% issue.date_due | $KohaDates %]. Devuelva o renueve ya. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: 2e avis - En retard: [% biblio.title %]. Echu le [% issue.date_due | $KohaDates %]. Retournez ou renouvelez maintenant. Appelez [% branch.branchphone %]."
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
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. You have a seriously overdue item: [% biblio.title %]. It was due [% issue.date_due | $KohaDates %]. Please return at your earliest convenience to avoid any additional fines. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Segundo aviso. Articulo atrasado: [% biblio.title %]. Vencio [% issue.date_due | $KohaDates %]. Devuelva o renueve ya. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Deuxieme avis. Document en retard: [% biblio.title %]. Echu le [% issue.date_due | $KohaDates %]. Retournez ou renouvelez maintenant. Appelez le [% branch.branchphone %]."
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
sms:
  text: "[% branch.branchcode %]: Final notice - Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return to avoid additional charges. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Aviso final - Atraso: [% biblio.title %]. Vencio [% issue.date_due | $KohaDates %]. Devuelva o renueve ya para evitar cargos. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Avis final - En retard: [% biblio.title %]. Echu le [% issue.date_due | $KohaDates %]. Retournez ou renouvelez maintenant pour eviter des frais. Appelez [% branch.branchphone %]."
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
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. This is the final overdue notice for item: [% biblio.title %]. It was due [% issue.date_due | $KohaDates %]. Please return or renew at your earliest convenience to avoid any additional charges. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. Aviso final. Articulo atrasado: [% biblio.title %]. Vencio [% issue.date_due | $KohaDates %]. Devuelva o renueve ya para evitar cargos. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. Avis final. Document en retard: [% biblio.title %]. Echu le [% issue.date_due | $KohaDates %]. Retournez ou renouvelez maintenant pour eviter des frais. Appelez le [% branch.branchphone %]."
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
    'PREDUEDGST_PHONE' => {
        module => 'circulation',
        code => 'PREDUEDGST',
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
  text: "[% branch.branchcode %]: [% biblio.title %] renewed. New due date: [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] renovado. Nueva fecha: [% issue.date_due | $KohaDates %]. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% biblio.title %] renouvele. Nouvelle echeance: [% issue.date_due | $KohaDates %]. Appelez [% branch.branchphone %]."
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
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. [% biblio.title %] has been renewed. The new due date is [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] fue renovado. Nueva fecha: [% issue.date_due | $KohaDates %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] a ete renouvele. Nouvelle echeance: [% issue.date_due | $KohaDates %]. Appelez le [% branch.branchphone %]."
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
sms:
  text: "[% branch.branchcode %]: [% IF auto_renewals.size > 1 %][% auto_renewals.size %] items auto renewed: [% FOREACH renewal IN auto_renewals %][% renewal.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %][% biblio.title %] auto-renewed[% END %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF auto_renewals.size > 1 %][% auto_renewals.size %] articulos renovados auto: [% FOREACH renewal IN auto_renewals %][% renewal.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Llame [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF auto_renewals.size > 1 %][% auto_renewals.size %] documents renouvelees auto: [% FOREACH renewal IN auto_renewals %][% renewal.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Appelez [% branch.branchphone %]."
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
call:
  script: "Hello [% borrower.firstname %]. This is [% branch.branchname %]. [% IF auto_renewals.size > 1 %][% auto_renewals.size %] items have auto renewed. Please check your account for details[% ELSE %][% biblio.title %] has been auto renewed. The new due date is [% issue.date_due | $KohaDates %][% END %]. Call [% branch.branchphone %]."
---
},
        'es-ES' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hola [% borrower.firstname %]. [% branch.branchname %]. [% IF auto_renewals.size > 1 %][% auto_renewals.size %] articulos renovados automaticamente: [% FOREACH renewal IN auto_renewals %][% renewal.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Llame al [% branch.branchphone %]."
---
},
        'fr-CA' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Bonjour [% borrower.firstname %]. [% branch.branchname %]. [% IF auto_renewals.size > 1 %][% auto_renewals.size %] documents renouvelees automatiquement: [% FOREACH renewal IN auto_renewals %][% renewal.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Appelez le [% branch.branchphone %]."
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


    my $content_for_lang = sub {
        my ($template, $lang) = @_;
        my $key = ($lang eq 'default') ? $default_content_key : $lang;
        return $template->{content}{$key};
    };

    my $install_template = sub {
        my ($name, $template, $lang, $code_override, $branchcode) = @_;
        $branchcode = '' unless defined $branchcode;
        my $content = $content_for_lang->($template, $lang);
        unless (defined $content && $content =~ /\S/) {
            _log(\@log_lines, "Skipping $name ($lang) — no content");
            return 0;
        }

        my $code = defined $code_override ? $code_override : $template->{code};
        my $src = ($lang eq 'default') ? "default<-$default_content_key" : $lang;
        my $branch_label = length($branchcode) ? "branch=$branchcode" : "branch=DEFAULT";

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
            _log(\@log_lines, "Updated $name code=$code [$src] ($branch_label)");
        } else {
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
    my @targets;
    if ($do_defaults) {
        push @targets, [undef, ''];
    }
    if ($do_ci_templates) {
        push @targets, ['__CI__', ''];
    }
    for my $b (@consortia_branches) {
        push @targets, [undef, $b];
    }

    eval {
        for my $lang (@want_langs) {
            _log(\@log_lines, "---- Language: $lang ----");
            for my $name (sort keys %templates) {
                my $tpl = $templates{$name};
                next unless $want_service{ $tpl->{transport} };
                for my $t (@targets) {
                    my ($code_mode, $branch) = @$t;
                    my $code_override;
                    if (defined $code_mode && $code_mode eq '__CI__') {
                        $code_override = $tpl->{code} . '-CI';
                    }
                    $count += $install_template->($name, $tpl, $lang, $code_override, $branch);
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

1;
