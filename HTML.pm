package MIME::Lite::HTML;

# module MIME::Lite::HTML : Provide routine to transform a HTML page in 
# a MIME::Lite mail
# Copyright 2000 A.Barbet alian@alianwebserver.com.  All rights reserved.

# $Log: HTML.pm,v $
# Revision 0.7  2000/12/30 20:22:27  alian
# - Allow to send a string of text to the parse function, instead of an url
# - Add feature to put data on the fly when image are available only on memory
# - Put comments on print when buffer find url
# Ideas suggested by mtveerman@mindless.com
#
# Revision 0.6  2000/12/13 11:02:58  alian
# - Allow sup parameter for MIME-Lite in constructor
# - Add parameter for parse url to include a text file when HTML
#    is not supported by client.
#
# Revision 0.5  2000/11/13 21:36:58  Administrateur
# - Arg, forgot cariage return in fill_template :-(
#
# Revision 0.4  2000/11/12 18:52:56  Administrateur
# - Add feature of replace word in gabarit (for newsletter by example)
# - Include body background
#
# Revision 0.3  2000/10/26 22:55:46  Administrateur
# Add parsing for form (action and input image)
#
# Revision 0.2  2000/10/26 20:08:06  Administrateur
# Update remplacement of relative url

use LWP::UserAgent;
use HTML::LinkExtor;
use URI::URL;
use MIME::Lite;
use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;

@ISA = qw(Exporter);
@EXPORT = qw();
$VERSION = ('$Revision: 0.7 $ ' =~ /(\d+\.\d+)/)[0];

=head1 NAME

MIME::Lite::HTML - Provide routine to transform a HTML page in a MIME-Lite mail

=head1 SYNOPSIS

  use MIME::Lite;
  use MIME::Lite::HTML;
  
  my $mailHTML = new MIME::Lite::HTML
       From     => 'MIME-Lite@alianwebserver.com',
     To       => 'alian@jupiter',
     Subject => 'Mail in HTML with images';
     
  $MIMEmail = $mailHTML->parse('http://www.alianwebserver.com');
  $MIMEmail->send; # or for win user : $mail->send_by_smtp('smtp.fai.com');

=head1 DESCRIPTION

This module provide routine to transform a HTML page in MIME::Lite mail.
The job done is:

=over

=item *

Get the file (LWP) if needed

=item *

Parse page to find include images

=item *

Attach them to mail with adequat cid

=item *

Include external CSS,Javascript file

=item *

Replace relative url with absolute one

=back

It can be used by example in a HTML newsletter. You make a classic HTML page,
and give just url to MIME::Lite::HTML.

=head1 VERSION

$Revision: 0.7 $

=head1 METHODS

=head2 new(%hash)

Create a new instance of MIME::Lite::HTML.

%hash can have this key : [Proxy], [Debug], [HashTemplate]
Others keys are use with MIME::Lite constructor.

This MIME-Lite keys are: Bcc, Encrypted, Received, Sender, Cc, From,
References, Subject, Comments, Keywords, Reply-To To, Content-*,
Message-ID,Resent-*, X-*,Date,MIME-Version,Return-Path,
Organization

$hash{'HashTemplate'} is a reference to a hash. If present, MIME::Lite::HTML will
substitute <? $name ?> with $hash{'HashTemplate'}{'name'} when parse url to
send. $hash{'HashTemplate'} can be used too for include data for subelement. Ex:
$hash{'HashTemplate'}{'http://www.alianwebserver.com/images/sommaire.gif'}=\@data;
or $hash{'HashTemplate'}{'http://www.alianwebserver.com/script.js'}="alert("Hello world");";

When module find the image http://www.alianwebserver.com/images/sommaire.gif in buffer,
it don't get image with LWP but use data found in $hash{'HashTemplate'}.


=cut

sub new
     {
     my $class = shift;
     my $self = {};
     bless $self, $class;
     my %param = @_;

     # Agent name
     $self->{_AGENT} = new LWP::UserAgent 'MIME-Lite-HTML-0-6', 'alian@alianwebserver.com';

     # Set debug level
     if ($param{'Debug'})
          {
          $self->{_DEBUG} = 1;
          delete $param{'Debug'};
          }

     # Set proxy to use to get file
     if ($param{'Proxy'})
          {
          $self->{_AGENT}->proxy('http',$param{'Proxy'}) ;
          print "Set proxy for http : ", $param{'Proxy'},"\n" if ($self->{_DEBUG});
          delete $param{'Proxy'};
          }

     # Set hash to use with template
     if ($param{'HashTemplate'})
          {
          $param{'HashTemplate'} = ref($param{'HashTemplate'}) eq "HASH" ? $param{'HashTemplate'} : %{$param{'HashTemplate'}}; #CHANGE
          $self->{_HASH_TEMPLATE}= $param{'HashTemplate'};
          delete $param{'HashTemplate'};
          }

     # Create MIME::Lite part
     $param{'Type'}='multipart/alternative'; #related
     #$param{'Type'}='multipart/related';
     my $mail = new MIME::Lite (%param);
     $self->{_MAIL} = $mail;

     return $self;
     }

=head2 parse($html, [$url_txt], [$url_base])

Subroutine used for created HTML mail with MIME-Lite

=over

=item $html

Url of HTML file to send, can be a local file. If $url is not an
url (http or https or ftp or file or nntp), $url is used as a buffer.
Example : http://www.alianwebserver.com, file://c|/tmp/index.html
or '<img src=toto.gif>'.

=item $url_txt

Url of text part to send for person who doesn't support HTML mail.

=item $url_base

$url_base is used if $url is a buffer, for get element found in HTML buffer.

=back

Return the MIME::Lite part to send

=cut

sub parse
     {
     my($self,$url_page,$url_txt,$url1)=@_;
     my ($type,@mail,$gabarit,$gabarit_txt,$racinePage);

     if ($url_page=~/^(https?|ftp|file|nntp):\/\//)
        {
        # Get content of $url_page with LWP
        print "Get ", $url_page,"\n" if $self->{_DEBUG};
        my $req = new HTTP::Request('GET' => $url_page);
        my $res = $self->{_AGENT}->request($req);
        if (!$res->is_success) {self->set_err("$url_page n'est pas accessible");}
        else {$gabarit = $res->content;}
        $racinePage=$res->base;
        }
     else {$gabarit=$url_page;$racinePage=$url1;}

     # Get content of $url_txt with LWP if needed
     if ($url_txt)
          {
          if ($url_txt=~/^(https?|ftp|file|nntp):\/\//)
            {
            print "Get ", $url_txt,"\n" if $self->{_DEBUG};
            my $req2 = new HTTP::Request('GET' => $url_txt);
            my $res3 = $self->{_AGENT}->request($req2);
            if (!$res3->is_success) {$self->set_err("$url_txt n'est pas accessible");}
            else {$gabarit_txt = $res3->content;}
            }
          else {$gabarit_txt=$url_txt;}
          }

     # Get all images and create part for each of them
     my $analyseur = HTML::LinkExtor->new;
     $analyseur->parse($gabarit);
     my @l = $analyseur->links;

     # Include external CSS files
     $gabarit = $self->include_css($gabarit,$racinePage);

     # Include external Javascript files
     $gabarit = $self->include_javascript($gabarit,$racinePage);
     ($gabarit,@mail) = $self->input_image($gabarit,$racinePage);
     $gabarit = $self->link_form($gabarit,$racinePage);
     my (%images_read,%url_remplace);
     # Scan each part found by linkExtor
     foreach my $url (@l)
          {#print @$url,"\n";
          my $urlAbs = URI::WithBase->new($$url[2],$racinePage)->abs;
          # Replace relative href found to absolute one
          if ( ($$url[0] eq 'a')
            && ($$url[1] eq 'href')
            && ($$url[2]!~m!^http://!)
            && (!$url_remplace{$urlAbs}) )
               {
               $gabarit=~s/href="?'?$$url[2]("?|'?)/href="$urlAbs"/gim;
               print "Replace ", $$url[2]," with ",$urlAbs,"\n" if $self->{_DEBUG};
               $url_remplace{$urlAbs}=1;
               }
          # Replace images background
          elsif ($$url[1] eq 'background')
               {
               my $v ='background=\'cid:'."$urlAbs".'\'';
               $gabarit=~s/background=\"$$url[2]\"/$v/im;
               print "Get ", $urlAbs,"\n" if $self->{_DEBUG};
               my $res2 = $self->{_AGENT}->request
                    (new HTTP::Request('GET' => $urlAbs));
               # Create MIME  type
               if (lc($urlAbs)=~/gif$/) {$type = "image/gif";}
               else {$type = "image/jpg";}
               # Create part
               my $mail = new MIME::Lite
                    Data => $res2->content,
                    Encoding =>'base64';
               $mail->attr("Content-type"=>$type);
               $mail->attr('Content-ID'=>$urlAbs);
               push(@mail,$mail);
               }
          # Get only new <img src>
          next if ((lc($$url[0]) ne 'img') && (lc($$url[0]) ne 'src') || ($images_read{$urlAbs}) );
          # Create MIME type
          if (lc($urlAbs)=~/gif$/) {$type = "image/gif";}
          else {$type = "image/jpg";}
          my $buff1;
          if ($self->{_HASH_TEMPLATE}{$urlAbs})
            {
            print "Using buffer on: ", $urlAbs,"\n" if $self->{_DEBUG};
            $buff1 = ref($self->{_HASH_TEMPLATE}{$urlAbs}) eq "ARRAY" ? join "", @{$self->{_HASH_TEMPLATE}{$urlAbs}} : $self->{_HASH_TEMPLATE}{$urlAbs};
            delete $self->{_HASH_TEMPLATE}{$urlAbs};
            }
          else
            {
            # Get image
            print "Get ", $urlAbs,"\n" if $self->{_DEBUG};
            my $res2 = $self->{_AGENT}->request(new HTTP::Request('GET' => $urlAbs));
            if (!$res2->is_success) {$self->set_err("Can't get $urlAbs\n");}
            $buff1=$res2->content;
            }
          # Create part
          $images_read{$urlAbs}=1;
          my $mail = new MIME::Lite
               Data => $buff1,
               Encoding =>'base64';
          $mail->attr("Content-type"=>$type);
          $mail->attr('Content-ID'=>$urlAbs);
          push(@mail,$mail);
          }

     # Replace in HTML link with image with cid:key
     sub pattern_image {return '<img '.$_[0].'src="cid:'.URI::WithBase->new($_[1],$_[2])->abs.'"';}
     $gabarit=~s/<img([^<>]*)src=(["']?)([^"'> ]*)(["']?)/pattern_image($1,$3,$racinePage)/ieg;

     # Substitue value in template if needed
     if (scalar keys %{$self->{_HASH_TEMPLATE}}!=0)
          {$gabarit=$self->fill_template($gabarit,$self->{_HASH_TEMPLATE});}

     # Create part for HTML
     my $part = new MIME::Lite
          'Type'      =>'TEXT',
          'Data'      =>$gabarit;
     $part->attr("content-type"=> "text/html; charset=iso-8859-1");

     # Create part for text if needed
     my $part2 = new MIME::Lite
          'Type'      =>'TEXT',
          'Data'      =>$gabarit_txt if ($gabarit_txt);

     my $email = new MIME::Lite ('Type'=>'multipart/related');
     $email->attach($part);
     foreach (@mail) {$email->attach($_);} # Attach list of part

     $self->{_MAIL}->attach($part2) if ($part2);
     $self->{_MAIL}->attach($email);
     return $self->{_MAIL};
     }

=head2 include_css($gabarit,$root)

(private)

Search in HTML buffer ($gabarit) to remplace call to extern CSS file
with his content. $root is original absolute url where css file will
be found.

=cut 

sub include_css
     {     
     my ($self,$gabarit,$root)=@_;
     sub pattern_css
          {
          my ($self,$url,$milieu,$fin,$root)=@_;
          my $ur = URI::URL->new($url, $root)->abs;
          print "Include CSS file $ur\n" if $self->{_DEBUG};
          my $res2 = $self->{_AGENT}->request(new HTTP::Request('GET' => $ur));
          print "Ok file downloaded\n" if $self->{_DEBUG};
          return      '<style type="text/css">'."\n".
               '<!--'."\n".$res2->content.
               "\n-->\n</style>\n";
          }
     $gabarit=~s/<link([^<>]*?)href="?([^" ]*css)"?([^>]*)>/$self->pattern_css($2,$1,$3,$root)/iegm;     
     print "Done CSS\n" if $self->{_DEBUG};
     return $gabarit;
     }

=head2 include_javascript($gabarit,$root) 

(private)

Search in HTML buffer ($gabarit) to remplace call to extern javascript file
with his content. $root is original absolute url where javascript file will
be found.

=cut

sub include_javascript
     {
     my ($self,$gabarit,$root)=@_;
     sub pattern_js
          {
          my ($self,$url,$milieu,$fin,$root)=@_;
          my $ur = URI::URL->new($url, $root)->abs;
          print "Include Javascript file $ur\n" if $self->{_DEBUG};
          my $res2 = $self->{_AGENT}->request(new HTTP::Request('GET' => $ur));
          my $content = $res2->content;
          print "Ok file downloaded\n" if $self->{_DEBUG};
          return "\n"."<!-- $ur -->\n".
               '<script '.$milieu.$fin.">\n".
               '<!--'."\n".$content.
               "\n-->\n</script>\n";
          }
     $gabarit=~s/<script([^>]*)src="?([^" ]*js)"?([^>]*)>/$self->pattern_js($2,$1,$3,$root)/iegm;     
     print "Done Javascript\n" if $self->{_DEBUG};
     return $gabarit;
     }


=head2 input_image($gabarit,$root) 

(private)

Search in HTML buffer ($gabarit) to remplace input form image with his cid

Return final buffer and list of MIME::Lite part

=cut

sub input_image
     {
     my ($self,$gabarit,$root)=@_;     
     my @mail;
     sub pattern_input_image
          {
          my ($self,$deb,$url,$fin,$base,$ref_tab_mail)=@_;
          my $type;
          my $ur = URI::URL->new($url, $base)->abs;
          # Create MIME type
          if (lc($ur)=~/gif$/) {$type="image/gif";}
          else {$type = "image/jpg";}          
          my $res = $self->{_AGENT}->request(new HTTP::Request('GET' => $ur));
          # Create part
          my $mail = new MIME::Lite 
               Data => $res->content,
               Encoding =>'base64';
          $mail->attr("Content-type"=>$type);
          $mail->attr('Content-ID'=>$ur);     
          push(@$ref_tab_mail,$mail);
          return '<input '.$deb.' src="cid:'.$ur.'"'.$fin;
          }
     $gabarit=~s/<input([^<>]*)src="?([^"'> ]*)"?([^>]*)>/$self->pattern_input_image($1,$2,$3,$root,\@mail)/iegm;
     print "Done input image\n" if $self->{_DEBUG};
     return ($gabarit,@mail);
     }


=head2 link_form($gabarit,$root) 

(private)

Replace link to formulaire with absolute link

=cut

sub link_form
     {
     my ($self,$gabarit,$root)=@_;     
     my @mail;
     sub pattern_link_form
          {
          my ($self,$deb,$url,$fin,$base)=@_;
          my $type;
          my $ur = URI::URL->new($url, $base)->abs;
          return '<form '.$deb.' action="'.$ur.'"'.$fin.'>';
          }
     $gabarit=~s/<form([^<>]*)action="?([^"'> ]*)"?([^>]*)>/$self->pattern_link_form($1,$2,$3,$root)/iegm;
     print "Done form\n" if $self->{_DEBUG};
     return $gabarit;
     }

=head2 fill_template($masque,$vars)

 $masque : Path of template
 $vars : hash ref with keys/val to substitue

Give template with remplaced variables
Ex: if $$vars{age}=12, and $masque have

  J'ai <? $age ?> ans, 

this function give:

  J'ai 12 ans,

=cut

sub fill_template
     {
     my ($self,$masque,$vars)=@_;
     my @buf=split(/\n/,$masque);
     my $i=0;
     while (my ($n,$v)=each(%$vars))
          {
          if ($v) {map {s/<\?\s\$$n\s\?>/$v/gm} @buf;}
          else {map {s/<\?\s\$$n\s\?>//gm} @buf;}
          $i++;
          }
       return join("\n",@buf);
     }
     
=head1 Error Handling

The set_err routine is used privately. You can ask for an array of all the errors which occured inside the parse routine by
calling:

@errors = $mailHTML->errstr;

If no errors where found, it'll return undef.

=cut 
sub set_err {
my($self,$error) = @_;

my @array = @{$self->{_ERRORS}};
push @array, $error;
$self->{_ERRORS} = \@array;
return 1;

}

sub errstr {
my($self) = @_;
return @{$self->{_ERRORS}} if ($self->{_ERRORS});
}
=head1 AUTHOR

Alain BARBET alian@alianwebserver.com

=cut
