#!/usr/bin/perl

use strict;
use warnings;
use DBI;
use Getopt::Long;

# CirriusImpact Message Template Installer (multilingual)
#
# Install modes (pick one or combine):
#   --defaults
#       Update system-default letters (letter.branchcode = '').
#       Backward-compatible default when no install mode is given.
#
#   --ci-templates
#       Create/update CODE-CI letters (CHECKOUT-CI, HOLD-CI, ...).
#       Leaves stock CODE defaults alone. Point member messaging /
#       overdue rules at the -CI codes for CI members only.
#
#   --consortia-branch=CODE
#       Create/update CI content for that Koha branchcode (same letter CODE,
#       branch-specific letter row). Repeatable / comma-separated.
#       Example: --consortia-branch=CPL,UPL
#       Creates letter rows like CHECKOUT with branchcode=CPL and UPL —
#       NOT letter codes named CHECKOUT-CPL or CHECKOUT-KDEMO_CPL.
#       Recommended for consortia: leave defaults alone; CI members
#       get branch-scoped templates Koha already prefers by library.
#
#   --consortia-from-plugin
#       Same as --consortia-branch for every Koha branch listed in the
#       plugin Configure → Branch services (enabled_branches derived from the
#       SMS/CIXL/Outbound matrix). Those values are
#       Koha branchcodes (CPL, UPL, FFL…), not CirriusImpact library IDs
#       (KDEMO_CPL / KDEMO_UPL).
#
# Recommendation:
#   Single library:           --defaults
#   Consortia (usual):        --consortia-branch=CPL --consortia-branch=UPL
#                             or --consortia-from-plugin
#   Alternate letter codes:   --ci-templates  (then assign *-CI in Koha)
#
# Other options:
#   --default-language=en|es-ES|fr-CA|eng|spa|fre
#   --services=sms,phone   (alias: --transports)
#   --languages=default,en,es-ES,fr-CA
#   --no-restart
#
# Examples:
#   perl install_message_templates.pl --defaults
#   perl install_message_templates.pl --ci-templates --services=sms
#   perl install_message_templates.pl --consortia-branch=CPL,UPL
#   perl install_message_templates.pl --consortia-from-plugin --no-restart

print "CirriusImpact Message Template Installer (multilingual)\n";
print "========================================================\n\n";

my @want_langs = ('default', 'en', 'es-ES', 'fr-CA');
my @want_services = ('sms', 'phone');  # Koha message_transport_type
my $no_restart = 0;
my $default_language_opt = 'en';
my $services_opt;
my $do_defaults = 0;
my $do_ci_templates = 0;
my $do_from_plugin = 0;
my @consortia_branch_opts;

GetOptions(
    'languages=s'              => \my $lang_opt,
    'default-language=s'       => \$default_language_opt,
    'services=s'               => \$services_opt,
    'transports=s'             => \$services_opt,  # alias
    'defaults!'                => \$do_defaults,
    'ci-templates!'            => \$do_ci_templates,
    'consortia-branch=s'       => \@consortia_branch_opts,
    'consortia-from-plugin!'   => \$do_from_plugin,
    'no-restart'               => \$no_restart,
) or die usage_die();

sub usage_die {
    return <<"EOF";
Usage: $0 [install mode...] [options]

Install modes:
  --defaults                 System-default letters (branchcode='')
  --ci-templates             CODE-CI letters; leave stock CODE alone
  --consortia-branch=CODE    Branch-scoped letters (repeatable / CSV)
  --consortia-from-plugin    Branches from plugin enabled_branches

If no install mode is given, --defaults is assumed.

Options:
  --default-language=en|es-ES|fr-CA|eng|spa|fre
  --services=sms,phone
  --languages=default,en,es-ES,fr-CA
  --no-restart
EOF
}

# Map checklist / IETF aliases to content keys (en, es-ES, fr-CA)
my %default_lang_aliases = (
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
my $default_content_key = $default_lang_aliases{$default_language_opt};
unless (defined $default_content_key) {
    die "Unknown --default-language='$default_language_opt' (use en|es-ES|fr-CA or eng|spa|fre)\n";
}

if (defined $lang_opt && $lang_opt =~ /\S/) {
    @want_langs = map { s/^\s+|\s+$//gr } split /,/, $lang_opt;
}

# --services / --transports: sms and/or phone (voice -> phone)
my %service_aliases = (
    sms   => 'sms',
    text  => 'sms',
    phone => 'phone',
    voice => 'phone',
    call  => 'phone',
    email => 'email',
);
if (defined $services_opt && $services_opt =~ /\S/) {
    my @raw = map { lc(s/^\s+|\s+$//gr) } split /,/, $services_opt;
    my @resolved;
    my %seen;
    for my $s (@raw) {
        my $t = $service_aliases{$s};
        die "Unknown --services entry '$s' (use sms, phone, and/or email)\n"
            unless defined $t;
        next if $seen{$t}++;
        push @resolved, $t;
    }
    die "--services must include at least one of: sms, phone, email\n" unless @resolved;
    @want_services = @resolved;
}

# Expand consortia branch args (repeatable + comma-separated)
my @consortia_branches;
for my $raw (@consortia_branch_opts) {
    for my $b (split /,/, $raw) {
        $b =~ s/^\s+|\s+$//g;
        next unless length $b;
        push @consortia_branches, $b;
    }
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

sub plugin_enabled_branches {
    my ($dbh) = @_;
    my @codes;

    # Preferred: plugin retrieve_data (values are encrypted at rest).
    if ($koha_available) {
        eval {
            require Koha::Plugin::Com::CirriusImpact;
            my $plugin = Koha::Plugin::Com::CirriusImpact->new;
            my $raw = $plugin->retrieve_data('enabled_branches');
            if (defined $raw) {
                $raw =~ s/^\s+|\s+$//g;
                if ($raw ne '' && $raw ne '*') {
                    for my $b (split /,/, $raw) {
                        $b =~ s/^\s+|\s+$//g;
                        push @codes, $b if length $b;
                    }
                }
            }
        };
        if ($@) {
            print "⚠️  Could not read enabled_branches via plugin API: $@\n";
        } else {
            return @codes;
        }
    }

    # Fallback: raw plugin_data (only works if value is plaintext — usually is not).
    my $sth = $dbh->prepare(q{
        SELECT plugin_value FROM plugin_data
        WHERE plugin_key = 'enabled_branches'
          AND plugin_class LIKE '%CirriusImpact%'
        ORDER BY plugin_class
        LIMIT 1
    });
    eval { $sth->execute(); };
    if ($@) {
        print "⚠️  Could not read plugin_data.enabled_branches: $@\n";
        return @codes;
    }
    my ($raw) = $sth->fetchrow_array;
    $sth->finish();
    return @codes unless defined $raw;
    $raw =~ s/^\s+|\s+$//g;
    # Encrypted blobs start like Salted__ / hex — ignore those here.
    if ($raw =~ /^53616c7465645f5f/ || $raw =~ /^Salted__/ || $raw =~ /[^A-Za-z0-9_,\-\s\*]/) {
        print "⚠️  enabled_branches looks encrypted; run installer with Koha modules so --consortia-from-plugin can decrypt it.\n";
        return @codes;
    }
    return @codes if $raw eq '' || $raw eq '*';
    for my $b (split /,/, $raw) {
        $b =~ s/^\s+|\s+$//g;
        push @codes, $b if length $b;
    }
    return @codes;
}

if ($do_from_plugin) {
    my @from_plugin = plugin_enabled_branches($dbh);
    if (@from_plugin) {
        print "Plugin enabled_branches: " . join(', ', @from_plugin) . "\n";
        push @consortia_branches, @from_plugin;
    } else {
        print "⚠️  --consortia-from-plugin: no concrete branches in enabled_branches (unset/*/empty).\n";
    }
}

# Dedupe branches (preserve order)
{
    my %seen;
    @consortia_branches = grep { !$seen{$_}++ } @consortia_branches;
}

# Backward compatible: no mode flags => --defaults
unless ($do_defaults || $do_ci_templates || @consortia_branches) {
    $do_defaults = 1;
    print "No install mode given; assuming --defaults\n";
}

print "Default letter.lang content: $default_content_key (--default-language=$default_language_opt)\n";
print "Services to install: " . join(', ', @want_services) . "\n";
print "Languages to install: " . join(', ', @want_langs) . "\n";
print "Modes:";
print " --defaults" if $do_defaults;
print " --ci-templates" if $do_ci_templates;
print " --consortia-branch=" . join(',', @consortia_branches) if @consortia_branches;
print "\n\n";

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

sub content_for_lang {
    my ($template, $lang) = @_;
    # Koha Default tab uses letter.lang=default; fill from --default-language.
    my $key = ($lang eq 'default') ? $default_content_key : $lang;
    return $template->{content}{$key};
}

# Install one letter row.
# $code_override: undef = template code; 'CI' suffix mode uses CODE-CI
# $branchcode: '' for defaults, or library branchcode for consortia rows
sub install_template {
    my ($name, $template, $lang, $code_override, $branchcode) = @_;
    $branchcode = '' unless defined $branchcode;
    my $content = content_for_lang($template, $lang);
    unless (defined $content && $content =~ /\S/) {
        print "Skipping $name ($lang) — no content\n";
        return 0;
    }

    my $code = defined $code_override ? $code_override : $template->{code};
    my $src = ($lang eq 'default') ? "default<-$default_content_key" : $lang;
    my $branch_label = length($branchcode) ? "branch=$branchcode" : "branch=DEFAULT";
    print "Installing $name code=$code [$src] ($branch_label)... ";

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
        print "updated.\n";
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
        print "installed.\n";
    }
    return 1;
}

print "Installing message templates...\n\n";
my %want_service = map { $_ => 1 } @want_services;
my $count = 0;

# Build install targets: list of [code_override_or_undef, branchcode]
my @targets;
if ($do_defaults) {
    push @targets, [undef, ''];
}
if ($do_ci_templates) {
    # CODE-CI at system default branchcode
    push @targets, ['__CI__', ''];
}
for my $b (@consortia_branches) {
    push @targets, [undef, $b];
}

for my $lang (@want_langs) {
    print "---- Language: $lang ----\n";
    for my $name (sort keys %templates) {
        my $tpl = $templates{$name};
        unless ($want_service{ $tpl->{transport} }) {
            next;
        }
        for my $t (@targets) {
            my ($code_mode, $branch) = @$t;
            my $code_override;
            if (defined $code_mode && $code_mode eq '__CI__') {
                $code_override = $tpl->{code} . '-CI';
            }
            $count += install_template($name, $tpl, $lang, $code_override, $branch);
        }
    }
    print "\n";
}

print "=" x 50, "\n";
print "Installation complete!\n";
print "Installed/Updated $count template rows\n";
print "  services:  @want_services\n";
print "  languages: @want_langs\n";
print "  defaults:  ", ($do_defaults ? 'yes' : 'no'), "\n";
print "  ci-templates (-CI codes): ", ($do_ci_templates ? 'yes' : 'no'), "\n";
print "  consortia branches: ", (@consortia_branches ? join(', ', @consortia_branches) : '(none)'), "\n\n";
print "Notes:\n";
print "- letter.lang=default content came from $default_content_key.\n";
print "- --defaults overwrites stock CODE letters (branchcode='').\n";
print "- --ci-templates creates CODE-CI and does not touch stock CODE.\n";
print "- --consortia-branch installs CI content for that library only; stock defaults stay intact.\n";
print "- Enable TranslateNotices; add en / es-ES / fr-CA under OPACLanguages for language tabs.\n";
print "- SMS text is GSM-7-safe (ASCII) so segments stay ~160 chars; accents would drop to ~70.\n\n";

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
