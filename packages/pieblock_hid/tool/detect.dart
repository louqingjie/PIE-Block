import 'package:pieblock_hid/pieblock_hid.dart';

void main() {
  final count = WindowsHidTransport().countDevices();
  print('STC USB-HID devices: $count');
}
