import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'storage_service.dart';

class FeedbackService {
  static final FeedbackService _instance = FeedbackService._();
  static FeedbackService get instance => _instance;
  
  final StorageService _storage = StorageService();
  
  bool _hapticEnabled = true;
  bool _soundEnabled = true;
  bool _initialized = false;
  
  final AudioPlayer _correctPlayer = AudioPlayer();
  final AudioPlayer _wrongPlayer = AudioPlayer();

  FeedbackService._();

  Future<void> initialize() async {
    if (_initialized) return;
    
    _hapticEnabled = await _storage.getHapticFeedbackEnabled();
    _soundEnabled = await _storage.getSoundEffectsEnabled();
    
    await _correctPlayer.setSource(AssetSource('sounds/correct.mp3'));
    await _wrongPlayer.setSource(AssetSource('sounds/wrong.mp3'));
    
    _initialized = true;
  }

  Future<void> refreshSettings() async {
    _hapticEnabled = await _storage.getHapticFeedbackEnabled();
    _soundEnabled = await _storage.getSoundEffectsEnabled();
  }

  Future<void> _playCorrect() async {
    if (!_soundEnabled) return;
    try {
      await _correctPlayer.stop();
      await _correctPlayer.play(AssetSource('sounds/correct.mp3'));
    } catch (e) {
      // Ignore audio errors
    }
  }

  Future<void> _playWrong() async {
    if (!_soundEnabled) return;
    try {
      await _wrongPlayer.stop();
      await _wrongPlayer.play(AssetSource('sounds/wrong.mp3'));
    } catch (e) {
      // Ignore audio errors
    }
  }

  Future<void> lightTap() async {
    if (!_hapticEnabled) return;
    await HapticFeedback.lightImpact();
  }

  Future<void> mediumTap() async {
    if (!_hapticEnabled) return;
    await HapticFeedback.mediumImpact();
  }

  Future<void> heavyTap() async {
    if (!_hapticEnabled) return;
    await HapticFeedback.heavyImpact();
  }

  Future<void> selectionTap() async {
    if (!_hapticEnabled) return;
    await HapticFeedback.selectionClick();
  }

  Future<void> successVibration() async {
    if (!_hapticEnabled) return;
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.lightImpact();
  }

  Future<void> errorVibration() async {
    if (!_hapticEnabled) return;
    await HapticFeedback.heavyImpact();
  }

  Future<void> onCorrectAnswer() async {
    await Future.wait([
      successVibration(),
      _playCorrect(),
    ]);
  }

  Future<void> onWrongAnswer() async {
    await Future.wait([
      errorVibration(),
      _playWrong(),
    ]);
  }

  Future<void> onButtonTap() async {
    await lightTap();
  }

  Future<void> onQuizComplete(bool passed) async {
    if (passed) {
      await Future.wait([
        successVibration(),
        _playCorrect(),
      ]);
    } else {
      await mediumTap();
    }
  }

  Future<void> onFlashcardSwipe() async {
    await lightTap();
  }

  void dispose() {
    _correctPlayer.dispose();
    _wrongPlayer.dispose();
  }
}
