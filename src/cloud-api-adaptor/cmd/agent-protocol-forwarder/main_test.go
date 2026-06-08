package main

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/confidential-containers/cloud-api-adaptor/src/cloud-api-adaptor/cmd"
	daemon "github.com/confidential-containers/cloud-api-adaptor/src/cloud-api-adaptor/pkg/forwarder"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

const testConfigFileMode = 0o600

func setupTestConfig(t *testing.T, configContent string, extraArgs ...string) (string, func()) {
	t.Helper()

	tmpDir := t.TempDir()
	configPath := filepath.Join(tmpDir, "config.json")

	require.NoError(t, os.WriteFile(configPath, []byte(configContent), testConfigFileMode))

	oldArgs := os.Args
	os.Args = append([]string{"agent-protocol-forwarder", "-config", configPath}, extraArgs...)

	return configPath, func() { os.Args = oldArgs }
}

func TestLoad(t *testing.T) {
	t.Run("missing file", func(t *testing.T) {
		var cfg daemon.Config

		path := filepath.Join(t.TempDir(), "missing.json")
		err := load(path, &cfg)
		assert.ErrorIs(t, err, os.ErrNotExist)
		assert.Contains(t, err.Error(), "failed to open")
	})

	t.Run("invalid json", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "config.json")

		require.NoError(t, os.WriteFile(path, []byte("{invalid"), testConfigFileMode))

		var cfg daemon.Config

		err := load(path, &cfg)
		assert.ErrorContains(t, err, "failed to decode")
	})

	t.Run("valid json", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "config.json")
		content := `{
			"pod-namespace": "test-namespace",
			"pod-name": "test-pod",
			"tls-server-key": "server-key",
			"tls-server-cert": "server-cert",
			"tls-client-ca": "client-ca"
		}`

		require.NoError(t, os.WriteFile(path, []byte(content), testConfigFileMode))

		expected := daemon.Config{
			PodNamespace:  "test-namespace",
			PodName:       "test-pod",
			TLSServerKey:  "server-key",
			TLSServerCert: "server-cert",
			TLSClientCA:   "client-ca",
		}
		var cfg daemon.Config
		err := load(path, &cfg)
		assert.NoError(t, err)
		assert.Equal(t, expected, cfg)
	})
}

func TestConfigSetup(t *testing.T) {
	// Save original Exit function and restore after test
	originalExit := cmd.Exit
	defer func() { cmd.Exit = originalExit }()

	t.Run("valid config with all flags", func(t *testing.T) {
		configContent := `{
			"pod-namespace": "test-ns",
			"pod-name": "test-pod",
			"tls-server-key": "server-key",
			"tls-server-cert": "server-cert",
			"tls-client-ca": "client-ca"
		}`

		configPath, cleanup := setupTestConfig(t, configContent,
			"-listen", "127.0.0.1:8080",
			"-kata-agent-socket", "/tmp/agent.sock",
			"-pod-namespace", "/run/netns/test",
			"-host-interface", "eth0",
			"-ca-cert-file", "/tmp/ca.crt",
			"-cert-file", "/tmp/server.crt",
			"-cert-key", "/tmp/server.key",
		)
		defer cleanup()

		cfg := &Config{}

		starter, err := cfg.Setup()
		require.NoError(t, err)
		assert.NotNil(t, starter)

		// Verify config values
		assert.Equal(t, configPath, cfg.configPath)
		assert.Equal(t, "127.0.0.1:8080", cfg.listenAddr)
		assert.Equal(t, "/tmp/agent.sock", cfg.kataAgentSocketPath)
		assert.Equal(t, "/run/netns/test", cfg.podNamespace)
		assert.Equal(t, "eth0", cfg.HostInterface)
		assert.NotNil(t, cfg.tlsConfig)
		assert.Equal(t, "/tmp/ca.crt", cfg.tlsConfig.CAFile)
	})

	t.Run("config with disable-tls flag", func(t *testing.T) {
		_, cleanup := setupTestConfig(t, `{"pod-namespace": "test-ns"}`,
			"-disable-tls",
		)
		defer cleanup()

		cfg := &Config{}

		starter, err := cfg.Setup()
		require.NoError(t, err)
		assert.NotNil(t, starter)
		assert.Nil(t, cfg.tlsConfig)
	})

	t.Run("config with tls-skip-verify flag", func(t *testing.T) {
		_, cleanup := setupTestConfig(t, `{"pod-namespace": "test-ns"}`,
			"-tls-skip-verify",
		)
		defer cleanup()

		cfg := &Config{}

		starter, err := cfg.Setup()
		require.NoError(t, err)
		assert.NotNil(t, starter)
		require.NotNil(t, cfg.tlsConfig)
		assert.True(t, cfg.tlsConfig.SkipVerify)
	})

	t.Run("version flag exits with code 0", func(t *testing.T) {
		exitCode := -1
		exitCalled := false

		originalExit := cmd.Exit
		defer func() { cmd.Exit = originalExit }()

		cmd.Exit = func(code int) {
			exitCode = code
			exitCalled = true
			panic("exit called")
		}

		cfg := &Config{}

		oldArgs := os.Args
		defer func() { os.Args = oldArgs }()
		os.Args = []string{"agent-protocol-forwarder", "-version"}

		// Expect panic from our Exit override
		defer func() {
			if r := recover(); r != nil {
				// Verify it was our expected panic
				if r != "exit called" {
					// Re-panic if it's a different panic
					panic(r)
				}
			}
		}()

		_, _ = cfg.Setup()

		// Verify exit was called with code 0
		assert.True(t, exitCalled, "Expected Exit to be called")
		assert.Equal(t, 0, exitCode)
	})

	t.Run("missing config file", func(t *testing.T) {
		cfg := &Config{}

		oldArgs := os.Args
		defer func() { os.Args = oldArgs }()
		os.Args = []string{
			"agent-protocol-forwarder",
			"-config", "/nonexistent/config.json",
		}

		_, err := cfg.Setup()
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "failed to open")
	})

	t.Run("invalid config file", func(t *testing.T) {
		tmpDir := t.TempDir()
		configPath := filepath.Join(tmpDir, "config.json")

		require.NoError(t, os.WriteFile(configPath, []byte("{invalid json"), testConfigFileMode))

		cfg := &Config{}

		oldArgs := os.Args
		defer func() { os.Args = oldArgs }()
		os.Args = []string{
			"agent-protocol-forwarder",
			"-config", configPath,
		}

		_, err := cfg.Setup()
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "failed to decode")
	})

	t.Run("default values", func(t *testing.T) {
		_, cleanup := setupTestConfig(t, `{"pod-namespace": "test-ns"}`)
		defer cleanup()

		cfg := &Config{}

		starter, err := cfg.Setup()
		require.NoError(t, err)
		assert.NotNil(t, starter)

		// Check default values
		assert.Equal(t, daemon.DefaultListenAddr, cfg.listenAddr)
		assert.Equal(t, daemon.DefaultKataAgentSocketPath, cfg.kataAgentSocketPath)
		assert.Equal(t, daemon.DefaultPodNamespace, cfg.podNamespace)
	})
}

func TestConfigSetupTLSConfiguration(t *testing.T) {
	t.Run("TLS config with all cert files", func(t *testing.T) {
		_, cleanup := setupTestConfig(t, `{"pod-namespace": "test-ns"}`,
			"-ca-cert-file", "/path/to/ca.crt",
			"-cert-file", "/path/to/server.crt",
			"-cert-key", "/path/to/server.key",
		)
		defer cleanup()

		cfg := &Config{}

		starter, err := cfg.Setup()
		require.NoError(t, err)
		assert.NotNil(t, starter)
		require.NotNil(t, cfg.tlsConfig)

		assert.Equal(t, "/path/to/ca.crt", cfg.tlsConfig.CAFile)
		assert.Equal(t, "/path/to/server.crt", cfg.tlsConfig.CertFile)
		assert.Equal(t, "/path/to/server.key", cfg.tlsConfig.KeyFile)
	})

	t.Run("TLS config with partial cert files", func(t *testing.T) {
		_, cleanup := setupTestConfig(t, `{"pod-namespace": "test-ns"}`,
			"-cert-file", "/path/to/server.crt",
		)
		defer cleanup()

		cfg := &Config{}

		starter, err := cfg.Setup()
		require.NoError(t, err)
		assert.NotNil(t, starter)
		require.NotNil(t, cfg.tlsConfig)

		assert.Equal(t, "/path/to/server.crt", cfg.tlsConfig.CertFile)
	})
}

func TestLoadEdgeCases(t *testing.T) {
	t.Run("empty config file", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "config.json")

		require.NoError(t, os.WriteFile(path, []byte("{}"), testConfigFileMode))

		var cfg daemon.Config

		err := load(path, &cfg)
		assert.NoError(t, err)
	})

	t.Run("config with extra fields", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "config.json")
		content := `{
			"pod-namespace": "test-namespace",
			"extra-field": "should-be-ignored",
			"another-extra": 123
		}`

		require.NoError(t, os.WriteFile(path, []byte(content), testConfigFileMode))

		var cfg daemon.Config

		err := load(path, &cfg)
		assert.NoError(t, err)
		assert.Equal(t, "test-namespace", cfg.PodNamespace)
	})

	t.Run("config with null values", func(t *testing.T) {
		path := filepath.Join(t.TempDir(), "config.json")
		content := `{
			"pod-namespace": null,
			"pod-name": "test-pod"
		}`

		require.NoError(t, os.WriteFile(path, []byte(content), testConfigFileMode))

		var cfg daemon.Config

		err := load(path, &cfg)
		assert.NoError(t, err)
		assert.Empty(t, cfg.PodNamespace)
		assert.Equal(t, "test-pod", cfg.PodName)
	})

	t.Run("config file with wrong permissions", func(t *testing.T) {
		if os.Getuid() == 0 {
			t.Skip("skipping test when running as root")
		}

		path := filepath.Join(t.TempDir(), "config.json")
		content := `{"pod-namespace": "test"}`

		require.NoError(t, os.WriteFile(path, []byte(content), 0o000))

		var cfg daemon.Config

		err := load(path, &cfg)
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "failed to open")
	})
}

func TestConfigSetupWithDifferentInterfaces(t *testing.T) {
	t.Run("with host interface specified", func(t *testing.T) {
		_, cleanup := setupTestConfig(t, `{"pod-namespace": "test-ns"}`,
			"-host-interface", "eth1",
		)
		defer cleanup()

		cfg := &Config{}

		starter, err := cfg.Setup()
		require.NoError(t, err)
		assert.NotNil(t, starter)
		assert.Equal(t, "eth1", cfg.HostInterface)
	})

	t.Run("without host interface", func(t *testing.T) {
		_, cleanup := setupTestConfig(t, `{"pod-namespace": "test-ns"}`)
		defer cleanup()

		cfg := &Config{}

		starter, err := cfg.Setup()
		require.NoError(t, err)
		assert.NotNil(t, starter)
		assert.Empty(t, cfg.HostInterface)
	})
}
