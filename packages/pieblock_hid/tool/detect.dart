import 'package:pieblock_hid/pieblock_hid.dart';

Future<void> main() async {
  final count = await WindowsHidTransport().countDevices();
  print('STC USB-HID devices: $count');
}
