"use server";

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
