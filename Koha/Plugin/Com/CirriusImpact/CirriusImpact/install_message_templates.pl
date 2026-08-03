#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Long;
use File::Basename qw(dirname);
use Cwd qw(abs_path);

# Prefer plugin @INC layout: .../plugins/Koha/Plugin/Com/CirriusImpact/InstallMessageTemplates.pm
BEGIN {
    my $here = abs_path(__FILE__);
    # plugins/Koha/Plugin/Com/CirriusImpact/CirriusImpact/install_message_templates.pl
    my $dir = dirname($here);
    for (1..6) { $dir = dirname($dir); }
    unshift @INC, $dir unless grep { $_ eq $dir } @INC;
}

use Koha::Plugin::Com::CirriusImpact::InstallMessageTemplates;

print "CirriusImpact Message Template Installer (multilingual)\n";
print "========================================================\n\n";

my $no_restart = 0;
my $default_language_opt = 'en';
my $services_opt;
my $do_defaults = 0;
my $do_ci_templates = 0;
my $do_from_plugin = 0;
my @consortia_branch_opts;
my $lang_opt;

GetOptions(
    'languages=s'              => \$lang_opt,
    'default-language=s'       => \$default_language_opt,
    'services=s'               => \$services_opt,
    'transports=s'             => \$services_opt,
    'defaults!'                => \$do_defaults,
    'ci-templates!'            => \$do_ci_templates,
    'consortia-branch=s'       => \@consortia_branch_opts,
    'consortia-from-plugin!'   => \$do_from_plugin,
    'no-restart'               => \$no_restart,
) or die <<"EOF";
Usage: $0 [install mode...] [options]
  --defaults / --ci-templates / --consortia-branch=CODE / --consortia-from-plugin
  --services=sms,phone --default-language=en --languages=default,en,es-ES,fr-CA --no-restart
EOF

my @branches;
for my $raw (@consortia_branch_opts) {
    push @branches, split /,/, $raw;
}

my $plugin;
if ($do_from_plugin) {
    eval {
        require C4::Context;
        require Koha::Plugin::Com::CirriusImpact;
        $plugin = Koha::Plugin::Com::CirriusImpact->new;
        1;
    } or do {
        warn "Could not load plugin for --consortia-from-plugin: $@\n";
    };
}

my $result = Koha::Plugin::Com::CirriusImpact::InstallMessageTemplates::run(
    defaults             => $do_defaults,
    ci_templates         => $do_ci_templates,
    consortia_branches   => \@branches,
    consortia_from_plugin => $do_from_plugin,
    services             => $services_opt,
    languages            => $lang_opt,
    default_language     => $default_language_opt,
    plugin               => $plugin,
);

print $result->{log} // '';
if ( $result->{error} ) {
    print "ERROR: $result->{error}\n";
    exit 1;
}
unless ( $result->{ok} ) {
    print "ERROR: install failed\n";
    exit 1;
}

unless ($no_restart) {
    print "Would you like to restart Koha services now? (y/n): ";
    my $restart_choice = <STDIN>;
    chomp($restart_choice) if defined $restart_choice;
    if (defined $restart_choice && $restart_choice =~ /^[yY]/) {
        print "\nRestarting Koha services...\n";
        system("sudo systemctl restart koha-common");
        print($? == 0 ? "Restarted.\n" : "Restart failed; restart manually.\n");
    } else {
        print "\nSkip restart. Later: sudo systemctl restart koha-common\n";
    }
} else {
    print "Skipping restart (--no-restart).\n";
}

print "\nDone.\n";
exit 0;
