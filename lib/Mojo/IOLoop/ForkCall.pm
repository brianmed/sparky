package Mojo::IOLoop::ForkCall;  # From jberger; some version weirdness with ppm
 
use Mojo::Base 'Mojo::EventEmitter';
 
our $VERSION = '0.05';
$VERSION = eval $VERSION;
 
use Mojo::IOLoop;
use POSIX ();
 
use Perl::OSType 'is_os_type';
use constant IS_WINDOWS => is_os_type('Windows');
 
use Exporter 'import';
our @EXPORT_OK = qw/fork_call/;
 
has 'ioloop'       => sub { Mojo::IOLoop->singleton };
has 'serializer'   => sub { require Storable; \&Storable::freeze };
has 'deserializer' => sub { require Storable; \&Storable::thaw   };
has 'weaken'       => 0;
 
sub run {
  my ($self, $job) = (shift, shift);
  my ($args, $cb);
  $args = shift if @_ and ref $_[0] eq 'ARRAY';
  $cb   = shift if @_;
 
  my ($r, $w);
  pipe($r, $w); 
  my $serializer = $self->serializer;
 
  my $pid = fork;
  die "Failed to fork: $!" unless defined $pid;
 
  if ($pid == 0) {
    # child
    close $r;
 
    local $@;
    my $res = eval {
      local $SIG{__DIE__};
      $serializer->([undef, $job->(@$args)]);
    };
    $res = $serializer->([$@]) if $@;
    syswrite $w, $res;
 
    # attempt to generalize exiting from child cleanly on all platforms
    # adapted from POE::Wheel::Run mostly
    eval { POSIX::_exit(0) } unless IS_WINDOWS;
    eval { CORE::kill KILL => $$ };
    exit 0;
 
  } else {
    # parent
    close $w;
 
    my $stream = Mojo::IOLoop::Stream->new($r);
    $self->ioloop->stream($stream);
 
    my $buffer = '';
    $stream->on( read  => sub { $buffer .= $_[1] } );
 
    if ($self->weaken) {
      require Scalar::Util;
      Scalar::Util::weaken($self);
    }
 
    my $deserializer = $self->deserializer;
    $stream->on( close => sub {
      my $res = do {
        local $@;
        eval { $deserializer->($buffer) } || [$@];
      };
      $self->$cb(@$res) if $cb;
      $self->emit( finish => @$res ) if $self;
 
      waitpid $pid, 0;
    });
 
    return $pid;
  }
}
 
## functions
 
sub fork_call (&@) {
  my $job = shift;
  my $cb  = pop;
  return __PACKAGE__->new->run($job, \@_, sub {
    # local $_ = shift; #TODO think about this
    shift;
    local $@ = shift;
    $cb->(@_);
  });
}
 
1;
