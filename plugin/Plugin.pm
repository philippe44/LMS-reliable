package Plugins::Reliable::Plugin;

use strict;
use base qw(Slim::Plugin::Base);

use Slim::Utils::Strings qw(string cstring);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

use Plugins::Reliable::ProtocolHandler;

my	$log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.reliable',
	'defaultLevel' => 'ERROR',
	'description'  => 'PLUGIN_RELIABLE',
});

my $prefs = preferences('plugin.reliable');
my $parseDirectHeaders = \&Slim::Player::Protocols::HTTP::parseDirectHeaders;

$prefs->init({ 
	enable => 0, 
});

sub parseDirectHeaders {
	my ( $self, $client, $url, @headers ) = @_;
	
	my ($header) = grep { $_ =~ /content-range:/i } @headers;
	$header =~ m%^Content-Range:\s+bytes\s+(\d+)-(\d+)/(\d+)%i;
	${*$self}{'range'} = $1 . '-' . $2 if ref $self;
	
	$parseDirectHeaders->(@_);
}

sub initPlugin {
	my $class = shift;
	
	*Slim::Player::Protocols::HTTP::parseDirectHeaders = \&parseDirectHeaders unless Slim::Player::Protocols::HTTP->can('_sysread');
	
	if ($prefs->get('enabled')) {
	
		Slim::Player::ProtocolHandlers->registerHandler(
			http => 'Plugins::Reliable::ProtocolHandler'
		);
	
		Slim::Player::ProtocolHandlers->registerHandler(
			https => 'Plugins::Reliable::ProtocolHandler'
		);
		
	}	

	$class->SUPER::initPlugin;

	if ( main::WEBUI ) {
		require Plugins::Reliable::Settings;
		Plugins::Reliable::Settings->new;
	}
}	
	
sub getDisplayName { 'PLUGIN_RELIABLE' }


1;
