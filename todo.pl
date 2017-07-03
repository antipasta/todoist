#!/usr/bin/env perl
package runner;
use strict;
use warnings;
use Moo;
use MooX::Options;
use WWW::JSON;
use URI;
use Data::Dumper::Concise;
use IO::Prompt;
use YAML::Tiny;

option config_file => ( is => 'lazy', builder => '_config_file' );
has config      => ( is => 'lazy', builder => '_config' );
has client_id =>
  ( is => 'lazy', default => sub { shift->config->{client_id}} );
has client_secret =>
  ( is => 'lazy', default => sub { shift->config->{client_secret}} );
option task => (
    is      => 'lazy',
    format  => 's',
    default => sub {
        return unless @ARGV;
        return ( @ARGV == 2 ) ? $ARGV[1] : $ARGV[0];
    }
);
option project => (
    is      => 'lazy',
    format  => 's',
    default => sub { return unless ( @ARGV == 2 ); return $ARGV[0]; }
);
has project_mapping => (
    is      => 'lazy',
    default => sub {
        my $self    = shift;
        my $payload = $self->api->get( '/sync',
            { sync_token => '*', resource_types => '["projects"]' } );
        return { map { lc( $_->{name} ) => $_->{id} }
              @{ $payload->res->{projects} } };
    }
);
option auth => ( is => 'ro' );

has project_id => (
    is      => 'lazy',
    default => sub {
        my $self  = shift;
        my $input = lc( $self->project );
        if ( my $pid = $self->project_mapping->{$input} ) {
            return $pid;
        }
        for my $pname ( keys %{ $self->project_mapping } ) {
            if ( $pname =~ /^\Q$input\E/ ) {
                warn "Fuzzy Adding to project $pname";
                return $self->project_mapping->{$pname};
            }
        }
        die "Could not find matching project for " . $self->project;
    }
);

has api => (
    is      => 'lazy',
    default => sub {
        WWW::JSON->new(
            {
                base_url     => 'https://todoist.com/API/v7/',
                query_params => { token => shift->access_token }
            }
        );
    }
);


sub _config_file {
    return $ENV{HOME} . '/.todoist';
}

sub _config {
    my $self = shift;
    my $yml  = YAML::Tiny::LoadFile( $self->config_file )
      or die "Config not found";
    return $yml;
}

sub save_config {
    my $self = shift;
    YAML::Tiny::DumpFile( $self->config_file, $self->config );
}

sub access_token {
    shift->config->{access_token};
}
sub run {
    my $self = shift;
    unless ($self->access_token) {
        $self->authorize;
    }
    if ( $self->task ) {
        return $self->add_task;
    }
}

sub add_task {
    my $self = shift;
    my $project_id;
    if ( $self->project ) {
        $project_id = $self->project_id;
    }
    my $p = $self->api->get(
        '/items/add',
        {
            ($project_id) ? ( project_id => $project_id ) : (),
            content => $self->task
        }
    );
    return warn $p->error if ( $p->error );
    warn "Task added";
}

sub authorize {
    my $self = shift;
    my $u    = URI->new('https://todoist.com/oauth/authorize');
    $u->query_form(
        client_id => $self->client_id,
        scope     => 'task:add,data:read',
        state     => 'arg'
    );
    print "Please visit "
      . $u->as_string
      . " and when you have, enter code below.\n";
    my $code = prompt("Enter Code:");
    chomp($code);
    my $token = $self->get_access_token($code);
    unless ($token) {
        die "Error getting token";
    }
    $self->config->{access_token} = $token;
    my $should_save = prompt("Got back access token. Save config (y/N): ");
    if (lc($should_save) eq 'y') {
        $self->save_config;
    }

}

sub get_access_token {
    my ( $self, $code ) = @_;
    my $wj = WWW::JSON->new( base_url => 'https://todoist.com/oauth/' );
    my $auth = $wj->post(
        '/access_token',
        {
            client_id     => $self->client_id,
            client_secret => $self->client_secret,
            code          => $code
        }
    );
    warn Dumper( $auth->res );
    return $auth->res->{access_token};

}
1;

package script;
use strict;
use warnings;

runner->new_with_options()->run();
1;

