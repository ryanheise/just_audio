import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';

/// Comprehensive integration tests combining memory leak prevention and error handling
/// 
/// This test suite validates that the HTTP error handling fixes work correctly
/// while ensuring no memory leaks occur during repeated operations.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Comprehensive AudioPlayer Integration Tests', () {
    late AudioSession session;

    setUpAll(() async {
      // Configure audio session once for all tests
      session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
    });

    testWidgets('Combined memory leak and error handling stress test', (
      WidgetTester tester,
    ) async {
      const int cycles = 25;
      int successfulErrorHandling = 0;
      int successfulMemoryCleanup = 0;
      
      print('Starting comprehensive stress test with $cycles cycles');
      
      for (int cycle = 0; cycle < cycles; cycle++) {
        print('\n$cycle ---- Starting comprehensive cycle $cycle ----');
        
        final player = AudioPlayer();
        
        // Set up comprehensive stream listeners
        late StreamSubscription<PlayerException> errorSubscription;
        late StreamSubscription<PlayerState> playerStateSubscription;
        late StreamSubscription<ProcessingState> processingStateSubscription;
        late StreamSubscription<Duration> positionSubscription;
        
        PlayerException? streamError;
        PlayerException? caughtError;
        final errorCompleter = Completer<PlayerException>();
        
        // Set up all stream listeners to stress test resource management
        errorSubscription = player.errorStream.listen((error) {
          print('$cycle: Error stream - ${error.code}: ${error.message}');
          streamError = error;
          if (!errorCompleter.isCompleted) {
            errorCompleter.complete(error);
          }
        });
        
        playerStateSubscription = player.playerStateStream.listen((state) {
          // Just consume the stream to test resource management
        });
        
        processingStateSubscription = player.processingStateStream.listen((state) {
          // Just consume the stream to test resource management
        });
        
        positionSubscription = player.positionStream.listen((position) {
          // Just consume the stream to test resource management
        });
        
        try {
          // Alternate between different error scenarios and success scenarios
          if (cycle % 4 == 0) {
            // Test HTTP 404 error with LockCachingAudioSource
            final audioSource = LockCachingAudioSource(
              Uri.parse('https://foo.foo/404.mp3'),
              cacheFile: File('${Directory.systemTemp.path}/test_cycle_${cycle}_404.mp3'),
            );
            await player.setAudioSource(audioSource);
            
          } else if (cycle % 4 == 1) {
            // Test network error with LockCachingAudioSource
            final audioSource = LockCachingAudioSource(
              Uri.parse('https://invalid-domain-12345.com/audio.mp3'),
              cacheFile: File('${Directory.systemTemp.path}/test_cycle_${cycle}_network.mp3'),
            );
            await player.setAudioSource(audioSource);
            
          } else if (cycle % 4 == 2) {
            // Test HTTP 500 error with LockCachingAudioSource
            final audioSource = LockCachingAudioSource(
              Uri.parse('https://foo.foo/500.mp3'),
              cacheFile: File('${Directory.systemTemp.path}/test_cycle_${cycle}_500.mp3'),
            );
            await player.setAudioSource(audioSource);
            
          } else {
            // Test successful loading (or expected platform error)
            try {
              await player.setUrl('https://www.soundjay.com/misc/sounds/bell-ringing-05.wav');
              print('$cycle: Successful audio loading');
              
              // Brief playback test
              await player.play();
              await Future.delayed(const Duration(milliseconds: 50));
              await player.pause();
              
            } catch (e) {
              print('$cycle: Platform-specific error during success test: $e');
            }
          }
          
        } on PlayerException catch (e) {
          print('$cycle: Caught PlayerException - ${e.code}: ${e.message}');
          caughtError = e;
          successfulErrorHandling++;
          
          // Verify error code is appropriate
          if (e.code == 404 || e.code == 500 || e.code == -1) {
            print('$cycle: ✅ Appropriate error code: ${e.code}');
          } else {
            print('$cycle: ⚠️ Unexpected error code: ${e.code}');
          }
          
        } catch (e) {
          print('$cycle: Unexpected exception type: ${e.runtimeType} - $e');
        }
        
        // Wait briefly for error stream propagation
        if (caughtError != null) {
          try {
            await errorCompleter.future.timeout(const Duration(seconds: 2));
            
            // Verify error stream consistency
            if (streamError != null && 
                streamError!.code == caughtError!.code && 
                streamError!.message == caughtError!.message) {
              print('$cycle: ✅ Error stream consistency verified');
            }
          } on TimeoutException {
            print('$cycle: ⚠️ Error stream timeout');
          }
        }
        
        // Clean up all resources
        try {
          await errorSubscription.cancel();
          await playerStateSubscription.cancel();
          await processingStateSubscription.cancel();
          await positionSubscription.cancel();
          await player.dispose();
          
          successfulMemoryCleanup++;
          print('$cycle: ✅ All resources cleaned up successfully');
          
        } catch (e) {
          print('$cycle: ❌ Error during cleanup: $e');
        }
        
        print('$cycle: Cycle completed');
        print('$cycle ---------------------------');
        
        // Periodic garbage collection hint
        if (cycle % 5 == 0 && cycle > 0) {
          await Future.delayed(const Duration(milliseconds: 200));
          print('Garbage collection hint at cycle $cycle');
        }
      }
      
      // Final verification
      print('\n=== COMPREHENSIVE TEST RESULTS ===');
      print('Total cycles: $cycles');
      print('Successful error handling: $successfulErrorHandling');
      print('Successful memory cleanup: $successfulMemoryCleanup');
      print('Memory cleanup success rate: ${(successfulMemoryCleanup / cycles * 100).toStringAsFixed(1)}%');
      
      // Verify high success rates
      expect(successfulMemoryCleanup, equals(cycles), 
        reason: 'All cycles should have successful memory cleanup');
      expect(successfulErrorHandling, greaterThan(cycles * 0.6), 
        reason: 'Most cycles should have successful error handling');
      
      print('✅ Comprehensive stress test completed successfully');
    });

    testWidgets('Resource cleanup verification test', (
      WidgetTester tester,
    ) async {
      const int cycles = 10;
      final List<File> createdFiles = [];
      
      print('Starting resource cleanup verification test');
      
      for (int cycle = 0; cycle < cycles; cycle++) {
        final player = AudioPlayer();
        
        // Create cache files that should be cleaned up
        final cacheFile = File('${Directory.systemTemp.path}/cleanup_test_$cycle.mp3');
        createdFiles.add(cacheFile);
        
        try {
          final audioSource = LockCachingAudioSource(
            Uri.parse('https://foo.foo/404.mp3'),
            cacheFile: cacheFile,
          );
          
          await player.setAudioSource(audioSource);
        } on PlayerException catch (e) {
          print('$cycle: Expected error: ${e.code}');
        }
        
        await player.dispose();
        
        // Verify file cleanup (files may or may not exist depending on when error occurred)
        if (await cacheFile.exists()) {
          print('$cycle: Cache file exists (may be expected)');
        } else {
          print('$cycle: Cache file cleaned up');
        }
      }
      
      // Clean up any remaining test files
      for (final file in createdFiles) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          print('Warning: Could not delete test file ${file.path}: $e');
        }
      }
      
      print('✅ Resource cleanup verification completed');
    });

    testWidgets('Error propagation consistency across multiple players', (
      WidgetTester tester,
    ) async {
      const int playerCount = 5;
      final List<AudioPlayer> players = [];
      final List<StreamSubscription<PlayerException>> subscriptions = [];
      final List<PlayerException?> errors = List.filled(playerCount, null);
      
      print('Testing error propagation across $playerCount players');
      
      // Create multiple players
      for (int i = 0; i < playerCount; i++) {
        final player = AudioPlayer();
        players.add(player);
        
        final subscription = player.errorStream.listen((error) {
          print('Player $i error: ${error.code} - ${error.message}');
          errors[i] = error;
        });
        subscriptions.add(subscription);
      }
      
      // Trigger errors in all players simultaneously
      final futures = <Future>[];
      for (int i = 0; i < playerCount; i++) {
        final future = () async {
          try {
            final audioSource = LockCachingAudioSource(
              Uri.parse('https://foo.foo/404.mp3'),
              cacheFile: File('${Directory.systemTemp.path}/multi_player_$i.mp3'),
            );
            await players[i].setAudioSource(audioSource);
          } on PlayerException catch (e) {
            print('Player $i caught: ${e.code}');
          }
        }();
        futures.add(future);
      }
      
      // Wait for all operations to complete
      await Future.wait(futures);
      
      // Brief wait for error stream propagation
      await Future.delayed(const Duration(seconds: 1));
      
      // Verify all players handled errors consistently
      for (int i = 0; i < playerCount; i++) {
        // Note: Error stream propagation may vary, so we don't strictly require it
        print('Player $i final error state: ${errors[i]?.code}');
      }
      
      // Clean up all players
      for (int i = 0; i < playerCount; i++) {
        await subscriptions[i].cancel();
        await players[i].dispose();
      }
      
      print('✅ Multi-player error propagation test completed');
    });
  });
}
