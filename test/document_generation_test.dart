// Generate questions from a PDF (Google Gemini): the checks the app makes
// before uploading, and how an upload's status is read back.
//
// The Edge Function itself is TypeScript; it was tested separately with a
// fake Supabase and a fake Gemini (see CHANGELOG, Session 66).
//
// Run: flutter test test/document_generation_test.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:crimireview/services/document_generation_service.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List pdfBytes([int extra = 10]) => Uint8List.fromList([...utf8.encode('%PDF-1.7'), ...List.filled(extra, 32)]);

void main() {
  group('pdfProblem', () {
    test('accepts a real PDF', () {
      expect(pdfProblem(name: 'Reviewer.pdf', size: 18, bytes: pdfBytes()), isNull);
    });

    test('accepts upper-case .PDF', () {
      expect(pdfProblem(name: 'LAW.PDF', size: 18, bytes: pdfBytes()), isNull);
    });

    test('refuses a file that is not named .pdf', () {
      expect(pdfProblem(name: 'notes.docx', size: 18, bytes: pdfBytes()), contains('not a PDF'));
    });

    test('refuses a file larger than 20 MB', () {
      const size = DocumentGenerationService.maxFileBytes + 1;
      expect(pdfProblem(name: 'big.pdf', size: size, bytes: pdfBytes()), contains('20 MB'));
    });

    test('accepts exactly 20 MB', () {
      expect(pdfProblem(name: 'ok.pdf', size: DocumentGenerationService.maxFileBytes, bytes: pdfBytes()), isNull);
    });

    test('refuses an unreadable file', () {
      expect(pdfProblem(name: 'a.pdf', size: 0, bytes: null), contains("Couldn't read"));
      expect(pdfProblem(name: 'a.pdf', size: 0, bytes: Uint8List(0)), contains("Couldn't read"));
    });

    test('refuses a renamed file that is not really a PDF', () {
      final fake = Uint8List.fromList(utf8.encode('PK\u0003\u0004 this is a docx'));
      expect(pdfProblem(name: 'renamed.pdf', size: fake.length, bytes: fake), contains('does not look like a real PDF'));
      expect(pdfProblem(name: 'tiny.pdf', size: 3, bytes: Uint8List.fromList([1, 2, 3])), isNotNull);
    });
  });

  group('DocumentUpload', () {
    Map<String, dynamic> row(String status, {int generated = 0, String? created}) => {
          'id': 'doc_1',
          'filename': 'Reviewer.pdf',
          'storage_path': 'user/doc_1.pdf',
          'subject_id': 'criminal_jurisprudence',
          'topic': null,
          'target_difficulty': 'hard',
          'requested_count': 10,
          'status': status,
          'generated_count': generated,
          'error_message': null,
          'created_at': created ?? DateTime.now().toUtc().toIso8601String(),
        };

    test('reads a row from the database', () {
      final u = DocumentUpload.fromJson(row('completed', generated: 7));
      expect(u.filename, 'Reviewer.pdf');
      expect(u.storagePath, 'user/doc_1.pdf');
      expect(u.targetDifficulty, 'hard');
      expect(u.generatedCount, 7);
      expect(u.hasQuestions, isTrue);
      expect(u.isWorking, isFalse);
    });

    test('pending and processing are both "working"', () {
      expect(DocumentUpload.fromJson(row('pending')).isWorking, isTrue);
      expect(DocumentUpload.fromJson(row('processing')).isWorking, isTrue);
    });

    test('completed with no questions has nothing to review', () {
      expect(DocumentUpload.fromJson(row('completed')).hasQuestions, isFalse);
    });

    test('a failed upload is failed, not working', () {
      final u = DocumentUpload.fromJson(row('failed'));
      expect(u.isFailed, isTrue);
      expect(u.isWorking, isFalse);
    });

    test('working longer than its steps may take counts as stuck', () {
      String ago(int minutes) => DateTime.now().subtract(Duration(minutes: minutes)).toUtc().toIso8601String();
      // 10 questions = 2 steps of 5 = up to 8 minutes.
      expect(DocumentUpload.fromJson(row('processing')).stuckAfter, const Duration(minutes: 8));
      expect(DocumentUpload.fromJson(row('processing', created: ago(9))).isStuck(DateTime.now()), isTrue);
      expect(DocumentUpload.fromJson(row('processing', created: ago(6))).isStuck(DateTime.now()), isFalse);
      expect(DocumentUpload.fromJson(row('processing')).isStuck(DateTime.now()), isFalse);
      expect(DocumentUpload.fromJson(row('completed', created: ago(9))).isStuck(DateTime.now()), isFalse);
    });

    test('missing fields fall back safely', () {
      final u = DocumentUpload.fromJson({'id': 'x'});
      expect(u.status, 'pending');
      expect(u.requestedCount, 0);
      expect(u.storagePath, '');
    });
  });
}
