#!/usr/bin/env perl
use strict;
use warnings;

use File::Find ();

sub check_file {
  my ($file, $prefix) = @_;
  $prefix = ''
    if !defined $prefix;
  open my $fh, '<', $file or die "can't read $file: $!";
  my $in_pod;
  my @buffer;
  while (my $line = <$fh>) {
    if ($line =~ /\0/) {
      return;
    }
    chomp $line;
    $line =~ s/\r\z//;
    if ($line =~ /^=(\w+)/) {
      $in_pod = $1 ne 'cut';
      next;
    }

    next
      if $in_pod;
    next
      if $line =~ /^\s*#/;
    next
      if $line =~ /^\s*(?:if|unless|elsif)/;

    if ($line =~ /\A__(?:DATA|END)__\z/) {
      push @buffer, $line;
      next;
    }

    if (
      $line =~ m{
        ^[\s\{;]*
        package
        \s+
        [a-zA-Z_]\w*(?:(?:'|::)\w+)*
        (\s+v?[0-9._]+)?
        \s*
        [;\{]
      }x
    ) {
      push @buffer, $line;
      next
        if !$1;
    }
    elsif (
      $line =~ m{
        (?<!\\)
        [\$*]
        [\w\:\']*
        \bVERSION\b
        .*
        (?<![<>=!])\=[^=]
      }x
    ) {
      push @buffer, $line;
    }
    else {
      next;
    }

    print "$prefix$_\n" for @buffer;
    @buffer = ();
  }
}

for my $in (@ARGV) {
  if (-d $in) {
    File::Find::find({
      no_chdir => 1,
      wanted => sub {
        my $file = $_;
        return
          if -d;
        return
          unless -e;
        (my $prefix = $file) =~ s{\A\Q$in\E/?}{};
        return
          if $prefix =~ m{\A[^/]+/inc/};
        check_file( $file, "$prefix:");
      },
    }, $in);
  }
  else {
    check_file($in, "$in:");
  }
}
