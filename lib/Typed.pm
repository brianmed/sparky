package Typed;

use strict;
use warnings FATAL => 'all';
use feature qw(:5.10);

use Carp qw();
use Scalar::Util qw();

use parent qw(Exporter);
our @EXPORT = qw(has subtype as where message new);

our $VERSION = '0.05';

sub new {
    my $self = shift;
    
    my $class = ref($self) || $self;
    my $blessed = bless({}, $class);

    my $meta_pkg = __PACKAGE__;
    my $meta = do { no strict 'refs'; \%{"${meta_pkg}::meta"}; };

    if ($meta && $$meta{$class}) {
        my $has = $$meta{$class};
        foreach my $name (keys %{ $has }) {
            my $opts = $$meta{$class}{$name};

            __PACKAGE__->default($blessed, $class, $name, $opts, $$opts{lazy});
        }
    }

    my %user_vals = @_;
    foreach my $k (keys %user_vals) {
        $blessed->{$k} = $user_vals{$k}; # TODO: Use the attribute method.
    }

    my $build = $blessed->can("BUILD");
    if ($build) {
        $build->($blessed);
    }

    return($blessed);
}

sub default {
    my $meta_pkg = shift;
    my $self = shift;
    my $package = shift;
    my $name = shift;
    my $opts = shift;
    my $lazy = shift;

    my $default;
    unless ($lazy) {
        if ($$opts{default}) {
            my $type = ref($$opts{default});
            if ($type && "CODE" eq $type) {
                $default = $$opts{default}->();
            }
            else {
                $default = $$opts{default};
            }
        }

        if ($$opts{builder}) {
            my $builder = do { no strict 'refs'; \&{"${package}::$$opts{builder}"}; };

            if ($builder) {
                $default = $builder->($self);
            }
        }

        $self->{$name} = $default; # TODO: Use the attribute method.
    }
    
    return($default);
}

# Yes, we use a global cache for metadata
our %meta = (
);

my %constraints = (
    Bool => {
        where => sub {
            return 1 if '1' eq $_;
            return 1 if '0' eq $_;
            return 1 if '' eq $_;
            return 0;
        },
    },
    Str => {
        where => sub {
            my $type = ref($_);

            return 1 if !$type;
            return 0;
        },
    },
    "FileHandle" => {
        where => sub {
            my $type = Scalar::Util::openhandle($_);

            return 1 if defined $type;
            return 0;
        },
    },
    "Object" => {
        where => sub {
            my $type = Scalar::Util::blessed($_);

            return 1 if defined $type;
            return 0 if defined $type;
        },
    },
    "Num" => {
        where => sub {
            return 1 if Scalar::Util::looks_like_number($_);
            return 0;
        },
    },
    "Int" => {
        where => sub {
            return 0 if !Scalar::Util::looks_like_number($_);
            return 1 if $_ == int($_);
            return 0;
        },
    },
    ClassName => {
        where => sub {
            # Types::Standard
            return !!0 if ref $_;
            return !!0 if !defined $_;
            my $stash = do { no strict 'refs'; \%{"$_\::"} };
            return !!1 if exists $stash->{'ISA'};
            return !!1 if exists $stash->{'VERSION'};
            foreach my $globref (values %$stash) {
                return !!1 if *{$globref}{CODE};
            }
            return !!0;
        },
    },
);

# Constraint verification sub
sub type {
    my ($class, $name, $value, $opts) = @_;

    return 1 if !defined $value;

    my $isa = $$opts{isa};

    if ($constraints{$isa} && $constraints{$isa}{as}) {
        my $isa = $constraints{$isa}{as};
        my $where = $constraints{$isa}{where};

        $class->type($name, $value, { isa => $isa, where => $where, opts => { isa => $isa }});
    }

    {
        local $_ = $value;

        return 1 if $$opts{where}->();

        if ($constraints{$isa}{message}) {
            Carp::croak($constraints{$isa}{message}->());
        }
        else {
            Carp::croak("$_ does not match the type constraints: $isa for $name");
        }
    }
}

sub subtype {
    my $subtype = shift;
    my %opts = @_;

    Carp::croak("No subtype given.") if !$subtype;
    Carp::croak("No as given.") if !$opts{as};
    Carp::croak("No where given.") if !$opts{where};

    $constraints{$subtype} = {
        as => $opts{as},
        where => $opts{where},
        message => $opts{message},
    };
}

sub as          ($) { (as          => $_[0]) } ## no critic
sub where       (&) { (where       => $_[0]) } ## no critic
sub message     (&) { (message     => $_[0]) } ## no critic

sub process_has {
    my $self = shift;
    my $name = shift;
    my $package = shift;

    my $isa = $meta{$package}{$name}{isa};

    my $where;
    if ($constraints{$isa}) {
        $where = $constraints{$isa}{where};
    }
    else {
        $where = $constraints{ClassName}{where};
    }

    my $is = $meta{$package}{$name}{is};
    my $writable = $is && "rw" eq $is;
    my $type = { isa => $isa, where => $where, opts => { isa => $isa }};
    my $opts = $meta{$package}{$name};

    my $attribute = sub {
        if (!exists $_[0]->{$name}) {
            __PACKAGE__->default($_[0], $package, $name, $opts, 0);
        }

        # Do we set the value
        if (1 == $#_) {
            if ($writable) {
                return($_[0]->{$name} = undef) if !defined $_[1];

                # Need subtypes
                if ($constraints{$isa} && $constraints{$isa}{as}) {
                    __PACKAGE__->type($name, $_[1], $type);
                }
                else {
                    # Common case is faster
                    local $_ = $_[1];
                    $where->() || Carp::croak("$_ does not match the type constraints: $isa for $name");
                }

                $_[0]->{$name} = $_[1];
            }
            else {
                Carp::croak("Attempt to modify read-only attribute: $name");
            }
        }

        return($_[0]->{$name});
    };

    return($attribute);
}

sub has {
    my $name = shift;
    my %opts = @_;
    my $package = caller;

    $meta{$package}{$name} = \%opts;

    my $attribute = __PACKAGE__->process_has($name, $package);

    { no strict 'refs'; *{"${package}::$name"} = $attribute; }
}

1;

__END__

=head1 NAME

Typed - Minimal typed Object Oriented layer

=head1 SYNOPSIS

    package User;
    
    use Typed;
    use Email::Valid;
    
    subtype 'Email'
    
        => as 'Str'
        => where { Email::Valid->address($_) }
        => message { $_ ? "$_ is not a valid email address" : "No value given for address validation" };
    
    has 'id' => ( isa => 'Int', is => 'rw' );
    
    has 'email' => ( isa => 'Email', is => 'rw' );
    
    has 'password' => ( isa => 'Str', is => 'rw' );
    
    1;
    
    package main;
    
    use strict;
    use warnings;
    use feature qw(:5.10);
    
    my $user = User->new();
    
    $user->id(1);
    
    say($user->id());
    
    eval {
        $user->email("abc");
    };
    if ($@) {
        $user->email('abc@nowhere.com');
    }
    say($user->email());

=head1 DESCRIPTION

L<Typed> is a minimalistic typed Object Oriented layer.

The goal is to be mostly compatible with L<Moose::Manual::Types>.

=cut
