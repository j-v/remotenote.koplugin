# RemoteNote Plugin for KOReader

Adding annotations to your ebooks is a very useful, but typing on the on-screen keyboard of an e-ink display is cumbersome and slow. RemoteNote lets you use another device to type in notes to the passages you highlight in KOReader.

> **Note:** be aware that by default, opening RemoteNote starts a simple web server with an unsecured connection on your e-reader. It may be wise to avoid use on public networks.
> You can enable HTTPS but will be subject to limitations of self-signed certificates. See below for details.

## Supported devices

Tested working on an old Kindle Paperwhite. Your experience may vary.

## Demo

![remote-note-demo-fast](https://github.com/user-attachments/assets/0c1f2240-46a4-4116-a0e1-49f5704960e7)
## Installation

- Download the latest release and unzip it
- Copy the `remotenote.koplugin` folder to the `plugins` folder of your KOReader device

## Configuration

### Port

By default, RemoteNote runs a server on port 8089. This can be configured under the menu Tools > Remote Note > Port

### Encryption with HTTPS

> **NOTE:** Using HTTPS will ensure content is transmitted encrypted, but is still subject to the limitations of self-signed certificates such as man-in-the-middle attacks. Modern browsers will show the connect as unsecured

Generate https certificate files, for example:

```bash
openssl req -x509 -newkey rsa:4096 \
  -keyout key.pem -out cert.pem \
  -days 3650 -nodes \
  -subj "/CN=remotenote.koplugin"
```

Copy `key.pem` and `cert.pem` to the `plugins/remotenote.koplugin` directory on the device running KOReader

Enable HTTPS under the menu Tools > Remote Note > Enable HTTPS


