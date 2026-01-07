"use server";

import { AnalysisResult } from "./lib/imgValidatorTypes";

/**
 * Server action to fetch Pokemon data
 * This replaces the direct external API call with an internal action
 * @param pokemonId - Optional Pokemon ID (1-151 for first gen, 1-1000+ for all)
 * @param revalidate - Optional revalidation time in seconds for ISR
 */
export async function getPokemonAction(pokemonId?: number, revalidate?: number) {
  const randomId = pokemonId ?? Math.floor(Math.random() * 100) + 1;

  console.log(
    `[getPokemonAction] Fetching Pokemon with ID: ${randomId}${
      revalidate ? ` (revalidate: ${revalidate}s)` : ""
    }`
  );

  // Fetch from a public Pokemon API (PokeAPI) instead of Vercel
  const response = await fetch(`https://pokeapi.co/api/v2/pokemon/${randomId}`, {
    next: { revalidate: revalidate ?? 3600 }, // Default 1 hour, or use provided revalidate time
  });

  if (!response.ok) {
    console.error(`[getPokemonAction] Failed to fetch Pokemon ${randomId}: ${response.statusText}`);
    throw new Error(`Failed to fetch Pokemon: ${response.statusText}`);
  }

  const data = await response.json();
  console.log(`[getPokemonAction] Successfully fetched Pokemon: ${data.name} (ID: ${data.id})`);

  // Transform to match expected format
  return {
    id: data.id,
    name: data.name,
    type: data.types.map((t: { type: { name: string } }) => t.type.name),
  };
}

/**
 * Server action to proxy image analysis requests to the ai-img-validator service.
 * Expects a FormData with a `file` entry containing the image.
 */
export async function analyzeImageAction(formData: FormData): Promise<AnalysisResult> {
  const file = formData.get("file");

  if (!file || !(file instanceof File)) {
    throw new Error("No image file provided");
  }

  // Prefer explicit env override; otherwise pick a sensible default.
  const baseUrl =
    process.env.NSFW_API_URL ??
    (process.env.NODE_ENV === "production"
      ? "http://ai-img-validator:8000"
      : "http://localhost:8000");

  const backendUrl = `${baseUrl.replace(/\/+$/, "")}/analyze`;

  const outbound = new FormData();
  outbound.append("file", file);

  const response = await fetch(backendUrl, {
    method: "POST",
    body: outbound,
  });

  if (!response.ok) {
    let detail = response.statusText || "Analysis failed";
    try {
      const errorData = await response.json();
      if (typeof errorData?.detail === "string") {
        detail = errorData.detail;
      }
    } catch {
      // ignore JSON parse errors, fall back to status text
    }
    throw new Error(detail);
  }

  const data = (await response.json()) as AnalysisResult;

  return {
    filename: data.filename,
    nsfw_score: data.nsfw_score,
    is_nsfw: data.is_nsfw,
    dog_probability: data.dog_probability,
    is_dog: data.is_dog,
  };
}
