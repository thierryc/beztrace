# Build 14 qualification and publication boundary

Companion 0.1.0/build 14 corrects the native preference persistence failure found
in the exact committed build13 archive. NSUserDefaults returns PyObjC numeric
subclasses; native_preference_value converts these to built-in numbers only at
the native UI preference boundary. Booleans and invalid strings/types remain
subject to the unchanged strict pure settings validator. Build 13 and historical
artifacts are preserved. Stable engine 0.1.1 is unchanged.

The owner authorized this fix and GitHub publication on 2026-10-05. Publish an
independent unsigned development prerelease tagged glyphs-v0.1.0-build14, without
marking it latest. This does not authorize signing/notarization, changing engine
release bytes or claiming full native qualification. Intel remains deferred.

Clean-source provenance, twice-rebuilt archive and inventory checksums, automated
test logs and exact installed/loaded native preference receipts accompany the
release as a separate qualification report. Packaged source documentation records
this procedure; the final release report records subsequently observed results.

Remaining stable gates: complete visible UI/accessibility/light-dark/alignment
and placement acceptance; fresh-host Python setup and installation lifecycle;
Intel native execution; independent companion Developer ID signing, Apple
notarization and final Gatekeeper/signed-byte qualification. The manifest remains
development-unqualified, unsigned, not-submitted with no fully qualified native
builds. Engine signing/notarization cannot qualify this plugin.
