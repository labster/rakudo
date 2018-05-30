my enum Signal (
    |nqp::stmts(
        ( my $res  := nqp::hash ),
        ( my $iter := nqp::iterator(nqp::getsignals) ),
        nqp::while(
            $iter,
            nqp::stmts(
                ( my $p := nqp::shift($iter) ),
                nqp::bindkey($res, nqp::iterkey_s($p), nqp::abs_i(nqp::iterval($p)) )
            )
        ),
        $res
    )
);

proto sub signal($, |) {*}
multi sub signal(Signal $signal, *@signals, :$scheduler = $*SCHEDULER) {
    if @signals.grep( { !nqp::istype($_,Signal) } ).list -> @invalid {
        die "Found invalid signals: {@invalid.join(', ')}"
    }
    @signals.unshift: $signal;

    # 0: Signal not supported by host, Negative: Signal not supported by backend
    my &do-warning = -> $desc, $name, @sigs {
        warn "The following signals are not supported on this $desc ({$name}): "
             ~ "{@sigs.join(', ')}"
    };
    my %vm-sigs = nqp::getsignals();
    my ( @valid, @host-unsupported, @vm-unsupported );
    for @signals.unique {
        $_  ??  0 < %vm-sigs{$_}
                ?? @valid.push($_)
                !! @vm-unsupported.push($_)
            !! @host-unsupported.push($_)
    }
    if @host-unsupported -> @s { do-warning 'system',  $*KERNEL.name, @s }
    if @vm-unsupported   -> @s { do-warning 'backend', $*VM\   .name, @s }

    my class SignalCancellation is repr('AsyncTask') { }
    Supply.merge( @valid.map(-> $signal {
        class SignalTappable does Tappable {
            has $!scheduler;
            has $!signal;

            submethod BUILD(:$!scheduler, :$!signal) { }

            method tap(&emit, &, &, &tap) {
                my $cancellation := nqp::signal($!scheduler.queue(:hint-time-sensitive),
                    -> $signum { emit($signum) },
                    nqp::unbox_i($!signal),
                    SignalCancellation);
                my $t = Tap.new({ nqp::cancel($cancellation) });
                tap($t);
                $t;
            }

            method live(--> False) { }
            method sane(--> True) { }
            method serial(--> False) { }
        }
        Supply.new(SignalTappable.new(:$scheduler, :$signal));
    }) );
}

# vim: ft=perl6 expandtab sw=4
