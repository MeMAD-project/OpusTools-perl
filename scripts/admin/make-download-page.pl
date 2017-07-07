#!/usr/bin/perl
#
#------------------------------------------------------------------------------
# TODO: save info in some kind of database that can be used to search corpora
#
#------------------------------------------------------------------------------



use CGI qw(:standard);
use FindBin qw($Bin);
use strict;
use DB_File;

use LetsMT::Lang::ISO639 qw / iso639_TwoToThree iso639_ThreeToName /;


my $indir='.';

my $UplugTools="$Bin/../public/uplug/uplug-main/tools";
my $downloaddir="$Bin/../../html";
my $annotated="$Bin/../../annotated";


# my $downloaddir='/home/opus/OPUS/html';
# my $annotated='/home/opus/OPUS/annotated';
# my $Bin="/home/opus/OPUS/tools/uplug/tools";


my $SIZE=100;                   # size for html-sample-files (in sentences)
my $MAXLANG=25;                 # max number of languages in table without
                                # a new language column/row
my $EXT='ces';                  # file extension for alignment files
                                # 'srt5' for subtitle files
my $VERSION='';

my $gzip=1;       # 1 --> everything is compressed with gzip
my $AlwaysGzip=0; # 1 --> ignore uncompressed files

while ($ARGV[0]=~/^\-/){
    my $opt=shift(@ARGV);
    if ($opt=~/^\-s/){
	$SIZE=shift(@ARGV);
    }
    if ($opt=~/^\-m/){
	$MAXLANG=shift(@ARGV);
    }
    if ($opt=~/^\-e/){
	$EXT=shift(@ARGV);
    }
    if ($opt=~/^\-g/){
	$gzip = 0;
    }
    if ($opt=~/^\-G/){
	$AlwaysGzip = 1;
    }
}
if (@ARGV){
    $indir=shift(@ARGV);
}

if (@ARGV){
    $VERSION=shift(@ARGV); # corpus version number
}

my ($CORPUS)=split(/\//,$indir);

#-------------------------------------------------------------------------



my $CES2TXT="$UplugTools/uplug-readalign";                # alignment reader
my $CESREAD="$UplugTools/uplug-readalign -h -m $SIZE";
my $CES2MOSES="$UplugTools/opus2moses.pl";
my $CES2TMX="$UplugTools/xces2tmx";

my $PACK="tar -czf";
my $RMALL="rm -fr";
my $PWD=$ENV{PWD};
binmode(STDOUT,":encoding(utf-8)");

my %bitexts;
my %lang;

#&Unpack($indir);
&GetBitexts($indir,\%lang,\%bitexts);
&store_info($CORPUS,\%lang,\%bitexts);

my $header=&HtmlHeader();
$header=~s/^.*(\<\!DOCTYPE)/$1/s;     # skip Content-Type
$header=~s/\<base href=[^\>]+\>//s;   # skip <base href="..." />
print '<?php include("count.php"); ?>',"\n";
print $header;
print &h1($CORPUS);


my %samples;
my %parsesamples;
&MakeSampleFiles(\%lang,\%bitexts,\%samples,\%parsesamples);
&PackFiles($downloaddir."/".$CORPUS,\%lang);
my $download=&DownloadTable(\%lang,\%bitexts,\%samples,\%parsesamples);
my ($total,$lang)=&Statistics(\%lang,\%bitexts);

print &p().$total.&p();
print &h3('Download');
if (-e "$downloaddir/$CORPUS/$CORPUS$VERSION.tar.gz"){
    print "Complete download of aligned documents (in XML): ";
    print &a({-href=>"download.php?f=$CORPUS/$CORPUS$VERSION.tar.gz"},"$CORPUS$VERSION.tar.gz");
    my $size=`du -hs $downloaddir/$CORPUS/$CORPUS$VERSION.tar.gz | cut -f1`;
    print ' (',$size,')',&br(),&p();
}
elsif (-e "$downloaddir/$CORPUS/$CORPUS$VERSION.tar"){
    print "Complete download of aligned documents (in XML): ";
    print &a({-href=>"download.php?f=$CORPUS/$CORPUS$VERSION.tar"},"$CORPUS$VERSION.tar");
    my $size=`du -hs $downloaddir/$CORPUS/$CORPUS$VERSION.tar | cut -f1`;
    print ' (',$size,')',&br(),&p();
}


print '<table><tr><td>Bottom-left triangle: download files';
print '<ul><li><i>ces</i> = sentence alignments in XCES format</li> ';
print '<li><i>leftmost column language IDs</i> = tokenized corpus files in XML</li> ';
print '<li>TMX and plain text files (Moses): see "Statistics" below</li> ';
print '<li><i>lower row language IDs</i> = parsed corpus files (if they exist)</li></ul></td>';
# print &br();
print '<td>Upper-right triangle: ';
print 'sample files <ul><li><i>view</i> = bilingual XML file samples</li> ';
print '<li><i>upper row language IDs</i> = monolingual XML file samples</li> ';
print '<li><i>rightmost column language IDs</i> = untokenized corpus files</li></ul></td></tr></table>';


print &p();
print $download.&p();
print &h3('Statistics and TMX/Moses Downloads');
print 'Number of files, tokens, and sentences per language (including non-parallel ones if they exist)'.&br();
print 'Number of sentence alignment units per language pair'.&p();
print 'Upper-right triangle: ';
print 'download translation memory files (TMX)';
print &br();
print 'Bottom-left triangle: ';
print 'download plain text files (MOSES/GIZA++)';
print &br();
print "Language ID's, first row: monolingual plain text files (tokenized)";
print &br();
print "Language ID's, first column: monolingual plain text files (untokenized)";
print $lang.&p();
print 'Note that TMX files only contain unique translation units and, therefore, the number of aligned units is smaller than for the distributions in Moses and XML format. Moses downloads include all non-empty alignment units including duplicates. Token counts for each language also include duplicate sentences and documents.'.&p();
print &HtmlEnd();



#-------------------------------------------------------------------------
# pack files into tar/zip archives
#-------------------------------------------------------------------------

sub PackFiles{
    my $dir=shift;
    my $lang=shift;

#    system "$PACK $CORPUS.tar.gz $dir";
#    system "mv $CORPUS.tar.gz $dir/";
    foreach (keys %{$lang}){
	if (-e $$lang{$_}){
	    if (not -e "$dir/$_.tar.gz"){
		print STDERR "pack $$lang{$_} into $dir/$_.tar.gz!\n";
#		system "find $$lang{$_} -name '*.xml*' | xargs tar -czf $dir/$_.tar.gz";
		system "find $$lang{$_} -name '*.xml*' > $dir/$_.files";
		system "tar -T $dir/$_.files -czf $dir/$_.tar.gz";
		system "rm -f $dir/$_.files";

#		$$lang{$_}="$dir/$_.tar.gz";
#		system "$RMALL $$lang{$_}";

	    }
	}
### parsed files, if applicable
	if (-e $annotated."/".$$lang{$_}){
	    if (not -e "$dir/$_\_parse.tar.gz"){
		print STDERR "pack $annotated/$$lang{$_} into $dir/$_\_parse.tar.gz!\n";
#		system "cd $annotated; find $$lang{$_} -name '*.xml*' | xargs tar -czf $dir/$_\_parse.tar.gz ; cd -";

		system "find $$lang{$_} -name '*.xml*' > $dir/$_.parse.files";
		system "tar -T $dir/$_.parse.files -czf $dir/$_\_parse.tar.gz";
		system "rm -f $dir/$_.parse.files";

	    }
	}
    }
}


#-------------------------------------------------------------------------
# make short sample files
# make MOSES plain text files (not aymore ....)
# make TMX files (not anymore ...)
#-------------------------------------------------------------------------

sub MakeSampleFiles{
    my $lang=shift;
    my $bitexts=shift;
    my $samples=shift;
    my $parsesamples=shift;
    foreach (keys %{$lang}){
	$$parsesamples{$_}=$downloaddir."/".$$lang{$_};
	$$parsesamples{$_}.='_parse_sample.html';
	$$lang{$_}=~/^(.+)\/(.+)$/;
	my $currcorpus=$1;
	my $currlang=$2;
	if (not -e $$parsesamples{$_}){
	    if(-d $annotated."/".$$lang{$_}){
		system "echo '<html><head></head><body><pre>' > $$parsesamples{$_}";
		if ($gzip){
		    my $find="find $annotated/$$lang{$_} -name '*ml.gz'";
		    system "$find | xargs gzip -cd | head -$SIZE | recode utf8..html >> $$parsesamples{$_}";
		}
		else{
		    my $find="find $annotated/$$lang{$_} -name '*ml'";
		    system "$find | xargs cat | head -$SIZE | recode utf8..html >>$$parsesamples{$_}";
		}
		system "echo '</pre></body></html>' >> $$parsesamples{$_}";
	    }
	}
    }
    foreach (keys %{$lang}){
	$$samples{$_}=$downloaddir."/".$$lang{$_};
#	$$samples{$_}=$$lang{$_};
	$$samples{$_}.='_sample.html';
	if (not -e $$samples{$_}){
	    system "echo '<html><head></head><body><pre>' > $$samples{$_}";
	    if ($gzip){
		my $find="find $$lang{$_} -name '*ml.gz'";
		system "$find | xargs gzip -cd | head -$SIZE | recode utf8..html >> $$samples{$_}";
	    }
	    else{
		my $find="find $$lang{$_} -name '*ml'";
		system "$find | xargs cat | head -$SIZE | recode utf8..html >>$$samples{$_}";
	    }
	    system "echo '</pre></body></html>' >> $$samples{$_}";
	}
    }
    foreach (keys %{$bitexts}){
	if (-e $$bitexts{$_}){
	    $$samples{$_}=$downloaddir."/".$$bitexts{$_};
	    $$samples{$_}=~s/\.gz$//;
	    $$samples{$_}=~s/\.${EXT}$/_sample/;
#	    $$samples{$_}=~s/\.srt[0-9]$/_sample/;  # subtitles ...
	    $$samples{$_}.='.html';
	    if (not -e $$samples{$_}){
		print STDERR "make sample files from $$bitexts{$_}!\n";
		system "$CESREAD -d $indir $$bitexts{$_} >$$samples{$_} 2> /dev/null";
		print STDERR "cesread: $CESREAD\n";
	    }
	    if (-z $$samples{$_}){delete $$samples{$_};} #check if empty file
	    else{
#		my $base = $$bitexts{$_};
		my $base = $downloaddir."/".$$bitexts{$_};
		$base=~s/\.gz$//;
		$base=~s/\.${EXT}$//;
		my $src='src';
		my $trg='trg';
		if ($base=~/(..)-(..)/){
		    ($src,$trg)=($1,$2);
		}

		##---------------
		## skip making moses files from this script ...
		##---------------

		# # moses/giza++ plain text files
		# if (! -e $base.'.txt.zip'){
		#     print STDERR "make text files from $$bitexts{$_}!\n";
		#     my $command="$CES2MOSES -d $indir -e $base.$src -f $base.$trg";
		#     if ($$bitexts{$_}=~/\.gz/){
		# 	print STDERR "gzip -cd $$bitexts{$_} | $command > /dev/null 2> /dev/null\n";
		# 	system "gzip -cd $$bitexts{$_} | $command > /dev/null 2> /dev/null";
		#     }
		#     else{
		# 	print STDERR "$command $$bitexts{$_} > /dev/null 2> /dev/null/n";
		# 	system "$command $$bitexts{$_} > /dev/null 2> /dev/null";
		#     }
		#     system "zip $base.txt.zip $base.$src $base.$trg > /dev/null 2> /dev/null";
		#     system "rm -f $base.$src $base.$trg";
		# }


		##---------------
		## skip making TMX files from this script ...
		##---------------

# 		# TMX files
# #		if (! -e $base.'.tmx.zip'){
# 		if (! -e $base.'.tmx.gz'){
# 		    print STDERR "make TMX files from $$bitexts{$_}!\n";
# 		    system "$CES2TMX -d $indir -s $src -t $trg $$bitexts{$_} >$base.tmx 2> /dev/null";
# 		    system "gzip $base.tmx > /dev/null 2> /dev/null";
# #		    system "zip $base.tmx.zip $base.tmx > /dev/null 2> /dev/null";
# #		    system "rm -f $base.tmx";
# 		}

# 		my $txtfile = $$bitexts{$_};
# 		$txtfile=~s/\.gz$//;
# 		$txtfile=~s/\.${EXT}$/.txt/;
# 		if (! -e $txtfile.'.gz'){
# 		    print STDERR "make text files from $$bitexts{$_}!\n";
# 		    system "$CES2TXT $$bitexts{$_} | gzip -c >$txtfile.gz";
# 		}
	    }
	}
    }
}

sub Unpack{
    my $indir=shift;
    opendir(DIR, $indir);
    my @files=grep { /tar\.gz/ } readdir(DIR);
    closedir DIR;
    foreach (@files){
	print STDERR "unpack $indir/$_!\n";
	system "tar -xzf $indir/$_";
    }
}



#-------------------------------------------------------------------------
# look for all bitexts
# (I should have a more standardized format to skip all these file tests)
#-------------------------------------------------------------------------


sub GetBitexts{
    my $indir=shift;
    my $lang=shift;
    my $bitexts=shift;

    opendir(DIR, $indir);
    my @files=readdir(DIR);
    closedir DIR;

    my @subdir=grep {-d "$indir/$_" } @files;
    my @algfiles=grep { /\.$EXT/ } @files;
    my %alg=();
    foreach (@algfiles){$alg{$_}=1;}

    foreach my $s (@subdir){
	foreach my $t (@subdir){
#	    if (-e "$indir/$s-$t.$EXT.gz"){
	    if (exists $alg{"$s-$t.$EXT.gz"}){
		$$lang{$s}="$indir/$s";
		$$lang{$t}="$indir/$t";
		$$bitexts{"$s-$t"}="$indir/$s-$t.$EXT.gz";
	    }
#	    elsif (-e "$indir/$s$t.$EXT.gz"){
	    elsif (exists $alg{"$s$t.$EXT.gz"}){
		$$lang{$s}="$indir/$s";
		$$lang{$t}="$indir/$t";
		$$bitexts{"$s-$t"}="$indir/$s$t.$EXT.gz";
	    }
#	    elsif (-e "$indir/$s$t.$EXT"){
	    elsif (exists $alg{"$s$t.$EXT"}){
		$gzip = 0 unless ($AlwaysGzip);     # ---> assume that everything is uncompressed!
		$$lang{$s}="$indir/$s";
		$$lang{$t}="$indir/$t";
		$$bitexts{"$s-$t"}="$indir/$s$t.$EXT";
	    }
#	    elsif (-e "$indir/$s-$t.$EXT"){
	    elsif (exists $alg{"$s-$t.$EXT"}){
		$gzip = 0 unless ($AlwaysGzip);     # ---> assume that everything is uncompressed!
		$$lang{$s}="$indir/$s";
		$$lang{$t}="$indir/$t";
		$$bitexts{"$s-$t"}="$indir/$s-$t.$EXT";
	    }
	    else{
		my $src=$s;
		my $trg=$t;
		$src=~s/^[^\_]*\_//;
		$trg=~s/^[^\_]*\_//;
#		if (-e "$indir/$s-$t.$EXT.gz"){
		if (exists $alg{"$s-$t.$EXT.gz"}){
		    $$lang{$s}="$indir/$s";
		    $$lang{$t}="$indir/$t";
		    $$bitexts{"$s-$t"}="$indir/$s-$t.$EXT.gz";
		}
#		elsif (-e "$indir/$src$trg.$EXT.gz"){
		elsif (exists $alg{"$src$trg.$EXT.gz"}){
		    $$bitexts{"$src-$trg"}="$indir/$src$trg.$EXT.gz";
		    $$lang{$src}="$indir/$s";
		    $$lang{$trg}="$indir/$t";
		}
#		elsif (-e "$indir/$src$trg.$EXT"){
		elsif (exists $alg{"$src$trg.$EXT"}){
		    $gzip = 0 unless ($AlwaysGzip);;  # ---> assume that everything is uncompressed!
		    $$bitexts{"$src-$trg"}="$indir/$src$trg.$EXT";
		    $$lang{$src}="$indir/$s";
		    $$lang{$trg}="$indir/$t";
		}
#		elsif (-e "$indir/$src-$trg.$EXT"){
		elsif (exists $alg{"$src-$trg.$EXT"}){
		    $gzip = 0 unless ($AlwaysGzip);;  # ---> assume that everything is uncompressed!
		    $$bitexts{"$src-$trg"}="$indir/$src-$trg.$EXT";
		    $$lang{$src}="$indir/$s";
		    $$lang{$trg}="$indir/$t";
		}
	    }
	}
    }
}

sub size_color{
    my $nr=shift;

    # my $avg = 50000;
    # my $good = 20*$avg;

    my $avg = 2000000;
    my $good = 20*$avg;

    my $diff = $nr-$avg;

    my $red=255;
    my $green=255;
    my $blue=255;

    if ($diff<0){
	my $change1 = int((0-$diff/$avg)**6*48);
	my $change2 = int(($diff/$avg+1)*32);
	$green-=$change1;
	$blue-=$change1+$change2;
#	$red-=$change2;
    }
    else{
	my $change1 = int(($diff/$good)**0.25*48);
	my $change2 = 0;
	if ($diff<$good){
	    $change2 = int((1-$diff/$good)*32);
	}
	$change1 = 64 if ($change1>64);
	$red-=$change1;
	$blue-=$change1+$change2;
    }
    return sprintf "#%x%x%x",$red,$green,$blue;
}

sub pretty_number{
    my $nr=shift;
    my $dec = shift || 1;

    if ($nr>1000000000){
	return sprintf "%.${dec}fG",$nr/1000000000;
    }
    if ($nr>100000){
	return sprintf "%.${dec}fM",$nr/1000000;
    }
    if ($nr>100){
	return sprintf "%.${dec}fk",$nr/1000;
    }
    return $nr;
}

sub thousands{
    my $nr=shift;
    $nr =~ s/(\d)(?=(\d{3})+(\D|$))/$1\,/g;
    return $nr;
}

#-------------------------------------------------------------------------
# compute simple statstics (token/sentence counts)
# & create HTML code with these statistics
#-------------------------------------------------------------------------

sub Statistics{
    my $lang=shift;
    my $bitexts=shift;

    my $nrLang=keys %{$lang};
    my $nrBitexts;
    my %nrTokens;
    my %nrSent;
    my %nrFiles;
    my %nrLinks;

    my @rows;
    push (@rows,&th(['language','files','tokens','sentences']));
    foreach my $t (sort keys %{$lang}){
	my $txt = $t;
	if (-e "$downloaddir/$CORPUS/mono/$CORPUS.$t.gz"){
	    $txt  = "<a rel=\"nofollow\" title='monolingual tokenized $t plain text' href=\"download.php?f=$CORPUS/mono/$CORPUS.$t.gz\">$t</a>\n";
	}
	$rows[-1].=(&th([$txt]));
   }

    foreach my $s (sort keys %{$lang}){
	my $SrcLangName = &iso639_ThreeToName(&iso639_TwoToThree($s));
	print STDERR "count statistics for $s!\n";

	($nrFiles{$s},$nrSent{$s},$nrTokens{$s}) = 
	    &LanguageStatistics($$lang{$s},$gzip);

	# # just in case the XML is not tokenized (-->count=0):
	# # taken numbers from Moses files instead ....
	# if (!$nrTokens{$s}){
	#     my ($NrLinks,$NrSrc);
	#     ($NrLinks,$NrSrc,$nrTokens{$s}) = &MosesStatistics($$bitexts{"$t-$s"});
	# }

	my $txt = $s;
	if (-e "$downloaddir/$CORPUS/mono/$CORPUS.raw.$s.gz"){
	    $txt  = "<a rel=\"nofollow\" title='monolingual untokenized $s plain text' href=\"download.php?f=$CORPUS/mono/$CORPUS.raw.$s.gz\">$s</a>\n";
	}
	push (@rows,&th([$txt]).&td([&thousands($nrFiles{$s}),
				     pretty_number($nrTokens{$s}),
				     pretty_number($nrSent{$s})]));

	$nrFiles{total}+=$nrFiles{$s};
	$nrTokens{total}+=$nrTokens{$s};
	$nrSent{total}+=$nrSent{$s};

	foreach my $t (sort keys %{$lang}){
	    my $TrgLangName = &iso639_ThreeToName(&iso639_TwoToThree($t));
	    if (-e $$bitexts{"$t-$s"}){
		$nrBitexts++;

		($nrLinks{"$s-$t"},$nrTokens{"$s-$t.$t"},$nrTokens{"$s-$t.$s"})
		    = &MosesStatistics($$bitexts{"$t-$s"});

		# links to MOSES plain text files
		if ($nrLinks{"$s-$t"}>0){
		    my $truncfilebase=$CORPUS.'/'.$t.'-'.$s;
		    my $nr = pretty_number($nrLinks{"$s-$t"});
		    my $nrWords = pretty_number($nrTokens{"$s-$t.$s"}
						+$nrTokens{"$s-$t.$t"},2);

		    my $title = "$SrcLangName-$TrgLangName (";
		    $title .= &thousands($nrLinks{"$s-$t"})." sentence pairs";
		    $title .= ", ".$nrWords." words" if $nrWords;
		    $title .= ') - Moses format';

		    $rows[-1].=&td(
			# {bgcolor=>size_color($nrLinks{"$s-$t"})},
			{bgcolor=>size_color($nrTokens{"$s-$t.$s"}
					     +$nrTokens{"$s-$t.$t"})},
			["<a rel=\"nofollow\" title='$title' href=\"download.php?f=$truncfilebase.txt.zip\">$nr</a>\n"]);
		}
		else{$rows[-1].=&td(['']);}
	    }
	    elsif (-e $$bitexts{"$s-$t"}){
		my $sample=$$bitexts{"$s-$t"};
		$sample=~s/\.gz$//;
		$sample=~s/\.${EXT}$/_sample/;
		$sample.='.html';

		($nrLinks{"$s-$t"},$nrTokens{"$s-$t.$s"},$nrTokens{"$s-$t.$t"})
		    = &TMXStatistics($$bitexts{"$s-$t"});

		# links to TMX files

		if ($nrLinks{"$s-$t"}>0){
		    my $truncfilebase=$CORPUS.'/'.$s.'-'.$t;
		    my $nr = pretty_number($nrLinks{"$s-$t"});
		    my $nrWords = pretty_number($nrTokens{"$s-$t.$s"}
						+$nrTokens{"$s-$t.$t"},2);
		    my $title = "$SrcLangName-$TrgLangName (";
		    $title .= &thousands($nrLinks{"$s-$t"})." sentence pairs";
		    $title .= ", ".$nrWords." words" if $nrWords;
		    $title .= ') - TMX format';
		    $rows[-1].=&td(
			# {bgcolor=>size_color($nrLinks{"$s-$t"})},
			{bgcolor=>size_color($nrTokens{"$s-$t.$s"}
					     +$nrTokens{"$s-$t.$t"})},
			["<a rel=\"nofollow\" title='$title' href=\"download.php?f=$truncfilebase.tmx.gz\">$nr</a>\n"]);
		}
		else{$rows[-1].=&td(['']);}
	    }
	    else{$rows[-1].=&td(['']);}
	}
    }
    my $TOTAL="$nrLang languages, ";
    if ($nrBitexts>1){ $TOTAL.= &thousands($nrBitexts)." bitexts".&br(); }
    $TOTAL.="total number of files: ".&thousands($nrFiles{total}).&br();
    if ($nrTokens{total}){
	$TOTAL.="total number of tokens: ".pretty_number($nrTokens{total},2).&br();
    }
    $TOTAL.="total number of sentence fragments: ";
    $TOTAL.=pretty_number($nrSent{total},2).&br();

    my $LANG=&table(caption(''),Tr(\@rows));
    return ($TOTAL,&div({-class=>'counts'},$LANG));

}



# count statsistics for a bitext

sub BitextStatistics{
    my $bitext = shift;
    my ($nrLinks,$nrSrcTok,$nrTrgTok,$nrFiles)=(0,0,0,0);

    my $infofile = $bitext;
    $infofile=~s/\.xml(\.gz)?/.info/;

    # read info from file if it exists
    if (-e "$infofile"){
	open F,"<$infofile";
	my $line = <F>;
	$line=~/^\s*([0-9]+)\s+([0-9]+)\s/;
	($nrLinks,$nrSrcTok)=($1,$2);
	my $line = <F>;
	$line=~/^\s*([0-9]+)\s+([0-9]+)\s/;
	($nrLinks,$nrTrgTok)=($1,$2);
	my $line = <F>;
	$line=~/^\s*([0-9]+)/;
	$nrFiles=$1;
	close F;
	return ($nrLinks,$nrSrcTok,$nrTrgTok,$nrFiles);
    }

    if (-e $bitext){
	$nrLinks=`gzip -cd  $bitext | grep '<link ' | wc -l`;
	chomp($nrLinks);
    }


    # print info to file

# #    if ($nrLinks && $nrSrcTok && $nrTrgTok){
#     if ($nrLinks){

# 	open F,">$infofile";
# 	print F "  $nrLinks  $nrSrcTok source\n";
# 	print F "  $nrLinks  $nrTrgTok target\n";
# 	close F;
#     }

    return ($nrLinks,$nrSrcTok,$nrTrgTok,$nrFiles);
}


sub TMXStatistics{
    my $bitext = shift;
    my ($nrLinks,$nrSrcTok,$nrTrgTok)=(0,0,0);

    my $infofile = $bitext;
    $infofile=~s/\.xml(\.gz)?$/.tmx.info/;

    # read info from file if it exists
    if (-e "$infofile"){
	open F,"<$infofile";
	chomp($nrLinks = <F>);
	chomp($nrSrcTok = <F>);
	chomp($nrTrgTok = <F>);
	close F;
    }
    else{ return &BitextStatistics($bitext); }
    return ($nrLinks,$nrSrcTok,$nrTrgTok);
}

sub MosesStatistics{
    my $bitext = shift;
    my ($nrLinks,$nrSrcTok,$nrTrgTok)=(0,0,0);

    my $infofile = $bitext;
    $infofile=~s/\.xml(\.gz)?$/.txt.info/;

    # read info from file if it exists
    if (-e "$infofile"){
	open F,"<$infofile";
	chomp($nrLinks = <F>);
	chomp($nrSrcTok = <F>);
	chomp($nrTrgTok = <F>);
	close F;
    }
    else{ return &BitextStatistics($bitext); }
    return ($nrLinks,$nrSrcTok,$nrTrgTok);
}



sub CESStatistics{
    my $bitext = shift;
    my ($nrFiles,$nrLinks,$nrSrcTok,$nrTrgTok)=(0,0,0,0);


    my $infofile = $bitext;
    $infofile=~s/\.xml(\.gz)?$/.info/;

    # read info from file if it exists
    if (-e "$infofile"){
	open F,"<$infofile";
	chomp($nrFiles = <F>);
	chomp($nrLinks = <F>);
	chomp($nrSrcTok = <F>);
	chomp($nrTrgTok = <F>);
	close F;
    }
    else{ 
	($nrLinks,$nrSrcTok,$nrTrgTok,$nrFiles) = &BitextStatistics($bitext);
	return ($nrFiles,$nrLinks,$nrSrcTok,$nrTrgTok);
    }
    return ($nrFiles,$nrLinks,$nrSrcTok,$nrTrgTok);
}





sub LanguageStatistics{
    my $lang=shift;
    my $gzip=shift;

    my ($nrFiles,$nrTokens,$nrSent)=(0,0,0);

    # read info from file if it exists
    if (-e "$lang.info"){
	open F,"<$lang.info";
	$nrFiles = <F>;chomp $nrFiles;
	$nrSent = <F>;chomp $nrSent;
	$nrTokens = <F>;chomp $nrTokens;
	close F;
	return ($nrFiles,$nrSent,$nrTokens);
    }

    if ($gzip){
	my $find="find $lang -name '*ml.gz'";
	$nrFiles=`$find | wc -l`;
	chomp($nrFiles);
	if ($nrFiles>0){
	    $nrTokens=`$find | xargs gzip -cd | grep '</w>' | wc -l`;
	    $nrSent=`$find | xargs gzip -cd | grep '</s>' | wc -l`;
	    chomp($nrSent);
	    chomp($nrTokens);
	}
    }
    if ((not $gzip) || (not $nrFiles>0)){
	my $find="find $lang -name '*ml'";
	$nrFiles=`$find | wc -l`;
	$nrTokens=`$find | xargs grep '</w>' | wc -l`;
	$nrSent=`$find | xargs grep '</s>' | wc -l`;
	chomp($nrFiles);
	chomp($nrSent);
	chomp($nrTokens);
    }

    # print info to file
    open F,">$lang.info";
    print F $nrFiles."\n";
    print F $nrSent."\n";
    print F $nrTokens."\n";
    close F;

    return ($nrFiles,$nrSent,$nrTokens);
}



#-------------------------------------------------------------------------
# create download table in HTML
#-------------------------------------------------------------------------

sub DownloadTable{
    my $lang=shift;
    my $bitexts=shift;
    my $samples=shift;
    my $parsesamples=shift;

    my @LANG=sort keys %{$lang};
    my $SRCCOUNT=0;
    my $TRGCOUNT=0;

    # avoid strange divisions at the end of the matrix ...
    # (try to make equal parts with max MAXLANG languages per part)
    if ($#LANG>$MAXLANG){
	my $n = int($#LANG/$MAXLANG)+1;
	$MAXLANG = int($#LANG/$n)+1;
    }

    my $HTML="<table border=\"0\" cellpadding=\"0\">\n<tr>\n<th></th>\n";

    #---------------------------------
    # first line: links to sub-dir's
    #---------------------------------
    foreach my $l (@LANG){
	$SRCCOUNT++;
	if ($SRCCOUNT>$MAXLANG){
	    $HTML.="<th></th>\n";
	    $SRCCOUNT=0;
	}
	$HTML.="<th><a rel=\"nofollow\" href=\"$indir/$l\_sample.html\">$l</a></th>\n";
    }
    $HTML.="<th></th></tr>\n";

    #---------------------------------------
    # print bitext matrix
    #---------------------------------------
    $TRGCOUNT=0;
    foreach my $i (0..$#LANG){
	$SRCCOUNT=0;
	$TRGCOUNT++;
	if ($TRGCOUNT>$MAXLANG){
	    $SRCCOUNT=0;
	    $HTML.="<tr><th></th>\n";
	    foreach my $l (@LANG){
		$SRCCOUNT++;
		if ($SRCCOUNT>$MAXLANG){
		    $HTML.="<th></th>\n";
		    $SRCCOUNT=0;
		}
		$HTML.="<th>$l</th>\n";
	    }
	    $HTML.="<th></th></tr>\n";
	    $TRGCOUNT=0;
	}
	$SRCCOUNT=0;

#	$HTML.="<tr><th><a rel=\"nofollow\" href=\"download.php?f=$CORPUS/$$lang{$LANG[$i]}.tar.gz\">$LANG[$i]</a></th>\n";
	$HTML.="<tr><th><a rel=\"nofollow\" href=\"download.php?f=$$lang{$LANG[$i]}.tar.gz\">$LANG[$i]</a></th>\n";

	foreach my $j (0..$i-1){
	    $SRCCOUNT++;
	    if ($SRCCOUNT>$MAXLANG){
		$HTML.="<th>$LANG[$i]</th>\n";
		$SRCCOUNT=0;
	    }
	    my $bitext=$$bitexts{"$LANG[$i]-$LANG[$j]"};
	    if (not defined $bitext){
		$bitext=$$bitexts{"$LANG[$j]-$LANG[$i]"};
	    }
	    if (-s $bitext){
		my $ces=$bitext;
		$ces=~s/(\/[^\/]+)$/\/xml$1/;
		my $SrcLang = 
		    &iso639_ThreeToName(&iso639_TwoToThree($LANG[$i]));
		my $TrgLang = 
		    &iso639_ThreeToName(&iso639_TwoToThree($LANG[$j]));
		my ($nrFiles,$nrLinks,$nrSrc,$nrTrg) = &CESStatistics($bitext);

		my $title="sentence alignments for '$SrcLang-$TrgLang' (";
		$title .= &thousands($nrFiles)." aligned documents, " if ($nrFiles>1);
		$title .= &pretty_number($nrLinks)." links, " if ($nrLinks);
		$title .= &pretty_number($nrSrc+$nrTrg);
		$title .= " tokens)";
		$HTML.="<td><a rel=\"nofollow\" title=\"$title\" href=\"download.php?f=$ces\">ces</a></td>\n";
	    }
	    else{$HTML.="<td></td>\n";}
	}
	$SRCCOUNT++;
	if ($SRCCOUNT>$MAXLANG){
	    $HTML.="<th>$LANG[$i]</th>\n";
	    $SRCCOUNT=0;
	}

	#----------------------------------------------
	## also allow bitexts of the same language!
	if (exists $$bitexts{"$LANG[$i]-$LANG[$i]"}){
	    my $bitext=$$bitexts{"$LANG[$i]-$LANG[$i]"};
	    my $filebase=$$samples{"$LANG[$i]-$LANG[$i]"};
	    my $truncfilebase=$filebase;
	    $truncfilebase=~s/^.+\/$CORPUS\//$CORPUS\//;
	    $filebase=~s/\_sample\.html$//;
	    $HTML.='<th>';
	    if (-s $downloaddir."/".$truncfilebase && $truncfilebase=~/$CORPUS\/../){
		my $SrcLangName = 
		    &iso639_ThreeToName(&iso639_TwoToThree($LANG[$i]));
		my $TrgLangName = $SrcLangName;
		$HTML.="<a rel=\"nofollow\" title=\"$SrcLangName-$TrgLangName (sample file)\" href=\"$truncfilebase\">v\\</a>";
	    }
	    if (-s $bitext){
		my $ces=$bitext;
		$ces=~s/(\/[^\/]+)$/\/xml$1/;
		my $SrcLang = 
		    &iso639_ThreeToName(&iso639_TwoToThree($LANG[$i]));
		my $TrgLang = $SrcLang;
		my ($nrFiles,$nrLinks,$nrSrc,$nrTrg) = &CESStatistics($bitext);
		my $title="sentence alignments for '$SrcLang-$TrgLang' (";
		$title .= &thousands($nrFiles)." aligned documents, " if ($nrFiles>1);
		$title .= &pretty_number($nrLinks)." links, " if ($nrLinks);
		$title .= &pretty_number($nrSrc+$nrTrg);
		$title .= " tokens)";
		$HTML.="<a rel=\"nofollow\" title=\"$title\" href=\"download.php?f=$ces\">c</a>\n";
	    }
	    $HTML.='</th>';
	}
	## otherwise: print just an empty table cell
	else{
#	    $HTML.="<th>$LANG[$i]</th>\n";
	    $HTML.="<th></th>\n";
	}
	#----------------------------------------------

	foreach my $j ($i+1..$#LANG){
	    $SRCCOUNT++;
	    if ($SRCCOUNT>$MAXLANG){
		$HTML.="<th>$LANG[$i]</th>\n";
		$SRCCOUNT=0;
	    }

	    my $filebase=$$samples{"$LANG[$i]-$LANG[$j]"};
	    if (not defined $filebase){
		$filebase=$$samples{"$LANG[$j]-$LANG[$i]"};
	    }
	    my $truncfilebase=$filebase;
	    $truncfilebase=~s/^.+\/$CORPUS\//$CORPUS\//;
	    $filebase=~s/\_sample\.html$//;
	    $HTML.='<td>';
	    
	    if (-s $downloaddir."/".$truncfilebase && $truncfilebase=~/$CORPUS\/../){
		my $SrcLangName = 
		    &iso639_ThreeToName(&iso639_TwoToThree($LANG[$i]));
		my $TrgLangName = 
		    &iso639_ThreeToName(&iso639_TwoToThree($LANG[$j]));
		$HTML.="<a rel=\"nofollow\" title=\"$SrcLangName-$TrgLangName (sample file)\" href=\"$truncfilebase\">view</a>";
	    }    

	    $HTML.='</td>';
	}

	# download links for untokenized corpus files
	if(-e "$downloaddir/$CORPUS/$LANG[$i].raw.tar.gz"){
	    $HTML.="<th><a rel=\"nofollow\" href=\"download.php?f=$CORPUS/$LANG[$i].raw.tar.gz\">$LANG[$i]</a></th></tr>\n";
	}
	else{
	    $HTML.="<th>$LANG[$i]</th></tr>\n";
	}

# ### old: sample files for parsed corpus files
# ### parse results, if applicable
# 	if(not defined $$parsesamples{"$LANG[$i]"}){
# 	    $HTML.="<th>$LANG[$i]</th></tr>\n";
# 	}
# 	else{
# 	    my $filebase=$$parsesamples{"$LANG[$i]"};
# 	    my $truncfilebase=$filebase;
# 	    $truncfilebase=~s/^.+\/$CORPUS\//$CORPUS\//;
# 	    $filebase=~s/\_parse_sample\.html$//;
# 	    if (-s $downloaddir."/".$truncfilebase && $truncfilebase=~/$CORPUS\/../){
# 		$HTML.="<th><a rel=\"nofollow\" href=\"$truncfilebase\">$LANG[$i]</a></th></tr>\n";
# 	    }    
# 	    else{
# 		$HTML.="<th>$LANG[$i]</th></tr>\n";
# 	    }
# 	}

    }
    
    #---------------------------------------
    # last line: links language archives
    #---------------------------------------
    $HTML.="<tr><th></th>\n";
    $SRCCOUNT=0;
    foreach my $l (@LANG){
	$SRCCOUNT++;
	if ($SRCCOUNT>$MAXLANG){
	    $HTML.="<th></th>\n";
	    $SRCCOUNT=0;
	}
	#---------------------------------
	if(-d "$annotated/$$lang{$l}"){
	    $HTML.="<th><a rel=\"nofollow\" href=\"download.php?f=$$lang{$l}_parse.tar.gz\">$l</a></th>\n";
	}
	else{
	    $HTML.="<th>$l</th>\n";
	}
##	$HTML.="<th><a rel=\"nofollow\" href=\"download.php?f=$$lang{$l}.tar.gz\">$l</a></th>\n";
    }
    $HTML.="<th></th></tr>\n";

    $HTML.="</table>\n";
    return &div({-class=>'sample'},$HTML);
}


sub HtmlHeader{
    my $css="index.css";
    my $HTML=&header(-charset => 'utf-8');
    $HTML.=&start_html(-title => $CORPUS,
		       -author => 'Joerg Tiedemann',
		       -base=>'true',
		       -dtd=>1,
		       -meta=>{robots => 'NOFOLLOW'},
		       -style=>{'src'=>$css},
		       -encoding => 'utf-8');

    $HTML .= '<div class="header"><?php include("header.php"); ?></div>',"\n";
    return $HTML;
}

sub HtmlEnd{
#    my $HTML = '<script type="text/javascript">
#if (Date.parse(document.lastModified) != 0)
#            document.write('."'".'last update: '."'".' 
#                   + document.lastModified);
#</script>';
    my $HTML= '';
#    my $HTML.='OPUS, ';
#    $HTML.=&a({-href=>"http://folk.uio.no/larsnyg"},'Lars Nygaard');
#    $HTML.=' ('.&a({-href=>"http://www.hf.uio.no/tekstlab"},
#		   'The Text Laboratory').')';
#    $HTML.=' and ';
#    $HTML.=&a({-href=>"http://www.let.rug.nl/~tiedeman"},'J&ouml;rg Tiedemann');
#    $HTML.=' ('.&a({-href=>"http://www.let.ug.nl"},
#		   'Alfa-Informatica, Rijksuniversiteit Groningen').')';
    $HTML=&div({-class=>'footer'},$HTML);
    $HTML.=&end_html;
    return &hr.$HTML;
}



sub store_info{
    my $corpus = shift;
    my $lang = shift;     # hash of languages in that corpus (incl corpus name)
    my $bitexts = shift;  # hash of bitexts (xces alignment files

    tie my %LangNames,"DB_File",$downloaddir.'/LangNames.db';
    tie my %Corpora,"DB_File",$downloaddir.'/Corpora.db';
    tie my %LangPairs,"DB_File",$downloaddir.'/LangPairs.db';
    tie my %Bitexts,"DB_File",$downloaddir.'/Bitexts.db';
    tie my %Info,"DB_File",$downloaddir.'/Info.db';

    my %nrFiles=();
    my %nrSents=();
    my %nrTokens=();

    foreach my $l (keys %{$lang}){
	if (! exists $LangNames{$l}){
	    $LangNames{$l} = &iso639_ThreeToName(&iso639_TwoToThree($l));
	}
	my @corpora=split(/:/,$Corpora{$l});
	push(@corpora,$corpus) unless (grep { $_ eq $corpus } @corpora);
	$Corpora{$l}=join(":",sort @corpora) ;
	($nrFiles{$l},$nrSents{$l},$nrTokens{$l})
	    = &LanguageStatistics($$lang{$l},1);
    }
    foreach my $b (keys %{$bitexts}){
	my ($src,$trg) = split(/\-/,$b);
	my @trgs = split(/:/,$LangPairs{$src});
	push (@trgs,$trg) unless (grep { $_ eq $trg } @trgs);
	my @srcs = split(/:/,$LangPairs{$trg});
	push (@srcs,$src) unless (grep { $_ eq $src } @srcs);
	$LangPairs{$src}=join(':',sort @trgs);
	$LangPairs{$trg}=join(':',sort @srcs);
	my @corpora=split(/:/,$Bitexts{$b});
	push(@corpora,$corpus) unless (grep { $_ eq $corpus } @corpora);
	$Bitexts{$b}=join(":",sort @corpora) ;


	# database of resources!
	my @resources=();
	if (-e "$downloaddir/$corpus/$src-$trg.txt.zip"){
	    my ($MosesLinks,$MosesSrc,$MosesTrg) 
		= &MosesStatistics($$bitexts{"$src-$trg"});
	    my $descr = 'moses=';
	    $descr .= join(':',("$corpus/$src-$trg.txt.zip",
				$MosesLinks,$MosesSrc,$MosesTrg));
	    push(@resources,$descr);
	}
	if (-e "$downloaddir/$corpus/$src-$trg.tmx.gz"){
	    my ($links,$SrcToken,$TrgToken) 
		= &TMXStatistics($$bitexts{"$src-$trg"});
	    my $descr = 'tmx=';
	    $descr .= join(':',("$corpus/$src-$trg.tmx.gz",
				$links,$SrcToken,$TrgToken));
	    push(@resources,$descr);
	}
	if (-e "$downloaddir/$corpus/xml/$src-$trg.xml.gz"){
	    my ($nrFiles,$nrLinks,$nrSrc,$nrTrg) = 
		&CESStatistics($$bitexts{"$src-$trg"});
	    my $descr = 'xces=';
	    $descr .= join(':',("$corpus/xml/$src-$trg.xml.gz",
				"$corpus/$src.tar.gz",
				"$corpus/$trg.tar.gz",
				$nrFiles,$nrLinks,$nrSrc,$nrTrg));
	    push(@resources,$descr);
	}
	$Info{"$corpus/$src-$trg"}=join("+",sort @resources) ;
    }
}

