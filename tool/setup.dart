// Usage (project folder ke andar):
//   dart tool/setup.dart                      -> default package: com.stacktower.game
//   dart tool/setup.dart com.apnanaam.game    -> apna package/org naam
//
// IMPORTANT: Play Store par pehli upload ke baad package naam kabhi nahi badalta.
// Isliye pehli baar chalane se pehle apna unique org naam do.
import 'dart:io';

Future<void> run(String cmd, List<String> args) async {
  stdout.writeln('\n> $cmd ${args.join(' ')}');
  final p = await Process.start(cmd, args,
      runInShell: true, mode: ProcessStartMode.inheritStdio);
  final code = await p.exitCode;
  if (code != 0) {
    stderr.writeln('FAILED (exit $code): $cmd ${args.join(' ')}');
    exit(code);
  }
}

String read(String path) => File(path).readAsStringSync();
void write(String path, String s) => File(path).writeAsStringSync(s);

Future<void> main(List<String> args) async {
  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('pubspec.yaml nahi mili. Project folder ke andar se chalao.');
    exit(1);
  }

  // Input validation: org naam shell command me jaata hai, isliye sirf safe format allow.
  final org = args.isNotEmpty ? args[0] : 'com.stacktower.game';
  if (!RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(org)) {
    stderr.writeln('Galat org naam "$org". Example: com.apnanaam.game (sirf chhote letters, digits, _ aur dots).');
    exit(1);
  }

  // Backup: flutter create kisi bhi wajah se humari files na badle.
  final backup = <String, String>{
    for (final f in ['pubspec.yaml', 'lib/main.dart', 'lib/ads.dart'])
      f: read(f),
  };

  await run('flutter', [
    'create', '--platforms=android', '--org', org,
    '--project-name', 'stack_tower', '.'
  ]);

  backup.forEach((path, original) {
    if (read(path) != original) {
      write(path, original);
      stdout.writeln('Restored $path');
    }
  });

  final t = File('test/widget_test.dart');
  if (t.existsSync()) t.deleteSync();

  await run('flutter', ['pub', 'add', 'shared_preferences', 'google_mobile_ads']);
  await run('flutter', ['pub', 'add', '--dev', 'flutter_launcher_icons', 'flutter_lints']);

  // ---- AndroidManifest ----
  const manifestPath = 'android/app/src/main/AndroidManifest.xml';
  var m = read(manifestPath);
  if (!m.contains('android.permission.INTERNET')) {
    m = m.replaceFirst('<application',
        '<uses-permission android:name="android.permission.INTERNET"/>\n    <application');
  }
  if (!m.contains('android:allowBackup')) {
    m = m.replaceFirst('<application', '<application\n        android:allowBackup="false"');
  }
  if (!m.contains('com.google.android.gms.ads.APPLICATION_ID')) {
    m = m.replaceFirst('</application>',
        '''    <!-- TEST AdMob App ID. Play Store se pehle apni real App ID daalo -->
        <meta-data
            android:name="com.google.android.gms.ads.APPLICATION_ID"
            android:value="ca-app-pub-3940256099942544~3347511713"/>
    </application>''');
  }
  m = m.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Stack Tower"');
  write(manifestPath, m);
  stdout.writeln('AndroidManifest patched.');

  // ---- Gradle (kts ya groovy) ----
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  if (kts.existsSync()) {
    var g = kts.readAsStringSync();
    g = g.replaceAll('flutter.minSdkVersion', 'maxOf(23, flutter.minSdkVersion)');
    if (!g.contains('keystoreProperties')) {
      g = 'import java.util.Properties\nimport java.io.FileInputStream\n\n$g';
      g = g.replaceFirst(RegExp(r'^android \{', multiLine: true), r'''val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
''');
      if (g.contains('signingConfigs.getByName("debug")')) {
        g = g.replaceAll('signingConfigs.getByName("debug")',
            'if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")');
      } else {
        stdout.writeln('NOTE: release signingConfig manually set karo (PLAYSTORE_GUIDE.md dekho).');
      }
    }
    kts.writeAsStringSync(g);
    stdout.writeln('build.gradle.kts patched.');
  } else if (groovy.existsSync()) {
    var g = groovy.readAsStringSync();
    g = g.replaceAll('flutter.minSdkVersion', 'Math.max(23, flutter.minSdkVersion)');
    if (!g.contains('keystoreProperties')) {
      g = g.replaceFirst(RegExp(r'^android \{', multiLine: true), r'''def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
''');
      if (g.contains('signingConfigs.debug')) {
        g = g.replaceAll('signingConfigs.debug',
            'keystorePropertiesFile.exists() ? signingConfigs.release : signingConfigs.debug');
      } else {
        stdout.writeln('NOTE: release signingConfig manually set karo (PLAYSTORE_GUIDE.md dekho).');
      }
    }
    groovy.writeAsStringSync(g);
    stdout.writeln('build.gradle patched.');
  } else {
    stderr.writeln('build.gradle nahi mili - minSdk 23 aur signing manually set karo.');
  }

  await run('dart', ['run', 'flutter_launcher_icons']);
  await run('flutter', ['pub', 'get']);

  stdout.writeln('\nSETUP DONE. Ab phone connect karke chalao:  flutter run');
}
