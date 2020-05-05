package DatReader;
use strict;
use warnings;
use File::Basename;
use File::Spec;
use Exporter; *import = \&Exporter::import;

our @EXPORT_OK = qw(each_dat_code);

sub each_dat_code (&;@) {
  my ($cb, @files) = @_;
  if (!@files) {
    @files = glob 't/corpus/*.dat';
  }
  for my $data_file (@files) {
    open my $fh, '<', $data_file or die "can't read $data_file: $!";
    my $code = '';
    my $last_file;
    while (my $line = <$fh>) {
      chomp $line;
      my ($file, $code_line) = split /:/, $line, 2;
      if (defined $last_file) {
        if ($file ne $last_file) {
          $cb->($last_file, $code);
          $code = '';
        }
      }
      $code .= $code_line . "\n";
      $last_file = $file;
    }
    if (defined $last_file) {
      $cb->($last_file, $code);
    }
  }
}

1;
