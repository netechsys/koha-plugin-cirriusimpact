#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use Getopt::Long;

# CirriusImpact Message Template Installer (multilingual)
# Installs CirriusImpact YAML notices for:
#   default  = English fallback (Koha "Default" tab)
#   es-ES    = Spanish (GSM-7-safe ASCII for SMS bodies)
#   fr-CA    = French  (GSM-7-safe ASCII for SMS bodies)
#
# SMS wording avoids accents so carriers stay on GSM-7 (~160 chars/segment)
# instead of UCS-2 (~70 chars/segment). Titles still expand at send time.
#
# Usage:
#   perl install_message_templates.pl
#   perl install_message_templates.pl --languages=default,es-ES,fr-CA
#   perl install_message_templates.pl --languages=es-ES --no-restart

print "CirriusImpact Message Template Installer (multilingual)\n";
print "========================================================\n\n";

my @want_langs = ('default', 'es-ES', 'fr-CA');
my $no_restart = 0;
GetOptions(
    'languages=s' => \my $lang_opt,
    'no-restart'  => \$no_restart,
) or die "Usage: $0 [--languages=default,es-ES,fr-CA] [--no-restart]\n";
if (defined $lang_opt && $lang_opt =~ /\S/) {
    @want_langs = map { s/^\s+|\s+$//gr } split /,/, $lang_opt;
}

# Try to use Koha modules first, fall back to direct connection
my $dbh;
my $koha_available = 0;

eval {
    require C4::Context;
    require Koha::Database;
    $dbh = C4::Context->dbh;
    $koha_available = 1;
    print "✅ Connected to database via Koha modules\n";
};
if ($@) {
    print "⚠️  Koha modules not available, attempting direct connection...\n";
}

unless ($koha_available) {
    print "🔍 Attempting direct database connection...\n";
    my $koha_conf = $ENV{KOHA_CONF} || '/etc/koha/sites/library/koha-conf.xml';
    unless (-f $koha_conf) {
        # common lab path
        $koha_conf = '/etc/koha/sites/kohalab/koha-conf.xml' if -f '/etc/koha/sites/kohalab/koha-conf.xml';
    }
    unless (-f $koha_conf) {
        print "❌ ERROR: Koha config file not found\n";
        exit 1;
    }
    my ($host, $port, $database, $user, $password);
    open my $fh, '<', $koha_conf or die "Cannot open $koha_conf: $!";
    while (<$fh>) {
        if (/<host>(.*?)<\/host>/) { $host = $1; }
        elsif (/<port>(.*?)<\/port>/) { $port = $1; }
        elsif (/<database>(.*?)<\/database>/) { $database = $1; }
        elsif (/<user>(.*?)<\/user>/) { $user = $1; }
        elsif (/<pass>(.*?)<\/pass>/) { $password = $1; }
    }
    close $fh;
    unless ($host && $database && $user) {
        print "❌ ERROR: Could not parse database connection info from $koha_conf\n";
        exit 1;
    }
    $port ||= 3306;
    eval {
        $dbh = DBI->connect("DBI:mysql:database=$database;host=$host;port=$port", $user, $password, {
            RaiseError => 1,
            AutoCommit => 1,
        });
        print "✅ Connected to database directly: $database on $host:$port\n";
    };
    if ($@) {
        print "❌ ERROR connecting to database: $@\n";
        exit 1;
    }
}

print "Languages to install: " . join(', ', @want_langs) . "\n\n";

# Each template: module/code/transport + content hash keyed by Koha letter.lang
my %templates = (
    'HOLD_SMS' => {
        module => 'reserves',
        code => 'HOLD',
        transport => 'sms',
        content => {
        'default' => q{
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
hold: [% hold.reserve_id %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF holds.size > 1 %][% holds.size %] items ready: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %]One item ready: [% biblio.title %][% END %]. Pickup by [% holds.0.expirationdate || hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF holds && holds.size > 1 %]You have [% holds.size %] holds ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %]; [% END %][% END %]. Pickup by [% holds.0.expirationdate | $KohaDates %][% ELSE %]Hold ready: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %][% END %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. You have [% IF holds && holds.size > 1 %][% holds.size %] holds ready for pickup: [% FOREACH h IN holds %][% h.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. Pickup by [% holds.0.expirationdate | $KohaDates %][% ELSE %]a hold ready for pickup: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %][% END %]. Call [% branch.branchphone %]."
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
        'default' => q{
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF checkouts.size > 1 %]You checked out [% checkouts.size %] items: [% FOREACH c IN checkouts %][% c.item.biblio.title %][% UNLESS loop.last %], [% END %][% END %]. All due [% checkouts.0.date_due | $KohaDates %][% ELSE %]You checked out [% biblio.title %] due [% checkout.date_due | $KohaDates %][% END %]. Thank you!"
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
        'default' => q{
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. The following item was checked in: [% IF checkins.size > 1 %][% FOREACH c IN checkins %][% c.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Thank you!"
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
        'default' => q{
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. You have an overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Second notice - Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. This is your second notice. You have an overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Final notice - Overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately to avoid additional charges. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. This is your final notice. You have an overdue item: [% biblio.title %]. Due [% issue.date_due | $KohaDates %]. Please return or renew immediately to avoid additional charges. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder - [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder - [% biblio.title %] is due [% issue.date_due | $KohaDates %]. Please return or renew. Call [% branch.branchphone %]."
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
        'default' => q{
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your hold status has changed for [% biblio.title %]. Please check your account for details. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Reminder - You have a hold ready for pickup: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Reminder - You have a hold ready for pickup: [% biblio.title %]. Pickup by [% hold.expirationdate | $KohaDates %]. Call [% branch.branchphone %]."
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
        'default' => q{
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Hold placed on [% biblio.title %]. You will be notified when ready for pickup. Call [% branch.branchphone %]."
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
        'default' => q{
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Hold confirmed for [% biblio.title %]. You will be notified when ready for pickup. Call [% branch.branchphone %]."
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
        'default' => q{
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
        'default' => q{
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] has been renewed. New due date: [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
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
        'default' => q{
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% biblio.title %] has been auto-renewed. New due date: [% issue.date_due | $KohaDates %]. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: [% IF auto_renewals.size > 1 %][% auto_renewals.size %] items auto-renewed: [% FOREACH renewal IN auto_renewals %][% renewal.biblio.title %][% UNLESS loop.last %]; [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. [% IF auto_renewals.size > 1 %][% auto_renewals.size %] items have been auto-renewed: [% FOREACH renewal IN auto_renewals %][% renewal.biblio.title %][% UNLESS loop.last %], [% END %][% END %][% ELSE %][% biblio.title %][% END %]. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Your library membership expires [% borrower.dateexpiry | $KohaDates %]. Please renew to continue using library services. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your library membership expires [% borrower.dateexpiry | $KohaDates %]. Please renew to continue using library services. Call [% branch.branchphone %]."
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
sms:
  text: "[% branch.branchcode %]: Your library membership has been renewed. New expiry date: [% borrower.dateexpiry | $KohaDates %]. Thank you!"
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Your library membership has been renewed. New expiry date: [% borrower.dateexpiry | $KohaDates %]. Thank you!"
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
        'default' => q{
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
        'default' => q{
---
CirriusImpact: yes
patron: [% borrowernumber %]
call:
  script: "Hello [% borrower.firstname %]. [% branch.branchname %]. Welcome to the library! Your membership is now active. We look forward to serving you. Call [% branch.branchphone %]."
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

sub install_template {
    my ($name, $template, $lang) = @_;
    my $content = $template->{content}{$lang};
    unless (defined $content && $content =~ /\S/) {
        print "Skipping $name ($lang) — no content\n";
        return 0;
    }

    print "Installing $name [$lang]... ";

    my $check_sth = $dbh->prepare(q{
        SELECT COUNT(*) FROM letter
        WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
          AND branchcode = ''
    });
    $check_sth->execute($template->{module}, $template->{code}, $template->{transport}, $lang);
    my ($exists) = $check_sth->fetchrow_array;
    $check_sth->finish();

    my $title = "$template->{code} - $template->{transport}";
    my $template_name = $template->{code};

    if ($exists) {
        my $update_sth = $dbh->prepare(q{
            UPDATE letter
            SET content = ?, name = ?, title = ?, branchcode = ''
            WHERE module = ? AND code = ? AND message_transport_type = ? AND lang = ?
              AND branchcode = ''
        });
        $update_sth->execute(
            $content, $template_name, $title,
            $template->{module}, $template->{code}, $template->{transport}, $lang
        );
        $update_sth->finish();
        print "updated.\n";
    } else {
        my $insert_sth = $dbh->prepare(q{
            INSERT INTO letter (module, code, message_transport_type, content, title, name, branchcode, lang)
            VALUES (?, ?, ?, ?, ?, ?, '', ?)
        });
        $insert_sth->execute(
            $template->{module}, $template->{code}, $template->{transport},
            $content, $title, $template_name, $lang
        );
        $insert_sth->finish();
        print "installed.\n";
    }
    return 1;
}

print "Installing message templates...\n\n";
my $count = 0;
for my $lang (@want_langs) {
    print "---- Language: $lang ----\n";
    for my $name (sort keys %templates) {
        $count += install_template($name, $templates{$name}, $lang);
    }
    print "\n";
}

print "=" x 50, "\n";
print "Installation complete!\n";
print "Installed/Updated $count template rows across languages: @want_langs\n\n";
print "Notes:\n";
print "- Enable TranslateNotices and add es-ES / fr-CA under OPACLanguages for tabs to appear.\n";
print "- SMS text is GSM-7-safe (ASCII) so segments stay ~160 chars; accents would drop to ~70.\n";
print "- Koha picks letter.lang from the patron language; CirriusImpact CSV language maps to eng/spa/fre.\n\n";

unless ($no_restart) {
    print "Would you like to restart Koha services now? (y/n): ";
    my $restart_choice = <STDIN>;
    chomp($restart_choice) if defined $restart_choice;
    if (defined $restart_choice && $restart_choice =~ /^[yY]/) {
        print "\n🔄 Restarting Koha services...\n";
        system("sudo systemctl restart koha-common");
        print($? == 0 ? "✅ Restarted.\n" : "❌ Restart failed; restart manually.\n");
    } else {
        print "\nSkip restart. Later: sudo systemctl restart koha-common\n";
    }
} else {
    print "Skipping restart (--no-restart).\n";
}

print "\nDone.\n";
