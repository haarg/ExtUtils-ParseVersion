package TestEUPVCommon;

sub _clean_eval { eval $_[0] }

{
  package
      ExtUtils::MakeMaker::_version;

  sub _eval_version {
    my ($name, $code) = @_;
    undef *version;
    eval {
        require version;
        version::->import;
    };
    no strict;
    local *{$name};
    local $^W = 0;
    eval $code;
    return ${$name};
  }
}

use strict;
use warnings;
use Exporter; *import = *import = \&Exporter::import;

our @EXPORT_OK = qw(
  dat_reader
  eumm_parse_version
  mm_parse_version
  mm_clean_version
);

sub dat_reader {
  my @files = @_;
  if (!@files) {
    @files = glob 't/corpus/*.dat';
  }
  my $last_file;
  my $code = '';
  my $fh;
  return sub {
    {
      if (!$fh) {
        my $data_file = shift @files or return;
        open $fh, '<', $data_file or do {
          undef $fh;
          die "can't read $data_file: $!";
        };
      }
      while (my $line = <$fh>) {
        chomp $line;
        my ($file, $code_line) = split /:/, $line, 2;
        my $return_code;
        if (defined $last_file) {
          if ($file ne $last_file) {
            my $return_code = $code;
            my $return_file = $last_file;
            $code = $code_line . "\n";
            $last_file = $file;
            return ($return_file, $return_code)
          }
        }
        $code .= $code_line . "\n";
        $last_file = $file;
        if (defined $return_code) {
          return ($last_file, $return_code);
        }
      }
      close $fh;
      undef $fh;

      redo if !defined $last_file;
    }

    return ($last_file, $code);
  };
}

# adapted from ExtUtils::MakeMaker 7.44
# returns undef rather than 'undef' if it didn't try to parse
sub eumm_parse_version {
  my $code = shift;

  my $result;

  my $found;
  my $inpod = 0;

  while ( $code =~ /(.*(?:\n|\z))/g ) {
    my $line = "$1";
    $inpod = $line =~ /^=(?!cut)/ ? 1 : $line =~ /^=cut/ ? 0 : $inpod;
    next
      if $inpod || $line =~ /^\s*#/;
    chop $line;
    next
      if $line =~ /^\s*(if|unless|elsif)/;
    if ( $line =~ m{^ \s* package \s+ \w[\w\:\']* \s+ (v?[0-9._]+) \s* (;|\{)  }x ) {
      $result = $1;
      $found = 1;
    }
    elsif ( $line =~ m{(?<!\\) ([\$*]) (([\w\:\']*) \bVERSION)\b .* (?<![<>=!])\=[^=]}x ) {
      my ($sigil, $name) = ($1, $2);
      my ($code) = $line =~ /\A(.*)\z/s;
      $result = ExtUtils::MakeMaker::_version::_eval_version($name, $code);
      $found = 1;
    }
    else {
      next;
    }
    last
      if defined $result;
  }

  return undef
    if !$found;

  if ( defined $result && $result !~ /^v?[\d_\.]+$/ ) {
    require version;
    my $normal = eval { version->new( $result ) };
    $result = $normal
      if defined $normal;
  }
  $result = "undef"
    unless defined $result;
  return $result;
}

# adapted from Module::Metadata 1.000037.
sub mm_parse_version {
  my $code = shift;

  my $in_pod;
  my $need_vers;
  my %vers;
  my $package = 'main';
  my @packages;
  my %packages;

  while ( $code =~ /(.*(?:\n|\z))/g ) {
    my $line = "$1";
    chomp $line;

    if ( $line =~ /^=([a-zA-Z].*)/ ) {
      my $cmd = $1;
      # Then it goes back to Perl code for "=cutX" where X is a non-alphabetic
      # character (which includes the newline, but here we chomped it away).
      $in_pod = $cmd !~ /^cut(?:[^a-zA-Z]|$)/;
      next;
    }

    next
      if $in_pod;

    next
      if $line =~ /^\s*#/;

    last
      if $line eq '__END__';
    last
      if $line eq '__DATA__';

    # parse $line to see if it's a $VERSION declaration
    my ( $version_sigil, $version_fullname, $version_package ) =
      index($line, 'VERSION') >= 1
        ? _mm_parse_version_assignment( $line )
        : ();

    if ( $line =~ m{
      ^[\s\{;]*
      package
      \s+
      (
        (?: :: )?
        [a-zA-Z_](?:[\w']?\w)*
        (?:
          (?: :: )+
          \w(?:[\w']?\w)*
        )*
        (?: :: )?
      )
      \s*
      (v?[0-9._]+)?
      \s*
      [;\{]
    }x) {
      $package = $1;
      my $version = $2;
      $need_vers = defined $version ? 0 : 1;
      push @packages, $package
        unless $packages{$package}++;

      if ( not exists $vers{$package} and defined $version ){
        $vers{$package} = mm_clean_version($version);
      }
    }

    # VERSION defined with full package spec, i.e. $Module::VERSION
    elsif ( $version_fullname && $version_package ) {
      # we do NOT save this package in found @packages
      $need_vers = 0
        if $version_package eq $package;

      unless ( defined $vers{$version_package} && length $vers{$version_package} ) {
        $vers{$version_package}
          = _mm_evaluate_version_line( $version_sigil, $version_fullname, $line );
      }
    }

    # first non-comment line in undeclared package main is VERSION
    elsif ( $package eq 'main' && $version_fullname && !exists($vers{main}) ) {
      $need_vers = 0;
      my $v = _mm_evaluate_version_line( $version_sigil, $version_fullname, $line );
      $vers{$package} = $v;
    }

    # first non-comment line in undeclared package defines package main
    elsif ( $package eq 'main' && !exists($vers{main}) && $line =~ /\w/ ) {
      $need_vers = 1;
      $vers{main} = '';
    }

    # only keep if this is the first $VERSION seen
    elsif ( $version_fullname && $need_vers ) {
      $need_vers = 0;
      my $v = _mm_evaluate_version_line( $version_sigil, $version_fullname, $line );

      unless ( defined $vers{$package} && length $vers{$package} ) {
        $vers{$package} = $v;
      }
    }
  }

  return (\%vers, \@packages);
}

sub _mm_parse_version_assignment {
  my $line = shift;

  if ( $line =~ m{
    (?:
      \(\s*
        ([\$*])
        (
          (
            (?:::|\')?
            (?:\w+(?:::|\'))*
          )?
          VERSION
        )\b
      \s*\)
    |
      ([\$*])
      (
        (
          (?:::|\')?
          (?:\w+(?:::|\'))*
        )?
        VERSION
      )\b
    )
    \s*
    =[^=~>]
  }x) {
    my ( $sigil, $variable_name, $package) = $2 ? ( $1, $2, $3 ) : ( $4, $5, $6 );
    if ( $package ) {
      $package = ($package eq '::') ? 'main' : $package;
      $package =~ s/::$//;
    }
    return ( $sigil, $variable_name, $package );
  }
  return;
}

sub mm_clean_version {
  my $version = shift;

  ref $version eq 'version'
    and return $version;

  eval { $version = version->new($version); 1 }
    and return $version;
  my $error = $@;

  $version =~ s{([0-9])[a-z-].*$}{$1}i;
  eval { $version = version->new($version); 1 }
    and return $version;

  if ($version !~ /\Av/) {
    my $dots = $version =~ tr/.//;
    my $unders = $version =~ tr/_//;

    if ( $dots < 2 && $unders > 1 ) {
      $version =~ tr{_}{}d;
      eval { $version = version->new($version); 1 }
        and return $version;
    }
  }

  no warnings 'numeric';
  $version = 0 + $version;
  eval { $version = version->new($version); 1 }
    and return $version;

  die $error;
}

my $pn = 0;
sub _mm_evaluate_version_line {
  my ($sigil, $variable_name, $line) = @_;

  $pn++;
  my $eval = qq{
    package Test_MM_Like::_version::p${pn};
    use version;
    sub {
      local $sigil$variable_name;
      $line;
      return \$$variable_name if defined \$$variable_name;
      return \$Test_MM_Like::_version::p${pn}::$variable_name;
    };
  };

  $eval = $1 if $eval =~ m{^(.+)}s;

  local $^W;
  my $vsub = _clean_eval($eval);
  warn $@
    if $@;

  die "failed to build version sub"
    unless ref $vsub eq 'CODE';

  return mm_clean_version($vsub->());
}

1;
