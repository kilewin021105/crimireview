// supabase/functions/generate-questions-from-document/index.ts
//
// Reads one row of public.document_uploads, downloads the admin's PDF from
// the `document-uploads` storage bucket, asks Claude to generate multiple-
// choice questions strictly from that document's content, and inserts them
// into public.questions with source = 'generated' and is_active = FALSE --
// the review gate AdminService.setActive() / AdminQuestionsScreen already
// implement (see supabase_document_generation.sql for why no new review
// screen was needed).
//
// Invoked fire-and-forget from document_generation_service.dart:
//   supabase.functions.invoke('generate-questions-from-document', body: {'upload_id': ...})
//
// Required secrets (set once via `supabase secrets set`):
//   ANTHROPIC_API_KEY
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically into
// every Edge Function -- nothing to configure for those.

import { createClient } from "npm:@supabase/supabase-js@2";
import Anthropic from "npm:@anthropic-ai/sdk";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Pinned to a specific model, not left to drift -- swap this constant if you
// want a cheaper model for routine generation (Sonnet/Haiku both work fine
// for structured MCQ extraction); Opus is the more conservative default for
// getting legal citations right on the first pass.
const MODEL = "claude-opus-5";

const QUESTION_SCHEMA = {
  type: "object",
  properties: {
    questions: {
      type: "array",
      items: {
        type: "object",
        properties: {
          topic: {
            type: "string",
            description:
              "Short topic label consistent with the subject's usual topic names (e.g. 'Justifying Circumstances'). Use 'General' only if the document gives no clearer grouping.",
          },
          question_text: { type: "string" },
          difficulty: { type: "string", enum: ["easy", "medium", "hard"] },
          options: {
            type: "array",
            description: "Exactly 4 options. Exactly one must have is_correct = true.",
            items: {
              type: "object",
              properties: {
                text: { type: "string" },
                is_correct: { type: "boolean" },
                rationale: {
                  type: "string",
                  description:
                    "Why THIS option is right or wrong, specifically -- not a generic remark.",
                },
              },
              required: ["text", "is_correct", "rationale"],
              additionalProperties: false,
            },
          },
          explanation: {
            type: "string",
            description: "Overall explanation of the correct answer, shown for both right and wrong responses.",
          },
          legal_basis: {
            anyOf: [{ type: "string" }, { type: "null" }],
            description:
              "A statute/article/case citation ONLY if it is explicitly present in the source document. Null if the document does not cite one -- never invent a citation.",
          },
          remediation_hint: {
            anyOf: [{ type: "string" }, { type: "null" }],
            description: "What to re-read in the source document after missing this item, or null.",
          },
        },
        required: [
          "topic",
          "question_text",
          "difficulty",
          "options",
          "explanation",
          "legal_basis",
          "remediation_hint",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["questions"],
  additionalProperties: false,
} as const;

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS_HEADERS });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let uploadId: string | undefined;

  try {
    const body = await req.json();
    uploadId = body.upload_id;
    if (!uploadId) {
      return new Response(JSON.stringify({ error: "upload_id is required" }), {
        status: 400,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const { data: upload, error: fetchError } = await supabase
      .from("document_uploads")
      .select("*")
      .eq("id", uploadId)
      .single();
    if (fetchError || !upload) {
      throw new Error(`Upload row not found: ${fetchError?.message ?? uploadId}`);
    }

    await supabase.from("document_uploads").update({ status: "processing" }).eq("id", uploadId);

    // ---------------------------------------------------------------------
    // 1. Fetch the PDF from storage and base64-encode it.
    // ---------------------------------------------------------------------
    const { data: fileBlob, error: downloadError } = await supabase.storage
      .from("document-uploads")
      .download(upload.storage_path);
    if (downloadError || !fileBlob) {
      throw new Error(`Could not download document: ${downloadError?.message}`);
    }
    const fileBytes = new Uint8Array(await fileBlob.arrayBuffer());
    const base64Pdf = toBase64(fileBytes);

    // ---------------------------------------------------------------------
    // 2. Ask Claude to generate questions strictly from the document.
    // ---------------------------------------------------------------------
    const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY") });

    const topicHint = upload.topic ? `Focus specifically on: ${upload.topic}.` : "";
    const difficultyHint = upload.target_difficulty
      ? `Target difficulty: ${upload.target_difficulty}.`
      : "Mix of easy, medium and hard, weighted toward medium.";

    const stream = anthropic.messages.stream({
      model: MODEL,
      max_tokens: 32000,
      output_config: { effort: "high", format: { type: "json_schema", schema: QUESTION_SCHEMA } },
      messages: [
        {
          role: "user",
          content: [
            {
              type: "document",
              source: { type: "base64", media_type: "application/pdf", data: base64Pdf },
            },
            {
              type: "text",
              text:
                `This is a reviewer document for the "${upload.subject_id}" subject of a criminology ` +
                `licensure board exam. Generate exactly ${upload.requested_count} multiple-choice ` +
                `questions drawn only from the material actually in this document -- do not bring in ` +
                `outside facts, and do not invent a legal citation that is not explicitly stated in the ` +
                `text. ${topicHint} ${difficultyHint}\n\n` +
                `Each question needs 4 answer options with exactly one correct, and a specific rationale ` +
                `for every option (why it's right, or why it's wrong) -- not a generic remark. Base every ` +
                `question on content a student could only get right by having read this document.`,
            },
          ],
        },
      ],
    });
    const response = await stream.finalMessage();

    if (response.stop_reason === "refusal") {
      throw new Error("Claude declined to process this document (safety refusal).");
    }

    const textBlock = response.content.find((b) => b.type === "text");
    if (!textBlock || textBlock.type !== "text") {
      throw new Error("No structured output returned by the model.");
    }
    const parsed = JSON.parse(textBlock.text) as {
      questions: Array<{
        topic: string;
        question_text: string;
        difficulty: string;
        options: Array<{ text: string; is_correct: boolean; rationale: string }>;
        explanation: string;
        legal_basis: string | null;
        remediation_hint: string | null;
      }>;
    };

    // ---------------------------------------------------------------------
    // 3. Insert each generated item as an inactive (pending-review) row.
    //    One insert at a time so a single duplicate stem (the DB's
    //    uq_questions_subject_stem guard) or a malformed item only skips
    //    that one question instead of losing the whole batch.
    // ---------------------------------------------------------------------
    let insertedCount = 0;
    let skippedCount = 0;

    for (const q of parsed.questions ?? []) {
      const correctCount = q.options?.filter((o) => o.is_correct).length ?? 0;
      if (!q.question_text?.trim() || q.options?.length !== 4 || correctCount !== 1) {
        skippedCount++;
        continue;
      }

      const correctIndex = q.options.findIndex((o) => o.is_correct);
      const row = {
        id: `gen_${crypto.randomUUID()}`,
        subject_id: upload.subject_id,
        topic: (q.topic || "General").trim(),
        question_text: q.question_text.trim(),
        options: q.options.map((o) => ({
          text: o.text,
          is_correct: o.is_correct,
          rationale: o.rationale ?? "",
        })),
        correct_answer_index: correctIndex,
        explanation: q.explanation ?? "",
        legal_basis: q.legal_basis,
        remediation_hint: q.remediation_hint,
        difficulty: ["easy", "medium", "hard"].includes(q.difficulty) ? q.difficulty : "medium",
        source: "generated",
        template_id: uploadId,
        version: 1,
        is_active: false,
        created_by: upload.uploaded_by,
      };

      const { error: insertError } = await supabase.from("questions").insert(row);
      if (insertError) {
        // Most commonly the subject+stem uniqueness guard -- a real
        // duplicate is not a failure, just nothing new to review.
        skippedCount++;
        console.warn(`Skipped one generated item: ${insertError.message}`);
      } else {
        insertedCount++;
      }
    }

    // ---------------------------------------------------------------------
    // 4. Resolve the upload row -- never left stuck at "processing".
    // ---------------------------------------------------------------------
    if (insertedCount === 0) {
      await supabase
        .from("document_uploads")
        .update({
          status: "failed",
          error_message:
            skippedCount > 0
              ? `All ${skippedCount} generated item(s) were duplicates or malformed -- nothing usable came out of this document.`
              : "The model returned no questions for this document.",
          completed_at: new Date().toISOString(),
        })
        .eq("id", uploadId);
    } else {
      await supabase
        .from("document_uploads")
        .update({
          status: "completed",
          generated_count: insertedCount,
          error_message: skippedCount > 0 ? `${skippedCount} item(s) skipped (duplicate or malformed).` : null,
          completed_at: new Date().toISOString(),
        })
        .eq("id", uploadId);
    }

    return new Response(JSON.stringify({ generated: insertedCount, skipped: skippedCount }), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("generate-questions-from-document failed:", err);
    if (uploadId) {
      // Best-effort -- if even this fails, the row is left at "processing",
      // which is why the admin screen should treat anything stuck there for
      // more than a few minutes as effectively failed.
      await supabase
        .from("document_uploads")
        .update({
          status: "failed",
          error_message: err instanceof Error ? err.message : String(err),
          completed_at: new Date().toISOString(),
        })
        .eq("id", uploadId)
        .then(undefined, () => {});
    }
    return new Response(JSON.stringify({ error: err instanceof Error ? err.message : String(err) }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
