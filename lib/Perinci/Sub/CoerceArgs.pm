package Perinci::Sub::CoerceArgs;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
#use Log::Any '$log';

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
                       coerce_args
               );

our %SPEC;

# a cheap Module::Load
#sub _require_class {
#    my $class = shift;
#    (my $class_pm = $class) =~ s!::!/!g; $class_pm .= ".pm";
#    require $class_pm;
#}

sub _coerce_to_datetime {
    my ($args, $arg_name) = @_;

    my $val = $args->{$arg_name};

    if ($val =~ /\A\d{8,}\z/) {
        require DateTime;
        $args->{$arg_name} = DateTime->from_epoch(
            epoch => $val,
            time_zone => $ENV{TZ} // "UTC",
        );
        return [200];
    } elsif ($val =~ m!\A
                       (\d{4})[/-](\d{1,2})[/-](\d{1,2})
                       (?:[ Tt](\d{1,2}):(\d{1,2}):(\d{1,2}))?
                       \z!x) {
        require DateTime;
        $args->{$arg_name} = DateTime->new(
            year => $1, month => $2, day => $3,
            hour => $4 // 0,
            minute => $4 // 0,
            second => $4 // 0,
            time_zone => $ENV{TZ} // "UTC",
        );
        return [200];
    } else {
        return [400, "Can't coerce DateTime object " .
                 "'$arg_name' from '$args->{$arg_name}'"];
    }
}

sub _coerce_to_datetime_duration {
    my ($args, $arg_name) = @_;

    my $val = $args->{$arg_name};

    if ($val =~ /\AP
                 (?:([0-9]+(?:\.[0-9]+)?)Y)?
                 (?:([0-9]+(?:\.[0-9]+)?)M)?
                 (?:([0-9]+(?:\.[0-9]+)?)W)?
                 (?:([0-9]+(?:\.[0-9]+)?)D)?
                 (?: T
                     (?:([0-9]+(?:\.[0-9]+)?)H)?
                     (?:([0-9]+(?:\.[0-9]+)?)M)?
                     (?:([0-9]+(?:\.[0-9]+)?)S)?
                 )?\z/x) {
        require DateTime::Duration;
        $args->{$arg_name} = DateTime::Duration->new(
            years   => $1 || 0,
            months  => $2 || 0,
            weeks   => $3 || 0,
            days    => $4 || 0,
            hours   => $5 || 0,
            minutes => $6 || 0,
            seconds => $7 || 0,
        );
        return [200];
    } else {
        return [400, "Can't coerce DateTime::Duration object " .
                    "'$arg_name' from '$args->{$arg_name}'"];
    }
}

sub _coerce_to_time_moment {
    my ($args, $arg_name) = @_;

    my $val = $args->{$arg_name};

    # XXX just use Time::Moment's from_string()?
    if ($val =~ /\A\d{8,}\z/) {
        require Time::Moment;
        $args->{$arg_name} = Time::Moment->from_epoch($val);
        return [200];
    } elsif ($val =~ m!\A
                       (\d{4})[/-](\d{1,2})[/-](\d{1,2})
                       (?:[ Tt](\d{1,2}):(\d{1,2}):(\d{1,2}))?
                       \z!x) {
        # XXX parse time zone offset
        require Time::Moment;
        $args->{$arg_name} = Time::Moment->new(
            year => $1, month => $2, day => $3,
            hour => $4 // 0,
            minute => $4 // 0,
            second => $4 // 0,
        );
        return [200];
    } else {
        return [400, "Can't coerce Time::Moment object " .
                    "'$arg_name' from '$args->{$arg_name}'"];
    }
}

$SPEC{coerce_args} = {
    v           => 1.1,
    summary     => 'Coerce arguments',
    description => <<'_',

This routine can be used when function arguments are retrieved from strings,
like from command-line arguments in CLI application (see
`Perinci::CmdLine::Lite` or `Perinci::CmdLine::Classic`) or from web form
variables in web application (see `Borang`). For convenience, object or complex
data structure can be converted from string (e.g. `DateTime` object from strings
like `2015-03-27` or epoch integer). And filters can be applied to
clean/preprocess the string (e.g. remove leading/trailing blanks) beforehand.

_
    args => {
        meta => {
            summary => 'Rinci function metadata',
            schema  => 'hash*',
            req     => 1,
        },
        meta_is_normalized => {
            schema => 'bool*',
        },
        args => {
            summary => 'Reference to hash which store the arguments',
            schema  => 'hash*',
        },
    },
};
sub coerce_args {
    my %fargs = @_;

    my $meta = $fargs{meta} or return [400, "Please specify meta"];
    unless ($fargs{meta_is_normalized}) {
        require Perinci::Sub::Normalize;
        $meta = Perinci::Sub::Normalize::normalize_function_metadata($meta);
    }
    my $args = $fargs{args};

    for my $arg_name (keys %$args) {
        my $val = $args->{$arg_name};
        next unless defined($val) && !ref($val);
        my $arg_spec = $meta->{args}{$arg_name};
        next unless $arg_spec;

        if (my $filters = $arg_spec->{filters}) {
            for my $filter (@$filters) {
                if (ref($filter) eq 'CODE') {
                    $val = $filter->($val);
                } elsif ($filter eq 'trim') {
                    $val =~ s/\A\s+//s;
                    $val =~ s/\s+\z//s;
                } elsif ($filter eq 'ltrim') {
                    $val =~ s/\s+\z//s;
                } elsif ($filter eq 'rtrim') {
                    $val =~ s/\A\s+//s;
                } else {
                    return [400, "Unknown filter '$filter' ".
                                "for argument '$arg_name'"];
                }
            }
            $args->{$arg_name} = $val if @$filters;
        }

        if (my $schema = $arg_spec->{schema}) {
            if ($schema->[0] eq 'obj') {
                my $class = $schema->[1]{isa} // '';
                # convert DateTime object from epoch/some formatted string
                if ($class eq 'DateTime') {
                    my $coerce_res = _coerce_to_datetime($args, $arg_name);
                    return $coerce_res unless $coerce_res->[0] == 200;
                } elsif ($class eq 'DateTime::Duration') {
                    my $coerce_res = _coerce_to_datetime_duration($args, $arg_name);
                    return $coerce_res unless $coerce_res->[0] == 200;
                } elsif ($class eq 'Time::Moment') {
                    my $coerce_res = _coerce_to_time_moment($args, $arg_name);
                    return $coerce_res unless $coerce_res->[0] == 200;
                }
            } elsif ($schema->[0] eq 'date' &&
                         $arg_spec->{'x.perl.coerce_to_datetime_obj'}) {
                my $coerce_res = _coerce_to_datetime($args, $arg_name);
                return $coerce_res unless $coerce_res->[0] == 200;
            } elsif ($schema->[0] eq 'date' &&
                         $arg_spec->{'x.perl.coerce_to_time_moment_obj'}) {
                my $coerce_res = _coerce_to_time_moment($args, $arg_name);
                return $coerce_res unless $coerce_res->[0] == 200;
            } elsif ($schema->[0] eq 'duration' &&
                         $arg_spec->{'x.perl.coerce_to_datetime_duration_obj'}) {
                my $coerce_res = _coerce_to_datetime_duration($args, $arg_name);
                return $coerce_res unless $coerce_res->[0] == 200;
            }
        } # has schema
    }

    [200, "OK", $args];
}

1;
#ABSTRACT:

=head1 SYNOPSIS

 use Perinci::Sub::CoerceArgs qw(coerce_args);

 my $res = coerce_args(meta=>$meta, args=>$args, ...);


=head1 DESCRIPTION

I expect this to be a temporary solution until L<Data::Sah> or
L<Perinci::Sub::Wrapper> has this functionality.

=cut
