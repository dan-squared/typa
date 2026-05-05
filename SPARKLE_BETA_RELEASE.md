# Sparkle Beta Release Guide

This project already includes the core Sparkle app settings:

- `SUFeedURL`
- `SUPublicEDKey`
- sandbox entitlements for Sparkle installer communication
- `SUEnableInstallerLauncherService`

What you still need to do for each beta release is produce a new app build, host it, and publish a valid appcast entry.

## Important Notes

- Sparkle may not behave reliably when testing from inside Xcode because Sparkle's XPC services use Hardened Runtime.
- If you see errors like `Unable to obtain a task name port right`, test the built app detached from Xcode instead.
- For a beta, you can use Sparkle without Apple notarization, but users may still see macOS security warnings because the app is unsigned.

## Your Feed URL

This app is configured to read updates from:

`https://dan-squared.github.io/typa/appcast.xml`

That means your GitHub Pages site needs to publish an `appcast.xml` file at that exact path.

## What You Need On Your Machine

1. A built `Typa.app`
2. Your Sparkle private EdDSA key
3. A way to generate the appcast

If you installed Sparkle properly, use Sparkle's `generate_appcast` tool rather than writing signatures by hand.

## Beta Release Flow

### 1. Bump the app version

Update both:

- `MARKETING_VERSION`
- `CURRENT_PROJECT_VERSION`

in the Xcode project before each release.

### 2. Build the app

Build a `Release` app for `My Mac`.

Do not test update flow only from Xcode's Run action.
Test the built app outside Xcode.

### 3. Zip the app

Sparkle commonly distributes the app as a zip archive.

Example:

```bash
ditto -c -k --sequesterRsrc --keepParent Typa.app Typa-beta-0.1.1.zip
```

### 4. Put the zip somewhere public

For example:

- GitHub Releases
- GitHub Pages assets
- another stable HTTPS host

The final download URL must be public and stable.

### 5. Generate the appcast

Use Sparkle's `generate_appcast` tool against the directory containing your release archive.

Typical flow:

```bash
generate_appcast /path/to/release-folder
```

This creates an `appcast.xml` with the correct Sparkle metadata and signatures.

### 6. Publish `appcast.xml`

Upload the generated `appcast.xml` to your GitHub Pages content so it is available at:

`https://dan-squared.github.io/typa/appcast.xml`

### 7. Test the update

1. Install the older beta build in `/Applications`
2. Launch it outside Xcode
3. Choose `Check for Updates...`
4. Verify Sparkle finds the newer build

## GitHub Pages Setup

You need one of these:

- GitHub Pages publishing from the repository root
- GitHub Pages publishing from `/docs`

As long as the published site exposes:

`/appcast.xml`

the current app configuration will work.

## What To Verify Before Testing

- the app's version is newer than the currently installed version
- the archive URL in the appcast is reachable in a browser
- the archive file name matches the appcast entry
- the appcast signature was generated with the private key matching the configured `SUPublicEDKey`

## If Updates Still Fail

Check these first:

1. Appcast URL loads in browser
2. Archive URL loads in browser
3. Installed app is not being run directly from Xcode
4. Version numbers increased
5. Appcast was regenerated after the new zip was created
6. Private/public Sparkle keys actually match

## Practical Beta Advice

For daily beta updates:

- keep version numbers simple and monotonic
- use GitHub Releases for the zip asset
- use GitHub Pages for `appcast.xml`
- always test one older installed build upgrading to one newer installed build
