#!/usr/bin/perl -w
use strict;
use File::Basename;
use Bio::SeqIO;
use Getopt::Std;
use File::Tee qw(tee);

# Search N-regions in multifasta (genomes)
# and produce a BED file with found locations
# use the knicker key file to rename contigs
#
# adapted from http://stackoverflow.com/questions/10319696
#
# Stephane Plaisance (VIB-NC+BITS) 2015/04/02; v1.01
#
# handle complex fasta headers including description
# added summary for absent / present
#
# visit our Git: https://github.com/BITS-VIB

# disable buffering to get output during long process (loop)
$|=1;

getopts('i:k:l:h');
our($opt_i, $opt_k, $opt_l, $opt_h);

my $usage="## Usage: findNregions.pl <-i fasta-file> <-k key-file to rename contigs>
# Additional optional parameters are:
# <-l minsize in bps (default to 100bps)>
# <-h to display this help>";

####################
# declare variables
####################

my $fastain = $opt_i || die $usage."\n";
my $keyfile = $opt_k || die $usage."\n";
my $minlen = $opt_l || 100;
defined($opt_h) && die $usage."\n";

# counters
our $present = 0;
our $absent = 0;
our $presentlen = 0;
our $absentlen = 0;
our $nlength = 0;

# load key-file data into hash
our %keyhash = ();
open KEYS, $keyfile or die $!;
while (<KEYS>) {
	chomp;
	next if ! ($_ =~ /^[0-9]/); # ignore header lines
	my ($CompntId, $CompntName, $CompntLength) = split "\t";
	$keyhash{$CompntName} = $CompntId;
	# debug print STDOUT "'",$CompntName,"' -> ",$CompntId,"\n";
}
close KEYS;

# open stream from BED file
my $outpath = dirname($fastain);
my $basename = basename($fastain);
(my $outbase = $basename) =~ s/\.[^.]+$//;

# include size limit and max intensity in file names
my $outfile = $outpath."/".$outbase."-".$minlen."bps_N-regions.bed";
open OUT, "> $outfile" || die $!;

# keep log copy of STDOUT (comment out if you do not have 'File::Tee' installed
tee STDOUT, '>', $outfile."_log.txt" or die $!;

# create parser for multiple fasta files
my $parser = Bio::SeqIO->new(-file => $fastain, -format => 'Fasta');

# look for $minlen N's in a row
my $motif="[N]{".$minlen.",}";
my $totcnt = 0;

############################################
# loop over records and return hits to BED #
############################################

while(my $seq_obj = $parser->next_seq()) {
	my $counter=0;

	# load id, and description into strings and merge into header
	my $seqid = $seq_obj->id;
	my $seqdesc = defined $seq_obj->desc ? $seq_obj->desc : "";
	my $seqheader = join(" ", $seqid, $seqdesc);
	$seqheader =~ s/\s+$//;

	# check if cmap has this fasta record
	if ( defined $keyhash{$seqheader}) {
		$present += 1;
		$presentlen += $seq_obj->length;
		print STDOUT "## Searching sequence $seqid for $motif\n";
		my $sequence = $seq_obj->seq();

		# scan for motif and report hits
		while ($sequence =~ m/$motif/gi) {
			$counter++;
			my $match_start = $-[0]+1; # BED is zero-based !
			my $match_end = $+[0];
			my $match_seq = $&;
			$nlength += length($&);
			# print in BED5 format when present in cmap
			print OUT join("\t", $keyhash{$seqheader}, $match_start,
				$match_end, "N-region", length($&), "+")."\n";
			}

		# end for this sequence
		print STDOUT "# found $counter matches for $seqid\n";
		$totcnt += $counter;
		} else {
		 	print STDOUT "# $seqid is absent from the cmap\n";
			$absent += 1;
			$absentlen += $seq_obj->length;
		}
	}

# close filehandle
close OUT;

# report absent maps and absent length
# reformat lengths with thousand separator
my $percentpresent = sprintf '%.1f%%', 100*$presentlen/($presentlen+$absentlen);
$presentlen =~ s/\d{1,3}(?=(\d{3})+(?!\d))/$&,/g;
$absentlen =~ s/\d{1,3}(?=(\d{3})+(?!\d))/$&,/g;
$nlength =~ s/\d{1,3}(?=(\d{3})+(?!\d))/$&,/g;

print STDOUT "\n############################# summary #############################\n";
print STDOUT "# $present fasta entries ($presentlen bps)\n";
print STDOUT "# reported a total of $totcnt N-regions of $minlen bps or more\n";
print STDOUT "# representing a cumulated N-length of $nlength bps\n";
print STDOUT "# $absent entries from the original fasta file are absent in the cmap\n";
print STDOUT "# for a total of $absentlen bps\n";
print STDOUT "# => $percentpresent of the fasta file is represented in the cmap\n";

exit 0;