// supabase/functions/generate-questions-from-document/index.ts
//
// Generates multiple-choice questions from a PDF a faculty member uploaded,
// using Google Gemini (free tier works). Flow:
//   1. Check that the caller is signed in AND is an admin (public.is_admin()).
//   2. Claim the public.document_uploads row (pending -> processing). A row
//      that is not pending is never processed again, so one upload can use
//      the Gemini quota only once.
//   3. Reply 202 straight away and finish in the background
//      (EdgeRuntime.waitUntil): download the PDF, send it to Gemini with a
//      JSON schema, check every question, insert the good ones as INACTIVE
//      rows (source = 'generated', template_id = upload id), write an audit
//      row, and mark the upload completed or failed with a plain message.
//
// Invoked from lib/services/document_generation_service.dart:
//   supabase.functions.invoke('generate-questions-from-document', body: {'upload_id': ...})
//
// Secrets (Dashboard -> Edge Functions -> Secrets, or `supabase secrets set`):
//   GEMINI_API_KEY   required. Free key from https://aistudio.google.com/apikey
//   GEMINI_MODEL     optional. Defaults to "gemini-flash-latest".
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are injected
// automatically.
//
// Privacy: only the PDF and the subject/topic are sent to Google -- never
// student data. On Gemini's free tier Google may use what is sent to improve
// its models, so upload only material meant for review (laws, reviewers).

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const DEFAULT_MODEL = "gemini-flash-latest";
const MAX_PDF_BYTES = 20 * 1024 * 1024;
const OPTION_COUNT = 4;

// Gemini's structured-output schema (OpenAPI subset, generateContent API).
const RESPONSE_SCHEMA = {
  type: "OBJECT",
  properties: {
    questions: {
      type: "ARRAY",
      items: {
        type: "OBJECT",
        properties: {
          topic: { type: "STRING", description: "Short topic label, e.g. 'Justifying Circumstances'." },
          question_text: { type: "STRING" },
          difficulty: { type: "STRING", enum: ["easy", "medium", "hard"] },
          options: {
            type: "ARRAY",
            description: "Exactly 4 options; exactly one has is_correct = true.",
            items: {
              type: "OBJECT",
              properties: {
                text: { type: "STRING" },
                is_correct: { type: "BOOLEAN" },
                rationale: { type: "STRING", description: "Why THIS option is right or wrong, specifically." },
              },
              required: ["text", "is_correct", "rationale"],
              propertyOrdering: ["text", "is_correct", "rationale"],
            },
          },
          explanation: { type: "STRING", description: "Explanation of the correct answer." },
          legal_basis: {
            type: "STRING",
            nullable: true,
            description: "A law, article or case ONLY if the document states it; otherwise null.",
          },
          remediation_hint: {
            type: "STRING",
            nullable: true,
            description: "What part of the document to re-read after missing this item, or null.",
          },
        },
        required: ["topic", "question_text", "difficulty", "options", "explanation"],
        propertyOrdering: [
          "topic", "question_text", "difficulty", "options", "explanation", "legal_basis", "remediation_hint",
        ],
      },
    },
  },
  required: ["questions"],
};

type GeneratedOption = { text?: string; is_correct?: boolean; rationale?: string };
type GeneratedQuestion = {
  topic?: string;
  question_text?: string;
  difficulty?: string;
  options?: GeneratedOption[];
  explanation?: string;
  legal_basis?: string | null;
  remediation_hint?: string | null;
};

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

/** Plain-language message for a failed Gemini call. */
function geminiError(status: number, text: string): string {
  if (status === 429) {
    return "Gemini's free limit was reached. Try again later; the free quota resets every day.";
  }
  if (status === 400 && /API key|API_KEY/i.test(text)) {
    return "The Gemini API key is not valid. Check the GEMINI_API_KEY secret in Supabase.";
  }
  if (status === 403) {
    return "Gemini refused the request (403). Check that the API key is allowed to use the Gemini API.";
  }
  if (status === 404) {
    return "The Gemini model was not found. Remove or correct the GEMINI_MODEL secret.";
  }
  return `Gemini returned an error (${status}). ${text.slice(0, 300)}`;
}

/** Keeps a question only if it is complete and has exactly one correct option. */
export function validQuestion(q: GeneratedQuestion): boolean {
  const opts = q.options ?? [];
  if (!q.question_text?.trim() || opts.length !== OPTION_COUNT) return false;
  if (opts.filter((o) => o.is_correct === true).length !== 1) return false;
  if (opts.some((o) => !o.text?.trim())) return false;
  const texts = new Set(opts.map((o) => o.text!.trim().toLowerCase()));
  return texts.size === OPTION_COUNT;
}

async function generate(admin: SupabaseClient, upload: Record<string, any>, callerId: string): Promise<void> {
  const uploadId = upload.id as string;
  const finish = (fields: Record<string, unknown>) =>
    admin.from("document_uploads")
      .update({ ...fields, completed_at: new Date().toISOString() })
      .eq("id", uploadId);

  try {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      throw new Error(
        "GEMINI_API_KEY is not set. Create a free key at aistudio.google.com/apikey and add it in " +
          "Supabase: Edge Functions -> Secrets -> GEMINI_API_KEY.",
      );
    }
    const model = (Deno.env.get("GEMINI_MODEL") || DEFAULT_MODEL).trim();

    // 1. The PDF.
    const { data: blob, error: downloadError } = await admin.storage
      .from("document-uploads")
      .download(upload.storage_path);
    if (downloadError || !blob) throw new Error(`Could not read the uploaded PDF: ${downloadError?.message}`);
    const bytes = new Uint8Array(await blob.arrayBuffer());
    if (bytes.length > MAX_PDF_BYTES) throw new Error("The PDF is larger than 20 MB.");
    if (new TextDecoder().decode(bytes.subarray(0, 5)) !== "%PDF-") throw new Error("The file is not a PDF.");

    // 2. Ask Gemini.
    const count = Math.min(Math.max(Number(upload.requested_count) || 10, 1), 20);
    const topicHint = upload.topic ? `Focus only on this topic: ${upload.topic}.` : "";
    const difficultyHint = upload.target_difficulty
      ? `Make every question ${upload.target_difficulty} difficulty.`
      : "Mix easy, medium and hard, mostly medium.";
    const prompt =
      `This PDF is review material for the "${upload.subject_id}" subject of the Philippine ` +
      `Criminologist Licensure Examination. Write exactly ${count} multiple-choice questions taken ONLY ` +
      `from what this document says. Do not add outside facts. Give a legal basis only when the document ` +
      `itself states that law, article or case; otherwise use null. ${topicHint} ${difficultyHint}\n\n` +
      `Each question has exactly ${OPTION_COUNT} options with exactly one correct option, plausible wrong ` +
      `options of similar length to the correct one, and a specific rationale for every option saying why ` +
      `it is right or wrong. Write in clear English.`;

    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json", "x-goog-api-key": apiKey },
        body: JSON.stringify({
          contents: [{
            role: "user",
            parts: [
              { inline_data: { mime_type: "application/pdf", data: toBase64(bytes) } },
              { text: prompt },
            ],
          }],
          generationConfig: {
            responseMimeType: "application/json",
            responseSchema: RESPONSE_SCHEMA,
            temperature: 0.4,
          },
        }),
      },
    );
    const raw = await res.text();
    if (!res.ok) throw new Error(geminiError(res.status, raw));

    const data = JSON.parse(raw);
    const blocked = data?.promptFeedback?.blockReason;
    if (blocked) throw new Error(`Gemini declined to read this document (${blocked}).`);
    const candidate = data?.candidates?.[0];
    const text: string = (candidate?.content?.parts ?? []).map((p: { text?: string }) => p.text ?? "").join("");
    if (!text.trim()) {
      throw new Error(`Gemini returned no questions (finish reason: ${candidate?.finishReason ?? "unknown"}).`);
    }
    const parsed = JSON.parse(text.replace(/^```(?:json)?\s*|\s*```$/g, "")) as { questions?: GeneratedQuestion[] };

    // 3. Insert the good questions, inactive, one at a time so one bad or
    //    duplicate item never loses the whole batch.
    let inserted = 0;
    let skipped = 0;
    for (const q of (parsed.questions ?? []).slice(0, count)) {
      if (!validQuestion(q)) {
        skipped++;
        continue;
      }
      const options = q.options!.map((o) => ({
        text: o.text!.trim(),
        is_correct: o.is_correct === true,
        rationale: (o.rationale ?? "").trim(),
      }));
      const row = {
        id: `gen_${crypto.randomUUID()}`,
        subject_id: upload.subject_id,
        topic: (q.topic?.trim() || upload.topic || "General").slice(0, 120),
        question_text: q.question_text!.trim(),
        options,
        correct_answer_index: options.findIndex((o) => o.is_correct),
        explanation: (q.explanation ?? "").trim(),
        legal_basis: q.legal_basis?.trim() || null,
        remediation_hint: q.remediation_hint?.trim() || null,
        difficulty: upload.target_difficulty ??
          (["easy", "medium", "hard"].includes(q.difficulty ?? "") ? q.difficulty : "medium"),
        source: "generated",
        template_id: uploadId,
        version: 1,
        is_active: false,
        created_by: callerId,
      };
      const { error } = await admin.from("questions").insert(row);
      if (error) {
        skipped++;
        console.warn(`Skipped one generated question: ${error.message}`);
      } else {
        inserted++;
      }
    }

    await admin.from("admin_audit_log").insert({
      admin_id: callerId,
      action: "generate",
      target_table: "questions",
      target_id: uploadId,
      details: { method: "pdf", model, filename: upload.filename, generated: inserted, skipped },
    });

    if (inserted === 0) {
      await finish({
        status: "failed",
        generated_count: 0,
        error_message: skipped > 0
          ? `All ${skipped} questions from Gemini were incomplete or duplicates, so none were saved. Try again or use a clearer PDF.`
          : "Gemini returned no questions for this document.",
      });
    } else {
      await finish({
        status: "completed",
        generated_count: inserted,
        error_message: skipped > 0 ? `${skipped} question(s) were skipped (incomplete or duplicate).` : null,
      });
    }
  } catch (err) {
    console.error("generate-questions-from-document failed:", err);
    await finish({ status: "failed", error_message: err instanceof Error ? err.message : String(err) })
      .then(undefined, () => {});
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Use POST." }, 405);

  const url = Deno.env.get("SUPABASE_URL")!;
  const authHeader = req.headers.get("Authorization") ?? "";

  // The caller must be a signed-in admin. Checked with the caller's own token,
  // so the same public.is_admin() rule as the rest of the database applies.
  const asCaller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData } = await asCaller.auth.getUser();
  const callerId = userData?.user?.id;
  if (!callerId) return json({ error: "Sign in first." }, 401);
  const { data: isAdmin, error: roleError } = await asCaller.rpc("is_admin");
  if (roleError || isAdmin !== true) return json({ error: "Only faculty administrators can do this." }, 403);

  let uploadId: string | undefined;
  try {
    uploadId = (await req.json())?.upload_id;
  } catch {
    // handled below
  }
  if (!uploadId || typeof uploadId !== "string") return json({ error: "upload_id is required." }, 400);

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  // Claim the row: only a pending upload moves to processing, exactly once.
  const { data: claimed, error: claimError } = await admin
    .from("document_uploads")
    .update({ status: "processing" })
    .eq("id", uploadId)
    .eq("status", "pending")
    .select()
    .maybeSingle();
  if (claimError) return json({ error: claimError.message }, 500);
  if (!claimed) return json({ error: "This upload was not found or was already processed." }, 409);

  const work = generate(admin, claimed, callerId);
  // deno-lint-ignore no-explicit-any
  const runtime = (globalThis as any).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(work);
    return json({ accepted: true, upload_id: uploadId }, 202);
  }
  await work;
  return json({ done: true, upload_id: uploadId }, 200);
});
