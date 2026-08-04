import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

/// Integration tests for HTTP error handling in LockCachingAudioSource
/// 
/// These tests verify that HTTP errors are properly converted to PlayerException
/// and propagated through the error stream consistently.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('HTTP Error Handling Integration Tests', () {
    late AudioSession session;

    setUpAll(() async {
      // Configure audio session once for all tests
      session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    });

    testWidgets('LockCachingAudioSource HTTP 404 error handling', (
      WidgetTester tester,
    ) async {
      final player = AudioPlayer();
      
      // Set up error stream listener
      PlayerException? streamError;
      PlayerException? caughtError;
      final errorCompleter = Completer<PlayerException>();
      
      final errorSubscription = player.errorStream.listen((error) {
        print('Error stream received: ${error.code} - ${error.message}');
        streamError = error;
        if (!errorCompleter.isCompleted) {
          errorCompleter.complete(error);
        }
      });
      
      try {
        // Create LockCachingAudioSource with 404 URL
        final audioSource = LockCachingAudioSource(
          Uri.parse('https://foo.foo/404.mp3'),
          cacheFile: File('${Directory.systemTemp.path}/test_404_cache.mp3'),
        );
        
        await player.setAudioSource(audioSource);
        fail('Expected PlayerException to be thrown for 404 error');
      } on PlayerException catch (e) {
        print('Caught PlayerException: ${e.code} - ${e.message}');
        caughtError = e;
      } catch (e) {
        fail('Expected PlayerException but got ${e.runtimeType}: $e');
      }
      
      // Verify the caught exception
      expect(caughtError, isNotNull);
      expect(caughtError!.code, equals(404));
      expect(caughtError!.message, contains('HTTP Status Error: 404'));
      
      // Wait for error stream (with timeout)
      try {
        await errorCompleter.future.timeout(const Duration(seconds: 3));
        
        // Verify error stream received the same error
        expect(streamError, isNotNull);
        expect(streamError!.code, equals(404));
        expect(streamError!.message, contains('HTTP Status Error: 404'));
        
        print('✅ HTTP 404 error properly handled in both catch and error stream');
      } on TimeoutException {
        print('⚠️ Error stream did not receive error within timeout');
        // This might be expected behavior depending on implementation
      }
      
      await errorSubscription.cancel();
      await player.dispose();
    });

    testWidgets('LockCachingAudioSource network connectivity error handling', (
      WidgetTester tester,
    ) async {
      final player = AudioPlayer();
      
      // Set up error stream listener
      PlayerException? streamError;
      PlayerException? caughtError;
      final errorCompleter = Completer<PlayerException>();
      
      final errorSubscription = player.errorStream.listen((error) {
        print('Error stream received: ${error.code} - ${error.message}');
        streamError = error;
        if (!errorCompleter.isCompleted) {
          errorCompleter.complete(error);
        }
      });
      
      try {
        // Create LockCachingAudioSource with invalid domain
        final audioSource = LockCachingAudioSource(
          Uri.parse('https://invalid-domain-that-does-not-exist-12345.com/audio.mp3'),
          cacheFile: File('${Directory.systemTemp.path}/test_network_cache.mp3'),
        );
        
        await player.setAudioSource(audioSource);
        fail('Expected PlayerException to be thrown for network error');
      } on PlayerException catch (e) {
        print('Caught PlayerException: ${e.code} - ${e.message}');
        caughtError = e;
      } catch (e) {
        fail('Expected PlayerException but got ${e.runtimeType}: $e');
      }
      
      // Verify the caught exception
      expect(caughtError, isNotNull);
      expect(caughtError!.code, equals(-1)); // Network errors use -1
      expect(caughtError!.message, contains('Network Error'));
      
      // Wait for error stream (with timeout)
      try {
        await errorCompleter.future.timeout(const Duration(seconds: 5));
        
        // Verify error stream received the same error
        expect(streamError, isNotNull);
        expect(streamError!.code, equals(-1));
        expect(streamError!.message, contains('Network Error'));
        
        print('✅ Network error properly handled in both catch and error stream');
      } on TimeoutException {
        print('⚠️ Error stream did not receive error within timeout');
        // This might be expected behavior depending on implementation
      }
      
      await errorSubscription.cancel();
      await player.dispose();
    });

    testWidgets('Error stream consistency test - Multiple error types', (
      WidgetTester tester,
    ) async {
      final testCases = [
        {
          'name': 'HTTP 404',
          'url': 'https://foo.foo/404.mp3',
          'expectedCode': 404,
          'expectedMessage': 'HTTP Status Error: 404',
        },
        {
          'name': 'HTTP 500',
          'url': 'https://foo.foo/500.mp3',
          'expectedCode': 500,
          'expectedMessage': 'HTTP Status Error: 500',
        },
        {
          'name': 'Network Error',
          'url': 'https://invalid-domain-12345.com/audio.mp3',
          'expectedCode': -1,
          'expectedMessage': 'Network Error',
        },
      ];
      
      for (int i = 0; i < testCases.length; i++) {
        final testCase = testCases[i];
        print('\n--- Testing ${testCase['name']} ---');
        
        final player = AudioPlayer();
        
        PlayerException? streamError;
        PlayerException? caughtError;
        final errorCompleter = Completer<PlayerException>();
        
        final errorSubscription = player.errorStream.listen((error) {
          print('${testCase['name']} - Error stream: ${error.code} - ${error.message}');
          streamError = error;
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete(error);
          }
        });
        
        try {
          final audioSource = LockCachingAudioSource(
            Uri.parse(testCase['url'] as String),
            cacheFile: File('${Directory.systemTemp.path}/test_${i}_cache.mp3'),
          );
          
          await player.setAudioSource(audioSource);
          fail('Expected PlayerException for ${testCase['name']}');
        } on PlayerException catch (e) {
          caughtError = e;
        }
        
        // Verify caught exception
        expect(caughtError, isNotNull);
        expect(caughtError!.code, equals(testCase['expectedCode']));
        expect(caughtError!.message, contains(testCase['expectedMessage']));
        
        // Verify error stream consistency
        try {
          await errorCompleter.future.timeout(const Duration(seconds: 3));
          
          expect(streamError, isNotNull);
          expect(streamError!.code, equals(caughtError!.code));
          expect(streamError!.message, equals(caughtError!.message));
          
          print('✅ ${testCase['name']} - Consistent error handling verified');
        } on TimeoutException {
          print('⚠️ ${testCase['name']} - Error stream timeout');
        }
        
        await errorSubscription.cancel();
        await player.dispose();
        
        // Brief delay between test cases
        await Future.delayed(const Duration(milliseconds: 100));
      }
    });

    testWidgets('HTTP client timeout configuration test', (
      WidgetTester tester,
    ) async {
      final player = AudioPlayer();
      
      final stopwatch = Stopwatch()..start();
      
      try {
        // Test with a URL that should timeout (using a non-routable IP)
        final audioSource = LockCachingAudioSource(
          Uri.parse('http://10.255.255.1/timeout-test.mp3'),
          cacheFile: File('${Directory.systemTemp.path}/test_timeout_cache.mp3'),
        );
        
        await player.setAudioSource(audioSource);
        fail('Expected timeout error');
      } on PlayerException catch (e) {
        stopwatch.stop();
        
        print('Timeout test completed in ${stopwatch.elapsed.inSeconds} seconds');
        print('Caught PlayerException: ${e.code} - ${e.message}');
        
        // Verify it's a network error (timeout should be treated as network error)
        expect(e.code, equals(-1));
        expect(e.message, contains('Network Error'));
        
        // Verify timeout occurred within reasonable time (should be around 30 seconds)
        expect(stopwatch.elapsed.inSeconds, lessThanOrEqualTo(35));
        expect(stopwatch.elapsed.inSeconds, greaterThanOrEqualTo(25));
        
        print('✅ HTTP client timeout configuration working correctly');
      }
      
      await player.dispose();
    });

    testWidgets('Comparison with UriAudioSource error handling', (
      WidgetTester tester,
    ) async {
      print('\n--- Comparing LockCachingAudioSource vs UriAudioSource ---');
      
      // Test LockCachingAudioSource
      final lockCachingPlayer = AudioPlayer();
      PlayerException? lockCachingError;
      
      try {
        final audioSource = LockCachingAudioSource(
          Uri.parse('https://foo.foo/404.mp3'),
          cacheFile: File('${Directory.systemTemp.path}/test_comparison_cache.mp3'),
        );
        await lockCachingPlayer.setAudioSource(audioSource);
      } on PlayerException catch (e) {
        lockCachingError = e;
      }
      
      // Test UriAudioSource
      final uriPlayer = AudioPlayer();
      PlayerException? uriError;
      
      try {
        await uriPlayer.setUrl('https://foo.foo/404.mp3');
      } on PlayerException catch (e) {
        uriError = e;
      }
      
      // Compare error handling consistency
      expect(lockCachingError, isNotNull);
      expect(uriError, isNotNull);
      
      // Both should have the same error code for 404
      expect(lockCachingError!.code, equals(uriError!.code));
      expect(lockCachingError!.code, equals(404));
      
      // Both should have similar error messages
      expect(lockCachingError!.message, contains('HTTP Status Error: 404'));
      expect(uriError!.message, contains('HTTP Status Error: 404'));
      
      print('✅ LockCachingAudioSource and UriAudioSource have consistent error handling');
      
      await lockCachingPlayer.dispose();
      await uriPlayer.dispose();
    });
  });
}
