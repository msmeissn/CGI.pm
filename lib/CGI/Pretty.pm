package CGI::Pretty;

use strict;
use if $] >= 5.019, 'deprecate';
use CGI ();

$CGI::Pretty::VERSION = '4.10';
$CGI::DefaultClass = __PACKAGE__;
$CGI::Pretty::AutoloadClass = 'CGI';
@CGI::Pretty::ISA = qw( CGI );

initialize_globals();

sub _prettyPrint {
    my $input = shift;
    return if !$$input;
    return if !$CGI::Pretty::LINEBREAK || !$CGI::Pretty::INDENT;

#    print STDERR "'", $$input, "'\n";

    foreach my $i ( @CGI::Pretty::AS_IS ) {
	if ( $$input =~ m{</$i>}si ) {
	    my ( $a, $b, $c ) = $$input =~ m{(.*)(<$i[\s/>].*?</$i>)(.*)}si;
	    next if !$b;
	    $a ||= "";
	    $c ||= "";

	    _prettyPrint( \$a ) if $a;
	    _prettyPrint( \$c ) if $c;
	    
	    $b ||= "";
	    $$input = "$a$b$c";
	    return;
	}
    }
    $$input =~ s/$CGI::Pretty::LINEBREAK/$CGI::Pretty::LINEBREAK$CGI::Pretty::INDENT/g;
}

sub comment {
    my($self,@p) = CGI::self_or_CGI(@_);

    my $s = "@p";
    $s =~ s/$CGI::Pretty::LINEBREAK/$CGI::Pretty::LINEBREAK$CGI::Pretty::INDENT/g if $CGI::Pretty::LINEBREAK; 
    
    return $self->SUPER::comment( "$CGI::Pretty::LINEBREAK$CGI::Pretty::INDENT$s$CGI::Pretty::LINEBREAK" ) . $CGI::Pretty::LINEBREAK;
}

sub _make_tag_func {
    my ($self,$tagname) = @_;

    # As Lincoln as noted, the last else clause is VERY hairy, and it
    # took me a while to figure out what I was trying to do.
    # What it does is look for tags that shouldn't be indented (e.g. PRE)
    # and makes sure that when we nest tags, those tags don't get
    # indented.
    # For an example, try print td( pre( "hello\nworld" ) );
    # If we didn't care about stuff like that, the code would be
    # MUCH simpler.  BTW: I won't claim to be a regular expression
    # guru, so if anybody wants to contribute something that would
    # be quicker, easier to read, etc, I would be more than
    # willing to put it in - Brian

    my $func = qq"
	sub $tagname {";

    $func .= q'
            shift if $_[0] && 
                    (ref($_[0]) &&
                     (substr(ref($_[0]),0,3) eq "CGI" ||
                    UNIVERSAL::isa($_[0],"CGI")));
	    my($attr) = "";
	    if (ref($_[0]) && ref($_[0]) eq "HASH") {
		my(@attr) = make_attributes(shift()||undef,1);
		$attr = " @attr" if @attr;
	    }';

    if ($tagname=~/start_(\w+)/i) {
	$func .= qq! 
            return "<\L$1\E\$attr>\$CGI::Pretty::LINEBREAK";} !;
    } elsif ($tagname=~/end_(\w+)/i) {
	$func .= qq! 
            return "<\L/$1\E>\$CGI::Pretty::LINEBREAK"; } !;
    } else {
	$func .= qq#
	    return ( \$CGI::XHTML ? "<\L$tagname\E\$attr />" : "<\L$tagname\E\$attr>" ) .
                   \$CGI::Pretty::LINEBREAK unless \@_;
	    my(\$tag,\$untag) = ("<\L$tagname\E\$attr>","</\L$tagname>\E");

            my \%ASIS = map { lc("\$_") => 1 } \@CGI::Pretty::AS_IS;
            my \@args;
            if ( \$CGI::Pretty::LINEBREAK || \$CGI::Pretty::INDENT ) {
   	      if(ref(\$_[0]) eq 'ARRAY') {
                 \@args = \@{\$_[0]}
              } else {
                  foreach (\@_) {
		      \$args[0] .= \$_;
                      \$args[0] .= \$CGI::Pretty::LINEBREAK if \$args[0] !~ /\$CGI::Pretty::LINEBREAK\$/ && 0;
                      chomp \$args[0] if exists \$ASIS{ "\L$tagname\E" };
                      
  	              \$args[0] .= \$" if \$args[0] !~ /\$CGI::Pretty::LINEBREAK\$/ && 1;
		  }
                  chop \$args[0] unless \$" eq "";
	      }
            }
            else {
              \@args = ref(\$_[0]) eq 'ARRAY' ? \@{\$_[0]} : "\@_";
            }

            my \@result;
            if ( exists \$ASIS{ "\L$tagname\E" } ) {
                \@result = map { "\$tag\$_\$untag" } \@args;
            }
	    else {
		\@result = map { 
		    chomp; 
		    my \$tmp = \$_;
		    CGI::Pretty::_prettyPrint( \\\$tmp );
                    \$tag . \$CGI::Pretty::LINEBREAK .
                    \$CGI::Pretty::INDENT . \$tmp . \$CGI::Pretty::LINEBREAK . 
                    \$untag . \$CGI::Pretty::LINEBREAK
                } \@args;
	    }
            if (\$CGI::Pretty::LINEBREAK || \$CGI::Pretty::INDENT) {
                return join ("", \@result);
            } else {
                return "\@result";
            }
	}#;
    }    

    return $func;
}

sub start_html {
    return CGI::start_html( @_ ) . $CGI::Pretty::LINEBREAK;
}

sub end_html {
    return CGI::end_html( @_ ) . $CGI::Pretty::LINEBREAK;
}

sub new {
    my $class = shift;
    my $this = $class->SUPER::new( @_ );

    if ($CGI::MOD_PERL) {
        if ($CGI::MOD_PERL == 1) {
            my $r = Apache->request;
            $r->register_cleanup(\&CGI::Pretty::_reset_globals);
        }
        else {
            my $r = Apache2::RequestUtil->request;
            $r->pool->cleanup_register(\&CGI::Pretty::_reset_globals);
        }
    }
    $class->_reset_globals if $CGI::PERLEX;

    return bless $this, $class;
}

sub initialize_globals {
    # This is the string used for indentation of tags
    $CGI::Pretty::INDENT = "\t";
    
    # This is the string used for separation between tags
    $CGI::Pretty::LINEBREAK = $/;

    # These tags are not prettify'd.
    # When this list is updated, also update the docs.
    @CGI::Pretty::AS_IS = qw( a pre code script textarea td );

    1;
}
sub _reset_globals { initialize_globals(); }

# ugly, but quick fix
sub import {
    my $self = shift;
    no strict 'refs';
    ${ "$self\::AutoloadClass" } = 'CGI';

    # This causes modules to clash.
    undef %CGI::EXPORT;
    undef %CGI::EXPORT;

    $self->_setup_symbols(@_);
    my ($callpack, $callfile, $callline) = caller;

    # To allow overriding, search through the packages
    # Till we find one in which the correct subroutine is defined.
    my @packages = ($self,@{"$self\:\:ISA"});
    foreach my $sym (keys %CGI::EXPORT) {
	my $pck;
	my $def = ${"$self\:\:AutoloadClass"} || $CGI::DefaultClass;
	foreach $pck (@packages) {
	    if (defined(&{"$pck\:\:$sym"})) {
		$def = $pck;
		last;
	    }
	}
	*{"${callpack}::$sym"} = \&{"$def\:\:$sym"};
    }
}

1;

=head1 NAME

CGI::Pretty - module to produce nicely formatted HTML code

=head1 SYNOPSIS

    use CGI::Pretty qw( :html3 );

    # Print a table with a single data element
    print table( TR( td( "foo" ) ) );

=head1 DESCRIPTION

CGI::Pretty is a module that derives from CGI.  It's sole function is to
allow users of CGI to output nicely formatted HTML code.

When using the CGI module, the following code:
    print table( TR( td( "foo" ) ) );

produces the following output:
    <TABLE><TR><TD>foo</TD></TR></TABLE>

If a user were to create a table consisting of many rows and many columns,
the resultant HTML code would be quite difficult to read since it has no
carriage returns or indentation.

CGI::Pretty fixes this problem.  What it does is add a carriage
return and indentation to the HTML code so that one can easily read
it.

    print table( TR( td( "foo" ) ) );

now produces the following output:
    <TABLE>
       <TR>
          <TD>foo</TD>
       </TR>
    </TABLE>

=head2 Recommendation for when to use CGI::Pretty

CGI::Pretty is far slower than using CGI.pm directly. A benchmark showed that
it could be about 10 times slower. Adding newlines and spaces may alter the
rendered appearance of HTML. Also, the extra newlines and spaces also make the
file size larger, making the files take longer to download.

With all those considerations, it is recommended that CGI::Pretty be used
primarily for debugging.

=head2 Tags that won't be formatted

The following tags are not formatted: <a>, <pre>, <code>, <script>, <textarea>, and <td>.
If these tags were formatted, the
user would see the extra indentation on the web browser causing the page to
look different than what would be expected.  If you wish to add more tags to
the list of tags that are not to be touched, push them onto the C<@AS_IS> array:

    push @CGI::Pretty::AS_IS,qw(XMP);

=head2 Customizing the Indenting

If you wish to have your own personal style of indenting, you can change the
C<$INDENT> variable:

    $CGI::Pretty::INDENT = "\t\t";

would cause the indents to be two tabs.

Similarly, if you wish to have more space between lines, you may change the
C<$LINEBREAK> variable:

    $CGI::Pretty::LINEBREAK = "\n\n";

would create two carriage returns between lines.

If you decide you want to use the regular CGI indenting, you can easily do 
the following:

    $CGI::Pretty::INDENT = $CGI::Pretty::LINEBREAK = "";

=head1 AUTHOR

Brian Paulsen <Brian@ThePaulsens.com>, with minor modifications by
Lincoln Stein <lstein@cshl.org> for incorporation into the CGI.pm
distribution.

Copyright 1999, Brian Paulsen.  All rights reserved.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Address bug reports and comments to: https://github.com/leejo/CGI.pm/issues

The original bug tracker can be found at: https://rt.cpan.org/Public/Dist/Display.html?Queue=CGI.pm

When sending bug reports, please provide the version of CGI.pm, the version of
Perl, the name and version of your Web server, and the name and version of the
operating system you are using.  If the problem is even remotely browser
dependent, please provide information about the affected browsers as well.

=head1 SEE ALSO

L<CGI>

=cut
