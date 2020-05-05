use strict;
use warnings;
use Test::More;
use ExtUtils::ParseVersion qw(parse_version);
use lib 't/lib';
use TestEUPVCommon qw(
  dat_reader  
  eumm_parse_version
);

my $reader = dat_reader('t/corpus/bad.dat');

while (my ($file, $code) = $reader->()) {
  next
    if $file !~ /\.pm\z/;
  my $want = eumm_parse_version($code);
  my ($package, $version) = parse_version(\$code,
    allow_safe => 1,
    accept_undef => 1,
  );
  $version = 'undef'
    if !defined $version; # && defined $package

  is $version, $want, $file or do { diag $code; exit };
};

done_testing;
