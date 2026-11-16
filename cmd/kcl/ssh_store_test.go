package main

import (
	"encoding/json"
	"os"
	"os/exec"
	"reflect"
	"strings"
	"testing"
)

// Opt-in integration check: creates only dedicated software test keys, never signs.
func TestSSHSharedStoreConcurrent(t *testing.T) {
	if os.Getenv("KCL_TEST_KEYS") != "1" {
		t.Skip("requires installed KCL; creates and deletes two dedicated test keys")
	}
	host := join(home, "Applications", appName, "Contents/MacOS/KeychainCompatibilityLayer")
	list := func() []string {
		t.Helper()
		b, e := exec.Command(host, "list").Output()
		if e != nil {
			t.Fatal(e)
		}
		var v []string
		if e = json.Unmarshal(b, &v); e != nil {
			t.Fatal(e)
		}
		return v
	}
	before := list()
	type result struct {
		ID  string `json:"id"`
		err error
	}
	results := make(chan result, 2)
	for i := 0; i < 2; i++ {
		go func() {
			b, e := exec.Command(host, "ssh-create", "KCL automated concurrency test").Output()
			var v result
			if e == nil {
				e = json.Unmarshal(b, &v)
			}
			v.err = e
			results <- v
		}()
	}
	var created []string
	var failure error
	for i := 0; i < 2; i++ {
		v := <-results
		if v.err != nil {
			failure = v.err
		}
		if v.ID != "" {
			created = append(created, v.ID)
		}
	}
	defer func() {
		for _, id := range created {
			if !strings.HasPrefix(id, "ssh-rsa-") {
				t.Errorf("unexpected test ID")
				continue
			}
			if b, e := exec.Command(host, "purge", id).CombinedOutput(); e != nil {
				t.Errorf("test cleanup failed: %v %s", e, b)
			}
		}
		if after := list(); !reflect.DeepEqual(before, after) {
			t.Error("pre-test identities not preserved after cleanup")
		}
	}()
	if len(created) != 2 || created[0] == created[1] {
		t.Fatal("expected two distinct dedicated keys")
	}
	if failure != nil {
		t.Fatal(failure)
	}
	after := list()
	for _, id := range append(append([]string{}, before...), created...) {
		found := false
		for _, candidate := range after {
			if candidate == id {
				found = true
			}
		}
		if !found {
			t.Error("concurrent publication lost a key")
		}
	}
}
