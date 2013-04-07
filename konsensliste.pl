#!/usr/bin/env perl

# Copyright (c) 2013 Helge Eichelberg
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
# associated documentation files (the "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the
# following conditions:
#
# The above copyright notice and this permission notice shall be included in all copies or substantial
# portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT
# LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

use strict;
use warnings;
use utf8;

use POSIX;
use LWP::Simple;

# check for command-line argument
die "\nUsage: perl konsensliste-erstellen.pl NUMBER\n\nThe (4-digit) number is to be found in the agenda's ".
  "web address query (e.g. '2656' in \nhttp://www.berlin.de/ba-lichtenberg/bvv-online/to010.asp?SILFDNR=2656).\n\n".
  "Invalid argument. Stopped"
  unless defined @ARGV && $ARGV[0] =~ m/^\d+$/;

# download website
my $html = get("http://www.berlin.de/ba-lichtenberg/bvv-online/to010.asp?SILFDNR=".$ARGV[0]);
die "Couldn't download website, stopped" unless defined $html;

# split tables in rows . this probably won't work with nested tables which we are luckily not dealing with
my @tablerows = ($html =~ m/(<tr.*?>.*?<\/tr>)/sg);

# prepare abbreviations of agenda items
my @agenda_item;
my %doc_type = ("Beschlussempfehlungen der Ausschüsse" => "BE",
  "Anträge zur Beschlussfassung" => "AzB",
  "Vorlagen zur Beschlussfassung" => "VzB",
  "Vorlagen zur Kenntnisnahme" => "VzK");

# counting the rows of the csv data file
my $row = 1;

# initializing csv data
my @csv;
push(@csv, '"Nummer","Betreff der Drucksache","Art","Ergebnis im Ältestenrat","Votum der Fraktion",'.
  '"ggf. Ausschuss benennen","FL","HE","MH","FJ","YM","Kommentar"'."\r\n");
$row++;

# looping through the agenda
foreach (@tablerows){
  # split rows into cells
  my @tablecells = ($_ =~ m/(<td.*?>.*?<\/td>)/sg);
  # ignore rows with less than 6 cells
  if(defined $tablecells[5]){
    # check for main agenda items (e.g. "Ö 42")
    if ($tablecells[0] =~ m/>Ö&nbsp;\d+</){
      # get agenda item and remove html tags
      @agenda_item = ($tablecells[3] =~ m/<td.*?>(.*)<\/td>/);
      $agenda_item[0] =~ s/<.*?>//g;
    }
    # check for documents (e.g. "DS/1337/VII")
    if ($tablecells[5] =~ m/>DS\/\d+\/\w+</){
      # get document number
      my @doc_no = ($tablecells[5] =~ m/>(DS\/\d+\/\w+)</);
      # print $doc_no[0]."\n";
      # get document url
      my @doc_url = ($tablecells[4] =~ m/name="VOLFDNR" value="(\d+)"/);
      $doc_url[0] = "http://www.berlin.de/ba-lichtenberg/bvv-online/vo020.asp?VOLFDNR=".$doc_url[0];
      # print $doc_url[0]."\n";
      # get document title and remove newline, redundant whitespace, html tags and replace " with '
      my @doc_title = ($tablecells[3] =~ m/<td.*?>(.*)<\/td>/s);
      $doc_title[0] =~ s/\n/ /g;
      $doc_title[0] =~ s/\s{2,}/ /g;
      $doc_title[0] =~ s/<.*?>//g;
      $doc_title[0] =~ s/"/'/g;
      #print $doc_title[0]."\n";
      
      # generating csv data
      if(defined $doc_type{ $agenda_item[0] }){
        push (@csv, '"=hyperlink(""'.$doc_url[0].'"",""'.$doc_no[0].'"")","'.
          $doc_title[0].'","'.$doc_type{$agenda_item[0]}.'",,"=if(countif(G'.$row.':K'.$row.
          ',""D"")>0,""Diskussion"",if(countif(G'.$row.':K'.$row.',""B"")>0,""BVV"",if(countif(G'.$row.
          ':K'.$row.',""A"")>0,""Ausschuss"",""beschließen"")))"'."\r\n");
        $row++;
      }
    }
  }
}

# preparing file name
my %number = ("I" => "01", "II" => "02", "III" => "03", "IIII" => "04", "IV" => "04", "V" => "05",
  "VI" => "06", "VII" => "07", "VIII" => "08", "VIIII" => "09", "IX" => "09", "X" => "10");
my $file;
if($html =~ m/Tagesordnung - (\d+). Sitzung in der (\w+)\. Wahlperiode/s){
  $file = "bvv-".$number{$2}."-".sprintf("%02d", $1).".csv";
}
else{
  die "Not enough information for name selection, stopped";
  # $file = "bvv-".$time."csv";
}

# write data to csv file
open(CSV, "+>:encoding(UTF-8)", $file);
foreach(@csv){
  print CSV $_;
}
close CSV;

__END__
