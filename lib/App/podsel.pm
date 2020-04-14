package App::podsel;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use App::CSelUtils;
use Module::Patch qw(patch_package);

our %SPEC;

our @patch_handles;
sub _patch {
    my $mod = shift;
    my $add_empty_children = shift;
    (my $mod_pm = "$mod.pm") =~ s!::!/!g;
    require $mod_pm;
    push @patch_handles, patch_package($mod, [
        ({action => 'add', sub_name => 'children', code => sub { [] }}) x !!$add_empty_children,
        {action => 'add', sub_name => 'parent'  , code => sub { $_[0]{_parent} }},
    ]);
}

sub _set_parent {
    my ($node, $parent) = @_;
    $node->{_parent} //= $parent;
    if ($node->{children} && @{ $node->{children} }) {
        for (@{ $node->{children} }) {
            _set_parent($_, $node);
        }
    }
}

$SPEC{podsel} = {
    v => 1.1,
    summary => 'Select Pod::Elemental nodes using CSel syntax',
    args => {
        %App::CSelUtils::foosel_args_common,
        transforms => {
            'x.name.is_plural' => 1,
            'x.name.singular' => 'transform',
            summary => "Apply one or more Pod::Elemental::Transform's",
            schema => [
                'array*', {
                    of=>['str*', in=>['Pod5','Nester']],
                    #'x.perl.coerce_rules' => ['From_str::comma_sep'],
                }],
            cmdline_aliases => {
                t => {},
                5 => {is_flag=>1, summary=>'Shortcut for -t Pod5 -t Nester', code=>sub { push @{ $_[0]{transforms} }, 'Pod5', 'Nester' }},
            },
            description => <<'_',

**TRANSFORMS**

First of all, by default, the "stock" Pod::Elemental parser will be generic and
often not very helpful in parsing your typical POD (Perl 5 variant) documents.
You often want to add:

    -t Pod5 -t Nester

or -5 for short, which is equivalent to the above. Except in some simple cases.
See examples below.

The following are available transforms:

* Pod5

Equivalent to this:

    Pod::Elemental::Transformer::Pod5->new->transform_node($tree);

* Nester

Equivalent to this:

    my $nester;

    $nester = Pod::Elemental::Transformer::Nester->new({
        top_selector      => Pod::Elemental::Selectors::s_command('head3'),
        content_selectors => [
            Pod::Elemental::Selectors::s_command([ qw(head4) ]),
            Pod::Elemental::Selectors::s_flat(),
        ],
    });
    $nester->new->transform_node($tree);

    $nester = Pod::Elemental::Transformer::Nester->new({
        top_selector      => Pod::Elemental::Selectors::s_command('head2'),
        content_selectors => [
            Pod::Elemental::Selectors::s_command([ qw(head3 head4) ]),
            Pod::Elemental::Selectors::s_flat(),
        ],
    });
    $nester->new->transform_node($tree);

    $nester = Pod::Elemental::Transformer::Nester->new({
        top_selector      => Pod::Elemental::Selectors::s_command('head1'),
        content_selectors => [
            Pod::Elemental::Selectors::s_command([ qw(head2 head3 head4) ]),
            Pod::Elemental::Selectors::s_flat(),
        ],
    });
    $nester->new->transform_node($tree);

**EXAMPLES**

Note: <prog:pmpath> is a CLI utility that returns the path of a locally
installed Perl module. It's distributed in <pm:App::PMUtils> distribution.

Select all head1 commands (only print the command lines and not the content):

    % podsel `pmpath strict` 'Command[command=head1]'
    =head1 NAME

    =head1 SYNOPSIS

    =head1 DESCRIPTION

    =head1 HISTORY

Select all head1 commands that contain "SYN" in them (only print the command
lines and not the content):

    % podsel `pmpath strict` 'Command[command=head1][content =~ /synopsis/i]'
    =head1 SYNOPSIS

Select all head1 commands that contain "SYN" in them (but now also print the
content; note now the use of the `Nested` class selector and the `-5` flag to
create a nested document tree instead of a flat one):

    % podsel -5 `pmpath strict` 'Nested[command=head1][content =~ /synopsis/i]'
    =head1 SYNOPSIS

        use strict;

        use strict "vars";
        use strict "refs";
        use strict "subs";

        use strict;
        no strict "vars";

List of head commands in POD of <pm:List::Util>:

    % podsel `pmpath List::Util` 'Command[command =~ /head/]'
    =head1 NAME

    =head1 SYNOPSIS

    =head1 DESCRIPTION

    =head1 LIST-REDUCTION FUNCTIONS

    =head2 reduce

    =head2 reductions

    ...

    =head1 KEY/VALUE PAIR LIST FUNCTIONS

    =head2 pairs

    =head2 unpairs

    =head2 pairkeys

    =head2 pairvalues

    ...

Only show head2 commands under certain head1 commands in POD of <pm:List::Util>.
Basically we want to list key-functions and not list-reduction functions:

    % podsel -5 `pmpath List::Util` 'Nested[command=head1][content =~ /pair/i] Nested[command=head2]' --print-method content
    pairs
    unpairs
    pairkeys
    pairvalues
    pairgrep
    pairfirst
    pairmap

_
        },
    },
};
sub podsel {
    my %podsel_args = @_;

    App::CSelUtils::foosel(
        @_,
        code_read_tree => sub {
            my $args = shift;

            my $src;
            if ($args->{file} eq '-') {
                binmode STDIN, ":encoding(utf8)";
                $src = join "", <>;
            } else {
                require File::Slurper;
                $src = File::Slurper::read_text($args->{file});
            }
            require Pod::Elemental;
            my $doc = Pod::Elemental->read_string($src);

            for my $transform (@{ $podsel_args{transforms} // [] }) {
                if ($transform eq 'Pod5') {
                    log_trace "Transforming POD with Pod5 ...";
                    require Pod::Elemental::Transformer::Pod5;
                    Pod::Elemental::Transformer::Pod5->new->transform_node($doc);
                } elsif ($transform eq 'Nester') {
                    log_trace "Transforming POD with Nester ...";
                    require Pod::Elemental::Transformer::Nester;
                    require Pod::Elemental::Selectors;
                    my $t;

                    $t = Pod::Elemental::Transformer::Nester->new({
                        top_selector      => Pod::Elemental::Selectors::s_command('head3'),
                        content_selectors => [
                            Pod::Elemental::Selectors::s_command([ qw(head4) ]),
                            Pod::Elemental::Selectors::s_flat(),
                        ],
                    });
                    $t->transform_node($doc);

                    $t = Pod::Elemental::Transformer::Nester->new({
                        top_selector      => Pod::Elemental::Selectors::s_command('head2'),
                        content_selectors => [
                            Pod::Elemental::Selectors::s_command([ qw(head3 head4) ]),
                            Pod::Elemental::Selectors::s_flat(),
                        ],
                    });
                    $t->transform_node($doc);

                    if (1) {
                        $t = Pod::Elemental::Transformer::Nester->new({
                            top_selector      => Pod::Elemental::Selectors::s_command('head1'),
                            content_selectors => [
                                Pod::Elemental::Selectors::s_command([ qw(head2 head3 head4) ]),
                                Pod::Elemental::Selectors::s_flat(),
                            ],
                        });
                        $t->transform_node($doc);
                    }

                } else {
                    die "Unknown transform '$transform'";
                }
            }

          PATCH: {
                last if @patch_handles;
                _patch('Pod::Elemental::Document', 0);
                _patch('Pod::Elemental::Element::Generic::Command', 1);
                _patch('Pod::Elemental::Element::Generic::Blank', 1);
                _patch('Pod::Elemental::Element::Generic::Text', 1);
            }

            $doc;
        }, # code_read_tree

        csel_opts => {
            class_prefixes=>[
                'Pod::Elemental::Element::Generic',
                'Pod::Elemental::Element::Pod5',
                'Pod::Elemental::Element',
                'Pod::Elemental',
            ]},

        code_transform_node_actions => sub {
            my $args = shift;

            for my $action (@{$args->{node_actions}}) {
                if ($action eq 'print' || $action eq 'print_as_string') {
                    $action = 'print_method:as_pod_string';
                } elsif ($action eq 'dump') {
                    $action = 'dump:as_pod_string';
                }
            }
        }, # code_transform_node_actions
    );
}

1;
#ABSTRACT:

=head1 SYNOPSIS


=head1 SEE ALSO
