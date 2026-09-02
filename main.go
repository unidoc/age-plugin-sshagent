// Copyright 2026 The age-plugin-sshagent Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// age-plugin-sshagent is an age plugin that derives X25519 identities from
// deterministic ssh-agent signatures, so files can be decrypted with a key
// held in (and never leaving) your ssh-agent.
//
// Recipients are native age X25519 recipients (age1...), so the encrypting
// side needs only stock age — no plugin. Only the identity owner needs this
// binary, at decryption time.
package main

import (
	"fmt"
	"os"
	"runtime/debug"

	"filippo.io/age"
	"filippo.io/age/plugin"
)

// version is set at build time via -ldflags "-X main.version=...";
// defaults to "dev" so a source build is distinguishable from a
// tagged release.
var version = "dev"

func main() {
	if len(os.Args) > 1 {
		switch os.Args[1] {
		case "keygen":
			os.Exit(cmdKeygen(os.Args[2:]))
		case "list":
			os.Exit(cmdList(os.Args[2:]))
		case "recipient":
			os.Exit(cmdRecipient(os.Args[2:]))
		case "version", "--version":
			cmdVersion()
			os.Exit(0)
		case "help", "-h", "--help":
			usage()
			os.Exit(0)
		}
	} else {
		usage()
		os.Exit(2)
	}

	p, err := plugin.New(pluginName)
	if err != nil {
		os.Exit(fatalf("%v", err))
	}
	p.HandleIdentity(func(data []byte) (age.Identity, error) {
		return deriveFromPayload(data)
	})
	p.HandleIdentityAsRecipient(func(data []byte) (age.Recipient, error) {
		id, err := deriveFromPayload(data)
		if err != nil {
			return nil, err
		}
		return id.Recipient(), nil
	})
	os.Exit(p.Main())
}

func usage() {
	fmt.Fprint(os.Stderr, `Usage:
  age-plugin-sshagent keygen [-k SELECTOR] [-o FILE]
      Derive an identity from an ssh-ed25519 key in your ssh-agent.
      Prints the identity (safe to store anywhere — it contains no secrets)
      and the age1... public key to encrypt to.

  age-plugin-sshagent recipient [-i FILE]
      Re-derive and print the public key for an existing identity.

  age-plugin-sshagent list
      List ssh-agent keys and their eligibility.

  age-plugin-sshagent version
      Print binary version and build info.

Decryption happens through age itself:
  age -d -i identity.txt file.age

The ssh-agent must be running and hold the key (SSH_AUTH_SOCK).
`)
}

func cmdVersion() {
	fmt.Printf("age-plugin-sshagent %s\n", version)
	if bi, ok := debug.ReadBuildInfo(); ok {
		fmt.Printf("go:      %s\n", bi.GoVersion)
		for _, s := range bi.Settings {
			switch s.Key {
			case "vcs.revision":
				fmt.Printf("commit:  %s\n", s.Value)
			case "vcs.time":
				fmt.Printf("built:   %s\n", s.Value)
			case "vcs.modified":
				fmt.Printf("dirty:   %s\n", s.Value)
			}
		}
	}
}
