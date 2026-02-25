# RemoteNote Plugin for KOReader

Adding annotations to your e-books is super useful, but typing on the on-screen keyboard of an e-ink display is cumbersome and slow. RemoteNote lets you use another device to type in notes to the passages you highlight in KOReader. It also allows you to remotely enter text into any text dialog natively found in KOReader.

> **Note:** be aware that by default, opening RemoteNote starts a simple web server with an unsecured connection on your e-reader. It may be wise to avoid use on public networks.
> You can enable HTTPS but will be subject to limitations of self-signed certificates. See below for details.

## Supported devices

Tested working on an old Kindle Paperwhite. Your experience may vary.

KOReader minimum version: 2025.10 - other versions may not be supported 

## Features

- **Remote Note**: Type in notes for passages you highlight within a book.
- **Remote Input**: A "Remote input" button is seamlessly injected into standard KOReader text input dialogs (e.g. search boxes, library settings), allowing you to fill them using a remote device.

## Demos
### Creating a note
![remote-note-demo-fast](https://github.com/user-attachments/assets/0c1f2240-46a4-4116-a0e1-49f5704960e7)

### Editing a review
![RemoteNote-ReviewEditDemo-White-drop](https://github.com/user-attachments/assets/86a675b3-979a-4858-8faa-0de0e7c345fc)

## Known issues

- When opening the "Edit note" dialog, the KOReader keyboard may occlude the bottom buttons of the dialog. This will be fixed with the next KOReader release with this fix [InputDialog: fix adding widget with 'use available height'
](https://github.com/koreader/koreader/pull/15010#event-22970496454). As a mitigation you can enable the "Render inline 'Remote input' button" option, described below.

## Installation

1. Download the release for your device's architecture from the [Releases](https://github.com/j-v/remotenote.koplugin/releases) page:

   | Architecture | Devices |
   | ------------ | ------- |
   | **armv7** | Kindle (all models), Kobo, reMarkable 2, PocketBook |
   | **arm64** | reMarkable Paper Pro |
   | **arm-legacy** | Kindle 3, Kindle DX, older 32-bit ARM devices |
   | **x86_64** | Emulator |

   > **Not sure?** Try `armv7` first. Use `arm-legacy` only if `armv7` doesn't work on older hardware.

2. Extract `remotenote.koplugin` to your KOReader plugins directory, for example:
   - Kindle: `/mnt/us/koreader/plugins/`
   - Kobo: `/.adds/koreader/plugins/`

## Configuration

Settings can be accessed from the Top Menu: **Tools > Remote Note**

### Port
By default, RemoteNote runs a server on port 8089. You can change this here.

### Enable HTTPS (Encryption)
> **NOTE:** Using HTTPS will ensure content is transmitted encrypted, but is still subject to the limitations of self-signed certificates such as man-in-the-middle attacks. Modern browsers will show the connection as unsecured.

When enabled, the plugin will automatically generate the required TLS certificates (`cert.pem` and `key.pem`) and use a secure connection. 

### Refresh TLS certificates
Forces the generation of new HTTPS certificates. (Only visible when HTTPS is enabled).

### Allow remote input in all text input dialogs
Toggles the injection of the Remote Input functionality globally across the KOReader UI. Requires a restart to take effect after changing. Enabled by default.

### Render inline 'Remote input' button
Toggles how the "Remote input" button looks in dialogs. If checked, it will try to place it inline with the default KOReader buttons. If unchecked, it places it in a separate row within the dialog boundary. This option may be fragile and more prone to breaking with updates to KOReader. 
