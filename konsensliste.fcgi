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

use FCGI;
use POSIX;
use LWP::Simple;

my $req = FCGI::Request();
while($req->Accept() >= 0) {

  # printing some html
  print "Content-type: text/html\n\n";
  print "<!DOCTYPE html>\n";
  print "<html lang=\"de\">\n";
  print "  <head>\n";
  print "    <meta charset=\"utf-8\">\n";
  print "    <title>Konsensliste erstellen</title>\n";
  print "    <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n";
  print "    <link href=\"bootstrap.css\" rel=\"stylesheet\">\n";
  print "    <style type=\"text/css\">\n";
  print "      body {\n";
  print "        padding: 40px;\n";
  print "        text-align: center;\n";
  print "      }\n";
  print "    </style>\n";
  print "    <link href=\"bootstrap-responsive.css\" rel=\"stylesheet\">\n";
  print "  </head>\n";
  print "  <body>\n";
  print "    <div class=\"container-fluid\">\n\n";
  print "    <h1>Konsensliste erstellen</h1>\n";
  print "    <p class=\"lead\">Mithilfe dieser Seite lässt sich die Konsensliste der Piraten Lichtenberg zu".
    " den Sitzungen der Bezirksverordnetenversammlung vorbereiten.</p>\n";
  print "    <p>Als Ergebnis erhält man eine csv-Datei, die für <a href=\"http://www.editgrid.com/home\"".
    " target=\"_blank\">Editgrid</a> optimiert ist und dort direkt importiert werden kann.</p>\n\n";
  print "    <hr>\n\n";

  # checking for post requests
  if (defined $ENV{'REQUEST_METHOD'} && $ENV{'REQUEST_METHOD'} =~ /POST/i) {
    read(STDIN, my $request, $ENV{'CONTENT_LENGTH'});
    if($request =~ m/sitzung=load/){
      my $html = get('http://www.berlin.de/ba-lichtenberg/bvv-online/si018.asp?GRA=1');
      my @tablerows = ($html =~ m/(<tr.*?>.*?<\/tr>)/sg);
      my $url = "http://www.berlin.de/ba-lichtenberg/bvv-online/to010.asp?SILFDNR";
      foreach(@tablerows){
        if ($_ =~ m/(\d{2}\.\d{2}\.\d{4}).*?name="SILFDNR" value="(\d+)".*?<a.*?>(\d{1,}\. Sitzung)/s){
          print "      <form action=\"konsensliste-erstellen.fcgi\" method=\"post\">\n";
          print "        <div class=\"row-fluid\">\n";
          print "          <div class=\"span4 offset4\">\n";
          print "            <p><button class=\"btn btn-large btn-success\" type=\"submit\" name=\"SILFDNR\"".
            " value=\"".$2."\">Liste der ".$3." erstellen<br>(".$1.")</button></p>\n";
          print "          </div>\n"; #close span4
          print "        </div>\n"; # close row-fluid
          print "      </form>\n";
        }
        elsif($_ =~ m/(\d{2}\.\d{2}\.\d{4}).*?(\d{1,}\. Sitzung)/s){
          print "      <form action=\"konsensliste-erstellen.fcgi\" method=\"post\">\n";
          print "        <div class=\"row-fluid\">\n";
          print "          <div class=\"span4 offset4\">\n";
          print "            <p><button class=\"btn btn-large btn-success\" disabled>Liste der ".$2.
            " erstellen<br>(".$1.")</button></p>\n";
          print "          </div>\n"; #close span4
          print "        </div>\n"; #close row-fluid
          print "      </form>\n";
        }
      }
    }
    elsif($request =~ m/SILFDNR=(\d+)/){
      my $html = get("http://www.berlin.de/ba-lichtenberg/bvv-online/to010.asp?SILFDNR=".$1);
      die "Couldn't download website, stopped" unless defined $html;

      # split tables in rows
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
      # my $time = POSIX::strftime("%F-%H-%M", localtime);
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
      print "   <div class=\"row-fluid\">\n";
      print "	   <div class=\"span4 offset2\">\n";
      print "        <p><a href=\"".$file."\" class=\"btn btn-large btn-success\">CSV herunterladen</a></p>\n";
      print "      </div>\n"; # close span4
      print "      <form action=\"konsensliste-erstellen.fcgi\" method=\"post\">\n";
      print "        <div class=\"span4\">\n";
      print "          <p><button class=\"btn btn-large btn-success\" type=\"submit\" name=\"sitzung\"".
        " value=\"load\">Sitzung auswählen</button></p>\n";
      print "        </div>\n"; # close span4
      print "      </form>\n";
      print "	 </div>\n"; # close row-fluid
    }
  }
  else{
    # printing start page button
    print "      <form action=\"konsensliste-erstellen.fcgi\" method=\"post\">\n";
    print "        <div class=\"row-fluid\">\n";
    print "          <div class=\"span4 offset4\">\n";
    print "            <p><button class=\"btn btn-large btn-success\" type=\"submit\" name=\"sitzung\"".
      " value=\"load\">Sitzung auswählen</button></p>\n";
    print "          </div>\n"; # closing span4
    print "        </div>\n"; # closing row-fluid
    print "      </form>\n\n";
    print "      <h2>oder</h2>\n\n";

    opendir(DIR, ".") or die "Couldn't open directory, stopped";
    foreach(readdir(DIR)){
      if($_ =~ m/(bvv-(\d+)-(\d+)\.csv)/){
        print "      <div class=\"row-fluid\">\n";
        print "        <div class=\"span4 offset4\">\n";
        print "          <p><a href=\"".$1."\" class=\"btn btn-success\">CSV direkt herunterladen<br>(".
          $3.". Sitzung)</a></p>\n";
        print "        </div>\n"; # close span4
        print "      </div>\n"; # close row-fluid
      }
    }
  }

  # closing html
  print "    </div>\n"; # closing container-fluid
  print "  </body>\n";
  print "</html>\n";
}
__END__
