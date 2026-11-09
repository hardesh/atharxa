import 'package:atharxa/ui/widgets/youtube_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('YouTube ids from the common link shapes', () {
    expect(youTubeId('https://youtu.be/dQw4w9WgXcQ?si=abc'), 'dQw4w9WgXcQ');
    expect(youTubeId('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=30s'), 'dQw4w9WgXcQ');
    expect(youTubeId('https://m.youtube.com/watch?v=dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(youTubeId('https://youtube.com/shorts/aBcDeFgHiJk'), 'aBcDeFgHiJk');
    expect(youTubeId('https://www.youtube.com/embed/dQw4w9WgXcQ'), 'dQw4w9WgXcQ');
    expect(youTubeId('https://vimeo.com/123456'), isNull);
    expect(youTubeId('not a link'), isNull);
  });
}
