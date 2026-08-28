import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pieblock_app/src/music_preview.dart';
import 'package:pieblock_core/pieblock_core.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('SoLoud 可以播放、停止整曲并切换琴键方波', (tester) async {
    final preview = SoloudMusicPreview();
    final config = MusicConfig(
      notes: const [
        MusicNote(id: 'c4', pitch: 60, startTick: 0, durationTicks: 480),
      ],
    );

    await preview.play(config, looping: true);
    expect(preview.playing, isTrue);
    await preview.stop();
    expect(preview.playing, isFalse);

    await preview.startPitch(60);
    await preview.startPitch(61);
    await preview.stopPitch();
    await preview.dispose();
  });
}
