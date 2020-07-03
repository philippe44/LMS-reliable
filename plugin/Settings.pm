package Plugins::Reliable::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.reliable');

sub name {
	return 'PLUGIN_RELIABLE';
}

sub page {
	return 'plugins/reliable/settings/basic.html';
}

sub prefs {
	return (preferences('plugin.reliable'), qw(enabled));
}

sub handler {
	my ($class, $client, $params, $pageSetup) = @_;
	
	if ($params->{'saveSettings'}) {
		if ( $params->{pref_enabled} ) {
			Slim::Player::ProtocolHandlers->registerHandler(
				http => 'Plugins::Reliable::ProtocolHandler'
			);
	
			Slim::Player::ProtocolHandlers->registerHandler(
				https => 'Plugins::Reliable::ProtocolHandler'
			);
		} else {
			Slim::Player::ProtocolHandlers->registerHandler(
				http => 'Slim::Player::Protocols::HTTP'
			);
	
			Slim::Player::ProtocolHandlers->registerHandler(
				https => http => 'Slim::Player::Protocols::HTTPS'
			);
		}
	}
	
	return $class->SUPER::handler($client, $params, $pageSetup);
}

	
1;
