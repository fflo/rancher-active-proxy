package main

import "testing"

func TestValidators(t *testing.T) {
	ok := []string{"example.com", "a-b.example.co.uk", "*.example.com", "localhost", "xn--bcher-kva.de"}
	bad := []string{"", "-bad.com", "a..b", "bad;.com", "a b", "x{", "a.com\nlocation", "a'b.com", "a.com;rm -rf /"}
	for _, h := range ok {
		if !isHostname(h) {
			t.Errorf("expected valid hostname: %q", h)
		}
	}
	for _, h := range bad {
		if isHostname(h) {
			t.Errorf("expected invalid hostname: %q", h)
		}
	}
	for _, p := range []string{"1", "80", "65535"} {
		if !isPort(p) {
			t.Errorf("expected valid port %q", p)
		}
	}
	for _, p := range []string{"0", "65536", "8o", "", "80;"} {
		if isPort(p) {
			t.Errorf("expected invalid port %q", p)
		}
	}
	if !isSafeToken("10m") || isSafeToken("10m;") || isSafeToken("a b") || isSafeToken("") {
		t.Error("isSafeToken misbehaves")
	}
	if !isEmail("ops@example.com") || isEmail("foo") || isEmail("a@b") || isEmail("a@b.c d") {
		t.Error("isEmail misbehaves")
	}
}
