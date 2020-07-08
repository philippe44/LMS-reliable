package Plugins::Reliable::ProtocolHandler;

use strict;
use base qw(IO::Handle Slim::Player::Protocols::HTTP);

use Slim::Utils::Log;
use Slim::Utils::Errno;

use constant MAX_ERRORS	=> 5;

use constant DISCONNECTED => 0;
use constant IDLE         => 1;
use constant CONNECTING   => 2;
use constant CONNECTED    => 3;

my $log = logger('player.streaming.remote');

sub new {
	my $class  = shift;
	my $args   = shift;
	my $song = $args->{'song'};

	my $sock = $class->SUPER::new;
	my $session;
	
	main::INFOLOG && $log->is_info && $log->info("opening reliable url $args->{url} ", $song->streamUrl);
	
	if ( $args->{'url'} =~ /https:\/\// && Slim::Networking::Async::HTTP->hasSSL ) {
		require Slim::Player::Protocols::HTTPS;
		$session = Slim::Player::Protocols::HTTPS->new($args);
	} else {
		$session = Slim::Player::Protocols::HTTP->new($args);
	}	

	# I don't think we need a deep copy
	%{*$sock} = %{*$session};

	${*$sock}{'reliable'} = {    
		'status'  => IDLE,       
		'errors'  => 0,   
		'offset'  => 0,		
		'session' => Slim::Networking::Async::HTTP->new,
	};
	
	# need to know the range of the request we'll "proxy"
	if ((delete ${*$sock}{'range'}) =~ /(\d+)-(\d+)/) {
		${*$sock}{'reliable'}{'offset'} = $1;
		${*$sock}{'reliable'}{'last'} = $2;
	}
	
	# we don't need anymore that http object
	$session->close;

	return $sock;
}

sub close {
	my $self = shift;
	my $v = ${*$self}{'reliable'};
	$v->{'session'}->disconnect unless $v->{'status'} == DISCONNECTED;
	$v->{'status'} = DISCONNECTED;
	$v->{'offset'} = 0;
	$self->SUPER::close();
	main::INFOLOG && $log->is_info && $log->info("closing reliable url ${*$self}{url}");
}

# we need that call structure to make sure that SUPER calls the 
# object's parent, not the package's parent
# see http://modernperlbooks.com/mt/2009/09/when-super-isnt.html
sub _sysread {
	my $self  = $_[0];
	# return in $_[1]
	my $maxBytes = $_[2];
	my $v = ${*$self}{'reliable'};
	
	return 0 if $v->{'status'} == DISCONNECTED;

	# need to start streaming
	if ( $v->{'status'} == IDLE ) {
		my $request = HTTP::Request->new( GET => ${*$self}{'url'} ); 
		$request->header( 'Range', "bytes=$v->{'offset'}-" . $v->{'last'} );
		$v->{'status'} = CONNECTING;		
		$v->{'lastSeen'} = undef;

		main::DEBUGLOG && $log->is_debug && $log->debug("streaming from $v->{'offset'} for ${*$self}{'url'}");

		$v->{'session'}->send_request( {
			request     => $request,
			onHeaders => sub {
				$v->{'length'} = shift->response->headers->header('Content-Length');
				$v->{'length'} += $v->{'offset'} if $v->{'length'};
				$v->{'status'} = CONNECTED;
				$v->{'errors'} = 0;
			},
			onError  => sub {
				$v->{'session'}->disconnect;
				$v->{'status'} = IDLE;
				$v->{'errors'}++;
				$log->error("cannot open session for ${*$self}{'url'} $_[1] ");
			},
		} );
	}

	# the child socket should be non-blocking so here we can safely call
	# read_entity_body which calls sysread if buffer is empty. This is normally
	# a callback invoked when select() has something to read on that socket.
	my $bytes = $v->{'session'}->socket->read_entity_body($_[1], $maxBytes) if $v->{'status'} == CONNECTED;
	
	if ( $bytes && $bytes != -1 ) {
		$v->{'offset'} += $bytes;
		$v->{'lastSeen'} = time();
		return $bytes;
	} elsif ( $bytes == -1 || (!defined $bytes && $v->{'errors'} < MAX_ERRORS && ($v->{'status'} != CONNECTED || $! == EINTR || $! == EWOULDBLOCK) && (!defined $v->{'lastSeen'} || time() - $v->{'lastSeen'} < 5)) ){
		$! = EINTR;
		main::DEBUGLOG && $log->is_debug && $log->debug("need to wait for ${*$self}{'url'}");
		return undef;
	} elsif ( !$v->{'length'} || $v->{'offset'} == $v->{'length'} || $v->{'errors'} >= MAX_ERRORS ) {
		$v->{'session'}->disconnect;
		$v->{'status'} = DISCONNECTED;
		main::INFOLOG && $log->is_info && $log->info("end of ${*$self}{'url'} s:", time() - $v->{'lastSeen'}, " e:$v->{'errors'}");
		return 0;
	} else {
		$log->warn("unexpected connection close at $v->{'offset'}/$v->{'length'} for ${*$self}{'url'}\n\tsince:", time() - $v->{'lastSeen'}, "\n\terror:", ($! != EINTR && $! != EWOULDBLOCK) ? $! : "N/A");
		$v->{'session'}->disconnect;
		$v->{'status'} = IDLE;
		$v->{'errors'}++;
		$! = EINTR;
		return undef;
	}
}

sub sysread {
	return __sysread(@_) unless Slim::Player::Protocols::HTTP->can('_sysread');
	
	my $readLength = Slim::Player::Protocols::HTTP::sysread(@_);

	if (main::ISWINDOWS && !$readLength) {
		$! = EINTR;
	}

	return $readLength;
}

sub canDirectStreamSong { 0 }

# this code must be removed with updated LMS release
sub __readMetaData {
	my $self = shift;
	my $client = ${*$self}{'client'};

	my $metadataSize = 0;
	my $byteRead = 0;

	while ($byteRead == 0) {
		$byteRead = $self->_sysread($metadataSize, 1);
		if ($!) {
			if ($! ne "Unknown error" && $! != EWOULDBLOCK && $! != EINTR) {
				$log->error("missed metadata reading $!");		
			 	#return;
			 } 
		}
		$byteRead = defined $byteRead ? $byteRead : 0;
	}

	$metadataSize = ord($metadataSize) * 16;

	if ($metadataSize > 0) {
		my $metadata;
		my $metadatapart;

		do {
			$metadatapart = '';
			$byteRead = $self->_sysread($metadatapart, $metadataSize);
			if ($!) {
				if ($! ne "Unknown error" && $! != EWOULDBLOCK && $! != EINTR) {
					$log->error("missed metadata reading $!");		
					#return;
				} 
			}

			$byteRead = 0 if (!defined($byteRead));
			$metadataSize -= $byteRead;
			$metadata .= $metadatapart;

		} while ($metadataSize > 0);

		${*$self}{'title'} = Slim::Player::Protocols::HTTP->parseMetadata($client, $self->url, $metadata);
	}
}

sub __sysread {
	my $self = $_[0];
	my $chunkSize = $_[2];
	
	my $metaInterval = ${*$self}{'metaInterval'};
	my $metaPointer  = ${*$self}{'metaPointer'};

	if ($metaInterval && ($metaPointer + $chunkSize) > $metaInterval) {
		$chunkSize = $metaInterval - $metaPointer;
		$log->debug("reduced for metadata $chunkSize");		
	}

	my $readLength = $self->_sysread($_[1], $chunkSize, length($_[1] || ''));
	
	# use $readLength from socket for meta interval adjustement
	if ($metaInterval && $readLength) {

		$metaPointer += $readLength;
		${*$self}{'metaPointer'} = $metaPointer;

		# handle instream metadata for shoutcast/icecast
		if ($metaPointer == $metaInterval) {
			$self->__readMetaData();
			${*$self}{'metaPointer'} = 0;
			$log->debug("rightshoot $metaPointer");				
		} 
		elsif ($metaPointer > $metaInterval) {
			$log->debug("overshoot $metaPointer $metaInterval");		
		}
	}
	
	if (main::ISWINDOWS && !$readLength) {
		$! = EINTR;
	}

	return $readLength;
}


1;