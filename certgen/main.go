package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"time"
)

func main() {
	// Generate in current directory based on where it's called from
	certDir, err := os.Getwd()
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error getting current directory: %v\n", err)
		os.Exit(1)
	}

	privKeyFile := filepath.Join(certDir, "key.pem")
	certFile := filepath.Join(certDir, "cert.pem")

	// Skip if they already exist
	_, errCert := os.Stat(certFile)
	_, errKey := os.Stat(privKeyFile)
	if errCert == nil && errKey == nil {
		fmt.Println("Certificates already exist. Skipping generation.")
		os.Exit(0)
	}

	fmt.Println("Generating new TLS certificates...")
	err = genAndSaveTLScert(privKeyFile, certFile)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to generate certificates: %v\n", err)
		os.Exit(1)
	}

	fmt.Println("Successfully generated cert.pem and key.pem.")
}

// genAndSaveTLScert generates an RSA 2048 TLS certificate.
// We use RSA instead of Ed25519 because the version of OpenSSL/LuaSec
// bundled with KOReader does not consistently support Ed25519 or PKCS#8.
func genAndSaveTLScert(privKeyFile, certFile string) error {
	// Generate RSA key pair (2048 bits is a good balance for constrained devices)
	privkey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return err
	}

	template := x509.Certificate{
		SerialNumber: big.NewInt(1),
		Subject: pkix.Name{
			CommonName: "RemoteNote KOReader Server",
		},
		NotBefore:             time.Now(),
		NotAfter:              time.Now().AddDate(10, 0, 0), // 10 years
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
		BasicConstraintsValid: true,
		IsCA:                  false,
		DNSNames:              []string{"localhost", "remotenote.koplugin"},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("0.0.0.0")},
	}

	certBytes, err := x509.CreateCertificate(rand.Reader, &template, &template, &privkey.PublicKey, privkey)
	if err != nil {
		return err
	}

	// Marshal RSA private key to PKCS1 format (widely supported by older OpenSSL)
	privBytes := x509.MarshalPKCS1PrivateKey(privkey)

	certPrivKeyPem := pem.EncodeToMemory(&pem.Block{
		Type:  "RSA PRIVATE KEY",
		Bytes: privBytes,
	})

	certPem := pem.EncodeToMemory(&pem.Block{
		Type:  "CERTIFICATE",
		Bytes: certBytes,
	})

	// save certificate (public, can be group-readable)
	err = os.WriteFile(certFile, certPem, 0o644)
	if err != nil {
		return err
	}

	// save private key (restricted permissions - owner only)
	err = os.WriteFile(privKeyFile, certPrivKeyPem, 0o600)
	if err != nil {
		return err
	}

	return nil
}
