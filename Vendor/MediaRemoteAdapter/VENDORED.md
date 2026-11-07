# MediaRemote Adapter

Vendored from https://github.com/ungive/mediaremote-adapter at commit
`0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd` (BSD 3-Clause, see LICENSE).

Since macOS 15.4 only Apple-signed processes may read "Now Playing"
information. The adapter loads this small framework into `/usr/bin/perl`,
which is allowed to, and prints updates as JSON lines. Polka reads them in
`PolkaSystem/Media/NowPlayingAdapter.swift`.

Only the framework sources and the Perl entry script are included; the test
client is not. To update, replace `src`, `include` and `bin` with a newer
upstream revision and record the commit above.
