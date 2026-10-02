import '../domain/transport.dart';

/// Parent-facing setup copy. Hardware-dependent lines are marked; confirm them
/// against the final firmware and industrial design before release.
abstract final class SetupCopy {
  static const powerOnTitle = 'Turn on your Zivoo';
  static const powerOnBody =
      'Press the button on the base until the light comes on.'; // CONFIRM WITH HARDWARE

  static const setupModeTitle = 'Put Zivoo in setup mode';
  static const setupModeBody =
      'Hold the leaf button for 5 seconds, until the light pulses slowly.'; // CONFIRM WITH HARDWARE

  static const bluetoothTitle = 'Allow Bluetooth';
  static const bluetoothBody =
      'Your phone uses Bluetooth to find Zivoo nearby and pass on your Wi-Fi details. '
      'It is only used during setup.';

  static const scanTitle = 'Scan the setup code';
  static const scanBody = "You'll find it on the card in the box and inside the battery door.";

  static const wifiTitle = 'Choose your home Wi-Fi';
  static const wifiBody = 'These are the networks Zivoo can see.';
  static const wifi24 =
      'Zivoo works with 2.4 GHz Wi-Fi. If your network is missing, check that '
      '2.4 GHz is turned on in your router settings.';

  static String failureTitle(ProvisioningFailure f) => switch (f) {
    ProvisioningFailure.bluetoothOff => 'Bluetooth is off',
    ProvisioningFailure.bluetoothDenied => 'Bluetooth permission is needed',
    ProvisioningFailure.notFound => "We couldn't find your Zivoo",
    ProvisioningFailure.secureSessionFailed => "We couldn't connect to Zivoo",
    ProvisioningFailure.timeout => 'This is taking longer than expected',
    ProvisioningFailure.wifiScanFailed => "Zivoo couldn't look for Wi-Fi",
    ProvisioningFailure.wrongPassword => "That password didn't work",
    ProvisioningFailure.networkNotFound => "Zivoo can't see that network",
    ProvisioningFailure.wifiFailed => "Zivoo couldn't join your Wi-Fi",
    ProvisioningFailure.claimRejected => "We couldn't add Zivoo to your account",
    ProvisioningFailure.ownedElsewhere => 'This Zivoo belongs to another account',
    ProvisioningFailure.claimExpired => 'Setup took too long',
    ProvisioningFailure.cloudUnreachable => "Zivoo is on Wi-Fi but can't reach us",
    ProvisioningFailure.greetingFailed => "We didn't hear back from Zivoo",
    ProvisioningFailure.backendOffline => "You're offline",
    ProvisioningFailure.invalidCode => "That code doesn't match",
  };

  static String failureBody(ProvisioningFailure f) => switch (f) {
    ProvisioningFailure.bluetoothOff => 'Turn on Bluetooth in your phone settings, then try again.',
    ProvisioningFailure.bluetoothDenied =>
      'Open Settings and allow Bluetooth for Zivoo. It is only used during setup.',
    ProvisioningFailure.notFound =>
      'Keep your phone close to Zivoo and check the light is pulsing slowly. '
          'If it stopped, hold the leaf button again.',
    ProvisioningFailure.secureSessionFailed =>
      'Make sure you scanned the code for this Zivoo, then try again.',
    ProvisioningFailure.timeout => 'Keep your phone close to Zivoo and try again.',
    ProvisioningFailure.wifiScanFailed => 'Try again in a moment.',
    ProvisioningFailure.wrongPassword => 'Check the password and try again. Passwords are case-sensitive.',
    ProvisioningFailure.networkNotFound =>
      'Move Zivoo closer to your router, or check the network uses 2.4 GHz.',
    ProvisioningFailure.wifiFailed => 'Move Zivoo closer to your router and check the network uses 2.4 GHz.',
    ProvisioningFailure.claimRejected => 'Try again. If it keeps happening, contact support.',
    ProvisioningFailure.ownedElsewhere =>
      "Ask the person who set it up to remove it in their app, or factory reset Zivoo "
          "by holding the leaf and base buttons for 15 seconds.", // CONFIRM WITH HARDWARE
    ProvisioningFailure.claimExpired => 'Put Zivoo back into setup mode and start again.',
    ProvisioningFailure.cloudUnreachable => 'Check your internet connection is working, then try again.',
    ProvisioningFailure.greetingFailed => "Check Zivoo's volume and try again.",
    ProvisioningFailure.backendOffline => 'Connect your phone to the internet, then try again.',
    ProvisioningFailure.invalidCode => 'Check the code on the card and try again.',
  };
}
