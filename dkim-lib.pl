# Functions for setting up DKIM signing

$debian_dkim_config = "/etc/dkim-filter.conf";
$debian_dkim_default = "/etc/default/dkim-filter";

$redhat_dkim_config = "/etc/mail/dkim-milter/dkim-filter.conf";
$redhat_dkim_default = "/etc/sysconfig/dkim-milter";

$ubuntu_dkim_config = "/etc/opendkim.conf";
$ubuntu_dkim_default = "/etc/default/opendkim";

# get_dkim_type()
# Returns either 'ubuntu', 'debian', 'redhat' or undef
sub get_dkim_type
{
if ($gconfig{'os_type'} eq 'debian-linux' && $gconfig{'os_version'} >= 7) {
	# Debian 7+ uses OpenDKIM
	return 'ubuntu';
	}
elsif ($gconfig{'os_type'} eq 'debian-linux' && $gconfig{'os_version'} >= 6 &&
       !-x "/usr/sbin/dkim-filter") {
	# Debian 6 can use OpenDKIM, unless it is already using dkim-filter
	return 'ubuntu';
	}
elsif ($gconfig{'os_type'} eq 'debian-linux') {
	# Older Debian versions only have dkim-filter
	return 'debian';
	}
elsif ($gconfig{'os_type'} eq 'redhat-linux') {
	return 'redhat';
	}
return undef;
}

# get_dkim_config_file()
# Returns the path to the DKIM config file
sub get_dkim_config_file
{
return &get_dkim_type() eq 'ubuntu' ? $ubuntu_dkim_config :
       &get_dkim_type() eq 'debian' ? $debian_dkim_config :
       &get_dkim_type() eq 'redhat' ? $redhat_dkim_config :
				      undef;
}

# get_dkim_defaults_file()
# Returns the path to the DKIM defaults file
sub get_dkim_defaults_file
{
return &get_dkim_type() eq 'ubuntu' ? $ubuntu_dkim_default :
       &get_dkim_type() eq 'debian' ? $debian_dkim_default :
       &get_dkim_type() eq 'redhat' ? $redhat_dkim_default :
				      undef;
}

# get_dkim_init_name()
# Returns the name of the DKIM init script
sub get_dkim_init_name
{
return &get_dkim_type() eq 'ubuntu' ? 'opendkim' :
       &get_dkim_type() eq 'debian' ? 'dkim-filter' :
       &get_dkim_type() eq 'redhat' ? 'dkim-milter' : undef;
}

# check_dkim()
# Returns undef if all the needed commands for DKIM are installed, or an error
# message if not.
sub check_dkim
{
&foreign_require("init");
if (!&get_dkim_type()) {
	# Not supported on this OS
	return $text{'dkim_eos'};
	}
my $config_file = &get_dkim_config_file();
return &text('dkim_econfig', "<tt>$config_file</tt>")
	if (!-r $config_file);
my $init = &get_dkim_init_name();
return &text('dkim_einit', "<tt>$init</tt>")
	if (!&init::action_status($init));

# Check mail server
&require_mail();
if ($config{'mail_system'} > 1) {
	return $text{'dkim_emailsystem'};
	}
elsif ($config{'mail_system'} == 1) {
	-r $sendmail::config{'sendmail_mc'} ||
		return $text{'dkim_esendmailmc'};
	}
return undef;
}

# can_install_dkim()
# Returns 1 if DKIM package installation is supported on this OS
sub can_install_dkim
{
if ($gconfig{'os_type'} eq 'debian-linux' ||
    $gconfig{'os_type'} eq 'redhat-linux') {
	&foreign_require("software", "software-lib.pl");
	return defined(&software::update_system_install);
	}
return 0;
}

# install_dkim_package()
# Attempt to install DKIM filter, outputting progress messages
sub install_dkim_package
{
&foreign_require("software", "software-lib.pl");
my $pkg = &get_dkim_type() eq 'ubuntu' ? 'opendkim' :
	  &get_dkim_type() eq 'debian' ? 'dkim-filter' :
	  &get_dkim_type() eq 'redhat' ? 'dkim-milter' : 'dkim';
my @inst = &software::update_system_install($pkg);
return scalar(@inst) || !&check_dkim();
}

# get_dkim_config()
# Returns a hash containing details of the DKIM configuration and status.
# Keys are :
# enabled - Set to 1 if postfix is setup to use DKIM
# selector - Record within the domain for the key
# extra - Additional domains to enable for
# exclude - Domains for forcibly disable for
# keyfile - Private key file
sub get_dkim_config
{
&foreign_require("init");
my %rv;

# Check if filter is running
my $dkim_config = &get_dkim_config_file();
my $dkim_defaults = &get_dkim_defaults_file();
my $init = &get_dkim_init_name();
if (&get_dkim_type() eq 'debian' || &get_dkim_type() eq 'ubuntu') {
	# Read Debian dkim config file
	my $conf = &get_debian_dkim_config($dkim_config);
	$rv{'enabled'} = &init::action_status($init) == 2;
	$rv{'selector'} = $conf->{'Selector'};
	$rv{'keyfile'} = $conf->{'KeyFile'};

	# Read defaults file that specifies port
	my %def;
	&read_env_file($dkim_defaults, \%def);
	if ($def{'SOCKET'} =~ /^inet:(\d+)/) {
		$rv{'port'} = $1;
		}
	elsif ($def{'SOCKET'} =~ /^local:([^:]+)/) {
		$rv{'socket'} = $1;
		}
	else {
		$rv{'enabled'} = 0;
		}

	# Parse defaults option to get sign/verify mode
	if ($def{'DAEMON_OPTS'} =~ /-b\s*(\S+)/) {
		my $mode = $1;
		$rv{'sign'} = $mode =~ /s/ ? 1 : 0;
		$rv{'verify'} = $mode =~ /v/ ? 1 : 0;
		}
	else {
		$rv{'sign'} = 1;
		$rv{'verify'} = 1;
		}
	}
elsif (&get_dkim_type() eq 'redhat') {
	# Read Fedora dkim config file
	my $conf = &get_debian_dkim_config($dkim_config);
	$rv{'enabled'} = &init::action_status($init) == 2;
	$rv{'selector'} = $conf->{'Selector'};
	$rv{'keyfile'} = $conf->{'KeyFile'};

	# Read defaults file that specifies port
	my %def;
	&read_env_file($dkim_defaults, \%def);
	if ($def{'SOCKET'} =~ /^inet:(\d+)/) {
		$rv{'port'} = $1;
		}
	elsif ($def{'SOCKET'} =~ /^local:([^:]+)/) {
		$rv{'socket'} = $1;
		}
	else {
		# Assume default socket
		$rv{'socket'} = "/var/run/dkim-milter/dkim-milter.sock";
		}

	# Parse defaults option to get sign/verify mode
	if ($def{'EXTRA_FLAGS'} =~ /-b\s*(\S+)/) {
		my $mode = $1;
		$rv{'sign'} = $mode =~ /s/ ? 1 : 0;
		$rv{'verify'} = $mode =~ /v/ ? 1 : 0;
		}
	else {
		$rv{'sign'} = 1;
		$rv{'verify'} = 1;
		}
	}

# Check mail server
&require_mail();
if ($config{'mail_system'} == 0) {
	# Postfix config
	my $wantmilter = $rv{'port'} ? "inet:localhost:$rv{'port'}" :
			 $rv{'socket'} ? "local:$rv{'socket'}" : "";
	my $milters = &postfix::get_real_value("smtpd_milters");
	if ($wantmilter && $milters !~ /\Q$wantmilter\E/) {
		$rv{'enabled'} = 0;
		}
	}
elsif ($config{'mail_system'} == 1) {
	# Sendmail config
	my $wantmilter = $rv{'port'} ? "inet:$rv{'port'}\@localhost" :
			 $rv{'socket'} ? "local:$rv{'socket'}" : "";
	my @feats = &sendmail::list_features();
	my ($milter) = grep { $_->{'text'} =~ /INPUT_MAIL_FILTER/ &&
			      $_->{'text'} =~ /\Q$wantmilter\E/ } @feats;
	if (!$milter) {
		$rv{'enabled'} = 0;
                }
	}

# Add extra domains
$rv{'extra'} = [ split(/\s+/, $config{'dkim_extra'}) ];
$rv{'exclude'} = [ split(/\s+/, $config{'dkim_exclude'}) ];

# Work out key size
if ($rv{'keyfile'} && -r $rv{'keyfile'}) {
	$rv{'size'} = &get_key_size($rv{'keyfile'});
	}

return \%rv;
}

# get_debian_dkim_config(file)
# Returns the config file as seen on Debian into as hash ref
sub get_debian_dkim_config
{
my ($file) = @_;
my %conf;
open(DKIM, $file) || return undef;
while(my $l = <DKIM>) {
	$l =~ s/#.*$//;
	if ($l =~ /^\s*(\S+)\s+(\S.*)/) {
		$conf{$1} = $2;
		}
	}
close(DKIM);
return \%conf;
}

# save_debian_dkim_config(file, directive, value)
# Update a value in the Debian-style config file
sub save_debian_dkim_config
{
my ($file, $name, $value) = @_;
my $lref = &read_file_lines($file);
if (defined($value)) {
	# Change value
	my $found = 0;
	foreach my $l (@$lref) {
		if ($l =~ /^\s*(\S+)\s*/ && $1 eq $name) {
			$l = $name." ".$value;
			$found = 1;
			last;
			}
		}

	# Change commented value
	if (!$found) {
		foreach my $l (@$lref) {
			if ($l =~ /^\s*#+\s*(\S+)\s*/ && $1 eq $name) {
				$l = $name." ".$value;
				$found = 1;
				last;
				}
			}
		}

	# Add to end
	if (!$found) {
		push(@$lref, "$name $value");
		}
	}
else {
	# Comment out if set
	foreach my $l (@$lref) {
		if ($l =~ /^\s*(\S+)\s*/ && $1 eq $name) {
			$l = "# ".$l;
			}
		}
	}
&flush_file_lines($file);
}

# enable_dkim(&dkim, [force-new-key], [key-size])
# Perform all the steps needed to enable DKIM
sub enable_dkim
{
my ($dkim, $newkey, $size) = @_;
&foreign_require("webmin");
&foreign_require("init");

# Find domains that we can enable DKIM for (those with mail and DNS)
&$first_print($text{'dkim_domains'});
my @doms = grep { $_->{'dns'} && $_->{'mail'} } &list_domains();
@doms = grep { &indexof($_->{'dom'}, @{$dkim->{'exclude'}}) < 0 } @doms;
if (@doms) {
	&$second_print(&text('dkim_founddomains', scalar(@doms)));
	}
elsif (@{$dkim->{'extra'}}) {
	&$second_print(&text('dkim_founddomains2',
			     scalar(@{$dkim->{'extra'}})));
	}
else {
	&$second_print($text{'dkim_nodomains'});
	return 0;
	}

# Generate private key
if (!$dkim->{'keyfile'} || !-r $dkim->{'keyfile'} || $newkey) {
	$size ||= 2048;
	$dkim->{'keyfile'} ||= "/etc/dkim.key";
	&$first_print(&text('dkim_newkey', "<tt>$dkim->{'keyfile'}</tt>"));
	&lock_file($dkim->{'keyfile'});
	my $out = &backquote_logged("openssl genrsa -out ".
		quotemeta($dkim->{'keyfile'})." $size 2>&1 </dev/null");
	if ($?) {
		&$second_print(&text('dkim_enewkey',
				"<tt>".&html_escape($out)."</tt>"));
		return 0;
		}
	&unlock_file($dkim->{'keyfile'});
	&$second_print($text{'setup_done'});
	}

# Make sure key has the right permissions
if (&get_dkim_type() eq 'ubuntu') {
	&set_ownership_permissions("opendkim", undef, 0700,
				   $dkim->{'keyfile'});
	}
elsif (&get_dkim_type() eq 'debian') {
	&set_ownership_permissions("dkim-filter", undef, 0700,
				   $dkim->{'keyfile'});
	}
elsif (&get_dkim_type() eq 'redhat') {
	&set_ownership_permissions("dkim-milter", undef, 0700,
				   $dkim->{'keyfile'});
	}

# Get the public key
&$first_print(&text('dkim_pubkey', "<tt>$dkim->{'keyfile'}</tt>"));
my $pubkey = &get_dkim_pubkey($dkim);
if (!$pubkey) {
	&$second_print($text{'dkim_epubkey'});
	return 0;
	}
&$second_print($text{'setup_done'});

# Add domain, key and selector to config file
&$first_print($text{'dkim_config'});
my $dkim_config = &get_dkim_config_file();
if ($dkim_config) {
	# Save domains and key file in config
	&lock_file($dkim_config);
	&save_debian_dkim_config($dkim_config, 
		"Selector", $dkim->{'selector'});
	&save_debian_dkim_config($dkim_config, 
		"KeyFile", $dkim->{'keyfile'});
	&save_debian_dkim_config($dkim_config,
                "Syslog", "yes");

	my $conf = &get_debian_dkim_config($dkim_config);
	if (&get_dkim_type() eq 'ubuntu') {
		# OpenDKIM version supplied with Ubuntu and Debian 6 supports
		# a domains file
		my $domfile = $conf->{'Domain'};
		if ($domfile !~ /^\//) {
			$domfile = $dkim_config;
			$domfile =~ s/\/[^\/]+$/\/dkim-domains.txt/;
			}
		&open_lock_tempfile(DOMAINS, ">$domfile");
		foreach my $dom ((map { $_->{'dom'} } @doms),
				 @{$dkim->{'extra'}}) {
			&print_tempfile(DOMAINS, "$dom\n");
			}
		&close_tempfile(DOMAINS);
		&save_debian_dkim_config($dkim_config,
					 "Domain", $domfile);
		}
	else {
		# Work out mapping file
		&save_debian_dkim_config($dkim_config, 
			"Domain", undef);
		my $keylist = $conf->{'KeyList'};
		if (!$keylist) {
			$keylist = $dkim_config;
			$keylist =~ s/\/([^\/]+)$/\/keylist/;
			&save_debian_dkim_config($dkim_config,
				"KeyList", $keylist);
			}

		# Link key to same directory as mapping file, with selector
		# as filename
		my $selkeyfile = $keylist;
		$selkeyfile =~ s/\/([^\/]+)$/\/$dkim->{'selector'}/;
		if (-e $selkeyfile && !-l $selkeyfile) {
			&$second_print("<b>".&text('dkim_eselfile',
					   "<tt>$selkeyfile</tt>")."</b>");
			return 0;
			}
		&unlink_file($selkeyfile);
		&symlink_file($dkim->{'keyfile'}, $selkeyfile);

		# Create key mapping file
		&create_key_mapping_file(\@doms, $keylist, $selkeyfile,
					 $dkim->{'extra'});
		}
	&unlock_file($dkim_config);

	# Save list of extra domains
	$config{'dkim_extra'} = join(" ", @{$dkim->{'extra'}});
	$config{'dkim_exclude'} = join(" ", @{$dkim->{'exclude'}});
	&save_module_config();
	}

my $dkim_defaults = &get_dkim_defaults_file();
if (&get_dkim_type() eq 'debian' || &get_dkim_type() eq 'ubuntu') {
	# Set milter port to listen on
	&lock_file($dkim_defaults);
	my %def;
	&read_env_file($dkim_defaults, \%def);
	if (!$def{'SOCKET'} ||
	    $def{'SOCKET'} =~ /^local:/ && $config{'mail_system'} == 0) {
		# Set socket in defaults file if missing, or if a local file
		# and Postfix is in use
		$def{'SOCKET'} = "inet:8891\@localhost";
		$dkim->{'port'} = 8891;
		}

	# Save sign/verify mode flags
	my $flags = $def{'DAEMON_OPTS'};
	my $mode = ($dkim->{'sign'} ? "s" : "").
		   ($dkim->{'verify'} ? "v" : "");
	($flags =~ s/-b\s*(\S+)/-b $mode/) ||
		($flags .= ($flags ? " " : "")."-b $mode");
	$def{'DAEMON_OPTS'} = $flags;

	&write_env_file($dkim_defaults, \%def);
	&unlock_file($dkim_defaults);
	}
elsif (&get_dkim_type() eq 'redhat') {
	# Set milter port to listen on
	&lock_file($dkim_defaults);
	my %def;
	&read_env_file($dkim_defaults, \%def);
	if ($config{'mail_system'} == 0 && $dkim->{'socket'}) {
		# Force use of tcp socket in defaults file for postfix
		$def{'SOCKET'} = "inet:8891\@localhost";
		$dkim->{'port'} = 8891;
		delete($dkim->{'socket'});
		}

	# Save sign/verify mode flags
	my $flags = $def{'EXTRA_FLAGS'};
	my $mode = ($dkim->{'sign'} ? "s" : "").
		   ($dkim->{'verify'} ? "v" : "");
	($flags =~ s/-b\s*(\S+)/-b $mode/) ||
		($flags .= ($flags ? " " : "")."-b $mode");
	$def{'EXTRA_FLAGS'} = $flags;
	&write_env_file($dkim_defaults, \%def);
	&unlock_file($dkim_defaults);
	}
&$second_print($text{'setup_done'});

# Add public key to DNS domains
&add_dkim_dns_records(\@doms, $dkim);

# Remove from excluded domains
my @exdoms = grep { &indexof($_->{'dom'}, @{$dkim->{'exclude'}}) >= 0 }
		  grep { $_->{'dns'} } &list_domains();
if (@exdoms) {
	&remove_dkim_dns_records(\@exdoms, $dkim);
	}

# Enable filter at boot time
&$first_print($text{'dkim_boot'});
my $init = &get_dkim_init_name();
&init::enable_at_boot($init);
&$second_print($text{'setup_done'});

# Re-start filter now
&$first_print($text{'dkim_start'});
&init::stop_action($init);
my ($ok, $out) = &init::start_action($init);
if (!$ok) {
	&$second_print(&text('dkim_estart',
			"<tt>".&html_escape($out)."</tt>"));
	return 0;
	}
&$second_print($text{'setup_done'});

&$first_print($text{'dkim_mailserver'});
&require_mail();
if ($config{'mail_system'} == 0) {
	# Configure Postfix to use filter
	my $newmilter = $dkim->{'port'} ? "inet:localhost:$dkim->{'port'}"
					: "local:$dkim->{'socket'}";
	&lock_file($postfix::config{'postfix_config_file'});
	&postfix::set_current_value("milter_default_action", "accept");
	&postfix::set_current_value("milter_protocol", 2);
	my $milters = &postfix::get_current_value("smtpd_milters");
	if ($milters !~ /\Q$newmilter\E/) {
		$milters = $milters ? $milters.",".$newmilter : $newmilter;
		&postfix::set_current_value("smtpd_milters", $milters);
		&postfix::set_current_value("non_smtpd_milters", $milters);
		}
	&unlock_file($postfix::config{'postfix_config_file'});

	# Apply Postfix config
	&postfix::reload_postfix();
	}
elsif ($config{'mail_system'} == 1) {
	# Configure Sendmail to use filter
	my $newmilter = $dkim->{'port'} ? "inet:$dkim->{'port'}\@localhost"
					: "local:$dkim->{'socket'}";
	&lock_file($sendmail::config{'sendmail_mc'});
	my $changed = 0;
	my @feats = &sendmail::list_features();

	# Check for filter definition
	my ($milter) = grep { $_->{'text'} =~ /INPUT_MAIL_FILTER/ &&
			      $_->{'text'} =~ /\Q$newmilter\E/ } @feats;
	if (!$milter) {
		# Add to .mc file
		&sendmail::create_feature({
			'type' => 0,
	    		'text' =>
			  "INPUT_MAIL_FILTER(`dkim-filter', `S=$newmilter')" });
		$changed++;
		}

	# Check for config for filters to call
	my ($def) = grep { $_->{'type'} == 2 &&
			   $_->{'name'} eq 'confINPUT_MAIL_FILTERS' } @feats;
	if ($def) {
		my @filters = split(/,/, $def->{'value'});
		if (&indexof("dkim-filter", @filters) < 0) {
			# Add to existing define
			push(@filters, 'dkim-filter');
			$def->{'value'} = join(',', @filters);
			&sendmail::modify_feature($def);
			$changed++;
			}
		}
	else {
		# Add the define
		&sendmail::create_feature({
			'type' => 2,
			'name' => 'confINPUT_MAIL_FILTERS',
			'value' => 'dkim-filter' });
		$changed++;
		}

	if ($changed) {
		&rebuild_sendmail_cf();
		}
	&unlock_file($sendmail::config{'sendmail_mc'});
	if ($changed) {
		&sendmail::restart_sendmail();
		}
	}
&$second_print($text{'setup_done'});

return 1;
}

# get_dkim_pubkey(&dkim)
# Returns the public key in a format suitable for inclusion in a DNS record
sub get_dkim_pubkey
{
my ($dkim) = @_;
my $pubkey = &backquote_command(
        "openssl rsa -in ".quotemeta($dkim->{'keyfile'}).
        " -pubout -outform PEM 2>/dev/null");
if ($? || $pubkey !~ /BEGIN\s+PUBLIC\s+KEY/) {
	return undef;
        }
$pubkey =~ s/\-+(BEGIN|END)\s+PUBLIC\s+KEY\-+//g;
$pubkey =~ s/\s+//g;
return $pubkey;
}

# disable_dkim(&dkim)
# Turn off the DKIM filter and mail server integration
sub disable_dkim
{
my ($dkim) = @_;
&foreign_require("init");

# Remove from DNS
my @doms = grep { $_->{'dns'} && $_->{'mail'} } &list_domains();
&remove_dkim_dns_records(\@doms, $dkim);

&$first_print($text{'dkim_unmailserver'});
&require_mail();
if ($config{'mail_system'} == 0) {
	# Configure Postfix to not use filter
	my $oldmilter = $dkim->{'port'} ? "inet:localhost:$dkim->{'port'}"
					: "local:$dkim->{'socket'}";
	&lock_file($postfix::config{'postfix_config_file'});
	my $milters = &postfix::get_current_value("smtpd_milters");
	if ($milters =~ /\Q$oldmilter\E/) {
		$milters = join(",", grep { $_ ne $oldmilter }
				split(/\s*,\s*/, $milters));
		&postfix::set_current_value("smtpd_milters", $milters);
		&postfix::set_current_value("non_smtpd_milters", $milters);
		}
	&unlock_file($postfix::config{'postfix_config_file'});

	# Apply Postfix config
	&postfix::reload_postfix();
	}
elsif ($config{'mail_system'} == 1) {
	# Configure Sendmail to not use filter
	my $oldmilter = $dkim->{'port'} ? "inet:$dkim->{'port'}\@localhost"
					: "local:$dkim->{'socket'}";
	&lock_file($sendmail::config{'sendmail_mc'});
	my @feats = &sendmail::list_features();
	my $changed = 0;

	# Remove from list of milter to call
	my ($def) = grep { $_->{'type'} == 2 &&
			   $_->{'name'} eq 'confINPUT_MAIL_FILTERS' } @feats;
	if ($def) {
		my @filters = split(/,/, $def->{'value'});
		@filters = grep { $_ ne 'dkim-filter' } @filters;
		if (@filters) {
			# Some still left, so update
			$def->{'value'} = join(',', @filters);
			&sendmail::modify_feature($def);
			}
		else {
			# Delete completely
			&sendmail::delete_feature($def);
			}
		$changed++;
		}

	# Remove milter definition
	my ($milter) = grep { $_->{'text'} =~ /INPUT_MAIL_FILTER/ &&
			      $_->{'text'} =~ /\Q$oldmilter\E/ } @feats;
	if ($milter) {
		&sendmail::delete_feature($milter);
		$changed++;
		}

	if ($changed) {
		&rebuild_sendmail_cf();
		}
	&unlock_file($sendmail::config{'sendmail_mc'});
	if ($changed) {
		&sendmail::restart_sendmail();
		}
	}
&$second_print($text{'setup_done'});

# Stop filter now
&$first_print($text{'dkim_stop'});
my $init = &get_dkim_init_name();
&init::stop_action($init);
&$second_print($text{'setup_done'});

# Disable filter at boot time
&$first_print($text{'dkim_unboot'});
&init::disable_at_boot($init);
&$second_print($text{'setup_done'});

return 1;
}

# update_dkim_domains([&domain, action])
# Updates the list of domains to sign mail for, if needed
sub update_dkim_domains
{
my ($d, $action) = @_;
return if (&check_dkim());
&lock_file(&get_dkim_config_file());
my $dkim = &get_dkim_config();
return if (!$dkim || !$dkim->{'enabled'});

# Enable DKIM for all domains with mail
my @doms = grep { $_->{'mail'} && $_->{'dns'} } &list_domains();
if ($d && ($action eq 'setup' || $action eq 'modify')) {
	push(@doms, $d);
	}
elsif ($d && $action eq 'delete') {
	@doms = grep { $_->{'id'} ne $d->{'id'} } @doms;
	}
my %done;
@doms = grep { !$done{$_->{'id'}}++ } @doms;
@doms = grep { &indexof($_->{'dom'}, @{$dkim->{'exclude'}}) < 0 } @doms;
&set_dkim_domains(\@doms, $dkim);
&unlock_file(&get_dkim_config_file());

# Add or remove DNS records
if ($d->{'dns'}) {
	if ($d && ($action eq 'setup' || $action eq 'modify')) {
		&add_dkim_dns_records([ $d ], $dkim);
		}
	elsif ($d && $action eq 'delete') {
		&remove_dkim_dns_records([ $d ], $dkim);
		}
	else {
		&add_dkim_dns_records(\@doms, $dkim);
		}
	}
}

# create_key_mapping_file(&domains, mapping-file, key-file, &extra-domains)
# Write out a file of all domains to perform DKIM on
sub create_key_mapping_file
{
my ($doms, $keylist, $keyfile, $extra) = @_;
&open_lock_tempfile(KEYLIST, ">$keylist");
foreach my $d (@$doms) {
	&print_tempfile(KEYLIST,
		"*\@".$d->{'dom'}.":".$d->{'dom'}.":".$keyfile."\n");
	}
foreach my $dname (@$extra) {
	&print_tempfile(KEYLIST,
		"*\@".$dname.":".$dname.":".$keyfile."\n");
	}
&close_tempfile(KEYLIST);
&set_ownership_permissions(undef, undef, 0755, $keylist);
}

# set_dkim_domains(&domains, &dkim)
# Configure the DKIM filter to sign mail for the given list of domaisn
sub set_dkim_domains
{
my ($doms, $dkim) = @_;
my $dkim_config = &get_dkim_config_file();
my $init = &get_dkim_init_name();
my $dkim = &get_dkim_config();
if ($dkim_config) {
	my $conf = &get_debian_dkim_config($dkim_config);
	my $keylist = $conf->{'KeyList'};
	if ($keylist) {
		# Update key to domain map
		&save_debian_dkim_config($dkim_config, 
			"Domain", undef);
		my $selector = $conf->{'Selector'};
		my $keylist = $conf->{'KeyList'};
		my $selkeyfile = $keylist;
		$selkeyfile =~ s/\/([^\/]+)$/\/$selector/;
		&create_key_mapping_file($doms, $keylist, $selkeyfile,
					 $dkim->{'extra'});
		}
	else {
		# Just set list of domains
		my $domfile = $conf->{'Domain'};
		if ($domfile !~ /^\//) {
			$domfile = $dkim_config;
			$domfile =~ s/\/[^\/]+$/\/dkim-domains.txt/;
			}
		&open_lock_tempfile(DOMAINS, ">$domfile");
		foreach my $dom ((map { $_->{'dom'} } @$doms),
				 @{$dkim->{'extra'}}) {
			&print_tempfile(DOMAINS, "$dom\n");
			}
		&close_tempfile(DOMAINS);
		&save_debian_dkim_config($dkim_config,
					 "Domain", $domfile);
		}

	# Restart milter
	&foreign_require("init");
	if (&init::action_status($init)) {
		&init::restart_action($init);
		}
	}
}

# add_dkim_dns_records(&domains, &dkim)
# Add DKIM DNS records to the given list of domains
sub add_dkim_dns_records
{
my ($doms, $dkim) = @_;
my $pubkey = &get_dkim_pubkey($dkim);
my $anychanged = 0;
foreach my $d (@$doms) {
	&$first_print(&text('dkim_dns', "<tt>$d->{'dom'}</tt>"));
	my ($recs, $file) = &get_domain_dns_records_and_file($d);
	if (!$file) {
		&$second_print($text{'dkim_ednszone'});
		next;
		}
	if (&indexof($d->{'dom'}, @{$dkim->{'exclude'}}) >= 0) {
		&$second_print($text{'dkim_ednsexclude'});
		next;
		}
	&obtain_lock_dns($d);
	my $withdot = $d->{'dom'}.'.';
	my $dkname = '_domainkey.'.$withdot;
	my $changed = 0;
	my $selname = $dkim->{'selector'}.'.'.$dkname;
	my ($selrec) = grep { $_->{'name'} eq $selname && 
			      $_->{'type'} eq 'TXT' } @$recs;
	if (!$selrec) {
		# Add new record
		&bind8::create_record($file, $selname, undef, 'IN', 'TXT',
		    &split_long_txt_record(
			'"v=DKIM1; k=rsa; t=s; p='.$pubkey.'"'));
		$changed++;
		}
	elsif ($selrec && join("", @{$selrec->{'values'}}) !~ /p=\Q$pubkey\E/) {
		# Fix existing record
		my $val = join("", @{$selrec->{'values'}});
		if ($val !~ s/p=([^;]+)/p=$pubkey/) {
			$val = 'k=rsa; t=s; p='.$pubkey;
			}
		&bind8::modify_record($selrec->{'file'}, $selrec,
				      $selrec->{'name'}, $selrec->{'ttl'},
				      $selrec->{'class'}, $selrec->{'type'},
				      &split_long_txt_record('"'.$val.'"'));
		$changed++;
		}
	if ($changed) {
		&post_records_change($d, $recs, $file);
		&$second_print($text{'dkim_dnsadded'});
		$anychanged++;
		}
	else {
		&$second_print($text{'dkim_dnsalready'});
		}
	&release_lock_dns($d);
	}
&register_post_action(\&restart_bind) if ($anychanged);
}

# remove_dkim_dns_records(&domains, &dkim)
# Delete all DKIM TXT records from the given DNS domains
sub remove_dkim_dns_records
{
my ($doms, $dkim) = @_;
my $anychanged = 0;
foreach my $d (@$doms) {
	&$first_print(&text('dkim_undns', "<tt>$d->{'dom'}</tt>"));
	my ($recs, $file) = &get_domain_dns_records_and_file($d);
	if (!$file) {
		&$second_print($text{'dkim_ednszone'});
		next;
		}
	&obtain_lock_dns($d);
	my $withdot = $d->{'dom'}.'.';
	my $dkname = '_domainkey.'.$withdot;
	my ($dkrec) = grep { $_->{'name'} eq $dkname &&
			     $_->{'type'} eq 'TXT' } @$recs;
	my $selname = $dkim->{'selector'}.'.'.$dkname;
	my ($selrec) = grep { $_->{'name'} eq $selname &&
                              $_->{'type'} eq 'TXT' } @$recs;
	my $changed = 0;
	if ($selrec) {
		&bind8::delete_record($selrec->{'file'}, $selrec);
		$changed++;
		}
	if ($dkrec) {
		&bind8::delete_record($dkrec->{'file'}, $dkrec);
		$changed++;
		}
	if ($changed) {
		&post_records_change($d, $recs, $file);
		&$second_print($text{'dkim_dnsremoved'});
		$anychanged++;
		}
	else {
		&$second_print($text{'dkim_dnsalreadygone'});
		}
	&release_lock_dns($d);
	}
&register_post_action(\&restart_bind) if ($anychanged);
}

# rebuild_sendmail_cf()
# Rebuild sendmail's .cf file from the .mc file
sub rebuild_sendmail_cf
{
my $cmd = "cd $sendmail::config{'sendmail_features'}/m4 ; ".
	  "m4 $sendmail::config{'sendmail_features'}/m4/cf.m4 ".
	  "$sendmail::config{'sendmail_mc'}";
&lock_file($sendmail::config{'sendmail_cf'});
&system_logged("$cmd 2>/dev/null >$sendmail::config{'sendmail_cf'} ".
	       "</dev/null");
&unlock_file($sendmail::config{'sendmail_cf'});
}

# get_domain_dkim_key(&domain)
# Returns the DKIM private key for a domain
sub get_domain_dkim_key
{
my ($d) = @_;
my $dkim_config = &get_dkim_config_file();
return undef if (!-r $dkim_config);
my $conf = &get_debian_dkim_config($dkim_config);
return undef if (!$conf->{'KeyList'});
my $keyfile = $conf->{'KeyFile'};
my $lref = &read_file_lines($conf->{'KeyList'}, 1);
foreach my $l (@$lref) {
	my ($pat, $dom, $file) = split(/:/, $l);
	if ($dom eq $d->{'dom'} && !&same_file($file, $keyfile)) {
		# Has it's own key
		return &read_file_contents($file);
		}
	}
return undef;
}

# save_domain_dkim_key(&domain, key)
# Updates the private key for a domain (also in DNS)
sub save_domain_dkim_key
{
}

1;

